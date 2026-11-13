"""Exercise the SDK tier override without changing frozen operation-mode defaults."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


class GraphicsTierTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        root = Path(cls.tmp.name)
        text = (ROOT / 'dm/host/hle_oe.c').read_text()
        start = text.index('static int oe_graphics_scale(void)')
        end = text.index('HLE_FORCE("_ZN2nn2oe42', start)
        src = root / 'query.c'
        src.write_text('''#include <stdlib.h>
#include <stdio.h>
#include <stdatomic.h>
#define LOG(...) ((void)0)
#define HLE_FORCE(name, desc, result, fn, ...) result fn(__VA_ARGS__)
static int mode;
static int opmode(void) { return mode; }
''' + text[start:end] + '''
int main(int argc, char **argv) {
    (void)argc; mode = atoi(argv[1]);
    printf("%d %u\\n", h_oe_GfxScale(), h_oe_GfxParams());
}
''')
        cls.exe = root / 'query'
        subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', str(src),
                        '-o', str(cls.exe)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def query(self, mode, overrides):
        env = {k: v for k, v in os.environ.items()
               if k not in ('DM_GFX_SCALE', 'DM_GRAPHICS_SCALE')}
        env.update(overrides)
        return tuple(map(int, subprocess.check_output(
            [str(self.exe), str(mode)], env=env, text=True).split()))

    def test_legacy_defaults_and_invalid_overrides(self):
        for mode in (0, 1):
            for value in (None, '', '-1', '3', '1junk', ' 1'):
                with self.subTest(mode=mode, value=value):
                    env = {} if value is None else {'DM_GFX_SCALE': value}
                    self.assertEqual(self.query(mode, env), (mode, 10*(mode+1)))

    def test_sdk_parameters_agree_with_explicit_tiers(self):
        for mode in (0, 1):
            for tier in range(3):
                with self.subTest(mode=mode, tier=tier):
                    self.assertEqual(self.query(mode, {'DM_GRAPHICS_SCALE': str(tier)}),
                                     (tier, 10*(tier+1)))
                    self.assertEqual(self.query(mode, {'DM_GFX_SCALE': str(tier),
                                                       'DM_GRAPHICS_SCALE': '2'}),
                                     (tier, 10*(tier+1)))


if __name__ == '__main__':
    unittest.main()
