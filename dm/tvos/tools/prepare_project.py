#!/usr/bin/env python3
"""Prepare an independent tvOS Xcode project from existing iOS host inputs."""
import argparse
import json
import plistlib
from pathlib import Path
import shutil
import subprocess
import re


def replace_symlink(path: Path, target: Path, *, directory: bool = False) -> None:
    """Replace regular, directory, valid, or broken prior output uniformly."""
    if path.is_symlink() or path.exists():
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        else:
            path.unlink()
    path.symlink_to(target, target_is_directory=directory)


def prepare_save_sync(gen: Path, host: Path, require_hooks: bool) -> None:
    src = gen / 'src'
    for name in ('save_cloudkit.m', 'save_sync.c'):
        replace_symlink(src / f'host__{name}', host / name)
    replace_symlink(src / 'save_sync.h', host / 'save_sync.h')
    filesystem = src / 'host__hle_fs.c'
    if not filesystem.is_file():
        if require_hooks:
            raise ValueError('Missing game filesystem source: cannot enable CloudKit safely')
        return
    fs = filesystem.read_text()
    if 'save_sync_mount(' in fs and 'save_sync_committed();' in fs:
        return
    if not require_hooks:
        return
    # Frozen Z-A builds predate save sync. Keep their ROM filesystem and guest
    # host unchanged. Install hooks only at the verified save transactions.
    base_mount = '    return mount_ex(name, dd, 0, 1);'
    device_path = '    strlcat(dd, "_device", sizeof dd);'
    commit = 'atomic_fetch_add(&g_save_commits, 1);'
    if ('DM_GAME_PROGRAM_ID' not in fs or fs.count('#include "hle.h"') != 1 or fs.count(base_mount) != 2 or fs.count(device_path) != 1 or
        fs.count(commit) != 1 or 'save_sync_mount(' in fs or 'save_sync_committed();' in fs):
        raise ValueError('Unrecognized save filesystem: regenerate prepared game inputs with the current save hooks')
    fs = fs.replace('#include "hle.h"', '#include "hle.h"\n#include <stdio.h>\n#include "save_sync.h"\n'
        'static void tv_sync_save(const char *path) {\n'
        '    char title[17]; snprintf(title, sizeof title, "%016llX", (unsigned long long)DM_GAME_PROGRAM_ID);\n'
        '    if (save_sync_mount(path, title)) die("tvOS save recovery is incomplete; will not mount %s", path);\n'
        '}\n', 1)
    # Insert before resolving the separate device path, so both mounts share the same sync root.
    fs = fs.replace(base_mount, '    tv_sync_save(dd);\n' + base_mount, 1)
    fs = fs.replace(device_path, '    tv_sync_save(dd);\n' + device_path, 1)
    fs = fs.replace(commit, commit + ' save_sync_committed();', 1)
    filesystem.unlink()
    filesystem.write_text(fs)


def prepare_preview_assets(catalog: Path, entries) -> list:
    games = []
    seen = set()
    for key, title, artwork in entries:
        key = key.lower()
        if not re.fullmatch(r'[0-9a-f]{16}', key) or key in seen or not title.strip():
            raise ValueError(f'Invalid or repeated preview title: {key}')
        seen.add(key)
        asset = catalog / f'GameboxTitle-{key}.imageset'
        asset.mkdir(parents=True, exist_ok=True)
        subprocess.run(['/usr/bin/sips', '-s', 'format', 'png', '-Z', '1280', str(Path(artwork).resolve()),
                        '--out', str(asset / 'cover.png')], check=True, capture_output=True)
        (asset / 'Contents.json').write_text('{"images":[{"idiom":"universal","filename":"cover.png"}],"info":{"author":"xcode","version":1}}\n')
        games.append({'id': key, 'title': title})
    return games


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--ios-project', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--team', required=True)
    p.add_argument('--bundle-id', default='org.nxnative.0100f43008c44000.tv')
    p.add_argument('--shader-archive-sha256', required=True)
    p.add_argument('--build-number', default='1')
    p.add_argument('--gamebox', action='store_true', help='Use the focusable TonTon game library')
    p.add_argument('--artwork', type=Path, help='Use the Mac shelf hero image in the Apple TV shelf')
    p.add_argument('--display-title', help='Localized game name for the Gamebox shelf')
    p.add_argument('--preview-game', action='append', default=[], nargs=3, metavar=('TITLE_ID', 'TITLE', 'ARTWORK'),
                   help='Show an additional game and its cover in the library without enabling launch')
    p.add_argument('--runner-title-id', help='Build a native game framework instead of a standalone TV app')
    p.add_argument('--romfs-identity', type=Path, help='Expected packed RomFS identity for a game framework')
    p.add_argument('--runner-framework', type=Path, action='append', default=[],
                   help='Embed a prepared tvOS game framework; its game must be listed with --preview-game')
    p.add_argument('--cloud-container', help='CloudKit container already authorized by the tvOS provisioning profile')
    p.add_argument('--cloud-environment', default='Development', choices=('Development', 'Production'))
    a = p.parse_args()
    if not re.fullmatch('[0-9a-f]{64}', a.shader_archive_sha256):
        p.error('--shader-archive-sha256 must be a lowercase SHA-256 digest')
    if (a.artwork or a.display_title or a.preview_game or a.runner_framework) and not a.gamebox:
        p.error('--artwork, --display-title and --preview-game require --gamebox')
    if a.runner_title_id:
        a.runner_title_id = a.runner_title_id.lower()
        if a.gamebox or a.runner_framework or not re.fullmatch('[0-9a-f]{16}', a.runner_title_id):
            p.error('--runner-title-id requires a 16-digit ID and cannot be combined with --gamebox')
        if not a.romfs_identity or not a.romfs_identity.is_file():
            p.error('--runner-title-id requires --romfs-identity')
        identity = a.romfs_identity.read_text()
        if not re.fullmatch(r'DMROMFSID1 title=' + a.runner_title_id.upper() +
                            r' version=[^ ]+ build=[^ ]+ size=[0-9]+ index=[0-9a-f]{16}\n',
                            identity, re.IGNORECASE):
            p.error('packed RomFS identity must match the runner title ID')
    elif a.romfs_identity:
        p.error('--romfs-identity requires --runner-title-id')
    tv = Path(__file__).resolve().parents[1]
    if a.cloud_container and not re.fullmatch(r'iCloud\.[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', a.cloud_container):
        p.error('expected an explicit iCloud container identifier')
    out = a.output.resolve()
    if out == a.ios_project.resolve():
        p.error('--output must differ from the prepared iOS project')
    out.mkdir(parents=True, exist_ok=True)
    gen = out / 'Gen'; gen.mkdir(exist_ok=True)
    iosgen = a.ios_project.resolve() / 'Gen'
    directories = ['src', 'main', 'dm']
    if (iosgen / 'profile').is_dir():
        directories += ['profile']
    for n in directories:
        dest = gen / n
        # These are generated inputs. Refresh them together: retaining old
        # fixup tables while embed.S points at a newer module mixes layouts.
        replacement = gen / (n + '.incoming')
        if replacement.is_symlink():
            replacement.unlink()
        elif replacement.exists():
            shutil.rmtree(replacement)
        shutil.copytree(iosgen / n, replacement, symlinks=True)
        if n == 'dm':
            # ios.env is a platform-specific production profile. A prepared
            # tvOS project must use its own writable env.txt or frontend
            # defaults, never silently inherit iPad refresh/timing settings.
            (replacement / 'env.txt').unlink(missing_ok=True)
        if dest.is_symlink():
            dest.unlink()
        elif dest.exists():
            shutil.rmtree(dest)
        replacement.rename(dest)
    prepare_save_sync(gen, tv.parent / 'host', bool(a.cloud_container))
    # Let ld own segment addresses, fixup indices and signing metadata. The
    # guest's own PC-relative references keep their original module offsets.
    original = (iosgen / 'embed.S').read_text()
    bins = {Path(s).name.removesuffix('.patched.bin'): Path(s)
            for s in re.findall(r'\.incbin "([^"]+)"', original)}
    if not bins or any(not re.fullmatch(r'(?:main|rtld|sdk|subsdk[0-9]+)', mod) for mod in bins):
        raise ValueError('tvOS needs a prepared NSO-only module layout')
    if a.romfs_identity:
        shutil.copyfile(a.romfs_identity, gen / 'dm' / 'romfs.id')
    asm, flags, address = [], [], 0x04000000 if a.runner_title_id else 0x104000000
    for mod, binary in bins.items():
        hdr = dict(line[2:].split() for line in
                   (gen / 'dm' / f'{mod}.fixups.tsv').read_text().splitlines()
                   if line.startswith('# '))
        start = (int(hdr['TEXT_END'], 16) + 0x3fff) & ~0x3fff
        patch = int(hdr['PATCH_OFF'], 16)
        size = binary.stat().st_size; end = (size + 0x3fff) & ~0x3fff
        if patch <= start or patch % 0x4000 or patch >= size:
            raise ValueError('tvOS static layout requires positive aligned PATCH_OFF')
        for seg, section, lo, hi, prot in (
            (f'__DM{mod}0', f'__dm{mod}x0', 0, start, 'rx'),
            (f'__DM{mod}D', '__data', start, patch, 'rw'),
            (f'__DM{mod}1', f'__dm{mod}x1', patch, end, 'rx')):
            attrs = ',regular,pure_instructions' if prot == 'rx' else ',regular'
            fill = min(hi, size) - lo
            asm.extend([f'.section {seg},{section}{attrs}', '.p2align 14',
                        f'.incbin "{binary}", {lo:#x}, {fill:#x}'])
            if hi - lo > fill:
                asm.append(f'.space {hi - lo - fill:#x}')
            flags.extend([f'-Wl,-segprot,{seg},{prot},{prot}',
                          f'-Wl,-segaddr,{seg},{address:#x}'])
            address += hi - lo
        address += 0x4000
    (gen / 'embed.S').write_text('\n'.join(asm) + '\n')
    config = []
    for line in (iosgen / 'dm.xcconfig').read_text().splitlines():
        if line.startswith(('CODE_SIGN_ENTITLEMENTS', 'DM_XCODE_OUTPUT_ROOT', 'OTHER_LDFLAGS', 'DM_APPICON')):
            continue
        if re.match(r'HEADER_SEARCH_PATHS\s*=', line):
            line = line.replace('=', '= "$(SRCROOT)/Gen/src" ', 1)
        if line.startswith('DM_FRAMEWORKS ='):
            line = re.sub(r' -framework (?:Cocoa|IOKit)\b', '', line)
        config.append(line)
    cloudkit = [] if any(re.match(r'DM_FRAMEWORKS\s*=.*-framework CloudKit\b', line) for line in config) else ['-framework CloudKit']
    export = ['-Wl,-exported_symbol,_TonTonTVRunner'] if a.runner_title_id else []
    config.append('OTHER_LDFLAGS = $(inherited) $(DM_FRAMEWORKS) -lz ' + ' '.join(cloudkit + flags + export))
    (gen / 'dm-tv.xcconfig').write_text('\n'.join(config) + '\n')
    from app_icon import create as create_icon
    icon = iosgen / 'Assets.xcassets/AppIcon.appiconset/icon.png'
    if not a.runner_title_id and not icon.is_file():
        raise ValueError('Prepared iOS icon artwork is missing')
    if not a.runner_title_id:
        create_icon(icon, gen / 'TVAssets.xcassets')
    if a.gamebox:
        cover = gen / 'TVAssets.xcassets' / 'GameboxFeature.imageset'
        cover.mkdir(exist_ok=True)
        if a.artwork:
            subprocess.run(['/usr/bin/sips', '-s', 'format', 'png', '-Z', '1920', str(a.artwork.resolve()),
                            '--out', str(cover / 'cover.png')], check=True, capture_output=True)
        else:
            shutil.copyfile(icon, cover / 'cover.png')
        (cover / 'Contents.json').write_text('{"images":[{"idiom":"universal","filename":"cover.png"}],"info":{"author":"xcode","version":1}}\n')
    sources = out / 'Sources'
    replace_symlink(sources, tv / 'Sources', directory=True)
    name = 'DmTVGame' + a.runner_title_id if a.runner_title_id else 'DmTV'
    if a.runner_title_id:
        a.bundle_id = f'org.nxnative.{a.runner_title_id}.tv.runtime'
    cloud_info = cloud_sign = ''
    if a.cloud_container:
        (gen / 'TV-Cloud.entitlements').write_bytes(plistlib.dumps({
            'com.apple.developer.icloud-container-identifiers': [a.cloud_container],
            'com.apple.developer.icloud-services': ['CloudKit'],
            'com.apple.developer.icloud-container-environment': a.cloud_environment,
        }))
        cloud_info = f'DMCloudSaveContainer: {a.cloud_container}'
        if not a.runner_title_id:
            cloud_sign = 'CODE_SIGN_ENTITLEMENTS: Gen/TV-Cloud.entitlements'
    localized_game = f'DMGameboxTitle: {json.dumps(a.display_title, ensure_ascii=False)}' if a.display_title else ''
    dependencies = []
    runners = {}
    preview_ids = {key.lower() for key, _, _ in a.preview_game}
    for framework in a.runner_framework:
        framework = framework.resolve()
        info = plistlib.loads((framework / 'Info.plist').read_bytes())
        title = info.get('DMGameboxRunnerTitle')
        digest = info.get('DMShaderArchiveSHA256')
        if (title not in preview_ids or title in runners or not isinstance(digest, str) or
            not re.fullmatch(r'[0-9a-f]{64}', digest) or framework.stem != 'DmTVGame' + title or
            info.get('CFBundleExecutable') != framework.stem or
            not (framework / framework.stem).is_file() or not (framework / 'dm/romfs.id').is_file()):
            raise ValueError(f'Invalid tvOS game runtime: {framework}')
        runners[title] = digest
        dependencies.append(f'      - framework: {json.dumps(str(framework))}\n        embed: true\n        link: false\n')
    deps = '    dependencies:\n' + ''.join(dependencies) if dependencies else ''
    runner_info = f'DMGameboxRunners: {json.dumps(runners)}' if runners else ''
    runner_title = f'DMGameboxRunnerTitle: "{a.runner_title_id}"' if a.runner_title_id else ''
    flags = '$(inherited) -mcpu=apple-a15'
    if a.runner_title_id:
        flags += f' -DDM_TV_RUNNER=1 -DDM_TV_RUNNER_TITLE=\\\"{a.runner_title_id}\\\"'
    asset_source = '' if a.runner_title_id else '- path: Gen/TVAssets.xcassets'
    app_icon = '' if a.runner_title_id else 'ASSETCATALOG_COMPILER_APPICON_NAME: App Icon & Top Shelf Image'
    scene = '' if a.runner_title_id else """
        UIApplicationSceneManifest:
          UIApplicationSupportsMultipleScenes: false
          UISceneConfigurations:
            UIWindowSceneSessionRoleApplication:
              - UISceneConfigurationName: Default
                UISceneDelegateClassName: TVSceneDelegate"""
    previews = prepare_preview_assets(gen / 'TVAssets.xcassets', a.preview_game)
    preview_info = f'DMGameboxPreviews: {json.dumps(previews, ensure_ascii=False)}' if previews else ''
    (out / 'project.yml').write_text(f'''name: {name}
configFiles:
  Release: Gen/dm-tv.xcconfig
  Debug: Gen/dm-tv.xcconfig
targets:
  {name}:
    type: {'framework' if a.runner_title_id else 'application'}
    platform: tvOS
    deploymentTarget: '17.0'
    sources:
      - path: Sources
      - path: Gen/src
      - path: Gen/main/main.c
        compilerFlags: -Dmain=dm_main
      {asset_source}
      - path: Gen/embed.S
      - path: Gen/dm
        type: folder
        buildPhase: resources
{deps}    info:
      path: Gen/TV-Info.plist
      properties:
        CFBundleDisplayName: {'TonTon 游戏匣' if a.gamebox else 'Pokémon Legends Z-A'}
        {'DMGameboxTV: true' if a.gamebox or a.runner_title_id else ''}
        {localized_game}
        {preview_info}
        {runner_info}
        {runner_title}
        {cloud_info}
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        DMLanguage: zh-CN
        DMShaderArchiveSHA256: '{a.shader_archive_sha256}'
        GCSupportsControllerUserInteraction: true
        GCSupportedGameControllers:
          - ProfileName: ExtendedGamepad
          - ProfileName: MicroGamepad
{scene}
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: {a.bundle_id}
      PRODUCT_NAME: {name}
      DEFINES_MODULE: NO
      MARKETING_VERSION: '2.0.2'
      CURRENT_PROJECT_VERSION: '{a.build_number}'
      {app_icon}
      DEVELOPMENT_TEAM: {a.team}
      CODE_SIGN_STYLE: Automatic
      {cloud_sign}
      ENABLE_USER_SCRIPT_SANDBOXING: NO
      CLANG_ENABLE_OBJC_ARC: YES
      GCC_C_LANGUAGE_STANDARD: gnu11
      OTHER_CFLAGS: {flags}
      GCC_WARN_INHIBIT_ALL_WARNINGS: YES
      ENABLE_BITCODE: NO
      DEBUG_INFORMATION_FORMAT: dwarf
schemes:
  {name}:
    build:
      targets:
        {name}: all
    run:
      config: Release
''')
    subprocess.run(['xcodegen', 'generate', '--spec', str(out / 'project.yml')], check=True, cwd=out)
    print(out / (name + '.xcodeproj'))


if __name__ == '__main__':
    main()
