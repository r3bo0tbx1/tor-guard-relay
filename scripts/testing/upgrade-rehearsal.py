#!/usr/bin/env python3
"""Offline upgrade rehearsal between two local images using disposable identities."""
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess as sp
import tarfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('upgrade_backup', ROOT / 'scripts/utilities/relay_backup.py')
backup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backup)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--from-image', required=True, help='Locally available previous image')
    parser.add_argument('--to-image', required=True, help='Locally available candidate image')
    parser.add_argument('--platform', choices=('linux/amd64', 'linux/arm64'))
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    cli = backup.docker_cli()
    if not cli:
        raise RuntimeError('Docker is required')

    def run(*argv, check=True, **kwargs):
        result = sp.run([cli, *argv], capture_output=True, **kwargs)
        if check and result.returncode:
            raise RuntimeError(f'Docker upgrade fixture failed: {argv}: {result.stderr.decode(errors="replace")}')
        return result

    host_arch = run('version', '--format', '{{.Server.Arch}}').stdout.decode().strip()
    platform = args.platform or 'linux/' + host_arch
    images = [json.loads(run('image', 'inspect', image).stdout)[0]
              for image in (args.from_image, args.to_image)]
    for image in images:
        if image['Os'] != 'linux' or 'linux/' + image['Architecture'] != platform:
            raise ValueError('Both local images must match the selected platform')
    source, target = [image['Id'] for image in images]
    assert images[0]['Config'].get('ExposedPorts') == images[1]['Config'].get('ExposedPorts'), 'Default image ports changed'
    results = []
    report = {'source_image_id': source, 'target_image_id': target, 'platform': platform,
              'network': 'none', 'synthetic_identities_only': True, 'passed': False, 'cases': results}
    args.output.parent.mkdir(parents=True, exist_ok=True)

    def save_report():
        args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')

    save_report()

    def execute(name, *argv, **kwargs):
        return run('exec', name, *argv, **kwargs)

    def wait_ready(name, role):
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            result = execute(name, 'health', check=False)
            if not result.returncode:
                health = json.loads(result.stdout)
                required = {'liveness', 'config_valid', 'fingerprint', 'tor_version'}
                if not required <= set(health):
                    raise ValueError('Image lacks the v2.2.0 health contract; verify its image ID/version. '
                                     'A cached latest tag may still select an older release.')
                if health['liveness'] and health['config_valid'] and health['fingerprint'] != 'unknown':
                    if role == 'bridge':
                        # Old releases' helper can miss BridgeRelay inside includes.
                        # Observe the transport state directly for both versions.
                        transport = execute(name, 'test', '-s', '/var/lib/tor/pt_state/obfs4_bridgeline.txt', check=False)
                        if transport.returncode:
                            time.sleep(0.2)
                            continue
                    return health
            time.sleep(0.2)
        raise AssertionError('Synthetic relay did not initialize: ' + run('logs', '--tail', '25', name).stdout.decode(errors='replace'))

    def identities(name, role):
        paths = ['fingerprint', 'keys/secret_id_key', 'keys/ed25519_master_id_secret_key',
                 'keys/ed25519_master_id_public_key', 'keys/UpgradeFixture.secret_family_key']
        if role == 'bridge':
            paths += ['pt_state/obfs4_state.json', 'pt_state/obfs4_bridgeline.txt']
        return {path: hashlib.sha256(backup.read_file(name, '/var/lib/tor/' + path)).hexdigest()
                for path in paths}

    for role in ('guard', 'exit', 'bridge'):
        for config_source in ('environment', 'mounted'):
            prefix = 'relay-upgrade-' + uuid.uuid4().hex[:12]
            names = [prefix + '-old', prefix + '-new']
            volumes = [prefix + '-data', prefix + '-logs']
            config_volume = prefix + '-config'
            try:
                if config_source == 'mounted':
                    volumes.append(config_volume)
                for volume in volumes:
                    run('volume', 'create', '--label', 'org.tor-guard-relay.fixture=' + prefix, volume)
                mounts = ['--mount', 'type=volume,source=' + volumes[0] + ',target=/var/lib/tor',
                          '--mount', 'type=volume,source=' + volumes[1] + ',target=/var/log/tor']
                if config_source == 'mounted':
                    config = ('Nickname UpgradeFixture\nContactInfo operator@example.com\nORPort 9001\n'
                              'SocksPort 0\nDataDirectory /var/lib/tor\n'
                              'Log notice file /var/log/tor/notices.log\n%include /etc/tor/includes/role.conf\n')
                    options = {'guard': 'ExitRelay 0\n',
                               'exit': 'ExitRelay 1\nExitPolicy accept *:80,reject *:*\n',
                               'bridge': 'BridgeRelay 1\nPublishServerDescriptor bridge\nExtORPort auto\n'
                                         'ServerTransportPlugin obfs4 exec /usr/bin/lyrebird\n'
                                         'ServerTransportListenAddr obfs4 0.0.0.0:9002\n'}[role]
                    bundle = io.BytesIO()
                    with tarfile.open(fileobj=bundle, mode='w') as archive:
                        for path, text in (('torrc', config), ('includes/role.conf', options)):
                            content = text.encode()
                            member = tarfile.TarInfo(path)
                            member.uid = 100; member.gid = 101; member.mode = 0o600; member.size = len(content)
                            archive.addfile(member, io.BytesIO(content))
                    run('run', '--rm', '-i', '--pull=never', '--platform', platform, '--network', 'none',
                        '--user', '0', '--mount', 'type=volume,source=' + config_volume + ',target=/etc/tor',
                        '--entrypoint', 'tar', source, '-xf', '-', '-C', '/etc/tor', input=bundle.getvalue())
                    mounts += ['--mount', 'type=volume,source=' + config_volume + ',target=/etc/tor,readonly']
                else:
                    config = None
                for name, image in zip(names, (source, target)):
                    run('create', '--name', name, '--pull=never', '--platform', platform,
                        '--network', 'none', '--label', 'org.tor-guard-relay.fixture=' + prefix,
                        *mounts, '-e', 'TOR_NICKNAME=UpgradeFixture', '-e', 'TOR_CONTACT_INFO=operator@example.com',
                        '-e', 'TOR_RELAY_MODE=' + (role if config_source == 'environment' else 'guard'), image)
                run('start', names[0])
                old_health = wait_ready(names[0], role)
                execute(names[0], 'gen-family', 'UpgradeFixture')
                before = identities(names[0], role)
                paths = ['/etc/tor/torrc']
                if config_source == 'mounted':
                    paths.append('/etc/tor/includes/role.conf')
                config_before = {path: backup.read_file(names[0], path) for path in paths}
                # Old current-run logs must not establish new-container readiness.
                execute(names[0], 'sh', '-ec', "printf 'Bootstrapped 100%%\\n' >> /var/log/tor/notices.log")
                run('stop', '--time', '45', names[0])
                old_state = json.loads(run('inspect', names[0]).stdout)[0]['State']
                assert not old_state['Running'] and old_state['Pid'] == 0 and old_state['ExitCode'] == 0
                run('start', names[1])
                new_health = wait_ready(names[1], role)
                assert new_health['fingerprint'] == old_health['fingerprint']
                assert identities(names[1], role) == before, 'Identity, family or transport material changed'
                assert new_health['config_source'] == config_source, new_health
                assert new_health['relay_mode'] == role, new_health
                assert new_health['fresh'] and not new_health['readiness'] and new_health['bootstrap'] < 100, new_health
                assert execute(names[1], 'id', '-u').stdout.strip() == b'100'
                assert execute(names[1], 'id', '-g').stdout.strip() == b'101'
                execute(names[1], 'config', 'validate')
                if role == 'bridge':
                    bridge = json.loads(execute(names[1], 'bridge-line', '--json', '--address', '192.0.2.10').stdout)
                    assert bridge['reason'] == 'ready'
                if config_source == 'mounted':
                    assert all(backup.read_file(names[1], path) == value for path, value in config_before.items())
                else:
                    def directives(contents):
                        return [line.strip() for line in contents.decode().splitlines()
                                if line.strip() and not line.lstrip().startswith('#')]
                    assert directives(config_before['/etc/tor/torrc']) == directives(backup.read_file(names[1], '/etc/tor/torrc'))
                assert not json.loads(run('inspect', names[0]).stdout)[0]['State']['Running']
                result = {'role': role, 'config_source': config_source, 'passed': True,
                          'source_tor': old_health['tor_version'], 'target_tor': new_health['tor_version'],
                          'fingerprint_keys_family_and_transport_preserved': True,
                          'mounted_config_and_includes_unchanged': config_source == 'mounted',
                          'current_run_readiness_reset': True, 'uid_gid': '100:101',
                          'source_stopped_before_target_start': True}
                results.append(result)
                save_report()
                print(f'{role}/{config_source}: upgrade preserved identity, configuration and fresh health', flush=True)
            except BaseException as error:
                report['error'] = f'{role}/{config_source}: {error}'
                save_report()
                raise
            finally:
                for name in names:
                    run('rm', '-f', '-v', name, check=False)
                for volume in volumes:
                    actual = run('volume', 'inspect', volume, check=False)
                    if not actual.returncode:
                        label = json.loads(actual.stdout)[0].get('Labels', {}).get('org.tor-guard-relay.fixture')
                        if label == prefix:
                            run('volume', 'rm', volume)
    report['passed'] = True
    save_report()


if __name__ == '__main__':
    main()
