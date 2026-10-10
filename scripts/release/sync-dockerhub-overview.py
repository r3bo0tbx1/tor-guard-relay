#!/usr/bin/env python3
"""Update only the Docker Hub overview from the maintained, branded document."""
import json
import os
from pathlib import Path
import urllib.request

REPOSITORY = 'https://hub.docker.com/v2/repositories/r3bo0tbx1/onion-relay/'


def request(url, method='GET', data=None, token=None):
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    body = json.dumps(data).encode() if data is not None else None
    with urllib.request.urlopen(urllib.request.Request(url, body, headers, method=method), timeout=60) as response:
        return json.load(response)


def main():
    root = Path(__file__).resolve().parents[2]
    overview = (root / 'docs/DOCKERHUB.md').read_text(encoding='utf-8')
    if not overview.strip() or len(overview) > 25000:
        raise ValueError('Docker Hub overview must contain 1–25000 characters')
    before = request(REPOSITORY)
    Path('dockerhub-overview-before.json').write_text(json.dumps(before, indent=2) + '\n', encoding='utf-8')
    login = request('https://hub.docker.com/v2/users/login/', 'POST',
                    {'username': os.environ['DOCKERHUB_USERNAME'], 'password': os.environ['DOCKERHUB_TOKEN']})
    request(REPOSITORY, 'PATCH', {'full_description': overview}, login['token'])
    after = request(REPOSITORY)
    if after['full_description'].replace('\r\n', '\n') != overview:
        raise ValueError('Published Docker Hub overview differs from the maintained document')
    for key in ('name', 'namespace', 'is_private', 'description'):
        if after.get(key) != before.get(key):
            raise ValueError('Unrelated Docker Hub repository metadata changed: ' + key)
    print('Docker Hub overview matches docs/DOCKERHUB.md; repository metadata preserved.')


if __name__ == '__main__':
    main()
