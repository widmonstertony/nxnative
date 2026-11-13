#!/usr/bin/env python3
"""Prepare a single verified ExeFS/RomFS version from a ZIP without a loose RomFS copy."""
import argparse
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import time
from zipfile import BadZipFile, ZipFile

from pack_dump import program_id, romfs_image


def inspect(z, prefix):
    code, dirs = {}, {(): {}}
    for item in z.infolist():
        if not item.filename.startswith(prefix + '/'):
            continue
        raw = item.filename[len(prefix) + 1:]
        parts = raw.rstrip('/').split('/')
        if not raw:
            continue
        if any(not p or p in {'.', '..'} or '\\' in p for p in parts):
            raise ValueError(f'unsafe member name: {item.filename}')
        if stat.S_ISLNK(item.external_attr >> 16):
            raise ValueError(f'link in game data: {item.filename}')
        if any(p.startswith('._') or p in {'.listing', '.DS_Store'} for p in parts):
            continue
        if parts[0] == 'exefs' and not item.is_dir():
            if len(parts) != 2 or parts[1] in code:
                raise ValueError(f'invalid or repeated ExeFS member: {item.filename}')
            code[parts[1]] = item
        if parts[0] != 'romfs':
            continue
        path = tuple(parts[1:])
        for i, name in enumerate(path):
            parent = dirs[path[:i]]
            directory = i + 1 < len(path) or item.is_dir()
            if name in parent and (not directory or parent[name] is not None):
                raise ValueError(f'repeated or conflicting RomFS member: {item.filename}')
            parent[name] = None if directory else item
            if directory:
                dirs.setdefault(path[:i+1], {})
    if not {'main', 'main.npdm'} <= code.keys() or not dirs[()]:
        raise ValueError(f'{prefix} must have matching exefs/main, exefs/main.npdm and romfs')
    return code, dirs


def pack_entries(dirs):
    entries = [[b'', (), True, 0, 0]]
    for row in entries:
        if not row[2]:
            continue
        children = sorted(dirs[row[1]].items(), key=lambda p: p[0].encode())
        row[3:5] = len(entries), len(children)
        entries.extend([name.encode(), row[1] + (name,) if item is None else item,
                        item is None, 0, 0] for name, item in children)
    return entries


def mac_capacity(path):
    # Ask Foundation for space the system can make available to an opportunistic write.
    # This does not remove snapshots or change Time Machine settings.
    swift = """import Foundation
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let v = try url.resourceValues(forKeys: [.volumeAvailableCapacityForOpportunisticUsageKey])
print(v.volumeAvailableCapacityForOpportunisticUsage ?? 0)
"""
    with tempfile.TemporaryDirectory() as tmp:
        result = subprocess.run(['xcrun', 'swift', '-module-cache-path', tmp, '-e', swift, str(path)],
                                capture_output=True, text=True, timeout=30)
        return int(result.stdout.strip()) if result.returncode == 0 else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--prefix', required=True, help='exact ZIP version folder, e.g. base or updates/327680')
    parser.add_argument('--title-id', type=lambda s: int(s, 16), required=True)
    parser.add_argument('--main-build', required=True, help='expected first 16 bytes of the NSO Build ID in hex')
    parser.add_argument('--output', type=Path, help='new prepared version directory (omit to inspect only)')
    parser.add_argument('--allow-reclaimable', action='store_true', help='consider macOS opportunistic storage capacity')
    args = parser.parse_args()
    path = args.archive.resolve()
    before = romfs_image.file_identity(path)
    prefix = args.prefix.strip('/')
    if not prefix or '..' in PurePosixPath(prefix).parts:
        parser.error('give the exact version folder inside the ZIP')
    try:
        with ZipFile(path) as z:
            code, dirs = inspect(z, prefix)
            with tempfile.TemporaryDirectory() as tmp:
                npdm = Path(tmp) / 'main.npdm'
                npdm.write_bytes(z.read(code['main.npdm']))
                title = program_id(npdm)
            with z.open(code['main']) as f:
                head = f.read(0x50)
            build = head[0x40:0x50].hex()
            if title != args.title_id or head[:4] != b'NSO0' or build != args.main_build.lower():
                raise ValueError(f'{prefix}: unexpected title {title:016X} or main Build ID {build}')
            entries = pack_entries(dirs)
            size = sum(row[1].file_size for row in entries if not row[2])
            print(f'{prefix}: {title:016X}, main {build}, {len(entries):,} RomFS entries, {size:,} bytes', flush=True)
            if args.output is None:
                return
            output = args.output.absolute()
            if output.exists():
                raise ValueError(f'output already exists: {output}')
            output.parent.mkdir(parents=True, exist_ok=True)
            free = shutil.disk_usage(output.parent).free
            minimum = size + sum(f.file_size for f in code.values()) + (10 << 30)
            capacity = max(free, mac_capacity(output.parent)) if free < minimum and args.allow_reclaimable and sys.platform == 'darwin' else free
            if capacity < minimum:
                raise ValueError(f'{capacity / (1 << 30):.1f} GiB available; need the game image plus 10 GiB free')
            print(f'{free / (1 << 30):.1f} GiB free; {capacity / (1 << 30):.1f} GiB with reclaimable capacity', flush=True)
            with tempfile.TemporaryDirectory(prefix='.zip-prep-', dir=output.parent) as tmp:
                stage = Path(tmp) / 'version'
                (stage / 'exefs').mkdir(parents=True)
                for name, member in code.items():
                    with z.open(member) as f, (stage / 'exefs' / name).open('wb') as dst:
                        shutil.copyfileobj(f, dst, 1 << 20)
                check_at, report_at = 0, time.monotonic() + 30
                def copy(member, dst):
                    nonlocal check_at, report_at
                    with z.open(member) as f:
                        while block := f.read(1 << 20):
                            pos = dst.tell()
                            if pos >= check_at:
                                if shutil.disk_usage(stage).free < (6 << 30):
                                    raise OSError('free space dropped below 6 GiB while writing the image')
                                check_at = pos + (64 << 20)
                                if time.monotonic() >= report_at:
                                    print(f'Packing: {pos / (1 << 30):.1f}/{size / (1 << 30):.1f} GiB', flush=True)
                                    report_at = time.monotonic() + 30
                            dst.write(block)
                    return member.file_size
                img = str(stage / 'romfs.img')
                part = romfs_image.write(entries, img, copy)
                if before != romfs_image.file_identity(path):
                    raise ValueError('ZIP changed during preparation')
                romfs_image.identity(part)
                os.replace(part, img)
                stage.rename(output)
                print(output)
    except (BadZipFile, ValueError, OSError, struct.error, RuntimeError, subprocess.TimeoutExpired) as e:
        parser.exit(1, f'{e}\n')


if __name__ == '__main__':
    main()
