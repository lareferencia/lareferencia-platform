"""Small coordinated workflow; Git stores branches, commits and release state."""
import argparse
import json
import subprocess
from pathlib import Path
from urllib.parse import urlparse

from githelper_workflow import checked, clean, read_lock, release_plan, lock_command


def gh(repo, *args):
    try:
        p = subprocess.run(['gh', *args], cwd=repo, text=True, capture_output=True)
    except FileNotFoundError:
        raise RuntimeError('Install GitHub CLI (gh) and run gh auth login to manage PRs.')
    if p.returncode:
        raise RuntimeError(p.stderr.strip() or p.stdout.strip())
    return p.stdout.strip()


def repository(h, repo):
    url = checked(h, repo, 'remote', 'get-url', 'origin')
    url = h.url_to_https(url) or url
    path = urlparse(url).path.strip('/').removesuffix('.git')
    if len(path.split('/')) != 2:
        raise RuntimeError(f'{repo}: origin must identify a GitHub owner/repository.')
    return path


def context(h):
    root = h.get_repo_root()
    workspace = h.load_workspace(root)
    branch = h.get_current_branch(root)
    if not branch or branch == 'main':
        raise RuntimeError('Switch to a coordinated feature branch first.')
    mapping = workspace.branch_sets.get(branch)
    if mapping is None:
        raise RuntimeError('No branch-set for this branch; use feature start first.')
    return root, workspace, branch, dict(mapping)


def add(h, args):
    root, ws, branch, mapping = context(h)
    selected = h.select_modules(ws, args.modules)
    plans = []
    for m in selected:
        if m.name in mapping:
            raise RuntimeError(f'{m.name} already belongs to this feature.')
        repo = root / m.path
        clean(h, repo)
        checked(h, repo, 'fetch', 'origin', 'main')
        if h.local_branch_exists(repo, branch) or h.remote_branch_exists(repo, branch):
            raise RuntimeError(f'{m.name}: branch already exists: {branch}')
        plans.append((m, checked(h, repo, 'rev-parse', 'FETCH_HEAD')))
    for m, sha in plans:
        checked(h, root / m.path, 'switch', '--no-track', '-c', branch, sha)
        mapping[m.name] = branch
    h.write_branch_set(root, branch, mapping, force=True)
    h.info('Added: ' + ', '.join(m.name for m, _ in plans))
    return 0


def upsert(repo, repo_name, branch, title, body, draft=False):
    prs = json.loads(gh(repo, 'pr', 'list', '--repo', repo_name, '--head', branch,
                        '--base', 'main', '--state', 'open', '--json', 'number,url'))
    if prs:
        gh(repo, 'pr', 'edit', str(prs[0]['number']), '--repo', repo_name,
           '--title', title, '--body', body)
        return prs[0]['url']
    args = ['pr', 'create', '--repo', repo_name, '--base', 'main', '--head', branch,
            '--title', title, '--body', body]
    if draft:
        args.append('--draft')
    return gh(repo, *args)


def pull_requests(h, args):
    root, ws, branch, mapping = context(h)
    # Check every clone, including unselected modules, before any remote mutation.
    read_lock(h, root)
    root_dirty = checked(h, root, 'diff', '--name-only').splitlines()
    staged = checked(h, root, 'diff', '--cached', '--name-only')
    if staged or set(root_dirty) - {'workspace.ini', 'workspace.lock'} or checked(h, root, 'ls-files', '--others', '--exclude-standard'):
        raise RuntimeError('Commit platform source changes before githelper pr.')
    changes = []
    for m in ws.modules:
        repo = root / m.path
        clean(h, repo)
        checked(h, repo, 'fetch', 'origin', 'main')
        if m.name not in mapping:
            locked = next(e['commit'] for e in read_lock(h, root) if e['name'] == m.name)
            if checked(h, repo, 'rev-parse', 'HEAD') != locked:
                raise RuntimeError(f'{m.name}: changed outside this feature; use feature add.')
            continue
        expected = mapping[m.name]
        if h.get_current_branch(repo) != expected:
            raise RuntimeError(f'{m.name}: switch to registered branch {expected}.')
        if checked(h, repo, 'diff', '--name-only', 'FETCH_HEAD...HEAD'):
            changes.append((m, repo, expected))
    gh(root, 'auth', 'status')
    links = []
    for m, repo, head in changes:
        checked(h, repo, 'push', '-u', 'origin', head)
        url = upsert(repo, repository(h, repo), head, branch.split('/')[-1] + ': ' + m.name,
                     'Part of coordinated feature `' + branch + '`.\n\nMerge this module before finalizing the platform release lock.')
        links.append(f'- [{m.name}]({url})')
    if lock_command(h, argparse.Namespace(lock_action='capture', from_main=False, merged=False)):
        raise RuntimeError('Could not capture coordinator lock.')
    checked(h, root, 'add', '--', 'workspace.ini', 'workspace.lock')
    if checked(h, root, 'diff', '--cached', '--name-only'):
        checked(h, root, 'commit', '-m', 'Update coordinated module branches and lock')
    checked(h, root, 'push', '-u', 'origin', branch)
    body = 'Coordinated feature `' + branch + '`. CI builds the exact commits in workspace.lock.\n\n' + '\n'.join(links)
    body += '\n\nFor publication, run `githelper release prepare --bump rc` again after merging module PRs; commit/push the resulting coordinator and apply the matching release label.'
    url = upsert(root, repository(h, root), branch, branch.split('/')[-1], body, draft=True)
    h.info(url)
    return 0


def prepare(h, args):
    from platform_versioning import active_modules, version_changes
    root, ws, branch, mapping = context(h)
    clean(h, root)
    for m in ws.modules:
        clean(h, root / m.path)
    # Fetch tags without overwriting local tags (a conflicting tag fails visibly).
    checked(h, root, 'fetch', '--prune', 'origin', 'refs/tags/*:refs/githelper/releases/*')
    version = release_plan(h, root, args.bump, remote=True)['version']
    gh(root, 'auth', 'status')
    targets = {}
    locked = {e['name']: e['commit'] for e in read_lock(h, root)}
    for m in ws.modules:
        if m.name.startswith('lareferencia-contrib-'):
            targets[m.name] = locked[m.name]
            continue
        repo = root / m.path
        checked(h, repo, 'fetch', 'origin', m.tag or 'main')
        main = checked(h, repo, 'rev-parse', 'FETCH_HEAD^{commit}')
        if m.name in mapping:
            if h.get_current_branch(repo) != mapping[m.name]:
                raise RuntimeError(f'{m.name}: expected branch {mapping[m.name]}.')
            prs = json.loads(gh(repo, 'pr', 'list', '--repo', repository(h, repo),
                '--head', mapping[m.name], '--base', 'main', '--state', 'all', '--json', 'state'))
            merged = bool(prs) and prs[0]['state'] == 'MERGED'
            if not merged:
                targets[m.name] = None
                continue
        targets[m.name] = main
    for m in ws.modules:
        if targets[m.name] and m.path in active_modules(root):
            head = branch + '-version-' + version
            # Existing unused version branches need explicit inspection, never reset.
            if h.local_branch_exists(root / m.path, head) and m.name not in mapping:
                raise RuntimeError(f'{m.name}: version branch already exists: {head}')
    # Update merged modules; keep pending feature heads. Legacy pins remain pins.
    for m in ws.modules:
        if targets[m.name]:
            checked(h, root / m.path, 'checkout', '--detach', targets[m.name])
            mapping.pop(m.name, None)
    changes = version_changes(root, version)
    active = set(active_modules(root))
    for m in ws.modules:
        paths = [p for p in changes if p.is_relative_to(root / m.path)]
        if not paths or m.path not in active:
            continue
        repo = root / m.path
        if m.name not in mapping:
            head = branch + '-version-' + version
            checked(h, repo, 'check-ref-format', '--branch', head)
            if h.local_branch_exists(repo, head):
                raise RuntimeError(f'{m.name}: version branch already exists: {head}; inspect before retry.')
            checked(h, repo, 'switch', '--no-track', '-c', head, targets[m.name])
            mapping[m.name] = head
    for path, content in changes.items():
        path.write_text(content)
    for m in ws.modules:
        paths = [str(p.relative_to(root / m.path)) for p in changes if p.is_relative_to(root / m.path)]
        if paths:
            checked(h, root / m.path, 'add', '--', *paths)
            checked(h, root / m.path, 'commit', '-m', 'Align platform version ' + version)
    (root / 'VERSION').write_text(version + '\n')
    h.write_branch_set(root, branch, mapping, force=True)
    if lock_command(h, argparse.Namespace(lock_action='capture', from_main=False, merged=False)):
        raise RuntimeError('Could not capture release lock.')
    checked(h, root, 'add', '--', 'pom.xml', 'VERSION', 'workspace.ini', 'workspace.lock')
    if checked(h, root, 'diff', '--cached', '--name-only'):
        checked(h, root, 'commit', '-m', 'Prepare platform release ' + version)
    h.info(f'Prepared {version}. Run githelper pr. After module merges, repeat release prepare --bump {args.bump}, then pr; label coordinator release:{args.bump}.')
    return 0


def dispatch(h, action, args):
    try:
        return {'add': add, 'pr': pull_requests, 'prepare': prepare}[action](h, args)
    except (RuntimeError, OSError, ValueError, KeyError) as exc:
        return h.fail(str(exc))
