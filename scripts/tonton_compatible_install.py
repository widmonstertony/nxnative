#!/usr/bin/env python3
"""Sign an in-place update of an existing TonTon library and install it via the local device bridge."""
import argparse
import base64
import datetime
import fcntl
import hashlib
import http.client
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import secrets
import shlex
import shutil
import stat
import subprocess
import sys
import sys
import time
import urllib.parse
import urllib.request
import zipfile

from build_tonton_ios import binary_minima, say, version

BUNDLE_PATH = re.compile(r'/var/containers/Bundle/Application/[A-Fa-f0-9-]+/[^/]+\.app')
DATA_PATH = re.compile(r'/var/mobile/Containers/Data/Application/[A-Fa-f0-9-]+')
CACHE = '/var/mobile/Library/Caches/ios-mcp-uploads/'
Q = shlex.quote


def check(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    with open(path, 'rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def command(*args):
    return subprocess.check_output(args, stderr=subprocess.PIPE)


class Bridge:
    def __init__(self, host):
        url = urllib.parse.urlsplit(host)
        check(url.scheme == 'http' and url.hostname and not url.username and not url.path.strip('/')
              and not url.query and not url.fragment and not url.password, 'Expected an HTTP device bridge address')
        # The trusted USB/Wi-Fi device service is local only.
        import ipaddress
        address = ipaddress.ip_address(url.hostname)
        check(address.is_loopback or address in ipaddress.ip_network('192.168.0.0/16')
              or address in ipaddress.ip_network('10.0.0.0/8')
              or address in ipaddress.ip_network('172.16.0.0/12'), 'Use the device bridge on the local network')
        self.host, self.port, self.base = url.hostname, url.port or 8090, host.rstrip('/')

    def call(self, name, arguments, timeout=35):
        params = dict(name=name, arguments=arguments)
        request = urllib.request.Request(self.base + '/mcp', json.dumps(
            dict(jsonrpc='2.0', id=secrets.randbelow(1 << 30), method='tools/call', params=params)).encode(),
            {'Content-Type': 'application/json', 'Accept': 'application/json, text/event-stream'})
        with urllib.request.urlopen(request, timeout=timeout) as response:
            message = json.load(response)
        result = message.get('result', {})
        if message.get('error') or result.get('isError'):
            raise RuntimeError(f'Device bridge {name}: {str(message)[:600]}')
        return result.get('structuredContent') or json.loads(result['content'][0]['text'])

    def run(self, script):
        answer = self.call('run_command', dict(command=script, timeout=25))
        check(answer['exitCode'] == 0, 'Device verification command failed')
        return answer['output'].strip()

    def job(self, operation, cache_file, timeout=900):
        """Long operations run outside the bridge's per-request shell timeout."""
        marker = cache_file + '.status'
        log = cache_file + '.log'
        script = f'( {operation} ) >{Q(log)} 2>&1; code=$?; printf "%s\\n" "$code" > {Q(marker)}'
        self.run('nohup sh -c ' + Q(script) + ' </dev/null >/dev/null 2>&1 &')
        until = time.monotonic() + timeout
        while time.monotonic() < until:
            code = self.run(f'if test -s {Q(marker)}; then cat {Q(marker)}; fi')
            if code:
                check(code == '0', 'Device staging job failed: ' + self.run(f'tail -8 {Q(log)}'))
                return self.run(f'tail -8 {Q(log)}')
            time.sleep(3)
        raise TimeoutError('Device staging job is still running; check the bridge before retrying')

    def upload(self, file, work):
        # Bound memory and retain the reassembled upload on this run's nonce.
        # Confirm an existing checkpoint is bound to the same device and bytes.
        digest = sha(file)
        receipt = work / (file.name + '.upload.json')
        row = json.loads(receipt.read_text()) if receipt.is_file() else {}
        if row and (row['bridge'], row['sha256']) != (self.base, digest):
            raise ValueError(f'Upload checkpoint does not match {file}')
        path = row.get('path')
        if not path:
            path = self.send(b'\n')
            self.run('truncate -s 0 ' + Q(path))
            receipt.write_text(json.dumps(dict(bridge=self.base, sha256=digest, path=path)))
        check(path.startswith(CACHE) and re.fullmatch(r'[A-Za-z0-9_.-]+', path.removeprefix(CACHE)),
              'Invalid staging checkpoint path')
        done = int(self.run(f'test -f {Q(path)} && test ! -L {Q(path)} && stat -c %s {Q(path)}'))
        check(0 <= done <= file.stat().st_size, 'Invalid staged length')
        # Verify the retained prefix before appending anything.
        if done:
            h = hashlib.sha256()
            with file.open('rb') as stream:
                left = done
                while left:
                    block = stream.read(min(left, 8 << 20))
                    h.update(block)
                    left -= len(block)
            remote = self.job('sha256sum < ' + Q(path), self.send(b'\n')).split()[0]
            check(h.hexdigest() == remote, 'Retained upload prefix does not match the local file')
        with file.open('rb') as stream:
            stream.seek(done)
            while block := stream.read(16 << 20):
                piece = self.send(block)
                check(self.run(f'sha256sum < {Q(piece)}').split()[0] == hashlib.sha256(block).hexdigest(),
                      'Uploaded block does not match')
                self.run(f'test "$(stat -c %s {Q(path)})" = {done} && cat {Q(piece)} >> {Q(path)} && rm -- {Q(piece)}')
                done += len(block)
        check(self.job('sha256sum < ' + Q(path), self.send(b'\n')).split()[0] == digest,
              'Complete staged upload does not match')
        return path

    def send(self, data):
        connection = http.client.HTTPConnection(self.host, self.port, timeout=90)
        try:
            connection.request('POST', '/upload_file', data, headers={
                'X-Filename': 'tonton-compat-' + secrets.token_hex(16) + '.part',
                'Content-Type': 'application/octet-stream'})
            response = connection.getresponse()
            info = json.loads(response.read())
            check(response.status == 200 and info['size'] == len(data), 'Device rejected the upload')
            path = info['path']
            check(path.startswith(CACHE) and re.fullmatch(r'[A-Za-z0-9_.-]+', path.removeprefix(CACHE)),
                  'Bridge did not return an owned cache file')
            return path
        finally:
            connection.close()


def load_config(path):
    conf = json.loads(Path(path).read_text())
    for key in ('baseline_ipa', 'provisioning_profile', 'bundle_id', 'device_udid', 'app_version'):
        check(isinstance(conf.get(key), str) and conf[key], f'Missing configuration: {key}')
    check(re.fullmatch(r'[A-Za-z0-9.-]+', conf['bundle_id']), 'Invalid bundle identifier')
    check(re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,3}', conf['app_version']), 'Invalid app version')
    check(isinstance(conf.get('bridge'), str), 'Missing configuration: bridge')
    return conf


def preflight(conf, minimum, legacy_target=None):
    with zipfile.ZipFile(conf['baseline_ipa']) as arc:
        _, info = inspect_app(arc)
    check(info['CFBundleIdentifier'] == conf['bundle_id'] and version(info['MinimumOSVersion']) <= version(minimum),
          'Choose a signed TonTon baseline for this bundle and OS')
    check(version(conf['app_version']) > version(info['CFBundleVersion']), 'Update requires a newer CFBundleVersion')
    check(Path(conf['provisioning_profile']).is_file(), 'Provisioning profile does not exist')
    bridge = Bridge(conf['bridge'])
    live = verify_device(bridge, conf)
    check(live['version'] == info['CFBundleVersion'], 'The selected IPA is not the version installed on the device')
    if legacy_target == 'm2':
        check(bridge.run('sysctl -n hw.machine') == 'iPad14,6',
              'The M2 compatibility audit currently covers iPad14,6; select the verified device')


def signing_credentials(app, conf):
    profile_file = Path(conf['provisioning_profile'])
    profile = plistlib.loads(command('security', 'cms', '-D', '-i', str(profile_file)))
    team, = profile['TeamIdentifier']
    check(profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
          and conf['device_udid'] in profile.get('ProvisionedDevices', []), 'Signing profile is expired or does not cover the device')
    old = plistlib.loads(command('codesign', '-d', '--entitlements', ':-', str(app)))
    allowed = profile['Entitlements']
    # Preserve the signed app identity, keychain, CloudKit and all existing capabilities.
    identity = team + '.' + conf['bundle_id']
    check(old.get('application-identifier') == identity == allowed.get('application-identifier')
          and old.get('com.apple.developer.team-identifier') == team, 'Profile would change the installed app identity')
    import fnmatch
    for key, value in old.items():
        expected = allowed.get(key)
        ok = value == expected
        if isinstance(value, list) and isinstance(expected, list):
            ok = all(any(x == p or (isinstance(x, str) and isinstance(p, str) and fnmatch.fnmatchcase(x, p))
                         for p in expected) for x in value)
        elif isinstance(value, str) and isinstance(expected, list):
            ok = value in expected
        elif isinstance(value, list) and expected == '*':
            ok = all(isinstance(item, str) for item in value)
        elif isinstance(value, str) and isinstance(expected, str):
            ok |= fnmatch.fnmatchcase(value, expected)
        check(ok, f'The provisioning profile does not preserve {key}')
    identities = command('security', 'find-identity', '-v', '-p', 'codesigning').decode()
    fingerprints = [hashlib.sha1(cert).hexdigest().upper() for cert in profile['DeveloperCertificates']]
    eligible = [fingerprint for fingerprint in fingerprints if fingerprint in identities]
    check(eligible, 'No valid local signing identity matches the provisioning profile')
    return profile_file, old, eligible[0]


def inspect_app(archive):
    entries = archive.namelist()
    check(len(entries) == len(set(entries)), 'IPA contains duplicate entries')
    infos = [n for n in entries if re.fullmatch(r'Payload/[^/]+\.app/Info.plist', n)]
    check(len(infos) == 1, 'Expected one IPA app bundle')
    prefix = infos[0].removesuffix('Info.plist')
    for entry in archive.infolist():
        p = PurePosixPath(entry.filename)
        check(not p.is_absolute() and '..' not in p.parts and not stat.S_ISLNK(entry.external_attr >> 16),
              'IPA contains an unsafe path')
    return prefix, plistlib.loads(archive.read(infos[0]))


def stage_signed_update(framework, conf, work, minimum):
    baseline = Path(conf['baseline_ipa'])
    source = work / 'signed-app'
    source.mkdir(exist_ok=True)
    with zipfile.ZipFile(baseline) as arc:
        prefix, original = inspect_app(arc)
        check(original['CFBundleIdentifier'] == conf['bundle_id'], 'Baseline has a different app identity')
        check(version(original['MinimumOSVersion']) <= version(minimum), 'Baseline does not support selected iOS')
        check(version(conf['app_version']) > version(original['CFBundleVersion']), 'Update requires a newer CFBundleVersion')
        app = source / prefix
        if app.exists():
            shutil.rmtree(app)
        # ditto preserves the permissions of nested signed code.
        command('ditto', '-x', '-k', str(baseline), str(source))
        profile, entitlements, identity = signing_credentials(app, conf)
        manifest = json.loads((framework / 'game.manifest.json').read_text())
        dest = app / 'Frameworks' / framework.name
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(framework, dest)
        old_info = app / 'Info.plist'
        old_info.write_bytes(plistlib.dumps(dict(original, CFBundleVersion=conf['app_version'])))
        shutil.copy2(profile, app / 'embedded.mobileprovision')
        ent = work / 'preserved-entitlements.plist'
        ent.write_bytes(plistlib.dumps(entitlements))
        command('codesign', '--force', '--sign', identity, '--timestamp=none', str(dest))
        command('codesign', '--force', '--sign', identity, '--timestamp=none', '--entitlements', str(ent), str(app))
        command('codesign', '--verify', '--strict', '--deep', str(app))
        actual = plistlib.loads(command('codesign', '-d', '--entitlements', ':-', str(app)))
        check(actual == entitlements, 'Signed update changed the original entitlements')
        with (dest / 'DmGame').open('rb') as f:
            check([version(v) for v in binary_minima(f)] == [version(minimum)],
                  'Signed framework minimum changed')
        # The other framework files and immutable resources remain in the baseline archive.
        mutable = (app / original['CFBundleExecutable'], old_info, app / 'embedded.mobileprovision',
                   *sorted((app / '_CodeSignature').rglob('*')), *sorted(dest.rglob('*')))
        delta = work / 'signed-library-update.zip'
        changed = {}
        with zipfile.ZipFile(delta, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=3) as out:
            for path in mutable:
                if path.is_file():
                    name = path.relative_to(source).as_posix()
                    check(re.fullmatch(r'[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*', name), 'Invalid update member')
                    changed[name] = sha(path)
                    out.write(path, name)
        old_members = [n for n in arc.namelist() if n.startswith(prefix + 'Frameworks/' + framework.name + '/')
                       and not n.endswith('/')]
        remove = sorted(set(old_members) - changed.keys())
        check(all(re.fullmatch(r'[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*', n) for n in remove), 'Invalid obsolete member')
    return delta, changed, remove, prefix, original, manifest


def verify_device(bridge, conf):
    app = bridge.call('get_app_info', {'bundle_id': conf['bundle_id']})
    check(BUNDLE_PATH.fullmatch(app['bundle_path']) and DATA_PATH.fullmatch(app['data_container']),
          'Could not verify the installed app and data container')
    return app


def save_fingerprint(bridge, games):
    # Digest relative paths and save contents on the device. Save files never leave it.
    cmd = f"""set -euo pipefail
cd {Q(games)}
find . -type f -ipath '*/userdata/save*/*' -exec sha256sum -- {{}} + | LC_ALL=C sort | sha256sum
"""
    return bridge.job('bash -c ' + Q(cmd), bridge.send(b'\n')).split()[0]


def cached_baseline(bridge, conf, work):
    if not conf.get('baseline_device_ipa'):
        return bridge.upload(Path(conf['baseline_ipa']), work)
    remote = conf['baseline_device_ipa']
    check(re.fullmatch(re.escape(CACHE) + r'[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*', remote)
          and not {'.', '..'}.intersection(PurePosixPath(remote).parts), 'Invalid retained archive path')
    digest = sha(Path(conf['baseline_ipa']))
    check(bridge.job(f'test -f {Q(remote)} && test ! -L {Q(remote)} && sha256sum < {Q(remote)}',
                     bridge.send(b'\n')).split()[0] == digest, 'Retained archive differs from signed baseline')
    return remote


def reassemble(bridge, signed, conf, work):
    delta, changed, remove, prefix, original, manifest = signed
    remote = bridge.upload(delta, work)
    baseline = cached_baseline(bridge, conf, work)
    candidate = remote + '.new.ipa'
    directory = remote + '.unzip'
    checks = '\n'.join(f'test "$(unzip -p {Q(candidate)} {Q(n)} | sha256sum | cut -d " " -f1)" = {digest}'
                       for n, digest in changed.items())
    ready = work / 'candidate.json'
    if ready.is_file():
        previous = json.loads(ready.read_text())
        if previous == dict(path=candidate, delta_sha256=sha(delta)):
            bridge.job('set -eu\n' + checks, bridge.send(b'\n'))
            return candidate
    cleanup = 'zip -q -d ' + Q(candidate) + ' ' + ' '.join(map(Q, remove)) if remove else ':'
    names = ' '.join(map(Q, changed))
    # Reuse the retained IPA on-device. Never resend another title's data.
    script = f"""set -eu
umask 077
test ! -e {Q(candidate)}
mkdir -p {Q(directory)}
cd {Q(directory)}
unzip -qo {Q(remote)}
zip -q -6 {Q(baseline)} {names} --out {Q(candidate)}
{cleanup}
unzip -tq {Q(candidate)}
{checks}
"""
    remote_script = bridge.send(script.encode())
    bridge.job('sh ' + Q(remote_script), bridge.send(b'\n'))
    ready.write_text(json.dumps(dict(path=candidate, delta_sha256=sha(delta))) + '\n')
    return candidate


def prepare_shader_resources(ipa, framework, work, romfs_sha=None):
    """Export only new shader/module companions, with a binding to the exact source RomFS."""
    manifest = json.loads((framework / 'game.manifest.json').read_text())
    chain, title = manifest['chain'], manifest['title_id']
    check(re.fullmatch(r'b-[0-9a-f]{12}', chain) and re.fullmatch(r'[0-9A-F]{16}', title),
          'Invalid shader chain or title')
    layer = work / 'compatible-runtime'
    layer.mkdir(exist_ok=True)
    wanted = ('dm/', 'msl/' + chain + '/', 'msl/' + chain + '.img')
    with zipfile.ZipFile(ipa) as arc:
        prefix, info = inspect_app(arc)
        check(info['CFBundleIdentifier'].lower().endswith('.' + title.lower()), 'Build did not produce selected title')
        check(info['CFBundleShortVersionString'] == manifest['display_version'], 'Build and framework versions differ')
        if romfs_sha is None:
            name = prefix + 'romfs.img'
            if name in arc.namelist():
                with arc.open(name) as stream:
                    romfs_sha = hashlib.file_digest(stream, 'sha256').hexdigest()
            else:
                raise ValueError('This build needs an exact file-packed RomFS; provide its SHA-256 for a separate export')
        files = [n for n in arc.namelist() if not n.endswith('/') and n.startswith(prefix)
                 and n.removeprefix(prefix).startswith(wanted)]
        # A resource layer is private to this build; do not merge a stale layer.
        if (layer / 'dm').exists():
            shutil.rmtree(layer / 'dm')
        if (layer / 'msl').exists():
            shutil.rmtree(layer / 'msl')
        for name in files:
            path = layer / name.removeprefix(prefix)
            path.parent.mkdir(parents=True, exist_ok=True)
            with arc.open(name) as inp, path.open('wb') as out:
                shutil.copyfileobj(inp, out)
    stamp = (layer / 'msl' / chain / 'inputs.tsv').read_text().splitlines()
    check(f'game\t{title}' in stamp, 'Shader resource stamp does not match the title')
    for table in (framework / 'dm').iterdir():
        check((layer / 'dm' / table.name).read_bytes() == table.read_bytes(),
              f'Rewrite tables differ between framework and shader package: {table.name}')
    (layer / 'source.sha256').write_text(romfs_sha + '\n')
    # The classic NVN runtime supports the compact mapped image. The device only
    # needs the readiness stamp, side data, and the image, not 50,000 loose files.
    folder = layer / 'msl' / chain
    packed = folder.with_suffix('.img')
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'dm/tools'))
    from pack_nvn_shader_image import pack, SHADER
    if not packed.exists():
        pack(folder, packed)
    archive = work / 'shader-layer.zip'
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=3) as out:
        for path in sorted(layer.rglob('*')):
            if path.is_file() and not (path.parent == folder and SHADER.fullmatch(path.name)):
                out.write(path, path.relative_to(layer).as_posix())
    return archive


def install(signed, runtime, conf, work):
    bridge = Bridge(conf['bridge'])
    delta, changed, remove, prefix, original, manifest = signed
    title = manifest['title_id'].lower()
    bundle = conf['bundle_id']
    initial = verify_device(bridge, conf)
    check(initial['version'] == original['CFBundleVersion'], 'The installed app has changed since the chosen baseline')
    check(version(initial['minimum_os_version']) <= version(manifest['min_os']), 'Device app minimum no longer matches')
    live_plist = initial['bundle_path'] + '/Info.plist'
    with zipfile.ZipFile(conf['baseline_ipa']) as baseline:
        initial_plist = hashlib.sha256(baseline.read(prefix + 'Info.plist')).hexdigest()
    check(bridge.run('sha256sum < ' + Q(live_plist)).split()[0] == initial_plist, 'The installed app does not match the baseline IPA')
    games = initial['data_container'] + '/Documents/Games'
    slot = games + '/' + title
    target = slot + '/Resources'
    romfs = target + '/romfs.img'
    before_body = bridge.run(f'test ! -L {Q(romfs)} && stat -c "%s %d %i %Y" {Q(romfs)}')
    with zipfile.ZipFile(runtime) as arc:
        source_digest = arc.read('source.sha256').decode().strip()
        tables = {}
        for name in arc.namelist():
            if name.startswith('dm/'):
                relative = name.removeprefix('dm/')
                check(re.fullmatch(r'[a-zA-Z0-9_-]+(?:[./][a-zA-Z0-9_-]+)*', relative),
                      'Unexpected compatibility runtime table path')
                tables[relative] = hashlib.sha256(arc.read(name)).hexdigest()
        check(all(f'{module}.{suffix}.tsv' in tables for module in manifest['modules']
                  for suffix in ('fixups', 'gates', 'obs', 'cuts')), 'The runtime layer is missing signed module tables')
    expected = conf.get('verified_equivalent_romfs', {}).get(source_digest, source_digest)
    check(re.fullmatch(r'[0-9a-f]{64}', expected), 'Invalid expected local RomFS SHA-256')
    say('Checking the existing game image without transferring it')
    body = bridge.job('sha256sum < ' + Q(romfs), bridge.send(b'\n')).split()[0]
    check(body == expected, 'Existing RomFS is missing or differs from this build')
    say('Sending only the signed update and matching shader resources')
    candidate = reassemble(bridge, signed, conf, work)
    payload = bridge.upload(runtime, work)
    nonce = secrets.token_hex(8)
    pending = slot + '/.tonton-runtime-' + nonce
    chain = manifest['chain']
    check(re.fullmatch(r'b-[0-9a-f]{12}', chain), 'Invalid shader chain')
    bridge.job(f'set -eu; mkdir {Q(pending)}; unzip -q {Q(payload)} -d {Q(pending)}; '
               f'test -s {Q(pending + "/msl/" + chain + ".img")}', bridge.send(b'\n'))
    staged_app = verify_device(bridge, conf)
    check(all(staged_app[k] == initial[k] for k in ('version', 'data_container', 'bundle_path')),
          'Installed app changed while staging')
    try:
        bridge.call('kill_app', {'bundle_id': bundle})
    except RuntimeError:
        front = bridge.call('get_frontmost_app', {})
        check(front.get('bundleId') != bundle, 'Could not close the running library for an in-place update')
    saved = save_fingerprint(bridge, games)
    rolled = target + '/.tonton-previous-dm-' + nonce
    old_msl = target + '/msl/'
    new_msl = pending + '/msl/'
    # Add the shader chain without replacing a previous chain. Keep any
    # device-only settings and support files omitted by the build package.
    for component in (chain, chain + '.img'):
        bridge.run('test ! -e ' + Q(old_msl + component) + ' && test ! -L ' + Q(old_msl + component))
    def check_tables(directory):
        checks = '\n'.join(
            f'test "$(sha256sum < {Q(directory + "/" + name)} | cut -d " " -f1)" = {digest}'
            for name, digest in tables.items())
        bridge.job('set -eu\n' + checks, bridge.send(b'\n'))

    check_tables(pending + '/dm')
    bridge.run(f'''set -eu
test -d {Q(target + "/dm")} && test ! -L {Q(target + "/dm")} && test ! -L {Q(target + "/msl")}
cp -Rn {Q(target + "/dm/.")} {Q(pending + "/dm")}
mv {Q(new_msl + chain)} {Q(old_msl + chain)}
mv {Q(new_msl + chain + ".img")} {Q(old_msl + chain + ".img")}
''')
    local_receipt = work / 'install-pending.json'
    local_receipt.write_text(json.dumps(dict(candidate=candidate, old_dm=rolled, staged_dm=pending+'/dm',
                                             expected=conf['app_version'], original_app=original['CFBundleVersion']),
                                        indent=2) + '\n')
    say('Installing the signed update over the existing TonTon gamebox')
    try:
        bridge.call('install_app', {'path': candidate}, timeout=240)
    except (RuntimeError, OSError):
        # The daemon may still be extracting a large IPA after the call times out.
        pass
    deadline = time.monotonic() + 300
    installed = None
    while time.monotonic() < deadline:
        try:
            installed = verify_device(bridge, conf)
        except (OSError, RuntimeError, ValueError):
            time.sleep(5)
            continue
        if installed['version'] == conf['app_version']:
            break
        time.sleep(5)
    check(installed and installed.get('version') == conf['app_version'],
          f'Install has not been observed. Verified installer and previous resource tables are recorded in {local_receipt}.')
    check(installed['data_container'] == initial['data_container'], 'App update changed the data container')
    # Publish the matching tables only after the shell update is observed.
    # The old tables remain available if promotion of the staged directory fails.
    live_dm = target + '/dm'
    staged_dm = pending + '/dm'
    bridge.run(f'''set -eu
mv {Q(live_dm)} {Q(rolled)}
mv {Q(staged_dm)} {Q(live_dm)} || {{ mv {Q(rolled)} {Q(live_dm)}; exit 1; }}
''')
    check_tables(live_dm)
    for name, digest in changed.items():
        if name.endswith(('/Info.plist', '/DmGame', '/game.manifest.json')):
            live_path = installed['bundle_path'] + '/' + name.removeprefix(prefix)
            observed = bridge.job('sha256sum < ' + Q(live_path), bridge.send(b'\n')).split()[0]
            check(observed == digest, 'Installed component did not match signed update: ' + name)
    check(save_fingerprint(bridge, games) == saved, 'Save data changed during installation')
    check(bridge.run(f'stat -c "%s %d %i %Y" {Q(romfs)}') == before_body, 'Existing game body changed')
    result = dict(title_id=title, app_version=installed['version'], minimum_ios=manifest['min_os'],
                  saves_unchanged=True, existing_game_body_unchanged=True, runtime_tested=False)
    (work / 'install-verified.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def load_built_framework(work):
    location = work / 'ipa' / 'independent-host'
    info = json.loads((location / 'source.json').read_text())
    title = info['id']
    check(re.fullmatch(r'[A-F0-9]{16}', title), 'Invalid generated framework title')
    return location / f'DmGame{title}.framework', info['romfs_sha256']


def build_hook(argv):
    from build_tonton_compatible_framework import build_framework
    engine, patched, w, title, minimum, name, display, package, romfs, *modules = argv
    image = Path(romfs)
    check(image.is_file(), 'An existing gamebox install needs an exact RomFS image')
    directory = Path(w) / 'independent-host'
    output = build_framework(Path(engine).resolve(), Path(patched), directory, title, modules,
                             minimum, name, display, package_version=package)
    check(output.is_dir(), 'No built framework')
    (directory / 'source.json').write_text(json.dumps(dict(id=title, romfs_sha256=sha(image))) + '\n')


if __name__ == '__main__':
    try:
        if sys.argv[1:2] == ['build-framework']:
            build_hook(sys.argv[2:])
        else:
            p = argparse.ArgumentParser(description=__doc__)
            p.add_argument('--framework', required=True, type=Path)
            p.add_argument('--ipa', required=True, type=Path)
            p.add_argument('--device', required=True, type=Path)
            p.add_argument('--work', required=True, type=Path)
            p.add_argument('--romfs', type=Path)
            a = p.parse_args()
            manifest = json.loads((a.framework / 'game.manifest.json').read_text())
            conf = load_config(a.device)
            minimum = manifest['min_os']
            preflight(conf, minimum)
            a.work.mkdir(parents=True, exist_ok=True)
            with (a.work / 'install.lock').open('a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                signed = stage_signed_update(a.framework, conf, a.work, minimum)
                runtime = prepare_shader_resources(a.ipa, a.framework, a.work, sha(a.romfs) if a.romfs else None)
                print(json.dumps(install(signed, runtime, conf, a.work), indent=2))
    except (OSError, ValueError, RuntimeError, KeyError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr.decode(errors='replace')[-1600:], file=sys.stderr)
        print(f'[RED] {error}', file=sys.stderr)
        sys.exit(1)
