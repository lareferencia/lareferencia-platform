#!/usr/bin/env python3
"""Publish the exact version already committed and validated in the coordinator."""
import hashlib
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
loader = importlib.machinery.SourceFileLoader('release_githelper', str(ROOT / 'githelper'))
spec = importlib.util.spec_from_loader(loader.name, loader)
h = importlib.util.module_from_spec(spec)
sys.modules[loader.name] = h
loader.exec_module(h)
from githelper_workflow import read_lock, release_plan, VERSION


def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def plan(pr_path):
    pr = json.loads(Path(pr_path).read_text())
    labels = [e['name'][8:] for e in pr['labels'] if e['name'].startswith('release:')]
    if len(labels) != 1 or labels[0] not in ('patch', 'minor', 'major', 'rc', 'stable'):
        raise RuntimeError('Exactly one release label is required.')
    sha = run('git', 'rev-parse', 'HEAD')
    existing = [t for t in run('git', 'tag', '--points-at', sha).splitlines() if VERSION.fullmatch(t)]
    if len(existing) > 1:
        raise RuntimeError('Multiple release versions point at coordinator SHA.')
    from platform_versioning import read_version
    version = (ROOT / 'VERSION').read_text().strip()
    expected = existing[0] if existing else release_plan(h, ROOT, labels[0])['version']
    if not VERSION.fullmatch(version) or version != expected or read_version(ROOT) != version:
        raise RuntimeError(f'Prepared version is stale or inconsistent; run githelper release prepare --bump {labels[0]} (expected {expected}).')
    print(f'version={version}')


def metadata(pr_path, version):
    pr = json.loads(Path(pr_path).read_text())
    data = dict(version=version, coordinator_pr=pr['html_url'],
                coordinator_commit=run('git', 'rev-parse', 'HEAD'),
                modules=read_lock(h, ROOT),
                source_version=version)
    (ROOT / 'release.json').write_text(json.dumps(data, indent=2) + '\n')


def package(version):
    # Explicit allowlist of tracked files avoids local config, secrets, caches,
    # recursive archives and unrelated files in a runner workspace.
    archive = ROOT / f'lareferencia-platform-{version}.zip'
    directories = [ROOT] + [ROOT / e['path'] for e in read_lock(h, ROOT)]
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as output:
        added = set()
        def add(path):
            relative = path.relative_to(ROOT).as_posix()
            if path.is_file() and not path.is_symlink() and relative not in added:
                output.write(path, relative)
                added.add(relative)
        for directory in directories:
            for filename in run('git', '-C', str(directory), 'ls-files', '-z').split('\0'):
                if filename:
                    add(directory / filename)
        for name in ('VERSION', 'release.json'):
            add(ROOT / name)
        runtime_jars = {
            'lareferencia-lrharvester-app': 'harvester.jar',
            'lareferencia-shell': 'lareferencia-shell.jar',
            'lareferencia-entity-rest': 'entity-rest.jar',
            'lareferencia-oai-pmh': 'oai-pmh.jar',
        }
        for module, jar in runtime_jars.items():
            path = ROOT / module / jar
            if not path.is_file():
                raise RuntimeError(f'Missing deployable JAR: {path}')
            add(path)
        app = ROOT / 'lareferencia-lrharvester-app'
        for folder in ('admin-static', 'dashboard-static'):
            directory = app / folder
            if not directory.is_dir() or not any(directory.rglob('index.html')):
                raise RuntimeError(f'Missing built frontend: {folder}')
            for path in directory.rglob('*'):
                add(path)
        for module in runtime_jars:
            add(ROOT / module / 'config/third-party-context.xml')
    hasher = hashlib.sha256()
    with archive.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            hasher.update(chunk)
    digest = hasher.hexdigest()
    (ROOT / 'SHA256SUMS').write_text(f'{digest}  {archive.name}\n')



def labels():
    """Bootstrap release labels on trusted main pushes, preserving existing labels."""
    repo = os.environ['GH_REPO']
    for bump in ('rc', 'stable', 'patch', 'minor', 'major'):
        name = f'release:{bump}'
        lookup = subprocess.run(['gh', 'api', f'repos/{repo}/labels/{name}'],
                                cwd=ROOT, text=True, capture_output=True)
        if lookup.returncode == 0:
            continue
        if '404' not in lookup.stderr:
            raise RuntimeError(lookup.stderr)
        run('gh', 'api', '--method', 'POST', f'repos/{repo}/labels',
            '-f', f'name={name}', '-f', 'color=1D76DB',
            '-f', f'description=Automatic platform release: {bump}')


def publish(version):
    sha = run('git', 'rev-parse', 'HEAD')
    # CLI authenticates tag creation through the API; checkout credentials stay
    # disabled throughout builds. No force-push, deletion or asset replacement.
    repo = os.environ['GH_REPO']
    lookup = subprocess.run(['gh', 'api', f'repos/{repo}/git/ref/tags/{version}'],
                            cwd=ROOT, text=True, capture_output=True)
    if lookup.returncode == 0:
        ref = json.loads(lookup.stdout)
        if ref['object']['sha'] != sha:
            raise RuntimeError('Existing release tag points at a different commit.')
    elif '404' in lookup.stderr:
        run('gh', 'api', '--method', 'POST', f'repos/{repo}/git/refs',
            '-f', f'ref=refs/tags/{version}', '-f', f'sha={sha}')
    else:
        raise RuntimeError(lookup.stderr)
    lookup = subprocess.run(['gh', 'api', f'repos/{repo}/releases/tags/{version}'],
                            cwd=ROOT, text=True, capture_output=True)
    if lookup.returncode == 0:
        release = json.loads(lookup.stdout)
        if not release['draft']:
            print(f'Release {version} already published; preserved unchanged.')
            return
        raise RuntimeError('Existing draft must be inspected before retrying; no assets overwritten.')
    if '404' not in lookup.stderr:
        raise RuntimeError(lookup.stderr)
    args = ['gh', 'release', 'create', version, '--verify-tag', '--draft',
            '--title', f'Release {version}', '--generate-notes',
            f'lareferencia-platform-{version}.zip', 'SHA256SUMS', 'release.json', 'workspace.lock']
    if '-rc' in version:
        args.append('--prerelease')
    run(*args)
    run('gh', 'release', 'edit', version, '--draft=false')


if __name__ == '__main__':
    try:
        {'plan': plan, 'metadata': metadata, 'package': package, 'publish': publish, 'labels': labels}[sys.argv[1]](*sys.argv[2:])
    except (RuntimeError, OSError, subprocess.CalledProcessError, ValueError, KeyError, TypeError) as exc:
        sys.exit(str(exc))
