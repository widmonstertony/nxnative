#!/usr/bin/env python3
"""Read and change values in a game's BYML settings, writing the changed files into a RomFS overlay folder (nxnative's DM_ROMFS_OVERLAY reads overlay folders first).

Usage (run with python3 and the zstandard package):
  ultra.py ls    <RomFS.img> <archive path> [<inner file>] [--overlay DIR]          members of a SARC; with an inner file, every editable value in it
  ultra.py get   <RomFS.img> <archive path> <inner file> <field path> [--overlay DIR]
  ultra.py set   <RomFS.img> <archive path> <inner file> <field path> <value> [<field path> <value> ...] --overlay DIR [--shared] [--restbl]
  ultra.py apply <RomFS.img> <spec.tsv> --overlay DIR [--restbl]

  archive path  the file's RomFS path: a SARC (.sarc.zs, .pack.zs, .sarc), or a BYML itself (.bgyml, .byml.zs), compressed or not
  inner file    the member of the SARC ('-' when the archive is the BYML itself)
  field path    keys and array indexes joined by '/', e.g. LODDistanceRatio or PostProcess/IsEnableUpscale; a hash-keyed dictionary's keys as 0x-prefixed hex
  --overlay DIR the overlay folder; files go to DIR/<RomFS path>. set, get and ls start from DIR's copy when it has one, so several sets add up; apply always
                starts from the game's own files, so an overlay it builds holds exactly its spec
  --shared      allow setting a value whose node other paths share (a deduplicated BYML subtree: the change reaches them all)
  --restbl      when a rebuilt file decompresses to more than its resource size table entry, write the table with that entry raised into the overlay as well
                (without it, such an edit fails)

spec.tsv (apply): a header line, then rows of archive_path, inner_file, field_path, original, new, and optional effect, risk and flags columns (flags 'shared' = --shared).
Every row's current value must equal its original column (the spec was made for this game build), all of an archive's rows are applied in one rebuild, and every field
is read back from the written file.

Edits keep each value's type and size (in place), so the archive's other members and their offsets stay as they were and the file is compressed again like the original
(plain zstd or the game's dictionary, the same frame parameters). Before writing, the result is decompressed and parsed again and every edited value checked.
"""
import argparse
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ultra_byml   # noqa: E402
import ultra_restbl   # noqa: E402
import ultra_romfs   # noqa: E402
import ultra_sarc   # noqa: E402
import ultra_zstd   # noqa: E402

ZSTD = b'\x28\xb5\x2f\xfd'


class Archive:
    """An archive path's file, from the overlay when it holds it (and use_overlay), else from the RomFS image: its compression and whether it is a SARC"""
    def __init__(self, romfs, path, overlay=None, use_overlay=True):
        self.romfs, self.path = romfs, romfs.norm(path)
        self.overlay_file = os.path.join(overlay, self.path) if overlay else None
        self.from_overlay = bool(use_overlay and self.overlay_file and os.path.isfile(self.overlay_file))
        self.original = romfs.read(self.path)   # the frame parameters to keep come from the game's own file
        self.raw = open(self.overlay_file, 'rb').read() if self.from_overlay else self.original
        self.compressed = self.raw[:4] == ZSTD
        self.zdict = None
        if self.compressed:
            if ultra_zstd.frame_info(self.raw)['dict_id']: self.zdict = ultra_zstd.dict_for(self.path, romfs.dicts())
            self.data = ultra_zstd.decompress(self.raw, self.zdict)
        else: self.data = self.raw
        self.original_size = len(ultra_zstd.decompress(self.original, self.zdict)) if self.original[:4] == ZSTD else len(self.original)
        self.sarc = ultra_sarc.Sarc(self.data) if self.data[:4] == b'SARC' else None
        self.src = f'overlay {self.overlay_file}' if self.from_overlay else f'RomFS {self.path}'

    def member(self, inner):
        if inner in (None, '', '-'):
            if self.sarc: raise SystemExit(f'{self.path} is a SARC: name a member (ultra.py ls lists them)')
            return self.data
        if not self.sarc: raise SystemExit(f'{self.path} is not a SARC: use - as the inner file')
        try: return self.sarc.get(inner)
        except KeyError: raise SystemExit(f'{inner}: not a member of {self.path} (ultra.py ls lists them)')

    def rebuilt(self, members):
        """(file bytes, decompressed bytes) with the members in members ({inner: bytes}; '-' for the BYML itself) replaced"""
        data = self.sarc.repack(members) if self.sarc else members['-']
        if not self.compressed: return data, data
        like = self.original if self.original[:4] == ZSTD else self.raw
        return ultra_zstd.compress(data, like, self.zdict), data


def show(v):
    return repr(v) if isinstance(v, str) else str(v).lower() if isinstance(v, bool) else str(v)


def same(spec_value, value):
    """Whether a spec's text equals a parsed BYML value of the same type"""
    if isinstance(value, bool): return str(spec_value).strip().lower() in (('true', '1', 'yes', 'on') if value else ('false', '0', 'no', 'off'))
    if isinstance(value, int): return int(str(spec_value), 0) == value
    if isinstance(value, float): v = float(spec_value); return abs(v - value) <= 1e-6 * max(1.0, abs(v))
    return str(spec_value) == str(value)


class RestblCheck:
    """The game's resource size table: checks a rebuilt file's decompressed size against its entry, and writes the table when an entry was raised.
    from_overlay: start from the overlay's edited table when it has one (set); apply starts from the game's own"""
    def __init__(self, romfs, overlay, from_overlay=True):
        self.path = ultra_restbl.table_path(romfs.idx)
        self.table = None; self.changed = False
        if self.path:
            self.arc = Archive(romfs, self.path, overlay, use_overlay=from_overlay)
            self.table = ultra_restbl.Restbl(self.arc.data)

    def check(self, path, old_size, new_size, raise_entry):
        if not self.table: return 'no resource size table in this game'
        entry = self.table.get(path)
        if entry is None: return f'no RESTBL entry for {ultra_restbl.key(path)}: the game sizes it itself'
        if new_size <= entry: return f'{new_size} B decompressed <= RESTBL entry {entry} ({entry - new_size} B to spare)'
        if not raise_entry:
            raise SystemExit(f'{path}: decompresses to {new_size} B, more than its RESTBL entry {entry} in {self.path}: not written (--restbl raises the entry)')
        new_entry = new_size + max(0, entry - old_size)   # keep the headroom the game's own file had
        self.table.set(path, new_entry); self.changed = True
        return f'{new_size} B decompressed > RESTBL entry {entry}: entry raised to {new_entry}'

    def write(self):
        if not self.changed: return None
        out, _ = self.arc.rebuilt({'-': self.table.bytes()})
        back = ultra_restbl.Restbl(ultra_zstd.decompress(out, self.arc.zdict) if self.arc.compressed else out)
        if back.bytes() != self.table.bytes(): raise SystemExit('internal error: the RESTBL does not read back')
        write_file(self.arc.overlay_file, out)
        return self.arc.overlay_file


def write_file(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + '.tmp'
    with open(tmp, 'wb') as f: f.write(data)
    os.replace(tmp, path)


def edit_archive(arc, edits, restbl, raise_entry, quiet=False):
    """Apply edits [(inner, field, value, shared)] to arc in one rebuild, verify, check the RESTBL, write; returns a report line"""
    bymls = {}
    for inner, field, value, shared in edits:
        b = bymls.get(inner) or bymls.setdefault(inner, ultra_byml.Byml(arc.member(inner)))
        try: old, new = b.set(field, value, shared=shared)
        except ultra_byml.BymlError as e: raise SystemExit(f'{arc.path} {inner}: not set: {e}')
        others = b.sharers(field)
        if not quiet: print(f'  {inner} {field}: {show(old)} -> {show(new)}  ({b.type_of(field)})' + (f'; also, sharing its node: {others}' if others else ''))
    members = {inner: b.bytes() for inner, b in bymls.items()}
    for inner, data in members.items():
        if len(data) != len(arc.member(inner)): raise SystemExit(f'internal error: {inner} changed size')
    out, plain = arc.rebuilt(members)
    back = ultra_zstd.decompress(out, arc.zdict) if arc.compressed else out
    if back != plain: raise SystemExit('internal error: the compressed file does not decompress to what was written')
    bs = ultra_sarc.Sarc(back) if arc.sarc else None
    reread = {inner: ultra_byml.Byml(bs.get(inner) if bs else back) for inner in members}
    for inner, field, _, _ in edits:
        got = reread[inner].get(field)
        if got != bymls[inner].get(field): raise SystemExit(f'internal error: {inner} {field} reads back as {got!r}')
    if bs:
        changed = [n for n in arc.sarc.names() if n not in members and arc.sarc.get(n) != bs.get(n)]
        if changed: raise SystemExit(f'internal error: other members changed: {changed[:5]}')
    size_note = restbl.check(arc.path, arc.original_size, len(back), raise_entry)
    write_file(arc.overlay_file, out)
    info = ultra_zstd.frame_info(out) if arc.compressed else None
    return (f'wrote {arc.overlay_file}: {len(out)} B' + (f' (zstd, dict {info["dict_id"]}, checksum {info["has_checksum"]})' if info else ' (uncompressed)') +
            f'; {size_note}; {len(edits)} values read back from the written file; started from {arc.src}')


def read_spec(path):
    with open(path, newline='') as f:
        rows = [r for r in csv.reader(f, delimiter='\t', quoting=csv.QUOTE_NONE) if r and not r[0].startswith('#')]
    head = [h.strip() for h in rows[0]]
    need = ['archive_path', 'inner_file', 'field_path', 'original', 'new']
    if head[:5] != need: raise SystemExit(f'{path}: the header must start with {need}, not {head[:5]}')
    return [dict(zip(head, r + [''] * (len(head) - len(r)))) for r in rows[1:]]


def apply(romfs, spec, overlay, raise_entry):
    rows = read_spec(spec)
    groups = {}
    for r in rows: groups.setdefault(r['archive_path'], []).append(r)
    restbl = RestblCheck(romfs, overlay, from_overlay=False)
    print(f'{spec}: {len(rows)} rows in {len(groups)} files')
    for path, rs in groups.items():
        arc = Archive(romfs, path, overlay, use_overlay=False)
        bad, cache = [], {}
        for r in rs:
            b = cache.get(r['inner_file']) or cache.setdefault(r['inner_file'], ultra_byml.Byml(arc.member(r['inner_file'])))
            cur = b.get(r['field_path'])
            if not same(r['original'], cur): bad.append(f'{r["inner_file"]} {r["field_path"]}: the game has {show(cur)}, the spec says {r["original"]}')
        if bad: raise SystemExit(f'{path}: the spec does not match this game build:\n  ' + '\n  '.join(bad))
        print(f'{path} ({len(rs)} edits):')
        print('  ' + edit_archive(arc, [(r['inner_file'], r['field_path'], r['new'], 'shared' in r.get('flags', '').replace(' ', ',').split(',')) for r in rs], restbl, raise_entry))
    t = restbl.write()
    if t: print(f'wrote {t} (RESTBL entries raised)')


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('cmd', choices=['ls', 'get', 'set', 'apply'])
    ap.add_argument('img'); ap.add_argument('archive', help='archive path (spec.tsv for apply)')
    ap.add_argument('rest', nargs='*')
    ap.add_argument('--overlay')
    ap.add_argument('--shared', action='store_true')
    ap.add_argument('--restbl', action='store_true')
    a = ap.parse_args(argv)
    romfs = ultra_romfs.RomFS(a.img)
    if a.cmd == 'apply':
        if not a.overlay: ap.error('apply needs --overlay DIR')
        apply(romfs, a.archive, a.overlay, a.restbl)
        return 0
    arc = Archive(romfs, a.archive, a.overlay)
    if a.cmd == 'ls':
        if not a.rest:
            if not arc.sarc: raise SystemExit(f'{arc.path} is not a SARC; ls it with - to list its values')
            for name, nd in zip(arc.sarc.names(), arc.sarc.nodes): print(f'{nd[3] - nd[2]:10d}  {name}')
            return 0
        b = ultra_byml.Byml(arc.member(a.rest[0]))
        for p, t, v in b.scalars():
            sh = b.sharers(p)
            print(f'{p}\t{t}\t{show(v)}' + (f'\tshared with {len(sh)}' if sh else ''))
        return 0
    if a.cmd == 'get':
        if len(a.rest) != 2: ap.error('get takes <inner file> <field path>')
        b = ultra_byml.Byml(arc.member(a.rest[0]))
        v = b.get(a.rest[1])
        t = b.type_of(a.rest[1]); sh = b.sharers(a.rest[1])
        print(f'{a.rest[1]} = {show(v)}  ({t + ", " if t else ""}from {arc.src})' + (f'; its node is shared with {sh}' if sh else ''))
        return 0
    if len(a.rest) < 3 or len(a.rest) % 2 != 1: ap.error('set takes <inner file> <field path> <value> [<field path> <value> ...]')
    if not a.overlay: ap.error('set needs --overlay DIR')
    restbl = RestblCheck(romfs, a.overlay)
    print(edit_archive(arc, [(a.rest[0], f, v, a.shared) for f, v in zip(a.rest[1::2], a.rest[2::2])], restbl, a.restbl))
    t = restbl.write()
    if t: print(f'wrote {t} (RESTBL entry raised)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
