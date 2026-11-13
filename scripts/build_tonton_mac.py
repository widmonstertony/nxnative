#!/usr/bin/env python3
"""Build TonTon's pinned NX2Apple frontend with its existing save transport."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

REPO = Path(__file__).resolve().parents[1]
FRONT = REPO / 'contrib/tonton/nx2apple'


def run(*args, **kwargs):
    return subprocess.check_output([str(a) for a in args], text=True, **kwargs).strip()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('app', type=Path)
    ap.add_argument('--existing', type=Path, required=True, help='retain bundle identity, provisioning and icon')
    ap.add_argument('--build-path', type=Path, required=True)
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
    subprocess.run(['cp', '-cR', str(args.existing), str(app)], check=True)
    info_path = app / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    shutil.copyfile(Path(exe) / 'NX2Apple', app / 'Contents/MacOS' / info['CFBundleExecutable'])
    info.update(CFBundleShortVersionString='1.5.0', CFBundleVersion='2026111301',
                TonTonFrontendCommit=json.loads((FRONT / 'UPSTREAM.json').read_text())['commit'],
                TonTonEngineSource=str(REPO),
                TonTonUpdateReport=str(args.app.absolute().parent / 'games-progress.json'),
                TonTonPython=str(REPO.parent / 'nxnative-mac-builds/toolchain/python/bin/python3'),
                TonTonXcode='/Applications/Xcode.app/Contents/Developer',
                CFBundleLocalizations=['en', 'zh-Hans', 'zh-Hant'])
    info_path.write_bytes(plistlib.dumps(info))
    resources = app / 'Contents/Resources'
    for name in ['l10n', 'fonts']:
        shutil.copytree(FRONT / name, resources / name, dirs_exist_ok=True)
    for locale in ['zh-Hans', 'zh-Hant']:
        shutil.copytree(REPO / 'dm/mac/Localizations' / (locale + '.lproj'), resources / (locale + '.lproj'), dirs_exist_ok=True)
    shutil.copyfile(FRONT / 'LICENSE', resources / 'NX2Apple-LICENSE.txt')
    shutil.copyfile(FRONT / 'NOTICE', resources / 'NX2Apple-NOTICE.txt')
    print(app)


if __name__ == '__main__':
    main()
