"""A scene cap changes only verified data; rejected contracts are atomic."""
import ctypes
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]


class Result(ctypes.Structure):
    _fields_ = [("width", ctypes.c_uint), ("height", ctypes.c_uint),
                ("changed", ctypes.c_uint), ("reason", ctypes.c_char_p)]


class ResolutionLevelsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        source = cls.root / "wrapper.c"
        source.write_text('''#include "resolution_levels.h"
int open_contract(const char *dir, const char *selected, const char *rom) {
    FILE *f = dm_resolution_contract_open(dir, selected, rom);
    if (!f) return -1;
    int c = fgetc(f); fclose(f); return c;
}
int apply(const char *path, const char *build, unsigned char *data,
          size_t size, const char *request, dm_resolution_result *result) {
    FILE *f = fopen(path, "r"); if (!f) return -2;
    int code = dm_resolution_levels(f, build, data, size, 64, size, request, result);
    fclose(f); return code;
}
''')
        library = cls.root / "wrapper.so"
        subprocess.run([shutil.which("cc") or "cc", "-std=c11", "-Wall", "-Wextra",
                        "-Werror", "-shared", "-fPIC", "-I", str(REPO / "dm/host"),
                        str(source), "-o", str(library)], check=True, capture_output=True)
        cls.lib = ctypes.CDLL(str(library))
        cls.lib.apply.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p,
                                  ctypes.c_size_t, ctypes.c_char_p, ctypes.POINTER(Result)]

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def setUp(self):
        self.build = "816c5358e8178d802fcec4a7ce5a741a"
        self.contract = ("schema\t1\nbuild\t" + self.build +
                         "\ndefault\t1280x720\ntable\t0x80\n"
                         "level\t0\t960\t540\nlevel\t1\t1280\t720\n"
                         "level\t2\t1920\t1080\nlist\t0x100\t020100\n"
                         "list\t0x110\t0100\n")
        self.image = bytearray([0xA5] * 512)
        self.image[128:152] = struct.pack("<6I", 960, 1280, 1920, 540, 720, 1080)
        self.image[256:259] = bytes([2, 1, 0])
        self.image[272:274] = bytes([1, 0])

    def apply(self, request=None, build=None):
        path = self.root / "contract.tsv"
        path.write_text(self.contract)
        buf = (ctypes.c_ubyte * len(self.image)).from_buffer(self.image)
        result = Result()
        code = self.lib.apply(str(path).encode(), (build or self.build).encode(), buf,
                              len(self.image), request.encode() if request else None,
                              ctypes.byref(result))
        return code, result

    def test_contract_tracks_current_cartridge_and_preserves_overrides(self):
        signed = self.root / "signed-profile"
        current = self.root / "current-container" / "Resources"
        moved = self.root / "moved-container" / "Resources"
        for folder in (signed, current / "dm", moved / "dm"):
            folder.mkdir(parents=True, exist_ok=True)
        (current / "dm/resolution_levels.tsv").write_text("C")
        (moved / "dm/resolution_levels.tsv").write_text("M")
        def opened(folder, override, rom):
            return self.lib.open_contract(str(folder).encode(),
                str(override).encode() if override else None, str(rom).encode())
        self.assertEqual(opened(signed, None, current / "romfs.img"), ord("C"))
        self.assertEqual(opened(signed, None, moved / "romfs.img"), ord("M"))
        (signed / "resolution_levels.tsv").write_text("S")
        self.assertEqual(opened(signed, None, current / "romfs.img"), ord("S"))
        self.assertEqual(opened(signed, current / "dm/resolution_levels.tsv",
                                moved / "romfs.img"), ord("C"))
        self.assertEqual(opened(signed, signed / "missing.tsv",
                                current / "romfs.img"), -1)
        self.assertEqual(opened(self.root / "missing", None, "relative.img"), -1)
        self.assertEqual(opened("/" + "x" * 1500, None, current / "romfs.img"), ord("C"))

    def test_default_caps_scene_without_resizing_targets(self):
        before = bytes(self.image)
        code, result = self.apply()
        self.assertEqual((code, result.width, result.height, result.changed), (1, 1280, 720, 1))
        self.assertEqual(self.image[256:259], bytes([1, 1, 0]))
        self.image[256] = before[256]
        self.assertEqual(bytes(self.image), before)

    def test_540p_reaches_all_modes(self):
        code, result = self.apply("960x540")
        self.assertEqual((code, result.width, result.height, result.changed), (1, 960, 540, 2))
        self.assertEqual(self.image[256:259], bytes(3))
        self.assertEqual(self.image[272:274], bytes(2))

    def test_wrong_build_and_original_never_write(self):
        before = bytes(self.image)
        for request, build in [(None, "0" * 32), ("original", None)]:
            self.assertEqual(self.apply(request, build)[0], 0)
            self.assertEqual(bytes(self.image), before)

    def test_bad_request_rejected(self):
        before = bytes(self.image)
        for request in ["1280x720junk", "0x720", "640x360", "999999x999999"]:
            self.assertEqual(self.apply(request)[0], -1)
            self.assertEqual(bytes(self.image), before)

    def test_last_list_mismatch_never_partially_writes_first(self):
        self.image[272] = 2
        before = bytes(self.image)
        self.assertEqual(self.apply()[0], -1)
        self.assertEqual(bytes(self.image), before)

    def test_layout_mismatch_never_writes(self):
        self.image[128] ^= 1
        before = bytes(self.image)
        self.assertEqual(self.apply()[0], -1)
        self.assertEqual(bytes(self.image), before)

    def test_no_writes_to_code_outside_image_or_overlapping_data(self):
        original = self.contract
        before = bytes(self.image)
        for extra in ["list\t0x10\ta5\n", "list\t0xffffffffffffffff\t00\n",
                      "list\t0x100\t020100\n", "list\t0x80\tc0\n"]:
            self.contract = original + extra
            self.assertEqual(self.apply()[0], -1)
            self.assertEqual(bytes(self.image), before)


if __name__ == "__main__":
    unittest.main()
