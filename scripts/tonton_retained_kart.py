"""Build the audited MKW v0 cartridge for the existing iPadOS 16.1 library.

Keep the deployed classic host and its shader chain together. The live game
data is only read for verification; the signed update contains no game image.
"""
import hashlib
import json
from pathlib import Path
import re
import struct
import zipfile
import os

from build_tonton_ios import REPO, binary_minima, say
from tonton_compatible_install import (
    Bridge, Q, check, command, install, sha, stage_signed_update, verify_device,
)

TITLE = '0400C3F00006E000'
BUILD = '9e244438c3d8ef1c703a6a85ef99c4f0'
CONTRACT = 'b88c9e5f457cf0954b7b52ccc4b72b0259da903c8d2cab782b0e5ff99d49d35d'
CHAIN = f'b-{CONTRACT[:12]}'
INPUTS = 'acf8841f2327'
FRAMEWORK = f'DmGame{TITLE}.framework'
SITES = ((0x415690, 0xbd01b260), (0x4156a0, 0xbd01b660))


def branch(site, target):
    delta = target - site
    check(delta % 4 == 0 and -(1 << 27) <= delta < (1 << 27), 'Invalid branch range')
    return 0x14000000 | ((delta // 4) & 0x3ffffff)


def build_kart_framework(baseline, work):
    from tonton_compatible_install import inspect_app
    import sys
    sys.path.insert(0, str(REPO / 'dm/ios/tools'))
    from build_game_framework import host_sections

    with zipfile.ZipFile(baseline) as archive:
        prefix, original = inspect_app(archive)
        check(original['MinimumOSVersion'] == '16.1', 'Choose the iPadOS 16.1 classic shell')
        path = prefix + 'Frameworks/' + FRAMEWORK + '/'
        entries = [n for n in archive.namelist() if n.startswith(path) and not n.endswith('/')]
        check(entries and all(re.fullmatch(r'[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*', n)
                              and not {'..', '.'}.intersection(n.split('/')) for n in entries),
              'The baseline does not contain the expected classic cartridge')
        for n in entries:
            archive.extract(n, work)
    fw = work / path
    manifest = json.loads((fw / 'game.manifest.json').read_text())
    required = dict(title_id=TITLE, package_version='v0', chain=CHAIN, shader_contract_sha256=CONTRACT,
                    min_os='16.1', tonton_host_abi='tonton-signed-text-v1', modules=['main', 'subsdk0', 'sdk'])
    check(all(manifest.get(key) == value for key, value in required.items()), 'Unsupported Kart engine or shader contract')
    check(f'# BUILD_ID\t{BUILD}' in (fw / 'dm/main.fixups.tsv').read_text().splitlines(), 'Unsupported Kart guest build')
    executable = fw / 'DmGame'
    with executable.open('rb') as stream:
        check(binary_minima(stream) == ['16.1.0'], 'The retained cartridge is not an iPadOS 16.1 build')
    offset, size = host_sections(executable)['__TEXT', '__dmmainimg']
    check((offset, size) == (0x4000, 0x36d4000), 'Kart guest segment layout changed')
    with executable.open('r+b') as stream:
        def read(at, count):
            stream.seek(offset + at)
            return stream.read(count)

        for address, word in ((0x99e144, 0xd280a008), (0x99e148, 0xf2c05a08),
                              (0xc10104, 0xd280a008), (0xc10110, 0xf2c05a08)):
            check(read(address, 4) == struct.pack('<I', word), 'The game viewport defaults differ')
        variants = []
        changes = []
        # Keep the UI/compositor at its own extent; scale only the computed
        # scene width and height to 0.75 of the game's local 720p extents.
        for i, (site, store) in enumerate(SITES):
            stub = size - 128 + i * 32
            instruction = struct.pack('<I', branch(site, stub))
            buffer = struct.pack('<8I', 0xadbf7fe0, 0x1e2d101f, 0x1e3f0800, store,
                                 0xacc17fe0, branch(stub + 20, site + 4), 0, 0)
            prior = (read(site, 4), read(stub, 32))
            if prior == (struct.pack('<I', store), bytes(32)):
                variants.append('720p')
            elif prior == (instruction, buffer):
                variants.append('540p')
            else:
                raise ValueError('Kart scene-scale instructions do not match the audited build')
            changes += [(site, instruction), (stub, buffer)]
        check(len(set(variants)) == 1, 'Kart baseline contains a partial scene-size patch')
        for address, data in changes:
            stream.seek(offset + address)
            stream.write(data)
    return fw, variants[0]


def verify_retained_resources(bridge, scope, target, framework, conf):
    manifest = json.loads((framework / 'game.manifest.json').read_text())
    shader = target + '/msl/' + CHAIN
    check(bridge.run(f'test -d {Q(shader)} && test ! -L {Q(shader)} && cat {Q(shader + "/inputs.tsv")}').splitlines()[-2:]
          == [f'game\t{TITLE}', f'inputs\t{INPUTS}'], 'The device lacks the audited Kart shader set')
    tables = framework / 'dm'
    probes = []
    for module in manifest['modules']:
        for suffix in ('fixups', 'gates', 'obs', 'cuts'):
            name = f'{module}.{suffix}.tsv'
            digest = hashlib.sha256((tables / name).read_bytes()).hexdigest()
            source = Q(target + '/dm/' + name)
            probes.append(f'test ! -L {source} && test "$(sha256sum < {source} | cut -d " " -f1)" = {digest}')
    bridge.job('set -eu\n' + '\n'.join(probes), bridge.send(b'\n'))
    check(re.fullmatch(r'[a-f0-9]{64}', scope['romfs_sha256']), 'Missing known Kart game image digest')
    say('Checking the existing Mario Kart World game image on the iPad')
    romfs = target + '/romfs.img'
    check(bridge.job('sha256sum < ' + Q(romfs), bridge.send(b'\n')).split()[0] == scope['romfs_sha256'],
          'The iPad has a different Kart game image')


def deliver(conf, work, output):
    from build_ipa_from_nsp import Progress
    work.mkdir(parents=True, exist_ok=True)
    progress = Progress('json')
    progress.plan(3)
    scope = conf['retained_kart']
    try:
        progress.stage('Verify retained iPadOS 16.1 engine')
        check(conf.get('baseline_device_ipa'), 'This retained route requires the signed baseline already on the iPad')
        fw, previous_scale = build_kart_framework(conf['baseline_ipa'], work)
        bridge = Bridge(conf['bridge'])
        app = verify_device(bridge, conf)
        target = app['data_container'] + '/Documents/Games/' + TITLE.lower() + '/Resources'
        verify_retained_resources(bridge, scope, target, fw, conf)
        progress.stage('Build and sign the 540p cartridge')
        plan = work / 'signed-kart-plan.json'
        binding = dict(app_version=conf['app_version'], baseline=sha(conf['baseline_ipa']),
                       profile=sha(conf['provisioning_profile']), cartridge=sha(fw / 'DmGame'))
        delta = work / 'signed-library-update.zip'
        if plan.exists():
            state = json.loads(plan.read_text())
            check(state['binding'] == binding and state['delta'] == sha(delta),
                  'Signed Kart checkpoint differs; choose a new build folder')
            _, changed, remove, prefix, original, manifest = state['plan']
            command('codesign', '--verify', '--deep', '--strict', str(work / 'signed-app' / prefix))
            signed = (delta, changed, remove, prefix, original, manifest)
        else:
            signed = stage_signed_update(fw, conf, work, '16.1')
            checkpoint = plan.with_suffix('.tmp')
            checkpoint.write_text(json.dumps(dict(binding=binding, delta=sha(delta),
                                                  plan=[str(delta), *signed[1:]])) + '\n')
            os.replace(checkpoint, plan)
        progress.stage('Update existing TonTon gamebox')
        report = install(signed, None, conf, work)
        report.update(previous_scene=previous_scale, scene_target='960x540', shader_chain=CHAIN,
                      reused_host=True, reused_device_shaders=True)
        output.with_suffix('.build-report.json').write_text(json.dumps(report, indent=2) + '\n')
        progress.end()
        say(f"TonTon gamebox updated and verified: {report['app_version']}")
    except BaseException:
        progress.end(ok=False)
        raise
