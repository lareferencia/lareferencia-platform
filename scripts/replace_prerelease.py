#!/usr/bin/env python3
"""Explicit RC replacement: upload and verify a draft before touching the old release."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from scripts import coordinator_release as release
from platform_versioning import read_version


def validate(version, expected_sha):
    if not re.fullmatch(r'\d+\.\d+\.\d+-rc\d+', version) or not re.fullmatch(r'[0-9a-f]{40}', expected_sha):
        raise RuntimeError('Replacement requires an explicit numbered RC and the old full tag SHA.')
    if read_version(release.ROOT) != version or (release.ROOT / 'VERSION').read_text().strip() != version:
        raise RuntimeError('Replacement version must match the committed parent and VERSION.')


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            h.update(block)
    return 'sha256:' + h.hexdigest()


def replace(version, expected_sha):
    validate(version, expected_sha)
    repo = os.environ['GH_REPO']
    base = f'repos/{repo}'
    def api(path, *args):
        raw = release.run('gh', 'api', base + path, *args)
        return json.loads(raw) if raw else None
    sha = release.run('git', 'rev-parse', 'HEAD')
    old = api('/releases/tags/' + version)
    if old['draft'] or not old['prerelease'] or old.get('immutable'):
        raise RuntimeError('Only a published, mutable prerelease can be explicitly replaced.')
    if api('/git/ref/tags/' + version)['object']['sha'] != expected_sha:
        raise RuntimeError('Published tag changed; refusing replacement.')
    if sha == expected_sha:
        raise RuntimeError('Replacement must identify a different coordinator commit.')
    files = [f'lareferencia-platform-{version}.zip', 'SHA256SUMS', 'release.json', 'workspace.lock']
    expected = {name: (release.ROOT / name).stat().st_size for name in files}
    checksums = {name: digest(release.ROOT / name) for name in files}
    staging_tag = f'replacement-{version}-{sha[:12]}'
    note = (f'Complete {version} integration. Replaces the earlier publication at {expected_sha}.\n\n'
            'Includes metadata exchange documentation, immutable SQLite export reads, export profile listing, '
            'batch outcome codes, reviewed component guides and corrected Admin build destination. '
            'Exact source commits and provenance are in workspace.lock and release.json.')
    release.run('gh', 'release', 'create', staging_tag, '--draft', '--prerelease', '--target', sha,
                '--title', f'Staged replacement {version}', '--notes', note, *files)
    # Drafts may not have a Git tag yet, so GitHub's published-by-tag endpoint
    # returns 404. Resolve the uniquely named draft through the release listing.
    matches = [r for r in api('/releases?per_page=100') if r['tag_name'] == staging_tag and r['draft']]
    if len(matches) != 1:
        raise RuntimeError('Expected exactly one uploaded replacement draft; old release preserved.')
    staged = matches[0]
    print(f"Replacement draft uploaded: {staged['id']}", flush=True)
    if not staged['draft']:
        raise RuntimeError('Replacement staging release must be a draft.')
    assets = {a['name']: a for a in staged['assets']}
    for name in files:
        a = assets.get(name, {})
        if a.get('state') != 'uploaded' or a.get('size') != expected[name] or a.get('digest') != checksums[name]:
            raise RuntimeError('Staged asset failed size/hash verification: ' + name)
    # Recheck immediately before the explicitly authorized destructive swap.
    if api('/git/ref/tags/' + version)['object']['sha'] != expected_sha or api('/releases/tags/' + version)['id'] != old['id']:
        raise RuntimeError('Published release changed during upload; old release preserved.')
    api('/releases/' + str(old['id']), '--method', 'DELETE')
    api('/git/refs/tags/' + version, '--method', 'PATCH', '-f', 'sha=' + sha, '-F', 'force=true')
    result = api('/releases/' + str(staged['id']), '--method', 'PATCH', '-f', 'tag_name=' + version,
                 '-f', 'target_commitish=' + sha, '-f', 'name=Release ' + version, '-F', 'draft=false', '-F', 'prerelease=true')
    # A draft may have created its temporary tag; remove only our own exact ref.
    lookup = subprocess.run(['gh', 'api', base + '/git/ref/tags/' + staging_tag], cwd=release.ROOT,
                            text=True, capture_output=True)
    if lookup.returncode == 0 and json.loads(lookup.stdout)['object']['sha'] == sha:
        api('/git/refs/tags/' + staging_tag, '--method', 'DELETE')
    print(result['html_url'])


if __name__ == '__main__':
    try:
        replace(*sys.argv[1:])
    except (RuntimeError, OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as exc:
        sys.exit(str(exc))
