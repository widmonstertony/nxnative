#!/usr/bin/env python3
"""Verify exact-host migration and reject malformed Mach-O metadata."""
import hashlib
import importlib.util
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('framework', Path(__file__).parents[1] / 'tools/build_game_framework.py')
fw = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fw)


def host():
    data = bytearray(0x10000)
    struct.pack_into('<IIIIIIII', data, 0, 0xFEEDFACF, 0x100000C, 0, 2, 2, 304, 0, 0)
    for at, segment, section, offset in [(32, '__TEXT', '__dm05mainimg', 0x4000),
                                          (184, '__DM05mainW', '__img', 0xC000)]:
        struct.pack_into('<II', data, at, 0x19, 152)
        struct.pack_into('<I', data, at + 64, 1)
        p = at + 72
        data[p:p+16] = section.encode().ljust(16, b'\0')
        data[p+16:p+32] = segment.encode().ljust(16, b'\0')
        struct.pack_into('<QQI', data, p+32, offset, 0x8000 if at == 32 else 0x4000, offset)
        data[offset:offset+0x4000] = bytes([offset // 0x4000]) * 0x4000
    struct.pack_into('<I4s', data, 0x4004, 8, b'MOD0')
    return data


class ReferenceFramework(unittest.TestCase):
    text_ends = {'main': 0x4000}
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.path = self.root / 'old-host'
        self.path.write_bytes(host())

    def test_exact_pages_including_padding(self):
        asm = self.root / 'embed.S'
        flags, proof = fw.reference_assembly(self.path, '05', ['main'], asm, self.text_ends)
        self.assertEqual(len(proof), 2)
        self.assertEqual(proof[0]['sha256'], hashlib.sha256(host()[0x4000:0xC000]).hexdigest())
        self.assertIn('.incbin', asm.read_text())
        self.assertIn('__dmmainimg', asm.read_text())
        self.assertIn('-Wl,-segprot,__DMmainW,rw,rw', flags)

    def test_wrong_namespace_rejected(self):
        for ns in ['06', '../', '5']:
            with self.assertRaises(ValueError):
                fw.reference_assembly(self.path, ns, ['main'], self.root / 'out.S', self.text_ends)

    def test_malformed_commands_rejected(self):
        for offset, value in [(4, 0x1000007), (16, 99), (20, 0xFFFFFFFF),
                              (36, 7), (32+64, 99), (32+72+44, 0xFFFFFFFF)]:
            data = host()
            struct.pack_into('<I', data, offset, value)
            self.path.write_bytes(data)
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                fw.host_sections(self.path)

    def test_file_section_bounds_and_command_overlap(self):
        for file_offset in [16, 0xFFFFFFFF]:
            data = host()
            struct.pack_into('<I', data, 32+72+48, file_offset)
            self.path.write_bytes(data)
            with self.assertRaises(ValueError): fw.host_sections(self.path)

    def test_zero_fill_is_not_an_image(self):
        data = host()
        struct.pack_into('<I', data, 32+72+64, 1)
        self.path.write_bytes(data)
        with self.assertRaises(ValueError):
            fw.reference_assembly(self.path, '05', ['main'], self.root / 'out.S', self.text_ends)

    def test_mod0_can_be_in_aliased_data(self):
        data = host()
        struct.pack_into('<I', data, 0x4004, 0x4000)
        data[0xC000:0xC004] = b'MOD0'
        self.path.write_bytes(data)
        fw.reference_assembly(self.path, '05', ['main'], self.root / 'out.S', self.text_ends)

    def test_extra_page_before_guest_image_is_rejected(self):
        data = host()
        data[0x4000:0x4000] = bytes(0x4000)
        struct.pack_into('<Q', data, 32+72+40, 0xC000)
        struct.pack_into('<I', data, 184+72+48, 0x10000)
        self.path.write_bytes(data)
        out = self.root / 'embed.S'
        with self.assertRaisesRegex(ValueError, 'main: MOD0 offset'):
            fw.reference_assembly(self.path, '05', ['main'], out, self.text_ends)
        self.assertFalse(out.exists())


@unittest.skipUnless(sys.platform == 'darwin', 'requires the iOS linker')
class SignedFrontLayout(unittest.TestCase):
    def test_retains_front_text_and_back_bytes_with_a_separate_writable_source(self):
        page = 0x4000
        text, writable, patch, back = (bytes([i]) * page for i in range(1, 5))
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'main.patched.bin').write_bytes(text + writable + patch + back)
            (root / 'main.fixups.tsv').write_text(
                '# TEXT_END\t0x4000\n# PATCH_OFF\t-0x8000\n# FILE_IMAGE_LEN\t0x8000\n'
                '# KEY_PAGE_OFF\t0xc000\n# KEY_PAGE_SIZE\t0x4000\n# IMAGE_SIZE\t0x14000\n'
                '# BACK_OFF\t0x10000\n# BACK_LEN\t0x4000\n')
            assembly, binary = root / 'embed.S', root / 'DmGame'
            env = dict(os.environ, DM_IOS_SIGNED_FRONT='1')
            flags = subprocess.check_output([sys.executable, str(fw.TOOLS / 'gen_embed_legacy.py'),
                                             str(root), str(assembly), 'main'], env=env, text=True).split()
            subprocess.run(['xcrun', '-sdk', 'iphoneos', 'clang', '-target', 'arm64-apple-ios16.1',
                            '-dynamiclib', *flags, str(assembly), '-o', str(binary)],
                           check=True, capture_output=True)
            sections = fw.host_sections(binary)
            raw = binary.read_bytes()
            def section(seg, name):
                off, size = sections[seg, name]
                return raw[off:off+size]
            self.assertEqual(section('__TEXT', '__dmmainfar'), patch + bytes(page) + text + bytes(3 * page) + back)
            self.assertEqual(section('__DMmainW', '__img'), writable)
            self.assertEqual(section('__DATA_CONST', '__dmmainplen'), struct.pack('<Q', page))
            self.assertNotIn(('__TEXT', '__dmmainx0'), sections)



if __name__ == '__main__': unittest.main()
