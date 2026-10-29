"""Captured shader packages must retain the exact identity used by NVN."""
import hashlib
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("pack_dumps", Path(__file__).resolve().parents[2] / "ios/tools/pack_shader_dumps.py")
assert SPEC is not None and SPEC.loader is not None
PACK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACK)


class CaptureTests(unittest.TestCase):
    def capture(self, stage=1):
        ctl, code = bytearray(0x880), bytearray(0x100)
        ctl[:4] = bytes.fromhex("34127698")
        code[:4] = bytes.fromhex("78563412")
        struct.pack_into("<I", ctl, 0x20, 0x848)
        struct.pack_into("<I", ctl, 0x704, len(code))
        struct.pack_into("<I", code, 0x30, (stage << 10) | 1)
        return hashlib.sha256(ctl[:0x848] + code).hexdigest()[:16], bytes(ctl), bytes(code)

    def test_exact_graphics_record(self):
        for stage, expected in [(1, "vs"), (5, "ps"), (0, "vs")]:
            key, ctl, code = self.capture(stage)
            actual, record = PACK.validate(key, ctl, code)
            self.assertEqual(actual, expected)
            self.assertEqual(record[0x38:], code + ctl)
            self.assertEqual(struct.unpack_from("<2I", record, 0x28), (len(ctl), len(code)))

    def test_invalid_capture_identity_and_layout(self):
        key, ctl, code = self.capture()
        for args in [("invalid", ctl, code), ("0" * 16, ctl, code), (key, ctl[:0x848], code), (key, ctl, code[:-1])]:
            with self.assertRaises(ValueError): PACK.validate(*args)
        with self.assertRaises(ValueError): PACK.validate(*self.capture(4))

    def test_export_is_deterministic_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); dumps = root / "dumps"; dumps.mkdir()
            key, ctl, code = self.capture()
            (dumps / (key + ".ctl")).write_bytes(ctl)
            (dumps / (key + ".code")).write_bytes(code)
            self.assertEqual(PACK.pack(dumps, root / "out"), 1)
            self.assertIn(key, (root / "out/shader_map.tsv").read_text())
            with self.assertRaises(FileExistsError): PACK.pack(dumps, root / "out")

    def test_later_batches_cannot_change_existing_package_identity(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            packages = {}
            for number, stage in enumerate((1, 5, 1)):
                dumps = root / f"dumps{number}"; dumps.mkdir()
                _, ctl, original = self.capture(stage)
                code = bytearray(original); code[-1] = number
                key = hashlib.sha256(ctl[:0x848] + code).hexdigest()[:16]
                (dumps / (key + ".ctl")).write_bytes(ctl)
                (dumps / (key + ".code")).write_bytes(code)
                output = root / f"out{number}"
                PACK.pack(dumps, output)
                row = (output / "shader_map.tsv").read_text().splitlines()[1].split("\t")
                self.assertEqual(row[1], "0")
                self.assertEqual(row[3], key)
                name = row[0]
                self.assertNotIn(name, packages)
                packages[name] = (output / name).read_bytes()
                self.assertEqual(packages[name][0x38:], code + ctl)


if __name__ == "__main__": unittest.main()
