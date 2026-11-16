#!/usr/bin/env python3
"""Build the standalone macOS TonTon Gamebox application."""
import argparse
from pathlib import Path
import plistlib
import shutil
import sys
import tempfile

REPO = Path(__file__).resolve().parents[1]
MAC = REPO / 'dm/mac'
sys.path.insert(0, str(MAC))
from pack_app import copy_launcher_localizations, make_icns, run, swift_sources


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path, help='output .app path')
    parser.add_argument('--catalog', type=Path, help='optional JSON list of queued games with id and name')
    parser.add_argument('--icon', type=Path, help='optional existing .icns to carry into the new build')
    args = parser.parse_args()
    app = args.app.expanduser().absolute()
    if app.suffix != '.app' or app.exists():
        parser.error('output must be a new .app path')
    app.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=app.parent) as temp:
        stage = Path(temp) / app.name
        contents = stage / 'Contents'
        executable = contents / 'MacOS/TonTonGamebox'
        resources = contents / 'Resources'
        executable.parent.mkdir(parents=True)
        resources.mkdir()
        min_os = '15.0'
        sdk = run(['xcrun', '--sdk', 'macosx', '--show-sdk-path']).strip()
        host = MAC.parent / 'host'
        objs = []
        for name in ('save_sync.c', 'save_cloudkit.m'):
            obj = Path(temp) / (name + '.o')
            arc = ['-fobjc-arc'] if name.endswith('.m') else []
            run(['xcrun', '--sdk', 'macosx', 'clang', '-O2', '-isysroot', sdk,
                 '-target', f'arm64-apple-macosx{min_os}', *arc, '-c', host / name, '-o', obj])
            objs.append(obj)
        run(['xcrun', '--sdk', 'macosx', 'swiftc', '-parse-as-library', '-O', '-sdk', sdk,
             '-target', f'arm64-apple-macosx{min_os}', '-module-cache-path', Path(temp) / 'modules',
             '-swift-version', '5', MAC / 'Gamebox.swift', MAC / 'GameboxCloud.swift',
             *swift_sources(), *objs, '-framework', 'CloudKit', '-o', executable])
        if args.icon:
            shutil.copyfile(args.icon, resources / 'AppIcon.icns')
        else:
            make_icns(MAC / 'GameboxIcon.png', resources / 'AppIcon.icns')
        if args.catalog:
            shutil.copyfile(args.catalog, resources / 'GameCatalog.json')
        copy_launcher_localizations(resources)
        with (contents / 'Info.plist').open('wb') as info:
            plistlib.dump({
                'CFBundleIdentifier': 'com.tonytan.nxgamelibrary.mac',
                'CFBundleName': 'TonTon游戏匣',
                'CFBundleDisplayName': 'TonTon游戏匣',
                'CFBundleDevelopmentRegion': 'en',
                'CFBundleExecutable': executable.name,
                'CFBundleIconFile': 'AppIcon',
                'CFBundlePackageType': 'APPL',
                'CFBundleShortVersionString': '0.5',
                'CFBundleVersion': '5',
                'LSMinimumSystemVersion': min_os,
                'LSApplicationCategoryType': 'public.app-category.games',
            }, info)
        run(['codesign', '--sign', '-', stage])
        run(['codesign', '--verify', '--strict', stage])
        stage.rename(app)
    print(app)


if __name__ == '__main__':
    main()
