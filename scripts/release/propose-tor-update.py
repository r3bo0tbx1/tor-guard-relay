#!/usr/bin/env python3
"""Prepare and maintain the single reviewed Tor source update PR."""
import argparse
import base64
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess as sp
from urllib.parse import urlencode

ROOT = Path(__file__).resolve().parents[2]
LOCK = 'build/tor/source.json'
BRANCH = 'build/tor-source-update'
MARKER = 'Tor-Source-Update: managed-v1'
PR_MARKER = '<!-- tor-source-update:managed-v1 -->'
spec = importlib.util.spec_from_file_location('updater', Path(__file__).with_name('update-tor-source.py'))
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)
source = updater.source


def prepare(report, assessments, owner, current):
    if report.get('current') != current or 'error' in report:
        raise ValueError('Source report must match the checked-out pin and have no verification error')
    if report.get('update_available') is False and report.get('latest') == current['version']:
        return None
    proposed = source.validate_lock(report.get('proposed'))
    version = proposed['version']
    if (report.get('update_available') is not True or report.get('latest') != version
            or report.get('verified') != proposed or source.version_tuple(version) <= source.version_tuple(current['version'])):
        raise ValueError('Expected an authenticated newer source proposal from this run')
    installed = updater.published_versions(assessments, owner)
    highest = max((row['version'] for row in installed), key=source.version_tuple)
    if source.version_tuple(version) < source.version_tuple(highest):
        raise ValueError(f'Tor {version} is below Tor {highest} already installed in a published image')
    return {'current': current, 'proposed': proposed, 'highest_installed': highest}


def api(path, method='GET', body=None):
    command = ['gh', 'api', '--method', method, path]
    if body is not None:
        command.extend(['--input', '-'])
    response = sp.run(command, input=None if body is None else json.dumps(body),
                      capture_output=True, encoding='utf-8', timeout=60)
    if response.returncode:
        detail = next((line for line in response.stderr.splitlines() if line.startswith('gh: ')),
                      f'exit code {response.returncode}')
        raise RuntimeError(f'GitHub {method} {path} failed: {detail}')
    return json.loads(response.stdout)


def git(*args, env=None):
    return sp.check_output(['git', *args], cwd=ROOT, env=env, text=True, encoding='utf-8').strip()


def head_state(prefix, repository, base, bot, read=api):
    refs = read(f'{prefix}/git/matching-refs/heads/{BRANCH}')
    heads = [row['object']['sha'] for row in refs if row['ref'] == f'refs/heads/{BRANCH}']
    if len(heads) > 1:
        raise ValueError('Ambiguous update branch')
    head = heads[0] if heads else ''
    owner = repository.split('/')[0]
    query = urlencode({'state': 'open', 'head': f'{owner}:{BRANCH}', 'per_page': 2})
    opened = read(f'{prefix}/pulls?{query}')
    if len(opened) > 1:
        raise ValueError('Expected a single open update PR')
    pull = opened[0] if opened else None
    if pull and (not head or pull['head']['sha'] != head or pull['head']['repo']['full_name'] != repository
                 or pull['base']['ref'] != 'main' or pull['user']['login'] != bot
                 or PR_MARKER not in (pull.get('body') or '')):
        raise ValueError('The existing PR is outside the managed Tor update branch contract')
    if not head:
        return head, pull, None, None
    if not re.fullmatch(r'[a-f0-9]{40}', head):
        raise ValueError('Invalid update branch head')
    commit = read(f'{prefix}/commits/{head}')
    if ((commit.get('author') or {}).get('login') != bot or (commit.get('committer') or {}).get('login') != bot
            or len(commit['parents']) != 1
            or MARKER not in commit['commit']['message'].splitlines()
            or [(row['filename'], row['status']) for row in commit['files']] != [(LOCK, 'modified')]):
        raise ValueError('The update branch contains changes outside the managed bot commit')
    parent = commit['parents'][0]['sha']
    if parent != base and read(f'{prefix}/compare/{parent}...{base}')['status'] != 'ahead':
        raise ValueError('The managed commit parent is outside main history')
    item = read(f'{prefix}/contents/{LOCK}?ref={head}')
    if item['encoding'] != 'base64':
        raise ValueError('Expected the stored source lock as base64')
    pending = source.validate_lock(json.loads(base64.b64decode(item['content'])))
    return head, pull, parent, pending


def declined_version(prefix, owner, bot, read=api):
    query = urlencode({'state': 'closed', 'head': f'{owner}:{BRANCH}', 'base': 'main',
                       'sort': 'updated', 'direction': 'desc', 'per_page': 1})
    closed = read(f'{prefix}/pulls?{query}')
    if not closed or closed[0].get('merged_at') or closed[0]['user']['login'] != bot:
        return None
    body = closed[0].get('body') or ''
    marker = re.search(r'(?m)^<!-- tor-source-update:version=(\d+\.\d+\.\d+\.\d+) -->$', body)
    return marker[1] if PR_MARKER in body and marker else None


def publish(plan, repository, app_slug):
    if (os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('GITHUB_REF') != 'refs/heads/main'
            or os.environ.get('GITHUB_REPOSITORY') != repository
            or os.environ.get('GITHUB_EVENT_NAME') not in {'schedule', 'workflow_dispatch'}
            or not os.environ.get('GH_TOKEN') or not re.fullmatch(r'[a-zA-Z0-9-]+', app_slug)):
        raise ValueError('PR updates require the main-branch workflow and its GitHub App token')
    prefix = f'repos/{repository}'
    bot = app_slug + '[bot]'
    base = git('rev-parse', 'HEAD')
    proposed = source.validate_lock(plan['proposed'])
    version = proposed['version']
    current = source.load_lock()
    if (plan['current'] != current or source.version_tuple(version) <= source.version_tuple(current['version'])
            or source.version_tuple(version) < source.version_tuple(plan['highest_installed'])):
        raise ValueError('The prepared proposal no longer matches the reviewed source or image baseline')
    head, pull, parent, pending = head_state(prefix, repository, base, bot, api)
    if pending and (source.version_tuple(version) < source.version_tuple(pending['version'])
                    or (version == pending['version'] and proposed != pending)):
        raise ValueError('The proposal would downgrade or replace the pending authenticated source')
    if not pull:
        declined = declined_version(prefix, repository.split('/')[0], bot, api)
        if declined and source.version_tuple(version) <= source.version_tuple(declined):
            print(f'Tor {version} was declined. A newer release can open another proposal.')
            return
    if api(f'{prefix}/git/ref/heads/main')['object']['sha'] != base:
        raise ValueError('Main advanced while gathering evidence. Run the check again on current main.')
    title = f'⬆️ build(deps): update authenticated Tor source to {version}'
    version_marker = f'<!-- tor-source-update:version={version} -->'
    body = (f'{PR_MARKER}\n{version_marker}\n\n'
            f'Update the reviewed Tor source from **{current["version"]}** to **{version}**. '
            f'The highest installed Tor version in the published-image assessments was **{plan["highest_installed"]}**.\n\n'
            f'- Archive SHA256: `{proposed["sha256"]}`\n'
            f'- Approved signing fingerprint: `{proposed["signing_fingerprint"]}`\n'
            f'- [Upstream changelog](https://gitlab.torproject.org/tpo/core/tor/-/blob/tor-{version}/ChangeLog)\n'
            f'- [Verification run](https://github.com/{repository}/actions/runs/{os.environ["GITHUB_RUN_ID"]})\n\n'
            '- [ ] Review upstream changes and add any operator or torrc guidance this release requires.\n'
            '- [ ] Confirm all required checks pass on this revision before merging.\n')
    changed = parent != base or pending != proposed
    if changed:
        if git('status', '--porcelain'):
            raise ValueError('Expected a clean checkout before preparing the bot commit')
        account = api('users/' + bot)
        if account['login'] != bot or account['type'] != 'Bot' or type(account['id']) is not int:
            raise ValueError('Could not confirm the GitHub App bot identity')
        env = {**os.environ, 'GIT_AUTHOR_NAME': bot, 'GIT_COMMITTER_NAME': bot,
               'GIT_AUTHOR_EMAIL': f'{account["id"]}+{bot}@users.noreply.github.com',
               'GIT_COMMITTER_EMAIL': f'{account["id"]}+{bot}@users.noreply.github.com', 'GIT_TERMINAL_PROMPT': '0'}
        (ROOT / LOCK).write_text(json.dumps(proposed, indent=2) + '\n', encoding='utf-8', newline='\n')
        git('add', '--', LOCK)
        git('-c', 'commit.gpgsign=false', 'commit', '-m', title, '-m', MARKER, env=env)
        ref = f'refs/heads/{BRANCH}'
        if api(f'{prefix}/git/ref/heads/main')['object']['sha'] != base:
            raise ValueError('Main advanced before the branch update. Run the check again on current main.')
        git('-c', 'credential.helper=', '-c', 'credential.helper=!gh auth git-credential', 'push',
            f'--force-with-lease={ref}:{head}', f'https://github.com/{repository}.git', f'HEAD:{ref}', env=env)
    if pull is None:
        pull = api(f'{prefix}/pulls', 'POST', {'title': title, 'body': body, 'base': 'main',
                                              'head': BRANCH, 'draft': True})
    elif changed or pull['title'] != title or version_marker not in (pull.get('body') or ''):
        pull = api(f'{prefix}/pulls/{pull["number"]}', 'PATCH', {'title': title, 'body': body})
    print(f'Tor source proposal: {pull["html_url"]}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', type=Path, required=True)
    parser.add_argument('--repository', required=True)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--published-reports', type=Path)
    parser.add_argument('--app-slug')
    args = parser.parse_args()
    if not re.fullmatch(r'[a-zA-Z0-9-]+/tor-guard-relay', args.repository):
        parser.error('Expected the tor-guard-relay repository')
    if args.app_slug:
        publish(json.loads(args.plan.read_text(encoding='utf-8')), args.repository, args.app_slug)
        return
    if args.report is None or args.published_reports is None:
        parser.error('Preparing a proposal requires the same-run report and image assessments')
    report = json.loads(args.report.read_text(encoding='utf-8'))
    plan = prepare(report, args.published_reports, args.repository.split('/')[0], source.load_lock())
    args.plan.write_text(json.dumps(plan, indent=2) + '\n', encoding='utf-8', newline='\n')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
            output.write('ready=' + str(plan is not None).lower() + '\n')
    print('Authenticated update ready for PR review.' if plan else 'Reviewed Tor source is current.')


if __name__ == '__main__':
    main()
