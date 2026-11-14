#!/usr/bin/env python3
"""Link a classic build as a TonTon independent engine, using its own profile and shader ABI."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import subprocess
import sys

from build_tonton_ios import REPO, binary_minima, version

MARKER = 'dm_game_image_marker'
EXPORTS = (MARKER, *('dm_glue_' + s for s in (
    'version', 'start_game', 'present_game', 'focus_event', 'set_catalog', 'shader_chain')))
ABI = 'tonton-independent-host-v1'


def build_framework(engine, patched, work, title, modules, minimum, name, display_version, jobs=2, env=None,
                    package_version=''):
    if not re.fullmatch(r'[0-9A-F]{16}', title) or not modules or len(set(modules)) != len(modules) or any(
            not re.fullmatch(r'[a-zA-Z][a-zA-Z0-9_]*', mod) for mod in modules):
        raise ValueError('Invalid title or module list')
    if minimum not in ('16.1', '17.0'):
        raise ValueError('Expected a classic 16.1 or 17.0 build')
    nro = patched / 'nro.tsv'
    if nro.is_file() and any(line and not line.startswith(('#', 'refused\t')) for line in nro.read_text().splitlines()):
        raise ValueError('This version of the shared loader cannot validate additional NRO modules')
    env = dict(env or os.environ, GAME=title, DM_IOS_RENDERER='legacy', DM_IOS_DEPLOYMENT_TARGET=minimum)
    ios = engine / 'dm/ios'
    host = engine / 'dm/host'
    abi = REPO / 'dm/ios/LibraryApp/Sources'
    header = engine / 'dm/gfx/nvn/dmsh_chain.h'
    chain = 'b-' + re.search(r'^#define DMSH_CHAIN "([0-9a-f]+)"', header.read_text(), re.M)[1]
    build_dir = work / 'objects'
    build_dir.mkdir(parents=True, exist_ok=True)
    # gen_build derives this from the game-specific Makefile inputs. Run under
    # the classic engine lock if sharing that snapshot with another build.
    gen = build_dir / 'gen'
    if gen.exists():
        shutil.rmtree(gen)
    config = subprocess.check_output([sys.executable, str(ios / 'tools/gen_build.py'), str(host), str(gen)],
                                     env=env, text=True)
    settings = dict(line.split(' = ', 1) for line in config.splitlines() if ' = ' in line)

    def flags(key):
        return [x for x in shlex.split(settings[key]) if x != '$(inherited)']

    srcdir = ios / 'Sources'
    srcs = [(p.resolve(), p.name) for p in sorted((gen / 'src').iterdir())]
    srcs += [(p, p.name) for p in sorted(srcdir.glob('*.m')) if p.name != 'main.m']
    srcs.append((gen / 'main/main.c', 'dm_main.c'))
    # Objective-C class registration is process-global even with RTLD_LOCAL.
    classes = {c for p, _ in srcs if p.suffix == '.m' for c in
               re.findall(r'^\s*@interface\s+(\w+)\s*:', p.read_text(), re.M)}
    glue = build_dir / 'IndependentGameGlue.m'
    glue.write_text((abi / glue.name).read_text() +
                    '\nDM_EXPORT const unsigned char dm_game_image_marker = 1;\n')
    srcs.append((glue, glue.name))
    cc = ['xcrun', '--sdk', 'iphoneos', 'clang', '-target', f'arm64-apple-ios{minimum}']
    common = ['-mcpu=apple-a10', '-O2', '-fvisibility=hidden', '-std=gnu11',
              *('-I' + d for d in flags('HEADER_SEARCH_PATHS')),
              *('-I' + str(d) for d in (srcdir, abi, host)), *flags('OTHER_CFLAGS'),
              *(f'-D{c}=TT_{title}_{c}' for c in sorted(classes)),
              f'-DDM_INDEPENDENT_GAME_TITLE="{title}"']

    def call_logged(cmd, logfile):
        with logfile.open('w') as log:
            status = subprocess.run(cmd, env=env, stdout=log, stderr=log)
        if status.returncode:
            raise RuntimeError(f'{logfile}:\n' + '\n'.join(logfile.read_text(errors='replace').splitlines()[-24:]))

    def compile_unit(item):
        source, base = item
        obj = build_dir / (base + '.o')
        opts = ['-fobjc-arc', '-fblocks'] if source.suffix == '.m' else []
        if base == 'dm_main.c':
            opts += ['-Dmain=dm_main']
        call_logged(cc + common + opts + ['-c', str(source), '-o', str(obj)], build_dir / (base + '.log'))
        return obj

    with ThreadPoolExecutor(max_workers=jobs) as pool:
        objects = list(pool.map(compile_unit, srcs))
    assembly = build_dir / 'embed.S'
    linkflags = subprocess.check_output([sys.executable, str(ios / 'tools/gen_embed.py'), str(patched),
                                        str(assembly), *modules], env=env, text=True)
    listing = build_dir / 'objects.LinkFileList'
    listing.write_text(''.join(f'{obj}\n' for obj in objects))
    framework = f'DmGame{title}.framework'
    executable = build_dir / 'DmGame'
    link = cc + ['-dynamiclib', '-fobjc-link-runtime', '-filelist', str(listing), str(assembly),
                 '-Wl,-dead_strip', f'-Wl,-install_name,@rpath/{framework}/DmGame',
                 *(f'-Wl,-exported_symbol,_{s}' for s in EXPORTS),
                 *shlex.split(linkflags), *flags('DM_FRAMEWORKS'),
                 *[arg for f in ('UIKit', 'Foundation', 'AVFoundation', 'CoreMotion', 'CoreGraphics', 'CoreText',
                                 'QuartzCore', 'GameController', 'AudioToolbox', 'VideoToolbox', 'CoreMedia',
                                 'CoreVideo', 'Metal', 'MetalKit', 'MetalFX') for arg in ('-framework', f)],
                 '-lz', '-lc++', '-o', str(executable)]
    call_logged(link, build_dir / 'link.log')
    subprocess.run([sys.executable, str(ios / 'tools/set_text_maxprot.py'), str(executable)],
                   env=env, check=True)
    exported = subprocess.check_output(['xcrun', 'nm', '-gUj', str(executable)], env=env, text=True).splitlines()
    if any('_' + symbol not in exported for symbol in EXPORTS):
        raise ValueError('Framework is missing required independent-host exports')
    with executable.open('rb') as stream:
        if [version(v) for v in binary_minima(stream)] != [version(minimum)]:
            raise ValueError('Framework does not have the selected iOS deployment target')
    staged = work / ('.' + framework)
    if staged.exists():
        shutil.rmtree(staged)
    (staged / 'dm').mkdir(parents=True)
    shutil.copy2(executable, staged / 'DmGame')
    for module in modules:
        for extension in ('fixups.tsv', 'gates.tsv', 'obs.tsv', 'cuts.tsv'):
            filename = f'{module}.{extension}'
            shutil.copyfile(patched / filename, staged / 'dm' / filename)
    (staged / 'Info.plist').write_bytes(plistlib.dumps(dict(
        CFBundleIdentifier='org.nxnative.cartridge.' + title.lower(), CFBundleName='DmGame',
        CFBundleExecutable='DmGame', CFBundlePackageType='FMWK', CFBundleVersion='1',
        CFBundleShortVersionString=display_version, MinimumOSVersion=minimum, CFBundleSupportedPlatforms=['iPhoneOS'])))
    manifest = dict(schema=1, title_id=title, name=name, display_version=display_version,
                    package_version=package_version, modules=modules,
                    framework=framework, framework_executable='DmGame', min_os=minimum, loader='FH',
                    tonton_host_abi=ABI, chain=chain, image_marker=MARKER, nro_count=0)
    (staged / 'game.manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    final = work / framework
    if final.exists():
        shutil.rmtree(final)
    staged.rename(final)
    return final


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--engine', type=Path, required=True)
    p.add_argument('--patched', type=Path, required=True)
    p.add_argument('--work', type=Path, required=True)
    p.add_argument('--title', required=True)
    p.add_argument('--modules', nargs='+', required=True)
    p.add_argument('--min-ios', required=True)
    p.add_argument('--name', required=True)
    p.add_argument('--version', required=True)
    p.add_argument('--package-version', default='')
    p.add_argument('--jobs', type=int, default=2)
    a = p.parse_args()
    print(build_framework(a.engine.resolve(), a.patched.resolve(), a.work.resolve(), a.title.upper(),
                          a.modules, a.min_ios, a.name, a.version, a.jobs, package_version=a.package_version))
