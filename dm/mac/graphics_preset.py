"""Build verified preset overlays from the player's own game; never edit the input."""
import json
import importlib.util
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
RECIPES = HERE / 'graphics_presets'
TOOLS = HERE.parent / 'third_party/nxnative-4k-presets/tools'
TITLE = '0400486024DEC000'
BUILD = 'e0f3ccfaf50065ae4ea01eb5aeb13b1a'


def sources():
    return [Path(__file__), *sorted(TOOLS.glob('*.py')), *sorted(RECIPES.rglob('*.tsv'))]


def prepare(title, patched, romfs, dm):
    if title.upper() != TITLE:
        return False
    fixups = Path(patched) / 'main.fixups.tsv'
    keys = dict(line[2:].split('\t', 1) for line in fixups.read_text().splitlines()
                if line.startswith('# ') and '\t' in line)
    if keys.get('BUILD_ID', '').lower() != BUILD or keys.get('WINDOW_SIZE') != '1':
        return False
    # A directory build is still supported by the packer, but this recipe reader
    # requires the extracted DMROMFS1 image. Never guess data for a different build.
    if not Path(romfs).is_file():
        return False
    if importlib.util.find_spec('zstandard') is None:
        raise SystemExit(f'Graphics presets need zstandard in the build Python: {sys.executable} -m pip install zstandard')
    env = dict(os.environ, NXNATIVE_TOOLS=str(HERE.parent / 'tools'))
    for preset in ('high', 'ultra', '4k', '4k-tfx'):
        subprocess.run([sys.executable, str(TOOLS / 'ultra.py'), 'apply',
                        str(romfs), str(RECIPES / 'specs' / f'oot-{preset}.tsv'),
                        '--overlay', str(dm / 'graphics-presets' / preset), '--restbl'],
                       check=True, env=env)
    # Defaults run after saved choices. The UI can still select the game's own
    # scaler; an explicit player env file also retains priority.
    (dm / 'graphics-defaults.env').write_text(
        'DM_DISPLAY_BUFFER=2160\nDM_HEAP_EXTRA=1600\n'
        'DM_UPSCALER=metalfx-temporal\n'
        'DM_ROMFS_OVERLAY=@R@/dm/graphics-presets/4k-tfx\n')
    settings = dm / 'launcher.json'
    if settings.is_file():
        spec = json.loads(settings.read_text())
        row = next(row for row in spec['settings'] if row['env'] == 'DM_UPSCALER')
        assert any(option[0] == 'metalfx-temporal' for option in row['options'])
        row['default'] = 'metalfx-temporal'
        settings.write_text(json.dumps(spec, ensure_ascii=False, indent=1) + '\n')
    return True
