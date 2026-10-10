#!/usr/bin/env python3
"""Preview evidence-backed rebuild retention; apply only a reviewed exact plan."""
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess as sp

from registry_tools import ARCHES, VARIANTS, Client, architecture_digests, is_ghcr

spec = importlib.util.spec_from_file_location('retired_images', Path(__file__).with_name('prune-old-images.py'))
prune = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prune)
DIGEST = re.compile(r'sha256:[0-9a-f]{64}')


def stamp(value):
    date = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if date.tzinfo is None:
        raise ValueError('Retention timestamps must include a timezone')
    return date.astimezone(timezone.utc)


def hash_json(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def validate_policy(policy, now, apply=False):
    if (type(policy.get('keep_builds')) is not int or policy['keep_builds'] < 2
            or type(policy.get('grace_days')) is not int or policy['grace_days'] < 7
            or type(policy.get('deployment_review_complete')) is not bool):
        raise ValueError('Retain at least two builds and a seven-day grace period')
    for field in ('protected_digests', 'protected_image_ids'):
        if not isinstance(policy.get(field), list) or any(not isinstance(x, str) or not DIGEST.fullmatch(x) for x in policy[field]):
            raise ValueError('Protection lists must contain complete SHA256 digests')
    if apply:
        reviewed = policy.get('deployment_reviewed_at')
        if not policy['deployment_review_complete'] or not reviewed:
            raise ValueError('Deletion blocked: deployment coverage has not been verified')
        age = now - stamp(reviewed)
        if age < timedelta(0) or age > timedelta(days=7):
            raise ValueError('Deletion blocked: deployment review must be within the last seven days')


def missing(error):
    return 'http 404' in str(error.stderr) and 'MANIFEST_UNKNOWN' in str(error.stderr)


def visit_optional(graph, digest):
    if not DIGEST.fullmatch(digest):
        raise ValueError('Invalid publication digest')
    if digest in graph.manifests:
        return True
    try:
        graph.client.manifest(graph.registry + '@' + digest)
    except sp.CalledProcessError as error:
        if not missing(error):
            raise
        return False
    graph.visit(digest)
    return True


def evidence_row(graph, row):
    if (row.get('variant') not in VARIANTS or set(row.get('architectures', {})) != set(ARCHES)
            or set(row.get('image_ids', {})) != set(ARCHES)):
        raise ValueError('Publication evidence must identify both architectures and image configs')
    root = row['index_digest']
    present = visit_optional(graph, root)
    if present and architecture_digests(graph.manifests[root]) != row['architectures']:
        raise ValueError('Recorded architecture manifests differ from the registry')
    roots = {root} if present else set()
    versions = set()
    for arch, digest in row['architectures'].items():
        if not visit_optional(graph, digest):
            if present:
                raise ValueError('A published index references a missing architecture')
            continue
        roots.add(digest)
        manifest = graph.manifests[digest]
        if manifest.get('config', {}).get('digest') != row['image_ids'][arch]:
            raise ValueError('Recorded image config differs from the registry')
        config = graph.configs[row['image_ids'][arch]]
        version = config.get('config', {}).get('Labels', {}).get('org.opencontainers.image.version', '')
        if config.get('architecture') != arch or not re.fullmatch(r'\d+\.\d+\.\d+' + ('-edge' if row['variant'] == 'edge' else ''), version):
            raise ValueError('Invalid recorded variant or architecture identity')
        versions.add(version.removesuffix('-edge'))
    if len(versions) > 1:
        raise ValueError('Architecture release versions disagree')
    if versions:
        version, = versions
        if row['tags'] != prune.tidy.public_tags(graph.registry, version, row['variant']):
            raise ValueError('Recorded publication tag conventions do not match')
    return roots


def legacy_roots(graph, legacy, keep):
    if legacy is None or graph.registry != legacy.get('registry'):
        return set()
    rows = legacy.get('builds')
    if not isinstance(rows, list):
        raise ValueError('Expected an exact reviewed legacy build list')
    roots, indexes = set(), set()
    for row in rows:
        version = row.get('version', '')
        index = row.get('index_digest', '')
        arches, approved = row.get('architectures', {}), row.get('manifest_digests', [])
        if (not re.fullmatch(r'\d+\.\d+\.\d+(?:-edge)?', version)
                or tuple(map(int, version.removesuffix('-edge').split('.'))) >= tuple(map(int, keep.split('.')))
                or not DIGEST.fullmatch(index) or index in indexes
                or set(arches) != set(ARCHES) or not isinstance(approved, list)
                or len(approved) != len(set(approved))
                or any(not DIGEST.fullmatch(x) for x in approved)
                or not {index, *arches.values()} <= set(approved)):
            raise ValueError('Invalid or newer legacy retirement identity')
        indexes.add(index)
        if visit_optional(graph, index):
            actual = {entry.get('platform', {}).get('architecture'): entry['digest']
                      for entry in graph.manifests[index].get('manifests', [])
                      if entry.get('platform', {}).get('architecture') in ARCHES}
            if (actual != arches or graph.closure([index]) != set(approved)
                    or graph.versions(index) != {version}):
                raise ValueError('Legacy graph differs from the reviewed complete architecture build')
        for digest in approved:
            if not visit_optional(graph, digest):
                continue  # A completed prior cleanup is idempotent.
            if not graph.closure([digest]) <= set(approved) or not graph.versions(digest) <= {version}:
                raise ValueError('Legacy image differs from its reviewed retirement scope')
            roots.add(digest)
        for arch, digest in arches.items():
            if digest in graph.manifests:
                config = graph.configs.get(graph.manifests[digest].get('config', {}).get('digest'), {})
                if config.get('architecture') != arch:
                    raise ValueError('Legacy architecture identity differs')
    return roots


def plan_registry(client, registry, catalog, policy, now, packages=None, legacy=None):
    validate_policy(policy, now)
    graph = prune.Graph(client, registry)
    tags = sorted(client.run('tag', 'ls', registry).splitlines())
    tag_roots = {tag: client.run('image', 'digest', registry + ':' + tag) for tag in tags}
    for digest in tag_roots.values():
        graph.visit(digest)
    current = [row for row in catalog['current'] if row['registry'] == registry]
    if len(current) != 2 or {row['variant'] for row in current} != set(VARIANTS):
        raise ValueError('Current publication must contain both variants in each registry')
    version, = {row['tags'][0] for row in current if row['variant'] == 'stable'}
    prune.verify_publication({'registry': registry, 'keep_version': version,
                              'protected': {'roots': tag_roots, 'manifests': graph.manifests}}, current)
    originals = catalog.get('original_image_ids', [])
    if len(originals) != 4 or len(set(originals)) != 4 or any(not DIGEST.fullmatch(x) for x in originals):
        raise ValueError('Missing original-release protection evidence')
    builds = {variant: {} for variant in VARIANTS}
    known, retained = set(), set(tag_roots.values())
    known.update(legacy_roots(graph, legacy, version))
    for publication in catalog['publications']:
        when = stamp(publication['published_at'])
        if when > now:
            raise ValueError('Publication timestamp is in the future')
        rows = [row for row in publication['rows'] if row['registry'] == registry]
        if len(rows) != 2 or {row['variant'] for row in rows} != set(VARIANTS):
            raise ValueError('Historical publication is incomplete')
        for row in rows:
            roots = evidence_row(graph, row)
            known.update(roots)
            entry = builds[row['variant']].setdefault(row['index_digest'], {'when': when, 'roots': roots})
            entry['when'] = max(entry['when'], when)
            entry['roots'].update(roots)
    for variant in VARIANTS:
        ordered = sorted(builds[variant].values(), key=lambda value: value['when'], reverse=True)
        for index, build in enumerate(ordered):
            if index < policy['keep_builds'] or now - build['when'] < timedelta(days=policy['grace_days']):
                retained.update(build['roots'])
    for digest in policy['protected_digests']:
        graph.visit(digest)  # A missing explicit protection is an error, never ignored.
        retained.add(digest)
    entries = [] if packages is None else packages.versions()
    by_digest, identities = {}, set()
    for item in entries:
        identity = prune.package_identity(item)
        if (type(identity['id']) is not int or identity['id'] <= 0 or identity['id'] in identities
                or identity['digest'] in by_digest):
            raise ValueError('Invalid or duplicate package identity')
        identities.add(identity['id'])
        by_digest[identity['digest']] = identity
        graph.visit(identity['digest'])
        if any(tag_roots.get(tag) != identity['digest'] for tag in identity['tags']):
            raise ValueError('Package inventory disagrees with registry tags')
    if packages and any(root not in by_digest for root in tag_roots.values()):
        raise ValueError('Incomplete package inventory')
    candidate_graph = graph.closure(known)
    retained.update(digest for digest in by_digest if digest not in candidate_graph)
    # Docker's containerd image store can report a manifest/index digest as .Id;
    # the classic image store reports a config digest. Resolve either form before
    # permitting deletion, rather than treating every engine ID as a config ID.
    engine_ids = set(policy['protected_image_ids'])
    unresolved = engine_ids - set(graph.manifests) - set(graph.configs)
    if unresolved:
        raise ValueError('Deployed image identities cannot be resolved in the registry graph')
    protected_configs = set(originals) | (engine_ids & set(graph.configs))
    # Protect parents too, so a deployed child can still be pulled through its index.
    for digest in graph.manifests:
        closure = graph.closure([digest])
        if closure & engine_ids or any(
                graph.manifests[child].get('config', {}).get('digest') in protected_configs
                for child in closure):
            retained.add(digest)
    protected = graph.closure(retained)
    targets = candidate_graph - protected
    ordered = sorted(targets, key=lambda digest: (-len(graph.closure([digest])), digest))
    package_targets = [by_digest[digest] for digest in ordered if digest in by_digest]
    if any(item['tags'] for item in package_targets):
        raise ValueError('Rebuild retention must never delete a tagged package version')
    return {'registry': registry, 'keep_version': version, 'tag_inventory': tag_roots,
            'protected': {'roots': tag_roots, 'manifests': {x: graph.manifests[x] for x in sorted(protected)}},
            'protected_configs': {manifest['config']['digest']: graph.configs[manifest['config']['digest']]
                                  for x, manifest in graph.manifests.items() if x in protected and manifest.get('config')},
            'manifest_targets': ordered if packages is None else [], 'package_targets': package_targets,
            'package_inventory': sorted(by_digest.values(), key=lambda item: item['id']),
            'unknown_hub_images': 'Not enumerated; only recorded publication digests can be targeted' if packages is None else None,
            'attempts': [], 'removed_manifests': [], 'removed_packages': [], 'applied': False}


def verify(client, report, packages=None):
    actual = sorted(client.run('tag', 'ls', report['registry']).splitlines())
    if actual != sorted(report['tag_inventory']):
        raise ValueError('Registry tag inventory changed after preview')
    prune.verify(client, report)
    if packages is not None:
        removed = {item['id'] for item in report['removed_packages']}
        expected = [item for item in report['package_inventory'] if item['id'] not in removed]
        actual = sorted((prune.package_identity(item) for item in packages.versions()), key=lambda item: item['id'])
        if actual != expected:
            raise ValueError('Package inventory changed after preview')


def apply_registry(client, report, packages=None, save=lambda: None):
    verify(client, report, packages)
    verify_layers(client, report)
    targets = report['package_targets'] if packages is not None else report['manifest_targets']
    for item in targets:
        digest = item['digest'] if packages is not None else item
        if digest in report['protected']['manifests']:
            raise ValueError('Deletion target overlaps a retained image')
        verify(client, report, packages)
        if packages is not None:
            if prune.package_identity(packages.get(item['id'])) != item or item['tags']:
                raise ValueError('Package deletion target changed')
        attempt = {'digest': digest, 'package_id': item['id'] if packages is not None else None, 'status': 'requested'}
        report['attempts'].append(attempt)
        save()  # A server timeout can still mean deletion was accepted asynchronously.
        if packages is not None:
            packages.delete(item['id'])
            report['removed_packages'].append(item)
        else:
            # Hub rejects manifests still referenced by another image/tag.
            # Never force deletion, delete blobs, or retry an uncertain failure.
            client.run('manifest', 'delete', report['registry'] + '@' + digest)
            report['removed_manifests'].append(digest)
        attempt['status'] = 'completed'
        save()
        verify(client, report, packages)
    verify(client, report, packages)
    verify_layers(client, report)
    report['applied'] = True
    save()


def verify_layers(client, report):
    layers = {layer['digest'] for manifest in report['protected']['manifests'].values()
              for layer in manifest.get('layers', [])}
    for digest in sorted(layers):
        if not DIGEST.fullmatch(digest):
            raise ValueError('Invalid retained layer digest')
        client.run('blob', 'head', report['registry'], digest)


def confirm_plan(expected, supplied):
    if not re.fullmatch(r'[0-9a-f]{64}', supplied) or supplied != expected:
        raise ValueError('Deletion blocked: provide the SHA256 of an unchanged reviewed preview')


def load_automation():
    auto_spec = importlib.util.spec_from_file_location('automatic_retention', Path(__file__).with_name('automatic-retention.py'))
    automatic = importlib.util.module_from_spec(auto_spec)
    auto_spec.loader.exec_module(automatic)
    return automatic


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--owner', required=True)
    parser.add_argument('--catalog', type=Path, required=True)
    parser.add_argument('--policy', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--confirm-plan', default='')
    parser.add_argument('--legacy', type=Path, help='Exact reviewed legacy Hub graph identities')
    parser.add_argument('--automatic', action='store_true', help='Apply only after the live notice, interval and deployment gates')
    parser.add_argument('--ghcr-inventory', type=Path, help='Fresh workflow inventory for local preview only')
    args = parser.parse_args()
    if not re.fullmatch(r'[a-zA-Z0-9-]+', args.owner):
        raise ValueError('Invalid registry owner')
    now = datetime.now(timezone.utc)
    policy = json.loads(args.policy.read_text(encoding='utf-8'))
    catalog = json.loads(args.catalog.read_text(encoding='utf-8'))
    validate_policy(policy, now, args.apply)
    legacy = json.loads(args.legacy.read_text(encoding='utf-8')) if args.legacy else None
    automatic = None
    gate = None
    if args.automatic or (args.apply and policy.get('automatic', {}).get('enabled')):
        if not args.apply or legacy is None or args.ghcr_inventory:
            raise ValueError('Automatic policy apply requires a live exact legacy scope and --apply')
        automatic = load_automation()
        gate = automatic.evaluate(args.owner + '/tor-guard-relay', policy, legacy,
                                  os.environ.get('REGISTRY_RETIREMENT_NOTICE_URL', ''), now,
                                  int(os.environ.get('GITHUB_RUN_ID', '0')))
        if not gate['due']:
            raise ValueError('Deletion blocked: ' + gate['reason'])
    if args.apply and args.ghcr_inventory:
        raise ValueError('Deletion requires live package inventory, never a saved snapshot')

    class SavedPackages:
        def versions(self):
            items = json.loads(args.ghcr_inventory.read_text(encoding='utf-8'))
            if not isinstance(items, list):
                raise ValueError('Expected a flat package inventory')
            return items

    client = Client()
    repository = args.owner + '/tor-guard-relay'
    before = prune.release_snapshot(repository)
    reports = []
    for registry in (args.owner.lower() + '/onion-relay', 'ghcr.io/' + args.owner.lower() + '/onion-relay'):
        packages = (SavedPackages() if args.ghcr_inventory else prune.Packages(registry)) if is_ghcr(registry) else None
        reports.append(plan_registry(client, registry, catalog, policy, now, packages, legacy))
    fingerprint = hash_json({'policy': policy, 'legacy': legacy, 'publication_run': catalog['publication_run'],
                             'releases_before': before, 'registries': reports})
    result = {'plan_sha256': fingerprint, 'deployment_review_complete': policy['deployment_review_complete'],
              'releases_before': before, 'registries': reports, 'completed': False, 'automatic_gate': gate}

    def save():
        args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8', newline='\n')

    save()
    print(f'Preview SHA256: {fingerprint}', flush=True)
    for report in reports:
        print(f"{report['registry']}: {len(report['manifest_targets'])} manifests, {len(report['package_targets'])} package versions eligible", flush=True)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with Path(os.environ['GITHUB_STEP_SUMMARY']).open('a', encoding='utf-8') as summary:
            summary.write(f"## 🛡️ Rebuild retention preview\n\nPlan SHA256: `{fingerprint}`\n\n")
            summary.write(f"Deployment coverage verified: **{policy['deployment_review_complete']}**\n\n")
            for report in reports:
                count = len(report['manifest_targets']) + len(report['package_targets'])
                summary.write(f"- {report['registry']}: {count} eligible manifests/package versions\n")
            summary.write('\n📎 Review the protection graphs and limitations in the retained artifact before any removal.\n')
    if args.apply:
        confirm_plan(fingerprint, args.confirm_plan)
        # Recheck BOTH registries before the first deletion.
        for report in reports:
            verify(client, report, prune.Packages(report['registry']) if is_ghcr(report['registry']) else None)
            verify_layers(client, report)
        deployment = None
        if automatic:
            # This durable intent survives a killed runner and expired artifacts.
            # A later run cannot blindly retry a partially applied plan.
            deployment = automatic.start(repository, fingerprint, gate['contract_sha256'])
            result['cleanup_deployment_id'] = deployment
            save()
        try:
            for report in reports:
                apply_registry(client, report, prune.Packages(report['registry']) if is_ghcr(report['registry']) else None, save)
            result['releases_after'] = prune.release_snapshot(repository)
            if result['releases_after'] != before:
                raise ValueError('GitHub release records or assets changed during cleanup')
            result['completed'] = True
            save()
            if deployment:
                automatic.finish(repository, deployment, 'success')
        except Exception:
            if deployment:
                automatic.finish(repository, deployment, 'failure')
            raise


if __name__ == '__main__':
    try:
        main()
    except sp.CalledProcessError as error:
        raise SystemExit(error.stderr or str(error)) from error
