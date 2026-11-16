#!/usr/bin/env python3
"""Generate one signed iOS host's registry and guest sections.

Usage: library_embed.py manifest.json output_directory

The local manifest contains a `games` array of objects with `profile` (a
game.tsv directory) and `patched` (a completed NSO patch output directory).
Only generated build files are written; game assets and signing material are
never copied into the repository or the output directory.
"""
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
GAMES = HERE.parents[1] / 'games'
sys.path.insert(0, str(GAMES))
from game import Game  # noqa: E402
from runtime_profiles import generate  # noqa: E402


def main(manifest_path: Path, out: Path) -> None:
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    rows = manifest['games']
    if not rows or len(rows) > 36 * 36:
        raise ValueError('manifest needs 1..1296 game profiles')
    out.mkdir(parents=True, exist_ok=True)
    profiles = []
    parts = []
    flags = []
    alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    for index, row in enumerate(rows):
        profile = Game(Path(row['profile']))
        patched = Path(row['patched'])
        modules = profile.words('modules')
        if not modules or not patched.is_dir():
            raise ValueError(f'{profile.id}: missing modules or patched directory')
        for name in modules:
            for ext in ('.patched.bin', '.fixups.tsv'):
                if not (patched / (name + ext)).is_file():
                    raise FileNotFoundError(patched / (name + ext))
        ns = alphabet[index // 36] + alphabet[index % 36]
        asm = out / f'embed-{ns}.S'
        result = subprocess.run([
            sys.executable, str(HERE / 'gen_embed.py'), '--namespace', ns,
            str(patched), str(asm), *modules,
        ], check=True, text=True, capture_output=True)
        profiles.append(profile)
        parts.append(asm.read_text())
        flags.extend(result.stdout.split())
    generate(out, profiles)
    (out / 'embed.S').write_text('\n'.join(parts))
    (out / 'link-flags.txt').write_text(' '.join(dict.fromkeys(flags)) + '\n')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    main(Path(sys.argv[1]), Path(sys.argv[2]))
