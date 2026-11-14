import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location('device_builds', ROOT / 'scripts/tonton_device_builds.py')
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)


class DeviceBuilds(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.job = dict(id='game-m2', title='0123456789ABCDEF', name='Game', devices=['M2'],
                        folder=str(self.root), log=str(self.root / 'build.log'),
                        state_file=str(self.root / 'state.json'), chain='testchain',
                        controller=str(self.root / 'continue.py'), python='/usr/bin/python3',
                        build_config=str(self.root / 'config.json'), reserve_bytes=100,
                        lock_file=str(self.root / 'dispatch.lock'), pause_file=str(self.root / '.tonton-pause-request'))
        self.state(reused=70, finished=5, expected=100, failed=[], chain='testchain', phase='compiling')

    def state(self, **state):
        (self.root / 'state.json').write_text(json.dumps(state))

    def test_status_is_checkpoint_total_not_current_batch_count(self):
        self.assertEqual(M.observe(self.job, [])['completed'], 75)
        self.assertEqual(M.observe(self.job, [])['state'], 'stopped')
        worker = [(9, ['python', self.job['build_config']])]
        self.assertEqual(M.observe(self.job, worker)['state'], 'running')
        # An unrelated process containing the name in one string is not a worker.
        self.assertEqual(M.matches([(9, ['editor', 'view ' + self.job['build_config']])], self.job['build_config']), [])

    def test_disk_wait_is_not_falsely_reported_as_compiling(self):
        rows = [(9, ['python', self.job['controller']])]
        with patch.object(M.shutil, 'disk_usage') as usage:
            usage.return_value.free = 50
            row = M.observe(self.job, rows)
        self.assertEqual(row['state'], 'waiting_space')
        self.assertEqual(row['reserveBytes'], 100)

    def test_pause_only_requests_batch_boundary_and_never_kills_a_worker(self):
        rows = [(9, ['python', self.job['build_config']])]
        with patch.object(M.subprocess, 'Popen') as spawn:
            M.action(self.job, 'pause', rows)
            spawn.assert_not_called()
        self.assertEqual(M.observe(self.job, rows)['state'], 'pausing')
        self.assertEqual(M.observe(self.job, [])['state'], 'paused')

    def test_resume_does_not_duplicate_a_worker_or_a_controller(self):
        for field in ['controller', 'build_config']:
            with self.subTest(field=field), patch.object(M.subprocess, 'Popen') as spawn:
                M.action(self.job, 'resume', [(9, ['python', self.job[field]])])
                spawn.assert_not_called()

    def test_wrong_chain_and_impossible_counts_refuse_resume(self):
        for change in [dict(chain='foreign'), dict(finished=40)]:
            self.state(reused=70, finished=5, expected=100, failed=[], chain='testchain', phase='compiling')
            state = M.load(self.job['state_file']); state.update(change)
            self.state(**state)
            with self.assertRaises(AssertionError), patch.object(M.subprocess, 'Popen') as spawn:
                M.action(self.job, 'resume', [])
            spawn.assert_not_called()

    def test_complete_shaders_are_not_claimed_installed(self):
        self.state(reused=95, finished=5, expected=100, failed=[], chain='testchain',
                   phase='missing_shader_pass_finished_final_table_merge_pending')
        self.assertEqual(M.observe(self.job, [])['state'], 'compiled')
        with self.assertRaises(AssertionError): M.action(self.job, 'resume', [])


if __name__ == '__main__':
    unittest.main()
