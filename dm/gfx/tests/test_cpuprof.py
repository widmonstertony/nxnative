#!/usr/bin/env python3
"""Run the renderer's diagnostic counters on independent submission threads."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

SOURCE = Path(os.environ.get('DM_CPUPROF_SOURCE', Path(__file__).parents[1] / 'nvn/nvn_mtl.m'))

class CpuProfile(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        source = SOURCE.read_text()
        begin = source.index('typedef struct { uint64_t wall, cpu; } cp_stamp;')
        end = source.index('#define AP_B', begin)
        harness = r'''
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
static _Thread_local uint64_t wall = 1, cpu = 1, reads;
static uint64_t prof_clock(clockid_t id) {
    reads++;
    return id == CLOCK_THREAD_CPUTIME_ID ? ++cpu : ++wall;
}
#define clock_gettime_nsec_np prof_clock
#define MLOG(...) do { printf(__VA_ARGS__); putchar('\n'); } while (0)
'''
        harness += source[begin:end]
        harness += r'''
static void *worker(void *unused) {
    (void)unused;
    pthread_setname_np("profile-worker");
    cp_report();
    for (int i = 0; i < 65; i++) {
        cp_stamp d = cp_begin(5);
        cp_stamp t = cp_begin(4);
        cp_end(4, t);
        cp_end(5, d);
    }
    uint64_t before = reads;
    wall += 6000000000ull;
    cp_report();
    printf("clock_reads=%llu\n", (unsigned long long)before);
    return NULL;
}
int main(void) {
    cp_report();
    cp_stamp x = cp_begin(7); cp_end(7, x);
    pthread_t thread;
    assert(!pthread_create(&thread, NULL, worker, NULL));
    assert(!pthread_join(thread, NULL));
    wall += 6000000000ull;
    cp_report();
    return 0;
}
'''
        c = Path(cls.tmp.name) / 'probe.c'
        c.write_text(harness)
        cls.exe = c.with_suffix('')
        subprocess.run(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pthread', str(c), '-o', str(cls.exe)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def run_probe(self, stride):
        env = os.environ.copy()
        env['DM_NVN_CPUPROF'] = str(stride)
        return subprocess.check_output([str(self.exe)], env=env, text=True)

    def test_disabled_reads_no_clocks(self):
        self.assertEqual(self.run_probe(0).strip(), 'clock_reads=0')
        self.assertEqual(self.run_probe(-1).strip(), 'clock_reads=0')

    def test_all_calls_and_separate_threads(self):
        s = self.run_probe(1)
        worker = next(x for x in s.splitlines() if "thread 'profile-worker'" in x)
        main = next(x for x in s.splitlines() if 'index 1/1' in x)
        self.assertIn('draw 65/65', worker)
        self.assertIn('texture 65/65', worker)
        self.assertNotIn('index ', worker)
        self.assertNotIn('draw ', main)

    def test_sampling_keeps_nested_phases(self):
        s = self.run_probe(64)
        self.assertIn('draw 2/65', s)
        self.assertIn('texture 2/65', s)
        self.assertIn('clock_reads=17', s)
        self.assertIn('raw sampled times; nested phases overlap', s)

    def test_stride_is_bounded(self):
        s = self.run_probe(5000)
        self.assertIn('stride 4096', s)
        self.assertIn('draw 1/65', s)

if __name__ == '__main__':
    unittest.main()
