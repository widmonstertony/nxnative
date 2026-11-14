#!/usr/bin/env python3
"""Observe and resume registered, checkpointed device builds from the Mac UI.

The local manifest names existing jobs. Nothing discovers game data, changes a
shader chain, deletes output, or starts a build during a status refresh.
"""
import argparse
import datetime
import fcntl
import hashlib
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import sys


def load(path):
    return json.loads(Path(path).read_text())


def processes():
    text = subprocess.check_output(['/bin/ps', '-axo', 'pid=,args='], text=True)
    result = []
    for line in text.splitlines():
        try:
            pid, command = line.strip().split(None, 1)
            result.append((int(pid), shlex.split(command)))
        except ValueError:
            continue
    return result


def matches(rows, argument):
    # An exact argv member, not a substring that could match an editor or shell.
    return [pid for pid, args in rows if str(argument) in args[1:]]


def checked_job(config, identifier):
    jobs = config['jobs']
    assert len({j['id'] for j in jobs}) == len(jobs), 'Duplicate build IDs'
    job = next(j for j in jobs if j['id'] == identifier)
    for key in ['state_file', 'log', 'folder']:
        assert Path(job[key]).is_absolute(), key
    if job.get('controller'):
        controller = Path(job['controller'])
        assert controller.is_absolute() and controller.is_file()
        assert hashlib.sha256(controller.read_bytes()).hexdigest() == job['controller_sha256'], 'Controller changed; review its registration'
        assert Path(job['python']).is_file()
        assert Path(job['pause_file']).parent == Path(job['folder'])
        assert Path(job['lock_file']).parent == Path(job['folder'])
    return job


def observe(job, rows):
    state = load(job['state_file'])
    base = {key: job[key] for key in ['id', 'title', 'name', 'devices', 'log', 'folder']}
    if job.get('receipt'):
        valid = all(state.get(k) == v for k, v in job['receipt'].items())
        return dict(base, state='installed' if valid else 'needs_attention',
                    completed=job.get('total', 0) if valid else 0, total=job.get('total', 0),
                    detail='awaiting_playtest' if valid else 'receipt_mismatch', canResume=False,
                    updated=state.get('updated'))
    assert state['chain'] == job['chain'], 'Shader lineage changed'
    total = int(state['expected'])
    completed = int(state.get('reused', 0)) + int(state.get('finished', 0))
    assert 0 <= completed <= total and total > 0
    controllers = matches(rows, job['controller'])
    workers = matches(rows, job['build_config'])
    free = shutil.disk_usage(job['folder']).free
    pause = Path(job['pause_file']).exists()
    if state.get('failed'):
        status, detail = 'needs_attention', 'failed_shaders'
    elif state.get('phase') == 'missing_shader_pass_finished_final_table_merge_pending':
        status, detail = 'compiled', 'tables_and_packaging_pending'
    elif pause:
        status, detail = ('pausing', 'finishing_current_batch') if workers else ('paused', 'paused_by_player')
    elif workers:
        status, detail = 'running', 'missing_shaders_only'
    elif controllers and free < job['reserve_bytes']:
        status, detail = 'waiting_space', 'disk_reserve'
    elif controllers:
        status, detail = 'waiting', 'next_batch'
    else:
        status, detail = 'stopped', 'resume_checkpoint'
    return dict(base, state=status, detail=detail, completed=completed, total=total,
                failed=len(state.get('failed', [])), updated=state.get('updated'),
                chain=state['chain'], freeBytes=free, reserveBytes=job['reserve_bytes'],
                canResume=status in ['paused', 'stopped'], controllerPIDs=controllers,
                workerPIDs=workers)


def action(job, operation, rows):
    assert job.get('controller'), 'This result is already delivered; use a new build for an engine update'
    # Validate the current chain/counts before permitting a mutation.
    current = observe(job, rows)
    if operation == 'pause':
        Path(job['pause_file']).write_text('Pause after the current checkpointed batch.\n')
        return
    assert current['state'] not in ['compiled', 'needs_attention'], 'Review this completed/failed job before resuming'
    pause = Path(job['pause_file'])
    pause.unlink(missing_ok=True)
    # Use the same lock the original controller owns, not an unreliable saved PID.
    with Path(job['lock_file']).open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return  # Already supervised. Do not launch a second controller.
        if matches(rows, job['controller']) or matches(rows, job['build_config']):
            return
    with Path(job['log']).open('ab', buffering=0) as log:
        subprocess.Popen([job['python'], '-u', job['controller']], cwd=job['folder'],
                         stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                         start_new_session=True, close_fds=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--config', type=Path, required=True)
    ap.add_argument('operation', choices=['status', 'resume', 'pause', 'log'])
    ap.add_argument('--job')
    args = ap.parse_args()
    config = load(args.config)
    assert config['schema'] == 1
    # Serialize UI clicks from multiple windows and CLI callers.
    with args.config.with_suffix('.control.lock').open('a') as control:
        fcntl.flock(control, fcntl.LOCK_EX)
        jobs = [checked_job(config, j['id']) for j in config['jobs']]
        rows = processes()
        if args.operation != 'status':
            assert args.job, 'Choose a build'
            job = next(j for j in jobs if j['id'] == args.job)
            if args.operation == 'log':
                with Path(job['log']).open('rb') as log:
                    log.seek(0, 2)
                    log.seek(max(0, log.tell() - 32768))
                    print(json.dumps({'text': log.read().decode('utf-8', errors='replace')}))
                return
            action(job, args.operation, rows)
            rows = processes()
        report = []
        for job in jobs:
            try:
                report.append(observe(job, rows))
            except (OSError, ValueError, KeyError, AssertionError) as error:
                report.append(dict(id=job['id'], title=job['title'], name=job['name'],
                                   devices=job['devices'], state='needs_attention', detail=str(error),
                                   completed=0, total=0, canResume=False, log=job['log'], folder=job['folder']))
        print(json.dumps({'jobs': report, 'updated': datetime.datetime.now().astimezone().isoformat()}))


if __name__ == '__main__':
    main()
