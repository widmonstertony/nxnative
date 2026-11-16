"""Check the compatibility IPA gate against real Mach-O load-command layout."""
import importlib.util
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

SPEC = importlib.util.spec_from_file_location('build_tonton_ios', Path(__file__).resolve().parents[3] / 'scripts/build_tonton_ios.py')
TOOL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TOOL)


def binary(major, minor=0, *, platform=2, kind=2):
    command = struct.pack('<6I', 0x32, 24, platform, major << 16 | minor << 8, 27 << 16, 0)
    return struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, kind, 1, len(command), 0, 0) + command


class CompatibilityIPA(unittest.TestCase):
    def make(self, minimum, executable, extra=None):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        path = Path(tmp.name) / 'fixture.ipa'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('Payload/Game.app/Info.plist', plistlib.dumps(dict(
                MinimumOSVersion=minimum, CFBundleIdentifier='test.compatibility', CFBundleExecutable='Game')))
            archive.writestr('Payload/Game.app/Game', executable)
            if extra:
                archive.writestr('Payload/Game.app/Frameworks/Engine.framework/Engine', extra)
        return path

    def test_distinct_targets_and_lower_minimum_framework(self):
        ipa = self.make('17.0', binary(17), binary(16, 1, kind=6))
        report = TOOL.verify_ipa(ipa, '17.0')
        self.assertEqual(len(report['binaries']), 2)
        self.assertEqual(report['minimum_ios'], '17.0')
        self.assertEqual(TOOL.verify_ipa(self.make('16.1', binary(16, 1)), '16.1')['minimum_ios'], '16.1')

    def test_plist_edit_cannot_mask_incompatible_executable(self):
        for name, extra in [('main', None), ('nested', binary(26, kind=6))]:
            with self.subTest(name=name):
                path = self.make('16.1', binary(26) if extra is None else binary(16, 1), extra)
                with self.assertRaisesRegex(ValueError, 'above selected'):
                    TOOL.verify_ipa(path, '16.1')

    def test_universal_engine_does_not_hide_higher_minimum(self):
        slice_ = binary(26, kind=6)
        engine = struct.pack('>7I', 0xcafebabe, 1, 0x100000c, 0, 28, len(slice_), 0) + slice_
        path = self.make('16.1', binary(16, 1), engine)
        with self.assertRaisesRegex(ValueError, 'above selected'):
            TOOL.verify_ipa(path, '16.1')

    def test_simulator_binary_is_not_device_compatible(self):
        path = self.make('16.1', binary(16, 1, platform=7))
        with self.assertRaisesRegex(ValueError, 'Not an iOS device binary'):
            TOOL.verify_ipa(path, '16.1')


if __name__ == '__main__':
    unittest.main()
