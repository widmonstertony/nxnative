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
OVERLAY_VERSION = 6


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
            # Use the pinned engine and translator together. The target-independent
            # 16.1 legacy shader libraries also run on 17.
            gen = engine / 'dm/ios/tools/gen_build.py'
            text = gen.read_text()
            text = text.replace("minimum = '16.1' if renderer == 'legacy' else '26.0'",
                                "minimum = os.environ.get('DM_IOS_DEPLOYMENT_TARGET', '16.1') if renderer == 'legacy' else '26.0'")
            text = text.replace("('26.0' if renderer == 'metal4' else '16.1')", 'minimum')
            text = text.replace("'MSL_MIN_iphoneos=' + minimum", "'MSL_MIN_iphoneos=16.1'")
            gen.write_text(text)
            pack = engine / 'dm/ios/tools/build_ipa.sh'
            pack_text = pack.read_text().replace('legacy) export DM_IOS_DEPLOYMENT_TARGET=16.1 ;;',
                'legacy) export DM_IOS_DEPLOYMENT_TARGET=${DM_IOS_DEPLOYMENT_TARGET:-16.1} ;;')
            # Record the exact profile and passed inputs, including synthesized
            # profiles; never guess the most recent patched directory.
            hook = '\nif [ -n "${TONTON_SHARED_HOOK:-}" ]; then\n' + (
                '  "${TONTON_SHARED_PYTHON}" "$TONTON_SHARED_HOOK" build-framework'
                ' "$IOS_SOURCE/../.." "$PATCHED" "$W" "$GAME" "$DM_IOS_DEPLOYMENT_TARGET"'
                ' "$DM_DISPLAY_NAME" "$DM_APP_VERSION" "$PKG" "$ROMFS" $MODS || die "shared framework"\nfi\n')
            marker = 't "pack IPA (already-compressed game files stored, everything else deflated)"'
            if pack_text.count(marker) != 1:
                raise ValueError('Classic checkout packaging hook moved')
            companion_call = 'python3 tools/validate_shader_companions.py "$GD/$COMPANION_REQUIREMENTS" "$MSL_IOS/b-$V" "$V"'
            if pack_text.count(companion_call) != 1:
                raise ValueError('Classic profile companion check moved')
            pack_text = pack_text.replace(companion_call,
                'companion_audit=()\n'
                '    if [ "${DM_IOS_RENDERER:-legacy}" = legacy ]; then companion_audit=(--legacy-audit "$W/legacy-resource-audit.json"); fi\n'
                '    ' + companion_call + ' ${companion_audit[@]+"${companion_audit[@]}"}')
            pack.write_text(pack_text.replace(marker, hook + marker))
            # The fixture compiles the production project without proprietary data.
            fixture = engine / 'dm/ios/tools/build_smoke.py'
            shutil.copyfile(REPO / 'dm/ios/tools/build_smoke.py', fixture)
            # The classic host and its translator need the same proof and
            # layout for Z-A's array image atomic. Regenerate the chain header;
            # the unchanged MSL can still use the content-addressed Metal cache.
            additions = []
            def replace(rel, old, new):
                dst = engine / rel
                body = dst.read_text()
                if body.count(old) != 1:
                    raise ValueError(f'Classic engine overlay moved: {rel}')
                dst.write_text(body.replace(old, new))
                additions.append(dst)

            pairs = (
                ('dm/gfx/tools/dmsh_legacy_atomic.py', 'dm/gfx/tools/dmsh_legacy_atomic.py'),
                ('dm/gfx/nvn/legacy/nvn_atomic_image_record.h', 'dm/gfx/nvn/nvn_atomic_image_record.h'),
                ('dm/gfx/nvn/legacy/nvn_zero_image_shadow.h', 'dm/gfx/nvn/nvn_zero_image_shadow.h'),
                ('dm/gfx/nvn/legacy/nvn_zero_image_runtime.h', 'dm/gfx/nvn/nvn_zero_image_runtime.h'),
            )
            for rel, dest in pairs:
                shutil.copyfile(REPO / rel, engine / dest)
                additions.append(engine / dest)
            replace('dm/gfx/nvn/nvn_refl.m', '[k isEqualToString:@"img_atomic_2d"])',
                    '[k isEqualToString:@"img_atomic_2d"] || [k isEqualToString:@"img_atomic_2d_array"])')
            replace('dm/gfx/nvn/nvn_refl.m', 'r->dtt = MTLTextureType2D; r->dpf = NVN_DPF_UINT;',
                    'r->dtt = [k isEqualToString:@"img_atomic_2d_array"] ? MTLTextureType2DArray : MTLTextureType2D; r->dpf = NVN_DPF_UINT;')
            replace('dm/gfx/nvn/nvn_mtl_legacy.inc',
                    '        o->zero_image_variant = 3; o->zero_image_aid',
                    '        o->zero_image_variant = [proof[@"kind"] isEqual:@"fragment-uint-max-2d-array-v1"] ? 4 : 3;\n        o->zero_image_aid')
            replace('dm/gfx/nvn/nvn_mtl_legacy.inc',
                    'if (j[@"legacy_image_atomic"]) {\n        NSData *bytes = [NSData dataWithContentsOfFile:lp options:NSDataReadingMappedIfSafe error:nil];',
                    'if (j[@"legacy_image_atomic"]) {\n        NSData *bytes = nvn_shader_data(g_msl_dir, lp);')
            replace('dm/gfx/nvn/nvn_mtl_legacy.inc',
                    'if (record && [manifest[@"schema"] isEqual:@1] && [manifest[@"chain"] isEqual:@DMSH_CHAIN]) {\n            NSData *bytes = [NSData dataWithContentsOfFile:lp options:NSDataReadingMappedIfSafe error:nil];',
                    'if (record && [manifest[@"schema"] isEqual:@1] && [manifest[@"chain"] isEqual:@DMSH_CHAIN]) {\n            NSData *bytes = nvn_shader_data(g_msl_dir, lp);')
            replace('dm/ios/tools/prepare_legacy_resources.py',
                    "b.get('kind') == 'img_atomic_2d'", "b.get('kind') in ('img_atomic_2d', 'img_atomic_2d_array')")
            # The current build page accepts NUP alongside NSP and dump folders.
            # Backport only its validated reader; all classic build stages remain pinned.
            for rel in ('scripts/pack_nup.py', 'dm/tools/romfs_image.py', 'dm/ios/tools/validate_shader_companions.py'):
                shutil.copyfile(REPO / rel, engine / rel)
                additions.append(engine / rel)
            pipeline = 'scripts/build_ipa_from_nsp.py'
            replace(pipeline, 'import pack_dump   # a folder of a game\'s files instead of NSPs',
                    'import pack_dump   # a folder of a game\'s files instead of NSPs\nimport pack_nup')
            replace(pipeline, "    if not nsp_dir.is_dir(): raise BuildError(f'not a folder: {nsp_dir}')\n    dump = dump_folder(nsp_dir)",
                    "    nup = nsp_dir if nsp_dir.is_file() and nsp_dir.suffix.lower() == '.nup' else None\n"
                    "    if nup is None and nsp_dir.is_dir():\n"
                    "        packages = [p for p in nsp_dir.iterdir() if p.is_file() and not p.name.startswith('._')]\n"
                    "        nups = [p for p in packages if p.suffix.lower() == '.nup']\n"
                    "        if nups and not any(p.suffix.lower() in ('.nsp', '.xci', '.nsz', '.xcz') for p in packages):\n"
                    "            if len(nups) != 1: raise BuildError('Select one NUP file')\n"
                    "            nup = nups[0]\n"
                    "    if not nsp_dir.is_dir() and nup is None: raise BuildError(f'not a folder or NUP: {nsp_dir}')\n"
                    "    if nup: nsp_dir = nup.parent\n"
                    "    dump = bool(nup) or dump_folder(nsp_dir)")
            replace(pipeline, '    if dump:\n        app, fam = scan_dump(nsp_dir, int(want, 16) if want else None)',
                    "    if nup:\n"
                    "        try:\n"
                    "            n = pack_nup.Nup(nup)\n"
                    "            app, base, updates, add_ons = pack_nup.scan(n)\n"
                    "        except pack_nup.Error as e: raise BuildError(str(e)) from e\n"
                    "        if base is None: raise BuildError('Classic NUP builds need the base package')\n"
                    "        if want and int(want, 16) != app: raise BuildError('Selected title does not match the NUP')\n"
                    "        fam = dict(base=base, updates=sorted(updates.items()), dlc=[(tid, None, package) for tid, package in add_ons.items()], nup=n)\n"
                    "        say(f'NUP: {app:016X}, {len(updates)} update(s), {len(add_ons)} DLC')\n"
                    "    elif dump:\n        app, fam = scan_dump(nsp_dir, int(want, 16) if want else None)")
            replace(pipeline, "gb = (sum(tree_size((u or b) / 'romfs')[1] for b, u in picks.values()) if dump else extract_bytes(picks, False))",
                    "gb = (sum(n.tree_bytes(pack_nup.romfs_of(u or b, b)) for b, u in picks.values()) if nup else sum(tree_size((u or b) / 'romfs')[1] for b, u in picks.values()) if dump else extract_bytes(picks, False))")
            replace(pipeline, "        dirs[ver] = extract_dump(ex, ver, u or b, app) if dump else extract(nx, keys, ex, ver, b, u, None, logs, g, app)",
                    "        if nup:\n"
                    "            PROG.stage(f'unpack {ver}')\n"
                    "            dirs[ver] = ex / ver\n"
                    "            try: how = pack_nup.pack_version(n, u or b, b, app, dirs[ver], say=say)\n"
                    "            except pack_nup.Error as e: raise BuildError(str(e)) from e\n"
                    "            PROG.end(how)\n"
                    "        else: dirs[ver] = extract_dump(ex, ver, u or b, app) if dump else extract(nx, keys, ex, ver, b, u, None, logs, g, app)")
            replace(pipeline, "    if not fam['dlc']: return None\n    if fam.get('dump'):",
                    "    if not fam['dlc']: return None\n"
                    "    if fam.get('nup'):\n"
                    "        PROG.stage('pack DLC')\n"
                    "        try: pack_nup.pack_dlc(fam['nup'], app, {t: k for t, _, k in fam['dlc']}, work / 'aoc', say=say)\n"
                    "        except pack_nup.Error as e: raise BuildError(str(e)) from e\n"
                    "        PROG.end()\n        return work / 'aoc'\n"
                    "    if fam.get('dump'):")
            subprocess.run([sys.executable, str(engine / 'dm/gfx/tools/dmsh_chain.py'), '--header'], check=True, cwd=engine)
            additions.append(engine / 'dm/gfx/nvn/dmsh_chain.h')
            overlays = {str(p.relative_to(engine)): hashlib.sha256(p.read_bytes()).hexdigest()
                        for p in (gen, pack, fixture, *additions)}
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
    parser.add_argument('--existing-gamebox', type=Path, help='sign and update an existing TonTon library using this local device configuration')
    args, forwarded = parser.parse_known_args()
    # Validate before exporting a source tree or doing any long compilation.
    if args.smoke_output:
        if args.existing_gamebox:
            parser.error('smoke builds do not update devices')
        work = args.smoke_output.resolve()
    else:
        if '--work-dir' not in forwarded or '-o' not in forwarded:
            parser.error('complete IPA builds require --work-dir and -o')
        work = Path(forwarded[forwarded.index('--work-dir') + 1]).resolve()
        if '--shell-framework' in forwarded or '--framework' in forwarded:
            parser.error('use --existing-gamebox to install via the TonTon independent-host ABI')
    cache = args.engine_cache or work.parent / '.tonton-engines'
    engine = REPO if args.minimum_ios == '26.0' else classic_engine(cache.resolve())
    renderer = 'metal4' if args.minimum_ios == '26.0' else 'legacy'
    env = dict(os.environ, DM_IOS_RENDERER=renderer, DM_IOS_DEPLOYMENT_TARGET=args.minimum_ios,
               DM_FULL_ROMFS='1', DM_COPY_ROMFS='YES', DM_LEGACY_TARGET=args.legacy_target, PYTHONUNBUFFERED='1')
    # A previously exported engine cannot silently change halfway through a resume.
    identity = dict(engine=CLASSIC if renderer == 'legacy' else str(engine), minimum_ios=args.minimum_ios,
                    renderer=renderer, legacy_target=args.legacy_target, overlay_version=OVERLAY_VERSION)
    conf = None
    if args.existing_gamebox:
        if renderer != 'legacy':
            parser.error('shared compatibility installation is for iOS 16.1 and 17')
        from tonton_compatible_install import load_config, preflight
        conf = load_config(args.existing_gamebox)
        preflight(conf, args.minimum_ios, args.legacy_target)
        if '--romfs' in forwarded:
            parser.error('--existing-gamebox already selects a separate RomFS')
        # Do not include the game body a second time in the intermediate IPA.
        if '--keep-extracted' not in forwarded:
            forwarded.append('--keep-extracted')
        forwarded += ['--romfs', 'separate']
        env.update(TONTON_SHARED_HOOK=str(REPO / 'scripts/tonton_compatible_install.py'),
                   TONTON_SHARED_PYTHON=sys.executable, DM_PACK_SHADER_IMAGE='1')
    if not args.smoke_output:
        work.mkdir(parents=True, exist_ok=True)
        stamp = work / 'tonton-ios-target.json'
        if stamp.exists():
            old = json.loads(stamp.read_text())
            if old.get('overlay_version') in (2, 3, 4, 5):
                old['overlay_version'] = OVERLAY_VERSION  # Reuse work; chain and MSL cache keys control shader invalidation.
            if old != identity:
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
        if conf:
            from tonton_compatible_install import load_built_framework, prepare_shader_resources, install, stage_signed_update
            framework, romfs_sha = load_built_framework(work)
            delivery = work / 'tonton-shared-install'
            delivery.mkdir(exist_ok=True)
            with (delivery / 'install.lock').open('a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                signed = stage_signed_update(framework, conf, delivery, args.minimum_ios)
                resources = prepare_shader_resources(ipa, framework, delivery, romfs_sha)
                report['library_install'] = install(signed, resources, conf, delivery)
                say(f"TonTon gamebox updated and verified: {report['library_install']['app_version']}")
        ipa.with_suffix('.build-report.json').write_text(json.dumps(report, indent=2) + '\n')
        say(f'Verified iOS {args.minimum_ios} IPA and embedded binaries: {ipa}')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, KeyError, RuntimeError, struct.error, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f'[RED] {error}', file=sys.stderr)
        sys.exit(1)
