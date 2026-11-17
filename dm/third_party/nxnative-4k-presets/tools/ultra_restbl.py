"""The resource size table (RESTBL v1, Tears of the Kingdom's format; Mario Kart World and Ocarina of Time ship one as System/Resource/ResourceSizeTable.Product.<n>.
Nin_Ounce_NVN2.rsizetable.zs, plain zstd). Each entry is the buffer size the game allocates for a file, keyed by the CRC32 of its RomFS path without the .zs
(a few colliding paths are in a name table instead). A file the game reads must decompress to no more than its entry. Files with no entry use the game's own sizing.

Layout: 'RESTBL', u32 version 1, u32 name length (160), u32 CRC entry count, u32 name entry count; CRC entries (u32 crc, u32 size) sorted by CRC; name entries
(char[name length] path, u32 size). Values are changed in place, so a table written back unchanged is the original, byte for byte.
"""
import re
import struct
import zlib


class RestblError(ValueError):
    pass


def key(path):
    p = path.lstrip('/')
    return p[:-3] if p.endswith('.zs') else p


class Restbl:
    def __init__(self, data):
        self.data = bytearray(data)
        if self.data[:6] != b'RESTBL': raise RestblError(f'not a RESTBL (magic {bytes(self.data[:6])!r})')
        self.version, self.name_len, self.ncrc, self.nname = struct.unpack_from('<IIII', self.data, 6)
        if self.version != 1: raise RestblError(f'RESTBL version {self.version} not supported')
        self.crc_at = 22
        self.name_at = self.crc_at + 8 * self.ncrc
        if self.name_at + (self.name_len + 4) * self.nname != len(self.data): raise RestblError('size does not match the header')
        self.crc = {}
        for i in range(self.ncrc):
            c, _ = struct.unpack_from('<II', self.data, self.crc_at + 8 * i)
            self.crc[c] = self.crc_at + 8 * i + 4
        self.names = {}
        for i in range(self.nname):
            at = self.name_at + (self.name_len + 4) * i
            self.names[bytes(self.data[at:at + self.name_len]).split(b'\0', 1)[0].decode()] = at + self.name_len

    def where(self, path):
        k = key(path)
        if k in self.names: return self.names[k]
        return self.crc.get(zlib.crc32(k.encode()) & 0xffffffff)

    def get(self, path):
        at = self.where(path)
        return None if at is None else struct.unpack_from('<I', self.data, at)[0]

    def set(self, path, size):
        at = self.where(path)
        if at is None: raise RestblError(f'{key(path)}: no entry (the game sizes it itself)')
        struct.pack_into('<I', self.data, at, size)

    def bytes(self):
        return bytes(self.data)


def table_path(romfs_paths):
    """The RESTBL path among a RomFS's paths: the highest Product number (an image built from a base and an update holds the update's)"""
    found = [(int(m.group(1)), p) for p in romfs_paths for m in [re.match(r'System/Resource/ResourceSizeTable\.Product\.(\d+)\..*rsizetable\.zs$', p)] if m]
    return max(found)[1] if found else None
