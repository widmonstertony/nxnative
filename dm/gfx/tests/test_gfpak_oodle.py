"""GFPAK type 3 must use the game's decoder and enable its build prerequisite."""
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest import mock

DM = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(DM / 'gfx/tools'), str(DM / 'games')]
import shader_split as split
import profile_guess as profile


def archive(compression=3, size=7):
    head = bytearray(0x38)
    head[:12] = b'GFLXPACK\0\x10\0\0'
    struct.pack_into('<IIQ', head, 0x10, 1, 0, 0x38)
    return bytes(head) + struct.pack('<HHIIIQ', 0, compression, size, 3, 0, 0x50) + b'abc'


class GfpakOodle(unittest.TestCase):
    def test_decode_routes_payload_and_checks_output_length(self):
        with mock.patch.object(split, 'oodle', return_value=b'decoded') as decode:
            self.assertEqual(list(split.gfpak_members(archive(), 'fixture')), [('#0', b'decoded')])
            decode.assert_called_once_with(b'abc', 7)
        with mock.patch.object(split, 'oodle', return_value=b'short'):
            with self.assertRaisesRegex(SystemExit, 'entry says'):
                list(split.gfpak_members(archive(), 'fixture'))

    def test_detects_oodle_without_decompressing_and_rejects_bad_tables(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'archive.gfpak'
            for kind in (0, 1, 2, 3):
                path.write_bytes(archive(kind))
                self.assertEqual(profile.gfpak_uses_oodle(path), kind == 3)
            path.write_bytes(archive()[:0x40])
            with self.assertRaisesRegex(ValueError, 'outside the archive'):
                profile.gfpak_uses_oodle(path)

    def test_build_requests_decoder_only_on_the_nvn_path(self):
        args = ({'nvnBootstrapLoader'}, 0, [], 0, 0)
        self.assertFalse(profile.shader_sources(*args)['oodle_packs'][0])
        self.assertTrue(profile.shader_sources(*args, oodle_gfpaks=1)['oodle_packs'][0])
        self.assertFalse(profile.shader_sources({'vkCreateInstance'}, 0, [], 0, 0, oodle_gfpaks=1)['oodle_packs'][0])


if __name__ == '__main__':
    unittest.main()
