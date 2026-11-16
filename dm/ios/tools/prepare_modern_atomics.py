#!/usr/bin/env python3
"""Build native image-atomic overlays for a Metal 4 host from original sources.

Legacy preparation may have replaced a shader's primary library with a shadow
buffer implementation. Never ship that replacement to the modern renderer.
Outputs go to a separate overlay; original legacy resources remain available.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def prepare(cache, libraries, output):
    output.mkdir(parents=True, exist_ok=True)
    repaired = []
    for path in sorted(libraries.glob('*.json')):
        legacy = json.loads(path.read_text())
        proof = legacy.get('legacy_image_atomic')
        if not proof:
            if any(b.get('kind', '').startswith('img_atomic') for b in legacy.get('bindings', [])):
                raise ValueError('Unproven legacy atomic: ' + path.name)
            continue
        key = legacy['key']
        if path.stem != key or Path(key).name != key:
            raise ValueError('Invalid shader key')
        source = cache / (key + '.metal')
        native = json.loads((cache / path.name).read_text())
        if hashlib.sha256(source.read_bytes()).hexdigest() != proof['original_sha256']:
            raise ValueError('Original source mismatch: ' + key)
        if native.get('chain') != legacy.get('chain') or native.get('key') != key:
            raise ValueError('Shader chain/key mismatch: ' + key)
        if not any(b.get('kind') == 'img' and b.get('atomic') for b in native['bindings']):
            raise ValueError('Native atomic reflection missing: ' + key)
        if any(b.get('kind', '').startswith('img_atomic') for b in native['bindings']):
            raise ValueError('Native reflection contains legacy pointers: ' + key)
        with tempfile.TemporaryDirectory(prefix='tonton-native-atomic-') as scratch:
            air = str(Path(scratch) / 'shader.air')
            args = ['xcrun', '-sdk', 'iphoneos', 'metal', '-c', '-std=metal3.1',
                    '-fmodules-cache-path=' + str(Path(scratch) / 'modules'),
                    '-mios-version-min=26.0', '-fmetal-math-mode=relaxed', '-fpreserve-invariance']
            subprocess.run(args + [str(source), '-o', air], check=True)
            library = output / (key + '.metallib')
            subprocess.run(['xcrun', '-sdk', 'iphoneos', 'metallib', air, '-o', str(library)], check=True)
        native.pop('chain_compiler', None)
        native['chain_metal'] = ' '.join(x for x in args if not x.startswith('-fmodules-cache-path='))
        (output / path.name).write_text(json.dumps(native, indent=1) + '\n')
        repaired.append({'key': key, 'library_sha256': hashlib.sha256(library.read_bytes()).hexdigest(),
                         'source_sha256': proof['original_sha256']})
    (output / 'modern-atomic-audit.json').write_text(json.dumps({'shaders': repaired,
        'minimum_os': '26.0', 'renderer': 'modern', 'gameplay_verified': False}, indent=2) + '\n')
    return repaired


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('cache', 'libraries', 'output'):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.cache, args.libraries, args.output), indent=2))
