"""Compatibility updates retain usable shader paths after a container rename."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'scripts'))
from tonton_compatible_install import relocated_shader_env


class RelocatedShaderEnvironment(unittest.TestCase):
    def test_repair_is_scoped_to_default_paths(self):
        old = '/var/mobile/Containers/Data/Application/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA'
        new = '/var/mobile/Containers/Data/Application/BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB'
        title = '010029b0118e8000'
        resources = f'{old}/Documents/Games/{title}/Resources'.encode()
        repair = (b' DM_MSL_DIR=' + resources + b'/msl\r\n'
                  b'DM_NVN_SHMAP=' + resources + b'/dm/shader_map.tsv\n')
        retain = (b'# DM_MSL_DIR=' + resources + b'/msl\n'
                  b'DM_SAVE=' + resources + b'/save\n'
                  b'DM_MSL_DIR=' + resources + b'/msl-custom\n'
                  b'DM_NVN_SHMAP=' + resources.replace(title.encode(), b'010029b0118e8010') + b'/dm/shader_map.tsv')
        expected = repair.replace(old.encode(), new.encode()) + retain
        self.assertEqual(relocated_shader_env(repair + retain, title, old, new), expected)
        self.assertEqual(relocated_shader_env(expected, title, old, new), expected)
