"""dm/tools/nacp.py's titles: name() (the first non-empty one, the app name) and names() (each language's, the Mac app's DMTitleNames), from a plain and from a compressed title area,
with entries that are empty, not UTF-8 or not printable left out."""
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import nacp

CODES = [c for c, _ in nacp.LANGUAGES]


def title_area(titles, entries=16):   # 0x300 bytes per language: name 0x200 + publisher 0x100
    t = bytearray(0x300 * entries)
    for code, n in titles.items():
        i = CODES.index(code) if isinstance(code, str) else code
        t[i * 0x300:i * 0x300 + len(n)] = n; t[i * 0x300 + 0x200:i * 0x300 + 0x203] = b'Pub'
    return bytes(t)


def plain(titles):
    return title_area(titles) + bytes(0x1000)


def compressed(titles):   # newer SDKs: a u16 size + raw deflate of 32 entries
    z = zlib.compressobj(9, zlib.DEFLATED, -15); area = z.compress(title_area(titles, 32)) + z.flush()
    b = bytearray(0x4000); struct.pack_into('<H', b, 0, len(area)); b[2:2 + len(area)] = area
    return bytes(b)


class Titles(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory(); self.addCleanup(self.dir.cleanup)

    def nacp(self, data):
        p = Path(self.dir.name) / 'control.nacp'; p.write_bytes(data); return p

    def test_names_by_language(self):
        titles = {'en-US': b'The Game', 'ja': 'ザ・ゲーム'.encode(), 'ko': '더 게임'.encode(), 'zh-Hant': '遊戲'.encode(), 'zh-Hans': '游戏'.encode()}
        for make in (plain, compressed):
            with self.subTest(make.__name__):
                p = self.nacp(make(titles))
                self.assertEqual(nacp.names(p), {'en-US': 'The Game', 'ja': 'ザ・ゲーム', 'ko': '더 게임', 'zh-Hant': '遊戲', 'zh-Hans': '游戏'})
                self.assertEqual(nacp.name(p), 'The Game')

    def test_first_title_names_the_app(self):   # a game without American English: the first non-empty entry
        p = self.nacp(plain({'ja': 'ザ・ゲーム'.encode(), 'ko': '더 게임'.encode()}))
        self.assertEqual(nacp.name(p), 'ザ・ゲーム')

    def test_bad_entries_left_out(self):   # an entry that is not UTF-8 or not printable is not a name; the others still are
        p = self.nacp(plain({'en-US': b'\xff\xfe', 'fr': b'Le\x01Jeu', 'de': b'Das Spiel'}))
        self.assertEqual(nacp.names(p), {'de': 'Das Spiel'})
        self.assertEqual(nacp.name(p), '')   # as before: the first non-empty entry decides

    def test_entries_beyond_the_known_languages(self):   # a compressed area has 32 entries: the 16 after LANGUAGES name no language the launcher knows
        p = self.nacp(compressed({'en-US': b'Game', 20: b'Other'}))
        self.assertEqual(nacp.names(p), {'en-US': 'Game'})

    def test_missing_or_short(self):
        self.assertEqual((nacp.names(Path(self.dir.name) / 'none.nacp'), nacp.name(Path(self.dir.name) / 'none.nacp')), ({}, ''))
        self.assertEqual(nacp.names(self.nacp(b'')), {})
        self.assertEqual(nacp.names(self.nacp(b'\0' * 0x4000)), {})


if __name__ == '__main__':
    unittest.main()
