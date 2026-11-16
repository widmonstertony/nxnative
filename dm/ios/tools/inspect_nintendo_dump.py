#!/usr/bin/env python3
"""Read-only preflight for the upstream base/updates/dlc console dump layout.

This produces input metadata, never a claim that code has been compiled or a
device is supported. Encrypted NSPs must go through the existing extractor.
"""
import argparse
import json
from pathlib import Path
import re
import struct


def program_id(path):
    data = path.read_bytes()
    if len(data) < 0x80 or data[:4] != b'META':
        raise ValueError('missing or truncated NPDM header')
    offset, size = struct.unpack_from('<II', data, 0x70)
    if size < 0x18 or offset < 0x80 or offset > len(data) or size > len(data) - offset:
        raise ValueError('invalid NPDM ACI0 bounds')
    if data[offset:offset + 4] != b'ACI0':
        raise ValueError('missing ACI0 header')
    return struct.unpack_from('<Q', data, offset + 0x10)[0]


def sdk_platform(path):
    # Match upstream's SDK marker, not a file name or a guessed title ID.
    # A compressed SDK needs decompression by the real extraction pipeline;
    # absence of a readable marker is deliberately not evidence of Switch 1.
    with path.open('rb') as source:
        header = source.read(0x100)
        if len(header) < 0x100 or header[:4] != b'NSO0':
            raise ValueError('missing or truncated SDK NSO header')
        flags = struct.unpack_from('<I', header, 0xC)[0]
        offset = struct.unpack_from('<I', header, 0x20)[0]
        size = struct.unpack_from('<I', header, 0x28)[0]
        stored_size = struct.unpack_from('<I', header, 0x64)[0] if flags & 2 else size
        total = path.stat().st_size
        if offset < 0x100 or offset > total or stored_size > total - offset or size > 256 << 20:
            raise ValueError('invalid SDK read-only segment bounds')
        if flags & 2:
            return 'unknown', 'compressed_sdk_requires_extractor'
        source.seek(offset)
        rodata = source.read(size)
        if len(rodata) != size:
            raise ValueError('SDK changed during inspection')
    if b'spec: Ounce' in rodata:
        return 'switch2', 'sdk_spec_ounce'
    if b'spec: NX' in rodata:
        return 'switch', 'sdk_spec_nx'
    return 'unknown', 'no_recognized_sdk_spec'


def inspect(dump, version=None, expected=None):
    dump = Path(dump)
    if not dump.is_dir():
        raise ValueError('provide an extracted base/updates/dlc dump directory')
    title = program_id(dump / 'base/exefs/main.npdm')
    if not title or title & 0xFFF:
        raise ValueError('NPDM does not identify a base title')
    versions = {}
    updates = dump / 'updates'
    for entry in updates.iterdir() if updates.is_dir() else []:
        if entry.name.startswith('.'):
            continue
        if not entry.is_dir() or not re.fullmatch(r'[1-9][0-9]*', entry.name):
            raise ValueError('updates must have positive decimal version directories')
        versions[int(entry.name)] = entry
    selected = max(versions, default=0) if version is None else version
    if selected < 0 or (selected != 0 and selected not in versions):
        raise ValueError('requested update is absent')
    # Audit every registered version so a mixed-title input cannot silently
    # become valid merely by selecting a different update.
    for folder in [dump / 'base', *versions.values()]:
        if program_id(folder / 'exefs/main.npdm') != title:
            raise ValueError('base and update program IDs differ')
        if not (folder / 'exefs/main').is_file() or not (folder / 'romfs').is_dir():
            raise ValueError('each version requires code and its full patched RomFS')
    folder = versions[selected] if selected else dump / 'base'
    platform, evidence = sdk_platform(folder / 'exefs/sdk')
    if expected and platform != 'unknown' and platform != expected:
        raise ValueError('SDK platform conflicts with the requested platform')
    dlc = []
    dlc_root = dump / 'dlc'
    for entry in sorted(dlc_root.iterdir()) if dlc_root.is_dir() else []:
        if entry.name.startswith('.'):
            continue
        if not entry.is_dir() or not re.fullmatch(r'[0-9a-fA-F]{16}', entry.name):
            raise ValueError('DLC directory must be a 16-digit title ID')
        index = int(entry.name, 16) - title - 0x1000
        if not 0 < index <= 2000:
            raise ValueError('DLC belongs to a different base title')
        roms = [p for p in entry.glob('*/romfs') if p.is_dir()]
        if (entry / 'romfs').is_dir():
            roms.append(entry / 'romfs')
        if len(roms) != 1:
            raise ValueError('each DLC requires exactly one RomFS directory')
        dlc.append(dict(title_id=entry.name.upper(), index=index))
    return dict(schema=1, title_id=f'{title:016X}', selected_version=selected,
                available_versions=[0, *sorted(versions)], dlc=dlc,
                detected_platform=platform, platform_evidence=evidence,
                requested_platform=expected, runtime='nintendo-aot',
                status='inspected_not_compiled', device_compatibility_verified=False,
                requirements=['matching_cpu_rewrite_and_shader_chain', 'signed_guest_framework',
                              'device_gpu_and_memory_validation'] +
                (['nvn2_backend_not_integrated_in_ios_fork'] if platform == 'switch2' or
                 expected == 'switch2' else []))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dump', type=Path)
    parser.add_argument('--version', type=int)
    parser.add_argument('--expect', choices=['switch', 'switch2'])
    args = parser.parse_args()
    try:
        result = inspect(args.dump, args.version, args.expect)
    except (OSError, ValueError, struct.error) as error:
        parser.exit(1, f'{error}\n')
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
