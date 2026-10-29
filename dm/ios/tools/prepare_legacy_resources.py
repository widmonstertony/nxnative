#!/usr/bin/env python3
"""Prepare and audit chain-matched A10X companions before packaging an IPA.

This checks resource completeness, not gameplay. Unsupported shader operations
remain explicit failures; no game shader is silently removed or relabelled.
"""
import argparse
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import re


def module(tools, name):
    spec = importlib.util.spec_from_file_location(name, tools / (name + '.py'))
    if spec is None or spec.loader is None:
        raise ImportError('Cannot load legacy resource tool: ' + name)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def prepare(source, cache, libraries, report):
    tools = source / 'dm/ios/tools'
    match = re.search(r'#define DMSH_CHAIN "([a-f0-9]+)"',
                      (source / 'dm/gfx/nvn/dmsh_chain.h').read_text())
    if match is None:
        raise ValueError('Host shader chain is missing')
    chain = match.group(1)
    if cache.name != 'b-' + chain or libraries.name != 'b-' + chain:
        raise ValueError('Cache, library and host chains must agree')
    target = os.environ.get('DM_LEGACY_TARGET', 'a10x')
    if target not in ('a10x', 'm2'):
        raise ValueError('Unknown legacy resource target: ' + target)
    # These predicates mirror nvn_mtl_legacy.inc: Apple5 layered rendering,
    # Apple4 fragment writes, and Tier2 samplers. Native texture atomics stay
    # prohibited on both targets; the compiled shadow proof is still checked.
    native_companion_kinds = {'layered-v1', 'sampler-limit-v1'} if target == 'm2' else set()
    result = {'chain': chain, 'target': target, 'required_machine': 'iPad14,6' if target == 'm2' else None,
              'gameplay_verified': False, 'issues': [], 'exports': {}, 'native_companions_not_required': []}

    def save():
        report.parent.mkdir(parents=True, exist_ok=True)
        report.write_text(json.dumps(result, indent=2) + '\n')

    build = json.loads((cache / '_b_build.json').read_text())
    result['shader_count'] = len(build)
    failed = [r for r in build if r.get('st') != 'ok']
    if failed:
        result['issues'].append({'shader_build_failures': failed})
        save()
        raise ValueError(f'{len(failed)} shader build failures; preserve diagnostics and repair before installation')
    if not build:
        raise ValueError('Empty shader build report')
    records = {}
    for record in build:
        key = record['key']
        # The report keys omit the route suffix.
        key = key if key.endswith('_b') else key + '_b'
        p = libraries / (key + '.json')
        meta = json.loads(p.read_text())
        if meta.get('chain') != chain or meta.get('key') != key:
            raise ValueError('Mismatched reflection: ' + key)
        if not (libraries / (key + '.metallib')).is_file():
            raise ValueError('Missing library: ' + key)
        if any(b.get('atomic') for b in meta.get('bindings', [])):
            result['issues'].append({'native_texture_atomics_unsupported_on_a10x': key})
        has_shadow = any(b.get('kind') == 'img_atomic_2d' for b in meta.get('bindings', []))
        if has_shadow or 'legacy_image_atomic' in meta:
            native = json.loads((cache / (key + '.json')).read_text())
            original = (cache / (key + '.metal')).read_text()
            with (libraries / (key + '.metallib')).open('rb') as stream:
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            expected = module(source / 'dm/gfx/tools', 'dmsh_legacy_atomic').reflection(original, native, digest)
            for field in ('legacy_image_atomic', 'bindings', 'entry', 'stage', 'msl_entry_kind', 'raster'):
                if field not in expected or expected[field] != meta.get(field):
                    raise ValueError('Atomic shadow proof/resource mismatch: ' + key + ' ' + field)
            result.setdefault('atomic_shadows', []).append(key)
        records[key] = meta
    if result['issues']:
        save()
        raise ValueError('Native texture atomics need a matching legacy implementation')

    exports = [
        ('export_nonpoint_sources', 'nonpoint-v1'),
        ('export_layered_sources', 'layered-v1'),
        ('export_sampler_limit_sources', 'sampler-limit-v1'),
        ('export_zero_image_sources', 'zero-image-v1'),
        ('export_legacy_atomics', 'atomic-v1'),
    ]
    for name, folder in exports:
        print('Preparing ' + folder, flush=True)
        exported = module(tools, name).export(cache, libraries, libraries / folder, chain)
        result['exports'][folder] = len(exported) if isinstance(exported, dict) else exported
        if isinstance(exported, dict):
            for key, record in exported.items():
                if record.get('supported') is False and folder in native_companion_kinds:
                    result['native_companions_not_required'].append({'shader': key, 'kind': folder})
                elif record.get('supported') is False:
                    result['issues'].append({'unsupported_companion': key, 'kind': folder,
                                             'reason': record.get('reason')})
        save()
    result['exports']['guarded-index-v1'] = module(tools, 'export_guarded_index_sources').export(
        libraries, libraries / 'guarded-index-v1', chain)
    zeros = json.loads((libraries / 'zero-image-v1/manifest.json').read_text())['shaders']
    for key, meta in records.items():
        if target == 'a10x' and meta.get('stage') == 'ps' and any(b.get('kind') == 'img' and b.get('rw')
                                           for b in meta.get('bindings', [])) and key not in zeros:
            result['issues'].append({'unproven_fragment_image_write': key})
    result['resource_checks_passed'] = not result['issues']
    save()
    if result['issues']:
        raise ValueError(f"{len(result['issues'])} unsupported A10X shader operations; see {report}")
    print('Legacy resource audit passed; gameplay remains for the user to test.', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'cache', 'libraries', 'report'):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    prepare(args.source, args.cache, args.libraries, args.report)
