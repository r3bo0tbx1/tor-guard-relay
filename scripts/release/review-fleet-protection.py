#!/usr/bin/env python3
"""Prepare an additive retention-policy proposal from fresh Docker inventories."""
import argparse
import copy
from datetime import datetime, timedelta, timezone
import importlib.util
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('rebuild_review', Path(__file__).with_name('prune-rebuilds.py'))
rebuild = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rebuild)


def prepare(policy, reports, expected_engines, complete, owner, now):
    """No network, Docker commands or writes; never replace evidence with today's date."""
    rebuild.validate_policy(policy, now)
    if not complete:
        raise ValueError('Confirm coverage of the complete fleet, dormant deployments and required rollbacks')
    if type(expected_engines) is not int or expected_engines < 1 or len(reports) != expected_engines:
        raise ValueError('One report is required for every expected Docker engine')
    engines, observed, image_ids, digests = set(), [], set(), set()
    for report in reports:
        engine = report.get('engine_id_sha256')
        if (type(report.get('schema')) is not int or report['schema'] != 1
                or report.get('owner') != owner or not isinstance(engine, str)
                or not re.fullmatch(r'[0-9a-f]{64}', engine)):
            raise ValueError('Use an inventory from the current collector for the correct repository owner')
        if engine in engines:
            raise ValueError('Duplicate Docker engine: Windows and WSL can inspect the same engine')
        engines.add(engine)
        if (type(report.get('relay_containers')) is not int or report['relay_containers'] < 1
                or report.get('deployment_review_complete') is not False):
            raise ValueError('Each report must contain relay containers; an empty local engine cannot certify a fleet')
        try:
            date = rebuild.stamp(report['observed_at'])
        except (KeyError, TypeError, ValueError, AttributeError) as error:
            raise ValueError('Inventory requires a valid observation timestamp') from error
        if now - date < timedelta(0) or now - date > timedelta(days=7):
            raise ValueError('Inventory must be no more than seven days old and cannot be from the future')
        observed.append(date)
        for field, target in (('protected_image_ids', image_ids), ('protected_digests', digests)):
            values = report.get(field)
            if not isinstance(values, list) or any(not isinstance(x, str) or not rebuild.DIGEST.fullmatch(x) for x in values):
                raise ValueError('Inventory protection lists require complete SHA256 identities')
            target.update(values)
        if not report['protected_image_ids']:
            raise ValueError('Relay inventory must include image IDs')
    proposal = copy.deepcopy(policy)
    proposal['protected_image_ids'] = sorted(set(policy['protected_image_ids']) | image_ids)
    proposal['protected_digests'] = sorted(set(policy['protected_digests']) | digests)
    proposal['deployment_review_complete'] = True
    # The oldest observation determines expiry. Reprocessing cannot renew it.
    proposal['deployment_reviewed_at'] = min(observed).strftime('%Y-%m-%dT%H:%M:%SZ')
    rebuild.validate_policy(proposal, now, apply=True)
    return proposal


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--policy', type=Path, default=ROOT / 'build/registry-retention.json')
    parser.add_argument('--report', action='append', type=Path, required=True)
    parser.add_argument('--expected-engines', type=int, required=True)
    parser.add_argument('--owner', default='r3bo0tbx1')
    parser.add_argument('--confirm-complete-fleet', action='store_true',
                        help='All fleet engines, dormant deployments and required rollback identities are covered')
    parser.add_argument('--output', type=Path, required=True, help='New proposal file; existing files are never overwritten')
    args = parser.parse_args()
    proposal = prepare(json.loads(args.policy.read_text(encoding='utf-8')),
                       [json.loads(path.read_text(encoding='utf-8')) for path in args.report],
                       args.expected_engines, args.confirm_complete_fleet, args.owner.lower(),
                       datetime.now(timezone.utc))
    with args.output.open('x', encoding='utf-8', newline='\n') as target:
        target.write(json.dumps(proposal, indent=2) + '\n')
    print('Prepared an additive policy proposal. Review the diff before replacing the tracked policy. No deletion performed.')


if __name__ == '__main__':
    main()
