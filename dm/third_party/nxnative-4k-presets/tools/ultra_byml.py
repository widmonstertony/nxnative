"""BYML (versions 2 to 7, little-endian "YB"; big-endian "BY" too): parse to Python values, and edit values in place.

parse() returns the tree as Python objects (dict, list, str, int, float, bool, None, bytes) and records where each scalar sits in the file. Byml.set() changes one
value without moving anything: int, uint, bool and float are patched in their 4 bytes (int64, uint64 and double in their 8 bytes elsewhere in the file); a string is set
to another string that the file's string table already holds (its index changes). Byml.bytes() is the file with those patches, so a file with no change set is the
original, byte for byte. A change that needs the file to grow (a new string, a new key, another type, a longer array) is refused: rebuilding a BYML moves its nodes, and
the game's resource size table may then be wrong.

Deduplicated subtrees: a BYML may point several containers at one node (Ocarina of Time's ModelSceneExtensionParam shares dynamic-resolution levels between two
palettes). Such a value has one slot and several paths; sharers(path) names the others, and set() refuses it unless shared=True, as the change reaches them all.

Paths name a value from the root: keys and array indexes joined by '/', e.g. 'PostProcess/IsEnableUpscale' or 'List/0/Value'. A hash-keyed dictionary's keys are
written as 0x-prefixed hex.
"""
import struct

T_STR, T_BIN, T_BIN_ALIGNED, T_ARRAY, T_DICT, T_STRTAB, T_HASH32, T_HASH64 = 0xA0, 0xA1, 0xA2, 0xC0, 0xC1, 0xC2, 0x20, 0x21
T_BOOL, T_INT, T_FLOAT, T_UINT, T_INT64, T_UINT64, T_DOUBLE, T_NULL = 0xD0, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xFF
CONTAINERS = (T_ARRAY, T_DICT, T_HASH32, T_HASH64)
TYPE_NAMES = {T_STR: 'string', T_BIN: 'binary', T_BIN_ALIGNED: 'binary', T_ARRAY: 'array', T_DICT: 'dict', T_HASH32: 'hash32 dict', T_HASH64: 'hash64 dict',
              T_BOOL: 'bool', T_INT: 'int', T_FLOAT: 'float', T_UINT: 'uint', T_INT64: 'int64', T_UINT64: 'uint64', T_DOUBLE: 'double', T_NULL: 'null'}


class BymlError(ValueError):
    pass


class Byml:
    def __init__(self, data):
        self.data = bytearray(data)
        if self.data[:2] == b'YB': self.e = '<'
        elif self.data[:2] == b'BY': self.e = '>'
        else: raise BymlError(f'not a BYML (magic {bytes(self.data[:2])!r})')
        self.version, self.keys_off, self.strs_off, self.root_off = struct.unpack_from(self.e + 'HIII', self.data, 2)
        if not 2 <= self.version <= 7: raise BymlError(f'BYML version {self.version} not supported')
        self.keys = self._strtab(self.keys_off)
        self.strs = self._strtab(self.strs_off)
        self.slots = {}   # path -> (type, where the value is: the 4-byte slot, or the 8-byte value for 64-bit types)
        self.tree = None if not self.root_off else self._node(self.data[self.root_off], self.root_off, '', top=True)

    def _u24(self, off): b = self.data[off:off + 3]; return int.from_bytes(b, 'little' if self.e == '<' else 'big')
    def _u32(self, off): return struct.unpack_from(self.e + 'I', self.data, off)[0]

    def _strtab(self, off):
        if not off: return []
        if self.data[off] != T_STRTAB: raise BymlError(f'string table expected at {off:#x}')
        n = self._u24(off + 1)
        offs = [self._u32(off + 4 + 4 * i) for i in range(n + 1)]
        return [bytes(self.data[off + offs[i]:off + offs[i + 1]]).split(b'\0', 1)[0].decode('utf-8') for i in range(n)]

    def _value(self, t, slot, path):
        """The value of a non-container node of type t whose 4-byte slot is at slot"""
        raw = self._u32(slot)
        if t == T_STR: self.slots[path] = (t, slot); return self.strs[raw]
        if t == T_BOOL: self.slots[path] = (t, slot); return bool(raw)
        if t == T_INT: self.slots[path] = (t, slot); return struct.unpack_from(self.e + 'i', self.data, slot)[0]
        if t == T_UINT: self.slots[path] = (t, slot); return raw
        if t == T_FLOAT: self.slots[path] = (t, slot); return struct.unpack_from(self.e + 'f', self.data, slot)[0]
        if t in (T_INT64, T_UINT64, T_DOUBLE):
            self.slots[path] = (t, raw)
            return struct.unpack_from(self.e + {T_INT64: 'q', T_UINT64: 'Q', T_DOUBLE: 'd'}[t], self.data, raw)[0]
        if t == T_NULL: return None
        if t == T_BIN: n = self._u32(raw); return bytes(self.data[raw + 4:raw + 4 + n])
        if t == T_BIN_ALIGNED: n = self._u32(raw); return bytes(self.data[raw + 8:raw + 8 + n])
        raise BymlError(f'{path or "/"}: node type {t:#x} not supported')

    def _child(self, t, slot, path):
        return self._node(t, self._u32(slot), path) if t in CONTAINERS else self._value(t, slot, path)

    def _node(self, t, off, path, top=False):
        if self.data[off] != t: raise BymlError(f'{path or "/"}: node at {off:#x} is {self.data[off]:#x}, expected {t:#x}')
        n = self._u24(off + 1)
        j = (path + '/') if path else ''
        if t == T_ARRAY:
            types = self.data[off + 4:off + 4 + n]
            vals = off + 4 + ((n + 3) & ~3)
            return [self._child(types[i], vals + 4 * i, f'{j}{i}') for i in range(n)]
        if t == T_DICT:
            out = {}
            for i in range(n):
                e = off + 4 + 8 * i
                k = self.keys[self._u24(e)]; ct = self.data[e + 3]
                out[k] = self._child(ct, e + 4, j + k)
            return out
        if t in (T_HASH32, T_HASH64):
            w = 8 if t == T_HASH32 else 12
            types_at = off + 4 + w * n
            out = {}
            for i in range(n):
                e = off + 4 + w * i
                h = struct.unpack_from(self.e + ('I' if t == T_HASH32 else 'Q'), self.data, e)[0]
                k = f'0x{h:x}'
                out[k] = self._child(self.data[types_at + i], e + w - 4, j + k)
            return out
        raise BymlError(f'{path or "/"}: container type {t:#x} not supported')

    def _walk(self, path):
        """The steps (keys or indexes) path names from the root. A dictionary key may itself contain '/' (scene paths): the shortest run of parts that is a key wins"""
        parts = [p for p in path.split('/') if p]
        node, steps, i = self.tree, [], 0
        while i < len(parts):
            if isinstance(node, list):
                k = int(parts[i]); node = node[k]; steps.append(k); i += 1; continue
            if not isinstance(node, dict): raise KeyError(f'{path}: {parts[i]!r} is inside a {type(node).__name__}')
            for j in range(i + 1, len(parts) + 1):
                k = '/'.join(parts[i:j])
                if k in node: break
            else: raise KeyError(f'{path}: no key {parts[i]!r} (have {sorted(node)[:20]})')
            node = node[k]; steps.append(k); i = j
        return steps

    def get(self, path):
        node = self.tree
        for k in self._walk(path): node = node[k]
        return node

    def type_of(self, path):
        s = self.slots.get(path.strip('/'))
        return TYPE_NAMES[s[0]] if s else None

    def sharers(self, path):
        """The other paths whose value is the same bytes as path's (a deduplicated subtree)"""
        path = path.strip('/')
        if path not in self.slots: return []
        if getattr(self, '_by_slot', None) is None:
            self._by_slot = {}
            for p, (_, a) in self.slots.items(): self._by_slot.setdefault(a, []).append(p)
        return [p for p in self._by_slot[self.slots[path][1]] if p != path]

    def set(self, path, value, shared=False):
        """Change one scalar in place; returns (old, new). A value other paths share (sharers) needs shared=True, and changes them all"""
        path = path.strip('/')
        if path not in self.slots: raise BymlError(f'{path}: not an editable value here (a container, null or binary, or no such path)')
        others = self.sharers(path)
        if others and not shared: raise BymlError(f'{path}: its node is shared with {others[:4]}{" …" if len(others) > 4 else ""}; an in-place change sets them all (--shared to accept)')
        t, at = self.slots[path]
        old = self.get(path)
        if t == T_STR:
            v = str(value)
            if v not in self.strs: raise BymlError(f'{path}: {v!r} is not in the string table (the file would have to grow)')
            struct.pack_into(self.e + 'I', self.data, at, self.strs.index(v))
        elif t == T_BOOL:
            v = value if isinstance(value, bool) else str(value).lower() in ('1', 'true', 'yes', 'on')
            if not isinstance(value, bool) and str(value).lower() not in ('0', '1', 'true', 'false', 'yes', 'no', 'on', 'off'): raise BymlError(f'{path}: bool expected, got {value!r}')
            struct.pack_into(self.e + 'I', self.data, at, int(v))
        elif t in (T_INT, T_UINT, T_INT64, T_UINT64):
            v = int(value, 0) if isinstance(value, str) else int(value)
            fmt = {T_INT: 'i', T_UINT: 'I', T_INT64: 'q', T_UINT64: 'Q'}[t]
            try: struct.pack_into(self.e + fmt, self.data, at, v)
            except struct.error: raise BymlError(f'{path}: {v} does not fit a {TYPE_NAMES[t]}') from None
        elif t in (T_FLOAT, T_DOUBLE):
            v = float(value)
            struct.pack_into(self.e + ('f' if t == T_FLOAT else 'd'), self.data, at, v)
            if t == T_FLOAT: v = struct.unpack_from(self.e + 'f', self.data, at)[0]
        else: raise BymlError(f'{path}: type {t:#x} not editable')
        for p in [path] + others: self._set_tree(p, v if t != T_STR else str(value))
        return old, self.get(path)

    def _set_tree(self, path, v):
        steps = self._walk(path); node = self.tree
        for k in steps[:-1]: node = node[k]
        node[steps[-1]] = v

    def bytes(self):
        return bytes(self.data)

    def scalars(self):
        """[(path, type name, value)] of every editable value, in file order of their paths"""
        return [(p, TYPE_NAMES[t], self.get(p)) for p, (t, _) in self.slots.items()]
