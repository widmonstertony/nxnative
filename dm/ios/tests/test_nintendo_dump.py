#!/usr/bin/env python3
"""Synthetic input identities and failure cases; no game assets required."""
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('dump', Path(__file__).parents[1] / 'tools/inspect_nintendo_dump.py')
dump = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(dump)
TITLE = 0x0400000000000000


def npdm(title=TITLE):
    data = bytearray(0xA0)
    data[:4] = b'META'
    struct.pack_into('<II', data, 0x70, 0x80, 0x20)
    data[0x80:0x84] = b'ACI0'
    struct.pack_into('<Q', data, 0x90, title)
    return data


def version(root, name, marker=b'spec: Ounce', title=TITLE):
    folder = root / name
    (folder / 'exefs').mkdir(parents=True)
    (folder / 'romfs').mkdir()
    (folder / 'exefs/main.npdm').write_bytes(npdm(title))
    (folder / 'exefs/main').write_bytes(b'NSO0')
    data = bytearray(0x100)
    data[:4] = b'NSO0'
    struct.pack_into('<I', data, 0x20, 0x100)
    struct.pack_into('<I', data, 0x28, len(marker))
    (folder / 'exefs/sdk').write_bytes(data + marker)
    return folder


class DumpInspection(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.base = version(self.root, 'base')

    def test_switch2_is_metadata_not_support(self):
        result = dump.inspect(self.root)
        self.assertEqual(result['detected_platform'], 'switch2')
        self.assertFalse(result['device_compatibility_verified'])
        self.assertIn('nvn2_backend_not_integrated_in_ios_fork', result['requirements'])

    def test_updates_are_numeric_and_same_title(self):
        version(self.root, 'updates/9')
        version(self.root, 'updates/10')
        self.assertEqual(dump.inspect(self.root)['selected_version'], 10)
        self.assertEqual(dump.inspect(self.root, 0)['selected_version'], 0)
        with self.assertRaises(ValueError): dump.inspect(self.root, 99)
        (self.root / 'updates/9/exefs/main.npdm').write_bytes(npdm(TITLE + 0x2000))
        with self.assertRaises(ValueError): dump.inspect(self.root, 10)

    def test_unknown_sdk_is_not_assumed_switch1(self):
        sdk = self.base / 'exefs/sdk'
        data = bytearray(sdk.read_bytes())
        data[0x100:] = b'x' * (len(data) - 0x100)
        sdk.write_bytes(data)
        self.assertEqual(dump.inspect(self.root, expected='switch2')['detected_platform'], 'unknown')
        struct.pack_into('<I', data, 0xC, 2)
        struct.pack_into('<I', data, 0x64, len(data) - 0x100)
        sdk.write_bytes(data)
        self.assertEqual(dump.inspect(self.root)['platform_evidence'], 'compressed_sdk_requires_extractor')

    def test_wrong_platform_rejected(self):
        with self.assertRaises(ValueError): dump.inspect(self.root, expected='switch')

    def test_npdm_bounds_rejected(self):
        path = self.base / 'exefs/main.npdm'
        good = npdm()
        for offset, size in [(0xFFFF, 0x20), (0x80, 0xFFFF), (0x80, 0x10), (0x20, 0x20)]:
            bad = good.copy()
            struct.pack_into('<II', bad, 0x70, offset, size)
            path.write_bytes(bad)
            with self.assertRaises(ValueError): dump.inspect(self.root)
        path.write_bytes(b'META')
        with self.assertRaises(ValueError): dump.inspect(self.root)

    def test_sdk_bounds_rejected(self):
        path = self.base / 'exefs/sdk'
        bad = bytearray(path.read_bytes())
        struct.pack_into('<I', bad, 0x28, 0xFFFFFFF0)
        path.write_bytes(bad)
        with self.assertRaises(ValueError): dump.inspect(self.root)

    def test_dlc_identity_and_ambiguity(self):
        dlc = self.root / 'dlc' / f'{TITLE + 0x1001:016X}'
        (dlc / '1/romfs').mkdir(parents=True)
        self.assertEqual(dump.inspect(self.root)['dlc'][0]['index'], 1)
        (dlc / '2/romfs').mkdir(parents=True)
        with self.assertRaises(ValueError): dump.inspect(self.root)

    def test_incomplete_update_rejected(self):
        (self.root / 'updates/4').mkdir(parents=True)
        with self.assertRaises(OSError): dump.inspect(self.root)


if __name__ == '__main__': unittest.main()
