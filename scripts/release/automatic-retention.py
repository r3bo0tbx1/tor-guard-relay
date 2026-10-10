#!/usr/bin/env python3
"""Authorize automatic retention from a public notice and completed run history."""
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess as sp

spec = importlib.util.spec_from_file_location('rebuild_retention', Path(__file__).with_name('prune-rebuilds.py'))
rebuild = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rebuild)
ENVIRONMENT = 'registry-retention'


def api(path):
    return json.loads(sp.check_output(['gh', 'api', path], text=True, encoding='utf-8'))


def contract(policy, legacy):
    automatic = policy['automatic']
    return {'keep_builds': policy['keep_builds'], 'grace_days': policy['grace_days'],
            'migration_days': automatic['migration_days'], 'interval_days': automatic['interval_days'],
            'legacy_sha256': rebuild.hash_json(legacy), 'architectures': ['amd64', 'arm64'],
            'scope': 'Reviewed legacy digests and evidence-backed superseded rebuilds; preserve deployed, original and tagged images'}


def marker(policy, legacy):
    return 'registry-retirement-policy-sha256: ' + rebuild.hash_json(contract(policy, legacy))


def validate_settings(policy):
    automatic = policy.get('automatic', {})
    if (type(automatic.get('enabled')) is not bool
            or type(automatic.get('migration_days')) is not int or automatic['migration_days'] < 14
            or type(automatic.get('interval_days')) is not int or automatic['interval_days'] < 14
            or policy.get('grace_days', 0) < 14
            or not isinstance(automatic.get('acknowledged_failed_deployments'), list)
            or any(type(x) is not int or x <= 0 for x in automatic['acknowledged_failed_deployments'])):
        raise ValueError('Automatic retention requires a 14-day window, interval and image grace period')
    rebuild.validate_policy(policy, datetime.now(timezone.utc))


def check_notice(repository, url, policy, legacy, now, fetch=api):
    match = re.fullmatch(r'https://github\.com/' + re.escape(repository) + r'/issues/([1-9][0-9]*)', url or '')
    if not match:
        return {'due': False, 'reason': 'Publish the notice and set REGISTRY_RETIREMENT_NOTICE_URL to its issue URL'}
    metadata = fetch('repos/' + repository)
    if metadata.get('private') is not False:
        raise ValueError('The retirement notice must be publicly readable')
    issue = fetch(f'repos/{repository}/issues/{match[1]}')
    if (issue.get('html_url') != url or 'pull_request' in issue or issue.get('state') != 'open'
            or issue.get('author_association') not in {'OWNER', 'MEMBER', 'COLLABORATOR'}
            or issue.get('user', {}).get('type') != 'User'
            or marker(policy, legacy) not in (issue.get('body') or '').splitlines()):
        return {'due': False, 'reason': 'Notice is closed, untrusted or does not match the reviewed retention contract'}
    created, edited = rebuild.stamp(issue['created_at']), rebuild.stamp(issue['updated_at'])
    if edited < created or created > now or edited > now:
        raise ValueError('Invalid retirement notice publication timestamps')
    # Edits conservatively restart the window; an earlier manually entered date
    # can never accelerate retirement. All dates are server-issued UTC values.
    deadline = max(created, edited) + timedelta(days=policy['automatic']['migration_days'])
    return {'due': now >= deadline, 'reason': 'Notice window complete' if now >= deadline else 'Waiting for the full notice window',
            'notice_url': url, 'notice_updated_at': edited.isoformat(),
            'not_before': deadline.isoformat(), 'contract_sha256': rebuild.hash_json(contract(policy, legacy))}


def history(repository, current_run, acknowledged, fetch=api):
    """Durable deployment records survive artifact expiry and lost runners."""
    latest = None
    page = 1
    while True:
        records = fetch(f'repos/{repository}/deployments?environment={ENVIRONMENT}&task=registry-retention&per_page=100&page={page}')
        for record in records:
            payload = record.get('payload', {})
            if (not isinstance(payload, dict) or payload.get('schema') != 1
                    or type(payload.get('run_id')) is not int
                    or not re.fullmatch(r'[0-9a-f]{64}', payload.get('plan_sha256', ''))):
                raise ValueError('Invalid automatic cleanup deployment record')
            # Reruns keep GITHUB_RUN_ID. Never ignore this run's previous intent;
            # a retry after a killed runner must be reconciled like any other.
            statuses = fetch(f'repos/{repository}/deployments/{record["id"]}/statuses?per_page=100')
            complete = bool(statuses) and statuses[0]['state'] == 'success'
            if not complete and record['id'] not in acknowledged:
                return latest, f'Reconcile interrupted cleanup deployment {record["id"]} (run {payload["run_id"]}) before acknowledging it in the policy'
            # Count an acknowledged attempt too: reconciliation is not permission
            # to retry immediately. Failed requests can complete asynchronously.
            finished = rebuild.stamp(statuses[0]['created_at'] if statuses else record['created_at'])
            latest = max(latest, finished) if latest else finished
        if len(records) < 100:
            break
        page += 1
    return latest, None


def evaluate(repository, policy, legacy, url, now, current_run=0, fetch=api):
    validate_settings(policy)
    if not policy['automatic']['enabled']:
        return {'due': False, 'reason': 'Automatic retention is disabled'}
    result = check_notice(repository, url, policy, legacy, now, fetch)
    if not result['due']:
        return result
    last, blocked = history(repository, current_run, policy['automatic']['acknowledged_failed_deployments'], fetch)
    if blocked:
        return {**result, 'due': False, 'reason': blocked}
    if last:
        next_run = last + timedelta(days=policy['automatic']['interval_days'])
        if last > now:
            raise ValueError('Automatic cleanup history is in the future')
        result['next_cleanup_at'] = next_run.isoformat()
        if now < next_run:
            return {**result, 'due': False, 'reason': 'Waiting for the 14-day cleanup interval'}
    try:
        rebuild.validate_policy(policy, now, apply=True)
    except ValueError as error:
        return {**result, 'due': False, 'reason': str(error)}
    return {**result, 'reason': 'Notice, interval and deployment protection permit a fresh cleanup plan'}


def post(path, body):
    return json.loads(sp.check_output(['gh', 'api', '--method', 'POST', path, '--input', '-'],
                                     input=json.dumps(body), text=True, encoding='utf-8'))


def start(repository, plan_sha256, contract_sha256):
    run = int(os.environ['GITHUB_RUN_ID'])
    revision = sp.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    if run <= 0 or not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('Automatic apply requires a trusted workflow revision and run')
    record = post(f'repos/{repository}/deployments', {
        'ref': revision, 'task': 'registry-retention', 'environment': ENVIRONMENT,
        'auto_merge': False, 'required_contexts': [], 'production_environment': False,
        'transient_environment': False, 'description': 'Guarded automatic registry retention',
        'payload': {'schema': 1, 'run_id': run, 'plan_sha256': plan_sha256, 'contract_sha256': contract_sha256}})
    identity = record['id']
    if type(identity) is not int or identity <= 0:
        raise ValueError('No durable automatic cleanup identity was created')
    finish(repository, identity, 'in_progress')
    return identity


def finish(repository, identity, state):
    post(f'repos/{repository}/deployments/{identity}/statuses', {
        'state': state, 'auto_inactive': False,
        'log_url': f'https://github.com/{repository}/actions/runs/' + os.environ['GITHUB_RUN_ID'],
        'description': 'Registry retention ' + state})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', required=True)
    parser.add_argument('--policy', type=Path, required=True)
    parser.add_argument('--legacy', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--notice-draft', type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-zA-Z0-9-]+/tor-guard-relay', args.repository):
        raise ValueError('Expected the relay repository')
    policy = json.loads(args.policy.read_text(encoding='utf-8'))
    legacy = json.loads(args.legacy.read_text(encoding='utf-8'))
    if args.notice_draft:
        validate_settings(policy)
        text = ('# 🧹 Container image retention notice\n\n'
                'We are enabling automatic cleanup of reviewed older container images. '
                'The first cleanup cannot occur before 14 full days after this notice is published; '
                'editing this notice restarts that window. Later cleanup runs are at least 14 days apart.\n\n'
                'Current stable/edge images, both AMD64 and ARM64 architecture graphs, original-release '
                'images and reviewed deployment/rollback digests remain protected. '
                'At least two recent builds are kept; superseded recorded builds must be at least 14 days old.\n\n'
                'The exact initial legacy digest list is in '
                '[build/retired-image-builds.json](https://github.com/' + args.repository +
                '/blob/main/build/retired-image-builds.json). '
                'This notice authorizes that reviewed list and the rolling retention policy, '
                'not arbitrary untagged images.\n\n'
                'Operators pinned to older digests should migrate or request protection before the window ends. '
                'Fresh pulls of retired digests will fail, including on ARM64. Running containers alone '
                'do not guarantee a future pull. Verify encrypted recovery backups and relay fingerprints when upgrading.\n\n'
                'Deletion remains conditional on fresh complete deployment protection, successful publication/security '
                'evidence and live registry checks. Interrupted cleanup requires reconciliation. '
                'GitHub releases, source tags and uploaded release assets remain available.\n\n' + marker(policy, legacy) + '\n')
        args.notice_draft.write_text(text, encoding='utf-8', newline='\n')
        return
    result = evaluate(args.repository, policy, legacy, os.environ.get('REGISTRY_RETIREMENT_NOTICE_URL', ''),
                      datetime.now(timezone.utc), int(os.environ.get('GITHUB_RUN_ID', '0')))
    args.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(result['reason'])
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as stream:
            stream.write('due=' + str(result['due']).lower() + '\n')
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as stream:
            stream.write('## 🧹 Automatic retirement gate\n\n' + result['reason'] + '\n\n')
            if result.get('not_before'):
                stream.write('Notice deadline (UTC): `' + result['not_before'] + '`\n')


if __name__ == '__main__':
    main()
