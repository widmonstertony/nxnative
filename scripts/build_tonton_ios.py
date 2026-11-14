#!/usr/bin/env python3
"""Build and verify complete iOS IPAs with an explicit, isolated deployment target.

16/17 use the coherent classic engine/translator revision below, never a modern
shader cache with a legacy ABI. 26 uses this checkout. No inputs or saves move.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import zipfile

REPO = Path(__file__).resolve().parents[1]
CLASSIC = 'b5ac83de5c3c01ab30b3e0dbac8eaf32fe2f9b14'
TARGETS = ('16.1', '17.0', '26.0')
OVERLAY_VERSION = 2


def say(message):
    print(json.dumps({'ev': 'say', 'msg': message}), flush=True)


def classic_engine(cache):
    """Export an engine as one transaction; incomplete exports are never reused."""
    cache.mkdir(parents=True, exist_ok=True)
    target = cache / f'classic-{CLASSIC[:12]}-v{OVERLAY_VERSION}'
    with (cache / '.classic.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        stamp = target / '.tonton-engine.json'
        if stamp.is_file():
            saved = json.loads(stamp.read_text())
            if saved.get('commit') != CLASSIC or any(
                    hashlib.sha256((target / path).read_bytes()).hexdigest() != digest
                    for path, digest in saved['overlays'].items()):
                raise ValueError(f'Compatibility engine was modified: {target}; choose a new cache directory')
            return target
        if target.exists():
            raise ValueError(f'Incomplete engine directory: {target}; choose a new cache directory')
        with tempfile.TemporaryDirectory(prefix='.classic-', dir=cache) as tmp:
            root = Path(tmp)
            archive = root / 'engine.tar'
            with archive.open('wb') as output:
                subprocess.run(['git', '-C', str(REPO), 'archive', CLASSIC], stdout=output, check=True)
            with tarfile.open(archive) as tar:
                tar.extractall(root / 'engine', filter='data')
            archive.unlink()
            engine = root / 'engine'
            # These packaging-only edits leave the pinned translator, reflection,
            # ABI and runtime units intact. 16.1 shader libraries also run on 17.
            gen = engine / 'dm/ios/tools/gen_build.py'
            text = gen.read_text()
            text = text.replace("minimum = '16.1' if renderer == 'legacy' else '26.0'",
                                "minimum = os.environ.get('DM_IOS_DEPLOYMENT_TARGET', '16.1') if renderer == 'legacy' else '26.0'")
            text = text.replace("('26.0' if renderer == 'metal4' else '16.1')", 'minimum')
            text = text.replace("'MSL_MIN_iphoneos=' + minimum", "'MSL_MIN_iphoneos=16.1'")
            gen.write_text(text)
            pack = engine / 'dm/ios/tools/build_ipa.sh'
            pack.write_text(pack.read_text().replace('legacy) export DM_IOS_DEPLOYMENT_TARGET=16.1 ;;',
                'legacy) export DM_IOS_DEPLOYMENT_TARGET=${DM_IOS_DEPLOYMENT_TARGET:-16.1} ;;'))
            # The fixture compiles the production project without proprietary data.
            fixture = engine / 'dm/ios/tools/build_smoke.py'
            shutil.copyfile(REPO / 'dm/ios/tools/build_smoke.py', fixture)
            overlays = {str(p.relative_to(engine)): hashlib.sha256(p.read_bytes()).hexdigest()
                        for p in (gen, pack, fixture)}
            (engine / '.tonton-engine.json').write_text(json.dumps(
                dict(commit=CLASSIC, overlays=overlays, overlay_version=OVERLAY_VERSION), indent=2) + '\n')
            engine.rename(target)
    return target


def version(text):
    return tuple(int(x) for x in text.split('.')) + (0,) * (3 - len(text.split('.')))


def macho_minimum(header):
    """Read LC_BUILD_VERSION / LC_VERSION_MIN_IPHONEOS from an arm64 Mach-O."""
    if header[:4] != b'\xcf\xfa\xed\xfe':
        return None
    if len(header) < 32:
        raise ValueError('Truncated Mach-O header')
    _, cpu, _, kind, count, size, _, _ = struct.unpack_from('<8I', header)
    if cpu != 0x100000C or kind not in (2, 6, 8):
        return None
    if 32 + size > len(header):
        raise ValueError('Truncated Mach-O load commands')
    offset = 32
    for _ in range(count):
        command, length = struct.unpack_from('<II', header, offset)
        if length < 8 or offset + length > 32 + size:
            raise ValueError('Invalid Mach-O load command')
        if command == 0x32:
            platform, minimum = struct.unpack_from('<II', header, offset + 8)
            if platform != 2:
                raise ValueError(f'Not an iOS device binary (platform {platform})')
            return f'{minimum >> 16}.{minimum >> 8 & 255}.{minimum & 255}'
        if command == 0x25:
            minimum = struct.unpack_from('<I', header, offset + 8)[0]
            return f'{minimum >> 16}.{minimum >> 8 & 255}.{minimum & 255}'
        offset += length
    raise ValueError('iOS binary has no minimum deployment command')


def binary_minima(entry):
    """Inspect a device image or all slices of a universal executable."""
    def thin(offset):
        entry.seek(offset)
        base = entry.read(32)
        if base[:4] != b'\xcf\xfa\xed\xfe' or len(base) != 32:
            raise ValueError('Expected a 64-bit Mach-O slice')
        commands = struct.unpack_from('<I', base, 20)[0]
        if commands > 16 * 1024 * 1024:
            raise ValueError('Invalid Mach-O load command size')
        return macho_minimum(base + entry.read(commands))

    magic = entry.read(4)
    if magic == b'\xcf\xfa\xed\xfe':
        minimum = thin(0)
        return [minimum] if minimum else []
    if magic not in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        return []
    count, = struct.unpack('>I', entry.read(4))
    if not 1 <= count <= 16:
        raise ValueError('Invalid Mach-O universal slice count')
    wide = magic.endswith(b'\xbf')
    size = 32 if wide else 20
    offsets = []
    for _ in range(count):
        row = entry.read(size)
        cpu, = struct.unpack_from('>I', row)
        if cpu == 0x100000C:
            offsets.append(struct.unpack_from('>Q' if wide else '>I', row, 8)[0])
    return [minimum for offset in offsets if (minimum := thin(offset))]


def verify_ipa(ipa, minimum):
    """Check both bundle metadata and every embedded arm64 binary, not just plist."""
    with zipfile.ZipFile(ipa) as archive:
        names = archive.namelist()
        plists = [n for n in names if n.startswith('Payload/') and n.count('/') == 2 and n.endswith('/Info.plist')]
        if len(plists) != 1:
            raise ValueError('Expected exactly one top-level iOS application')
        info = plistlib.loads(archive.read(plists[0]))
        if version(info.get('MinimumOSVersion', '0')) != version(minimum):
            raise ValueError(f'MinimumOSVersion is {info.get("MinimumOSVersion")}, expected {minimum}')
        prefix = plists[0].removesuffix('Info.plist')
        binaries = {}
        for name in names:
            if name.endswith('/') or not name.startswith(prefix):
                continue
            with archive.open(name) as entry:
                minima = binary_minima(entry)
            if minima:
                deployed = max(minima, key=version)
                if version(deployed) > version(minimum):
                    raise ValueError(f'{name} needs iOS {deployed}, above selected {minimum}')
                binaries[name] = deployed
        main = prefix + info['CFBundleExecutable']
        if main not in binaries or version(binaries[main]) != version(minimum):
            raise ValueError('Main executable deployment target does not match selection')
        return dict(minimum_ios=minimum, bundle_id=info['CFBundleIdentifier'], binaries=binaries)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--minimum-ios', choices=TARGETS, required=True)
    parser.add_argument('--engine-cache', type=Path)
    parser.add_argument('--legacy-target', choices=('a10x', 'm2'), default='a10x')
    parser.add_argument('--smoke-output', type=Path, help='compile/link fixture only; no game data or playable game')
    args, forwarded = parser.parse_known_args()
    # Validate before exporting a source tree or doing any long compilation.
    if args.smoke_output:
        work = args.smoke_output.resolve()
    else:
        if '--work-dir' not in forwarded or '-o' not in forwarded:
            parser.error('complete IPA builds require --work-dir and -o')
        work = Path(forwarded[forwarded.index('--work-dir') + 1]).resolve()
        if '--shell-framework' in forwarded or '--framework' in forwarded:
            parser.error('this compatibility route exports complete IPAs, not modern shell frameworks')
    cache = args.engine_cache or work.parent / '.tonton-engines'
    engine = REPO if args.minimum_ios == '26.0' else classic_engine(cache.resolve())
    renderer = 'metal4' if args.minimum_ios == '26.0' else 'legacy'
    env = dict(os.environ, DM_IOS_RENDERER=renderer, DM_IOS_DEPLOYMENT_TARGET=args.minimum_ios,
               DM_FULL_ROMFS='1', DM_COPY_ROMFS='YES', DM_LEGACY_TARGET=args.legacy_target, PYTHONUNBUFFERED='1')
    # A previously exported engine cannot silently change halfway through a resume.
    identity = dict(engine=CLASSIC if renderer == 'legacy' else str(engine), minimum_ios=args.minimum_ios,
                    renderer=renderer, legacy_target=args.legacy_target, overlay_version=OVERLAY_VERSION)
    if not args.smoke_output:
        work.mkdir(parents=True, exist_ok=True)
        stamp = work / 'tonton-ios-target.json'
        if stamp.exists() and json.loads(stamp.read_text()) != identity:
            raise ValueError('Build target changed; select a separate work directory')
        stamp.write_text(json.dumps(identity, indent=2) + '\n')
    say(f'iOS {args.minimum_ios}: {renderer}; engine {engine}; isolated work {work}')
    if args.smoke_output:
        command = [sys.executable, '-u', str(engine / 'dm/ios/tools/build_smoke.py'), '--output', str(work)]
    else:
        if renderer == 'legacy' and '--gpu' not in forwarded:
            forwarded += ['--gpu', 'none']
        command = [sys.executable, '-u', str(engine / 'scripts/build_ipa_from_nsp.py'), *forwarded]
    # Profile headers, built-in shaders and Xcode's generated source live in
    # the engine tree; serialize only jobs sharing that classic engine.
    if renderer == 'legacy':
        with (engine / '.tonton-build.lock').open('a') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                say('Waiting for the active build using this compatibility engine')
                fcntl.flock(lock, fcntl.LOCK_EX)
            result = subprocess.run(command, cwd=engine, env=env)
    else:
        result = subprocess.run(command, cwd=engine, env=env)
    if result.returncode:
        return result.returncode
    if not args.smoke_output:
        ipa = Path(forwarded[forwarded.index('-o') + 1])
        report = verify_ipa(ipa, args.minimum_ios)
        report.update(identity, ipa=str(ipa.resolve()), game_runtime_tested=False)
        ipa.with_suffix('.build-report.json').write_text(json.dumps(report, indent=2) + '\n')
        say(f'Verified iOS {args.minimum_ios} IPA and embedded binaries: {ipa}')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, KeyError, struct.error, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f'[RED] {error}', file=sys.stderr)
        sys.exit(1)
