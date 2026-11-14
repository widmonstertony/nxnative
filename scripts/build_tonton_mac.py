#!/usr/bin/env python3
"""Build TonTon's pinned NX2Apple frontend with its existing save transport."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]
FRONT = REPO / 'contrib/tonton/nx2apple'


def run(*args, **kwargs):
    return subprocess.check_output([str(a) for a in args], text=True, **kwargs).strip()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('app', type=Path)
    ap.add_argument('--existing', type=Path, help='optional app whose bundle identity, provisioning and icon are retained')
    ap.add_argument('--build-path', type=Path, required=True)
    ap.add_argument('--device-build-config', type=Path, help='adopt registered checkpointed device builds')
    ap.add_argument('--python', type=Path, help='local build interpreter (overrides another computer\'s layout)')
    ap.add_argument('--sign', help='optional macOS signing identity; fresh apps default to ad-hoc')
    args = ap.parse_args()
    generated = FRONT / 'Generated'
    desktop = generated / 'Desktop'
    desktop.mkdir(parents=True, exist_ok=True)
    for source in ['dm/mac/DesktopControls.swift', 'dm/mac/ControllerMap.swift', 'dm/ios/Sources/LauncherSettings.swift']:
        shutil.copyfile(REPO / source, desktop / Path(source).name)
    shutil.copyfile(FRONT / 'TonTonDesktopSettings.swift', desktop / 'TonTonDesktopSettings.swift')
    for name, source in [('Save', 'save_sync.c'), ('Cloud', 'save_cloudkit.m')]:
        folder = generated / name
        (folder / 'include').mkdir(parents=True, exist_ok=True)
        shutil.copyfile(REPO / 'dm/host' / source, folder / source)
        shutil.copyfile(REPO / 'dm/host/save_sync.h', folder / 'include/save_sync.h')
    # The broker is the same implementation used by the existing signed TonTon.
    broker = (REPO / 'dm/mac/GameboxCloud.swift').read_text()
    start = broker.index('@main\nenum GameboxMain')
    end = broker.index('\nenum GameboxCloud', start)
    (generated / 'GameboxCloud.swift').write_text(broker[:start] + broker[end:])
    exe = run('xcrun', 'swift', 'build', '--package-path', FRONT, '--scratch-path', args.build_path,
              '-c', 'release', '--product', 'NX2Apple', '--show-bin-path')
    subprocess.run(['xcrun', 'swift', 'build', '--package-path', str(FRONT), '--scratch-path', str(args.build_path),
                    '-c', 'release', '--product', 'NX2Apple', '-j', '4'], check=True)
    app = args.app.absolute()
    if app.exists():
        raise SystemExit('output already exists')
    if args.existing:
        subprocess.run(['cp', '-cR', str(args.existing), str(app)], check=True)
    else:
        (app / 'Contents/MacOS').mkdir(parents=True)
        (app / 'Contents/Resources').mkdir()
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'com.tonytan.nxgamelibrary.mac',
            'CFBundleExecutable': 'NX2Apple', 'CFBundleName': 'TonTon \u6e38\u620f\u5323',
            'CFBundleDisplayName': 'TonTon \u6e38\u620f\u5323', 'CFBundlePackageType': 'APPL',
            'LSMinimumSystemVersion': '13.0', 'NSHighResolutionCapable': True,
            'NSPrincipalClass': 'NSApplication', 'CFBundleIconFile': 'AppIcon',
        }))
    info_path = app / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    shutil.copy2(Path(exe) / 'NX2Apple', app / 'Contents/MacOS' / info['CFBundleExecutable'])
    info.update(CFBundleShortVersionString='1.5.0', CFBundleVersion='2026111307',
                TonTonFrontendCommit=json.loads((FRONT / 'UPSTREAM.json').read_text())['commit'],
                TonTonEngineSource=str(REPO),
                TonTonUpdateReport=str(args.app.absolute().parent / 'games-progress.json'),
                TonTonBuildConfig=str(Path.home() / 'Library/Application Support/TonTon Gamebox/local-mac-builds.json'),
                TonTonPython=str(REPO / 'build/toolchain/python/bin/python3'),
                TonTonXcode='/Applications/Xcode.app/Contents/Developer',
                CFBundleLocalizations=['en', 'zh-Hans', 'zh-Hant'])
    if args.python:
        # Resolving the venv's symlink loses pyvenv.cfg and its installed modules.
        info['TonTonPython'] = str(args.python.absolute())
    if args.device_build_config:
        info['TonTonDeviceBuildConfig'] = str(args.device_build_config.absolute())
        info['TonTonDeviceBuildController'] = str(REPO / 'scripts/tonton_device_builds.py')
    info_path.write_bytes(plistlib.dumps(info))
    resources = app / 'Contents/Resources'
    if not args.existing:
        sys.path.insert(0, str(REPO / 'dm/mac'))
        from pack_app import make_icns
        make_icns(REPO / 'dm/mac/GameboxIcon.png', resources / 'AppIcon.icns')
    for name in ['l10n', 'fonts']:
        shutil.copytree(FRONT / name, resources / name, dirs_exist_ok=True)
    for locale in ['zh-Hans', 'zh-Hant']:
        shutil.copytree(REPO / 'dm/mac/Localizations' / (locale + '.lproj'), resources / (locale + '.lproj'), dirs_exist_ok=True)
    tools = resources / 'tools'
    (tools / 'bin').mkdir(parents=True, exist_ok=True)
    cross = REPO / 'dm/gfx/tools/spirv_cross_bin'
    shutil.copy2(cross / 'spirv-cross', tools / 'bin/spirv-cross')
    shutil.copytree(cross / 'LICENSES', tools / 'licenses/spirv-cross', dirs_exist_ok=True)
    shutil.copy2(cross / 'LICENSE', tools / 'licenses/spirv-cross/LICENSE')
    shutil.copyfile(FRONT / 'LICENSE', resources / 'NX2Apple-LICENSE.txt')
    shutil.copyfile(FRONT / 'NOTICE', resources / 'NX2Apple-NOTICE.txt')
    if not args.existing or args.sign:
        subprocess.run(['codesign', '--force', '--sign', args.sign or '-', str(app)], check=True)
        subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
    print(app)


if __name__ == '__main__':
    main()
