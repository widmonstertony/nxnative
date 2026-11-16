#!/usr/bin/env python3
"""Prepare two iOS-specific HLE translation units from a verified pcrecomp pin.

The original toolkit and other platforms remain untouched. Generated retail
game C and game assets are neither read nor copied by this tool.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

PIN = 'ef3f0da6e08a8eb7a3f869273f3df071ca8d7373'


def prepare(toolkit, destination):
    toolkit = toolkit.resolve(strict=True)
    destination = destination.absolute()
    if destination.exists():
        raise ValueError('Output exists; inspect its manifest before preparing another overlay')
    originals = {}
    for name in ['gdidc.c', 'kernel32.c']:
        relative = 'runtime/win32hle/' + name
        expected = subprocess.check_output(['git', '-C', str(toolkit), 'show', PIN + ':' + relative])
        actual = (toolkit / relative).read_bytes()
        if actual != expected:
            raise ValueError(relative + ' differs from the reviewed upstream pin')
        originals[name] = actual
    gdi = originals['gdidc.c'].decode()
    start = gdi.index('const char *hle_font_file(')
    end = gdi.index('static font_t *FONT(', start)
    gdi = '#include "IOSPlatform.h"\n' + gdi[:start] + '''const char *hle_font_file(const char *face, int bold, int italic) {
    if (face) for (int i = 0; i < g_nadded; i++)
        if (!strcasecmp(g_added[i].family, face)) return g_added[i].path;
    return ra2_ios_font_file(face, bold, italic);
}
''' + gdi[end:]
    kernel = originals['kernel32.c'].decode()
    start = kernel.index('int hle_exe_path(')
    end = kernel.index('static const char g_default_cmdline', start)
    kernel = '#include "IOSPlatform.h"\n' + kernel[:start] + '''int hle_exe_path(char *out, size_t n) {
    return ra2_ios_settings_executable_path(out, n);
}
''' + kernel[end:]
    destination.mkdir(parents=True)
    for name, text in [('gdidc.c', gdi), ('kernel32.c', kernel)]:
        (destination / name).write_text(text)
    adapter = Path(__file__).resolve().parent
    for name in ['IOSPlatform.h', 'IOSPlatform.m']:
        shutil.copyfile(adapter / name, destination / name)
    manifest = dict(schema=1, platform='iOS16.1+ arm64', toolkit_pin=PIN,
                    toolkit=str(toolkit), replacement_units=['gdidc.c', 'kernel32.c'],
                    game_assets_copied=False, game_code_copied=False,
                    initialization='Call SDL_SetMainReady and ra2_ios_set_user_directory before native engine entry',
                    original_sha256={name: hashlib.sha256(data).hexdigest() for name, data in originals.items()},
                    overlay_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                    for p in destination.iterdir() if p.is_file()})
    (destination / 'ios-platform-overlay.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pcrecomp', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(prepare(args.pcrecomp, args.output), indent=2))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error) + '\n')
