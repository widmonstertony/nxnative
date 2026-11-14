#!/usr/bin/env python3
"""Run a pinned Route B translator, emitting its iOS-side libraries for tvOS.

The shader translator and the runtime must come from the same source tree.
The existing chain, reflection, and variant generation stay intact; only
the Apple SDK, deployment target, and recorded compiler command change.
"""
import argparse
import json
import os
from pathlib import Path
import runpy
import sys
from threading import Event, Thread

from build_progress import publish


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-source', type=Path, required=True)
    parser.add_argument('--package', type=Path, required=True, help='Extracted Route B shader packages')
    parser.add_argument('--source-cache', type=Path, required=True)
    parser.add_argument('--metal-directory', type=Path, help='Directory containing the installed metal and metallib tools')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--progress', type=Path, help='State file registered with Mac gamebox (absolute path)')
    args = parser.parse_args()
    translator = args.runtime_source.resolve() / 'dm/gfx/tools/dmsh_build.py'
    if not translator.is_file() or not args.package.is_dir():
        parser.error('expected a prepared shader package directory and the matching runtime source checkout')
    if args.progress and not args.progress.is_absolute():
        parser.error('--progress requires an absolute path')
    if args.output.resolve() == args.source_cache.resolve():
        parser.error('--output and --source-cache must differ')

    sys.path[:0] = [str(translator.parent), str(translator.parents[2] / 'ios/tools')]
    import ios_metal

    # Keep these roots dedicated to tvOS. In particular, never use iOS
    # libraries as an input cache despite the translator's IOSOUT spelling.
    os.environ.pop('DMSH_PREFILL', None)
    os.environ['DMSH_TARGETS'] = 'ios'
    os.environ['IOSOUT'] = str(args.output.resolve())
    prefix = ['xcrun', '-sdk', 'appletvos']
    metal = prefix + ['metal']
    metallib = prefix + ['metallib']
    if args.metal_directory:
        metal = [str(args.metal_directory.resolve() / 'metal')]
        metallib = [str(args.metal_directory.resolve() / 'metallib')]
        if not all(Path(command[0]).is_file() for command in (metal, metallib)):
            parser.error('--metal-directory must contain metal and metallib')
    module_cache = args.source_cache.resolve() / '.clang-modules'
    module_cache.mkdir(parents=True, exist_ok=True)
    ios_metal.METAL = [
        *metal, f'-fmodules-cache-path={module_cache}', '-c', '-target', 'air64-apple-tvos17.0',
        '-fmetal-math-mode=relaxed', '-fpreserve-invariance',
    ]
    ios_metal.METALLIB = metallib
    ios_metal.RECORD = ' '.join(prefix + ['metal'] + ios_metal.METAL[len(metal) + 1:]) + '; xcrun -sdk appletvos metallib'
    sys.argv = [str(translator), str(args.package.resolve()), str(args.source_cache.resolve())]
    if args.progress:
        observe_build(translator, args)
    else:
        runpy.run_path(str(translator), run_name='__main__')


def observe_build(translator, args):
    import dmsh_chain

    output = args.output / ('b-' + dmsh_chain.version())
    translated = args.source_cache / output.name
    table = dmsh_chain.load_game().table('shader_map.tsv')
    keys = {cols[3] for line in table.read_text().splitlines()
            if not line.startswith('#') and len(cols := line.split('\t')) >= 5 and cols[0].endswith('.bin')
            and len(cols[3]) == 16 and all(c in '0123456789abcdef' for c in cols[3])}
    if not keys:
        raise ValueError(f'No base shader keys in {table}')

    def snapshot():
        if not output.is_dir():
            return {}
        result = {}
        with os.scandir(output) as files:
            for item in files:
                if item.name.endswith('_b.metallib') and (key := item.name[:-11]) in keys:
                    try:
                        stat = item.stat()
                    except FileNotFoundError:
                        continue
                    result[key] = (stat.st_ino, stat.st_ctime_ns)
        return result

    before = snapshot()
    stop = Event()

    def count():
        # The translator cleans up old output for the selected keys. Don't
        # count libraries from a prior run before they are published again.
        return sum(before.get(k) != value for k, value in snapshot().items())

    def watch():
        while not stop.wait(3):
            publish(args.progress, 'running', 'tv_shaders', count(), len(keys), os.getpid())

    publish(args.progress, 'running', 'tv_shaders', 0, len(keys), os.getpid())
    monitor = Thread(target=watch, daemon=True)
    monitor.start()
    try:
        runpy.run_path(str(translator), run_name='__main__')
        report = json.loads((translated / '_b_build.json').read_text())
        requested = {row['key'] for row in report}
        done = sum(row['st'] == 'ok' and (output / (row['key'] + '_b.metallib')).is_file()
                   for row in report)
        total = len(requested)
        if not total or requested != keys or done != total:
            raise ValueError(f'tvOS shader pass: {done}/{total} requested base libraries verified')
    except BaseException:
        stop.set()
        monitor.join()
        publish(args.progress, 'needs_attention', 'failed_shaders', count(), len(keys))
        raise
    stop.set()
    monitor.join()
    publish(args.progress, 'compiled', 'tables_and_packaging_pending', done, total)


if __name__ == '__main__':
    main()
