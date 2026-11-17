"""Files out of a game's RomFS image (nxnative's DMROMFS1 RomFS.img), through nxnative's own reader (dm/tools/romfs_image.py, imported from the checkout NXNATIVE_TOOLS
names, ~/nxnative/dm/tools by default; nothing in it is changed), and the game's zstd dictionaries (Pack/ZsDic.pack.zs, when it has one)."""
import os
import sys

TOOLS = os.path.expanduser(os.environ.get('NXNATIVE_TOOLS', '~/nxnative/dm/tools'))
if TOOLS not in sys.path: sys.path.insert(0, TOOLS)
import romfs_image   # noqa: E402  nxnative's reader
import ultra_sarc   # noqa: E402
import ultra_zstd   # noqa: E402


class RomFS:
    def __init__(self, img):
        self.img = img
        self.idx = romfs_image.read_index(img)   # {guest path: (is dir, offset, size)}
        self._dicts = None

    def norm(self, path):
        return path.lstrip('/')

    def exists(self, path):
        e = self.idx.get(self.norm(path))
        return e is not None and not e[0]

    def read(self, path):
        e = self.idx.get(self.norm(path))
        if e is None or e[0]: raise FileNotFoundError(f'{path}: not a file in {self.img}')
        with open(self.img, 'rb') as f:
            f.seek(e[1]); data = f.read(e[2])
        if len(data) != e[2]: raise IOError(f'{path}: short read')
        return data

    def dicts(self):
        """{zsdic name: bytes} from Pack/ZsDic.pack.zs (a plain-zstd SARC), or {} for a game without one (Mario Kart World)"""
        if self._dicts is None:
            self._dicts = {}
            if self.exists('Pack/ZsDic.pack.zs'):
                self._dicts = ultra_sarc.Sarc(ultra_zstd.decompress(self.read('Pack/ZsDic.pack.zs'))).files()
        return self._dicts
