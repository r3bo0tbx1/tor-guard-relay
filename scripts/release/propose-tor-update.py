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
REVIEW_ITEMS = (
    'Review upstream changes and add any operator or torrc guidance this release requires.',
    'Confirm all required checks pass on this revision before merging.',
)
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


def github(args, body=None, token=None, accepted=(0,)):
    env = {**os.environ, 'GH_TOKEN': token} if token is not None else None
    response = sp.run(['gh', *args], input=None if body is None else json.dumps(body),
                      capture_output=True, encoding='utf-8', timeout=60, env=env)
    if response.returncode not in accepted:
        detail = next((line for line in response.stderr.splitlines() if line.startswith('gh: ')),
                      f'exit code {response.returncode}')
        raise RuntimeError(f'GitHub {args[0]} failed: {detail}')
    return response


def api(path, method='GET', body=None, *, paginate=False, token=None):
    command = ['api', '--method', method, path]
    if body is not None:
        command.extend(['--input', '-'])
    if paginate:
        command.extend(['--paginate', '--slurp'])
    data = json.loads(github(command, body, token).stdout)
    return [row for page in data for row in page] if paginate else data


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


def bot_email(bot):
    account = api('users/' + bot)
    if account['login'] != bot or account['type'] != 'Bot' or type(account['id']) is not int:
        raise ValueError('Could not confirm the GitHub App bot identity')
    return f'{account["id"]}+{bot}@users.noreply.github.com'


def process_review(prefix, repository, pull, head, bot, title, merge_message):
    if pull['head']['sha'] != head:
        raise ValueError('The Tor update PR head changed before processing review')
    number = str(pull['number'])
    read_token = os.environ['GH_REVIEW_READ_TOKEN']
    if not read_token:
        raise ValueError('Missing the read-only GitHub token for Tor update review')
    comments_path = f'{prefix}/issues/{number}/comments'
    # Earlier review comments explicitly left the squash merge to the owner.
    marker = f'<!-- tor-source-merge-approval:{head} -->'
    comments = api(f'{comments_path}?per_page=100', paginate=True, token=read_token)
    review_comments = [row for row in comments if (row.get('user') or {}).get('login') == bot
                       and marker in (row.get('body') or '').splitlines()]
    if len(review_comments) > 1:
        raise ValueError('Expected one bot review comment for this Tor update revision')
    if not review_comments:
        api(comments_path, 'POST', {'body': (
            f'{marker}\n\n'
            f'### 🧅 Review Tor update `{head[:12]}`\n\n'
            'After reviewing the upstream changes and any operator guidance, react 👍 on this comment '
            'to authorize the squash merge. '
            'On the next scheduled or manual 🔒🧅 run, I’ll check that this revision passed the required '
            'checks, tick both boxes, mark the draft ready and squash merge it.'
        )})
        return
    comment_id = review_comments[0]['id']
    reactions = api(f'{prefix}/issues/comments/{comment_id}/reactions?content=%2B1&per_page=100',
                    paginate=True, token=read_token)
    owner_id = int(os.environ['GITHUB_REPOSITORY_OWNER_ID'])
    if not any(reaction['content'] == '+1' and (reaction.get('user') or {}).get('id') == owner_id
               for reaction in reactions):
        print('Waiting for the repository owner’s 👍 on the current Tor update revision.')
        return
    result = github(['pr', 'checks', number, '--repo', repository, '--required', '--json', 'bucket'],
                    token=read_token, accepted=(0, 1, 8))
    checks = json.loads(result.stdout) if result.stdout.strip() else []
    if result.returncode or not checks or any(check['bucket'] != 'pass' for check in checks):
        print('Waiting for every required check to pass on the Tor update PR.')
        return
    pull_path = f'{prefix}/pulls/{number}'
    current = api(pull_path)
    if (current['state'] != 'open' or current['head']['sha'] != head
            or current['user']['login'] != bot or current['base']['ref'] != 'main'
            or f'<!-- tor-source-head:{head} -->' not in (current.get('body') or '').splitlines()
            or PR_MARKER not in (current.get('body') or '').splitlines()):
        raise ValueError('The managed Tor update PR changed while checking review readiness')
    body = current['body']
    for item in REVIEW_ITEMS:
        body, count = re.subn(r'(?m)^- \[[ xX]\] ' + re.escape(item) + '$', f'- [x] {item}', body)
        if count != 1:
            raise ValueError('Expected the two Tor update review checklist items')
    attribution = f'Co-authored-by: {bot} <{bot_email(bot)}>'
    if body != current['body']:
        api(pull_path, 'PATCH', {'body': body})
    if current['draft']:
        github(['pr', 'ready', number, '--repo', repository])
    result = api(f'{pull_path}/merge', 'PUT', {'sha': head, 'merge_method': 'squash',
                                             'commit_title': title,
                                             'commit_message': f'{merge_message}\n\n{attribution}'})
    if result.get('merged') is not True:
        raise RuntimeError(f'GitHub did not merge Tor update PR #{number}')
    print(f'Tor update checklist complete. Squash merged PR #{number}.')


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
            'React 👍 on the bot’s merge approval comment for this revision after your upstream review.\n\n'
            + ''.join(f'- [ ] {item}\n' for item in REVIEW_ITEMS))
    changed = parent != base or pending != proposed
    if changed:
        if git('status', '--porcelain'):
            raise ValueError('Expected a clean checkout before preparing the bot commit')
        email = bot_email(bot)
        env = {**os.environ, 'GIT_AUTHOR_NAME': bot, 'GIT_COMMITTER_NAME': bot,
               'GIT_AUTHOR_EMAIL': email, 'GIT_COMMITTER_EMAIL': email, 'GIT_TERMINAL_PROMPT': '0'}
        (ROOT / LOCK).write_text(json.dumps(proposed, indent=2) + '\n', encoding='utf-8', newline='\n')
        git('add', '--', LOCK)
        git('-c', 'commit.gpgsign=false', 'commit', '-m', title, '-m', MARKER, env=env)
        ref = f'refs/heads/{BRANCH}'
        if api(f'{prefix}/git/ref/heads/main')['object']['sha'] != base:
            raise ValueError('Main advanced before the branch update. Run the check again on current main.')
        if pull and not pull['draft']:
            github(['pr', 'ready', str(pull['number']), '--repo', repository, '--undo'])
        git('-c', 'credential.helper=', '-c', 'credential.helper=!gh auth git-credential', 'push',
            f'--force-with-lease={ref}:{head}', f'https://github.com/{repository}.git', f'HEAD:{ref}', env=env)
        head = git('rev-parse', 'HEAD')
    head_marker = f'<!-- tor-source-head:{head} -->'
    body = head_marker + '\n' + body
    if pull is None:
        pull = api(f'{prefix}/pulls', 'POST', {'title': title, 'body': body, 'base': 'main',
                                              'head': BRANCH, 'draft': True})
    elif (changed or pull['title'] != title
          or not {head_marker, version_marker}.issubset((pull.get('body') or '').splitlines())):
        pull = api(f'{prefix}/pulls/{pull["number"]}', 'PATCH', {'title': title, 'body': body})
    owner = repository.split('/')[0]
    if not any(row['login'].lower() == owner.lower() for row in pull['assignees']):
        assigned = api(f'{prefix}/issues/{pull["number"]}/assignees', 'POST', {'assignees': [owner]})
        if not any(row['login'].lower() == owner.lower() for row in assigned['assignees']):
            raise RuntimeError('GitHub did not assign the Tor update PR to the repository owner')
    merge_message = f'Update the reviewed Tor source from {current["version"]} to {version}.'
    process_review(prefix, repository, pull, head, bot, title, merge_message)
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
