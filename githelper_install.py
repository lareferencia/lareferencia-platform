"""Prepare source checkouts independently of the chosen build tool."""
import argparse
import json
from pathlib import Path
from githelper_workflow import checked, require_repository, read_lock, lock_command


def initialize_feature(h, root, args, mapping):
    try:
        ws = h.load_workspace(root)
        selected = h.select_modules(ws, args.modules)
        entries = {e['name']: e for e in read_lock(h, root)}
        for m in selected:
            if (root / m.path).exists():
                require_repository(h, root / m.path)
                origin = checked(h, root / m.path, 'remote', 'get-url', 'origin')
                if (h.url_to_https(origin) or origin).removesuffix('.git') != (h.url_to_https(m.url) or m.url).removesuffix('.git'):
                    raise RuntimeError(f'{m.name}: origin differs from manifest.')
        frozen = [m.name for m in selected if m.name not in mapping]
        if frozen and lock_command(h, argparse.Namespace(lock_action='checkout', merged=False, modules=','.join(frozen))):
            return 1
        for m in selected:
            if m.name not in mapping:
                continue
            repo = root / m.path
            if not repo.exists():
                checked(h, root, 'clone', '--no-checkout', '--', m.url, m.path)
            origin = checked(h, repo, 'remote', 'get-url', 'origin')
            if (h.url_to_https(origin) or origin).removesuffix('.git') != (h.url_to_https(m.url) or m.url).removesuffix('.git'):
                raise RuntimeError(f'{m.name}: origin differs from manifest.')
            checked(h, repo, 'fetch', 'origin')
            result = h.switch_to_branch(repo, mapping[m.name])
            if result.returncode:
                raise RuntimeError(result.stderr or result.stdout)
        return 0
    except (RuntimeError, OSError, ValueError) as exc:
        return h.fail(str(exc))


def switch(h, args):
    try:
        root = h.get_repo_root()
        require_repository(h, root)
        checked(h, root, 'fetch', 'origin')
        target = args.branch
        checked(h, root, 'check-ref-format', '--branch', target)
        ref = target
        if not h.run_git(['rev-parse', '--verify', ref + '^{commit}'], root).returncode == 0:
            ref = 'origin/' + target
        checked(h, root, 'rev-parse', '--verify', ref + '^{commit}')
        if not h.ref_contains_path(root, ref, 'workspace.ini'):
            raise RuntimeError('Target has no workspace.ini; inspect historical versions with plain git checkout.')
        # Check both current and destination paths before switching the parent.
        paths = {m.path for m in h.load_workspace(root).modules}
        raw = h.run_git(['show', ref + ':workspace.lock'], root)
        if raw.returncode == 0:
            paths.update(e['path'] for e in json.loads(raw.stdout)['modules'])
        for path in paths:
            h.validate_module_path(path)
            repo = root / path
            if repo.exists():
                require_repository(h, repo)
        if h.run_git(['rev-parse', '--verify', 'refs/tags/' + target], root).returncode == 0:
            checked(h, root, 'checkout', '--no-overwrite-ignore', '--detach', 'refs/tags/' + target)
        else:
            result = h.switch_to_branch(root, target)
            if result.returncode:
                raise RuntimeError(result.stderr or result.stdout)
        return h.cmd_init(argparse.Namespace(dev=False, modules=args.modules, branch_set=None,
                                             legacy_branch=None, jobs=4, depth=0))
    except (RuntimeError, OSError, ValueError, KeyError) as exc:
        return h.fail(str(exc))
