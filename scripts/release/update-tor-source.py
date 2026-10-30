#!/usr/bin/env python3
"""Detect a stable Tor release and prepare its authenticated source pin locally."""
import argparse
import importlib.util
import json
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('tor_source', ROOT / 'build/tor/source.py')
source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', help='Select an exact stable upstream release instead of discovering it')
    parser.add_argument('--write', action='store_true', help='Update only the local source lock after verification')
    parser.add_argument('--output', type=Path, help='Retain the current/proposed lock and update status as JSON')
    args = parser.parse_args()
    current = source.load_lock()
    report = {'current': current}
    try:
        latest = args.version or source.latest_release()
        report.update(latest=latest, update_available=latest != current['version'])
        if source.version_tuple(latest) < source.version_tuple(current['version']):
            raise ValueError('Refusing to downgrade the reviewed Tor source version')
        if report['update_available']:
            with tempfile.TemporaryDirectory(prefix='tor-source-update-') as directory:
                report['proposed'] = source.fetch_release(latest, directory)
            if args.write:
                (ROOT / 'build/tor/source.json').write_text(json.dumps(report['proposed'], indent=2) + '\n',
                                                           encoding='utf-8', newline='\n')
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        if args.output:
            args.output.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8', newline='\n')
        print(json.dumps(report, indent=2))
    return 1 if report['update_available'] and not args.write else 0


if __name__ == '__main__':
    raise SystemExit(main())
