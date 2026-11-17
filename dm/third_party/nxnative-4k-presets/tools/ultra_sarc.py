"""SARC archives (little-endian, as Switch / Switch 2 games ship them): unpack to {name: bytes} and repack.

Repacking keeps everything the original had before its data section byte for byte (header, SFAT node order and name hashes, SFNT name table) and only rewrites each
node's data range. A file whose size does not change keeps its exact offset; a file that grows or shrinks moves the files after it by the size difference, each rounded
up to the largest power of two (at most 0x2000) its original absolute offset was a multiple of, so every file keeps at least its original alignment. Padding is zeros.
So an archive repacked with no file changed is the original, byte for byte. Files cannot be added, removed or renamed.
"""
import struct


class SarcError(ValueError):
    pass


class Sarc:
    def __init__(self, data):
        data = bytes(data)
        if data[:4] != b'SARC': raise SarcError(f'not a SARC (magic {data[:4]!r})')
        hdr_len, bom, size, self.doff, version = struct.unpack_from('<HHIIH', data, 4)
        if bom != 0xfeff: raise SarcError('big-endian SARC: not supported')
        if size != len(data): raise SarcError(f'header size {size} != data {len(data)}')
        sfat = hdr_len
        if data[sfat:sfat + 4] != b'SFAT': raise SarcError('no SFAT')
        sfat_len, n, self.hash_key = struct.unpack_from('<HHI', data, sfat + 4)
        self.nodes = []   # [hash, attrs, begin, end, name]
        sfnt = sfat + sfat_len + 16 * n
        if data[sfnt:sfnt + 4] != b'SFNT': raise SarcError('no SFNT')
        names_at = sfnt + struct.unpack_from('<H', data, sfnt + 4)[0]
        for i in range(n):
            h, attrs, b, e = struct.unpack_from('<IIII', data, sfat + sfat_len + 16 * i)
            name = data[names_at + (attrs & 0xffffff) * 4:].split(b'\0', 1)[0].decode() if attrs >> 24 else None
            if name is not None and self.name_hash(name) != h: raise SarcError(f'{name}: hash {h:#x} does not match the name')
            self.nodes.append([h, attrs, b, e, name])
        self.raw = data
        self.by_name = {nm: i for i, nm in enumerate(self.names())}
        self.sfat_nodes_at = sfat + sfat_len
        self.trailer = len(data) - (self.doff + max((nd[3] for nd in self.nodes), default=0))

    def name_hash(self, name):
        h = 0
        for c in name.encode():
            h = (h * self.hash_key + (c if c < 0x80 else c - 0x100)) & 0xffffffff   # signed chars, as Nintendo's
        return h

    def names(self):
        return [nd[4] if nd[4] is not None else f'#{nd[0]:08x}' for nd in self.nodes]

    def files(self):
        return {name: self.raw[self.doff + nd[2]:self.doff + nd[3]] for name, nd in zip(self.names(), self.nodes)}

    def get(self, name):
        nd = self.nodes[self.by_name[name]]   # KeyError when it is not a member
        return self.raw[self.doff + nd[2]:self.doff + nd[3]]

    def repack(self, replace=None):
        """The archive with the files in replace ({name: bytes}) changed; every other byte as before (see the module's note)"""
        replace = dict(replace or {})
        names = self.names()
        unknown = set(replace) - set(names)
        if unknown: raise SarcError(f'not in the archive: {sorted(unknown)} (files cannot be added)')
        content = {nm: replace.get(nm, self.raw[self.doff + nd[2]:self.doff + nd[3]]) for nm, nd in zip(names, self.nodes)}
        order = sorted(range(len(self.nodes)), key=lambda i: (self.nodes[i][2], self.nodes[i][3]))   # data order, as the original lays it out
        def align_of(abs_off):
            a = 1
            while a < 0x2000 and abs_off % (a * 2) == 0: a *= 2
            return a
        new = {}
        cursor = 0; shift = 0
        for i in order:
            h, attrs, b, e, _ = self.nodes[i]
            body = content[names[i]]
            a = align_of(self.doff + b)
            nb = b + shift
            nb = (nb + (-(self.doff + nb)) % a) if (self.doff + nb) % a else nb
            nb = max(nb, cursor)
            nb = nb + (-(self.doff + nb)) % a
            ne = nb + len(body)
            new[i] = (nb, ne)
            shift = ne - e
            cursor = ne
        out = bytearray(self.raw[:self.doff])
        for i, (nb, ne) in new.items(): struct.pack_into('<II', out, self.sfat_nodes_at + 16 * i + 8, nb, ne)
        end = max((ne for nb, ne in new.values()), default=0)
        out += bytes(end + self.trailer)
        for i, (nb, ne) in new.items(): out[self.doff + nb:self.doff + ne] = content[names[i]]
        struct.pack_into('<I', out, 8, len(out))
        return bytes(out)
