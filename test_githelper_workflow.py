"""Integration tests use isolated local remotes, never the developer workspace."""
import argparse
import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from test_githelper import githelper as h, git, init_repo, run, GITHELPER
from githelper_workflow import (create_branches, lock_command, read_lock,
                                next_version, release_plan, stamp)
import sys


class VersionTests(unittest.TestCase):
    def test_bumps(self):
        for old, bump, expected in [
            ('5.0.0-rc3', 'rc', '5.0.0-rc4'),
            ('5.0.0-rc.9', 'rc', '5.0.0-rc10'),
            ('5.0.0-rc4', 'stable', '5.0.0'),
            ('5.0.0', 'patch', '5.0.1'),
            ('5.0.1', 'minor', '5.1.0'),
            ('5.1.0', 'major', '6.0.0'),
        ]:
            with self.subTest(old=old, bump=bump):
                self.assertEqual(next_version(old, bump), expected)

    def test_invalid_transitions(self):
        for old, bump in [('5.0.0', 'rc'), ('5.0.0', 'stable'),
                          ('5.0.0-rc3', 'patch'), ('garbage', 'patch')]:
            with self.subTest(old=old, bump=bump), self.assertRaises(RuntimeError):
                next_version(old, bump)



class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.remote = self.root / 'remote'
        init_repo(self.remote)
        (self.remote / 'file').write_text('base')
        git(['add', '.'], self.remote)
        git(['commit', '-m', 'base'], self.remote)
        self.base = git(['rev-parse', 'HEAD'], self.remote).stdout.strip()
        self.parent = self.root / 'parent'
        init_repo(self.parent)
        (self.parent / 'workspace.ini').write_text(f'[workspace]\ndefault_branch = main\n[module.module]\nurl = {self.remote}\nbranch = main\n')
        (self.parent / '.gitignore').write_text('/module/\n')
        git(['add', '.'], self.parent)
        git(['commit', '-m', 'parent'], self.parent)
        git(['clone', str(self.remote), 'module'], self.parent)
        self.module = self.parent / 'module'
        git(['config', 'user.name', 'Test'], self.module)
        git(['config', 'user.email', 'test@example.com'], self.module)
        self.patch = patch.object(h, 'get_repo_root', return_value=self.parent)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def lock(self, action, merged=False, from_main=False):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return lock_command(h, argparse.Namespace(lock_action=action, merged=merged, from_main=from_main))

    def test_new_branch_uses_remote_main_not_current_head(self):
        git(['switch', '-c', 'old-feature'], self.module)
        (self.module / 'other').write_text('unrelated')
        git(['add', '.'], self.module)
        git(['commit', '-m', 'unrelated'], self.module)
        args = argparse.Namespace(branch='codex/new', modules='module', base='origin/main')
        self.assertEqual(create_branches(h, args, False), 0)
        self.assertEqual(git(['rev-parse', 'HEAD'], self.module).stdout.strip(), self.base)
        self.assertFalse((self.module / 'other').exists())

    def test_dirty_clone_rejected_without_creating_branch(self):
        (self.module / 'file').write_text('local')
        args = argparse.Namespace(branch='codex/new', modules='module', base='origin/main')
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(create_branches(h, args, False), 1)
        self.assertFalse(h.local_branch_exists(self.module, 'codex/new'))

    def test_feature_preflight_leaves_parent_unchanged(self):
        git(['remote', 'add', 'origin', str(self.parent)], self.parent)
        (self.module / 'file').write_text('local')
        args = argparse.Namespace(branch='codex/new', modules='module', base='origin/main')
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(create_branches(h, args, True), 1)
        self.assertEqual(h.get_current_branch(self.parent), 'main')
        self.assertFalse(h.local_branch_exists(self.parent, 'codex/new'))

    def test_feature_registers_branch_set(self):
        git(['remote', 'add', 'origin', str(self.parent)], self.parent)
        args = argparse.Namespace(branch='codex/new', modules='module', base='origin/main')
        self.assertEqual(create_branches(h, args, True), 0)
        self.assertEqual(h.get_current_branch(self.parent), 'codex/new')
        self.assertEqual(h.load_workspace(self.parent).branch_sets['codex/new'], {'module': 'codex/new'})

    def test_lock_roundtrip_checkout_from_missing_clone(self):
        self.assertEqual(self.lock('capture'), 0)
        git(['switch', '-c', 'local'], self.module)
        (self.module / 'file').write_text('later')
        git(['commit', '-am', 'later'], self.module)
        self.assertEqual(self.lock('verify'), 1)
        self.assertEqual(self.lock('checkout'), 0)
        self.assertIsNone(h.get_current_branch(self.module))
        self.assertEqual(self.lock('verify', merged=True), 0)
        import shutil
        shutil.rmtree(self.module)
        self.assertEqual(self.lock('checkout'), 0)
        self.assertEqual(self.lock('verify'), 0)

    def test_unmerged_sha_rejected(self):
        git(['switch', '-c', 'feature'], self.module)
        (self.module / 'file').write_text('feature')
        git(['commit', '-am', 'feature'], self.module)
        self.assertEqual(self.lock('capture'), 0)
        self.assertEqual(self.lock('verify'), 0)
        self.assertEqual(self.lock('verify', merged=True), 1)

    def test_capture_from_main_preserves_local_work(self):
        (self.module / 'file').write_text('local')
        self.assertEqual(self.lock('capture', from_main=True), 0)
        self.assertEqual(read_lock(h, self.parent)[0]['commit'], self.base)
        self.assertEqual((self.module / 'file').read_text(), 'local')
        self.assertEqual(self.lock('checkout'), 0)
        self.assertEqual((self.module / 'file').read_text(), 'local')

    def test_checkout_blocks_overwriting_local_changes(self):
        self.assertEqual(self.lock('capture'), 0)
        (self.module / 'file').write_text('different commit')
        git(['commit', '-am', 'change file'], self.module)
        (self.module / 'file').write_text('local configuration')
        self.assertEqual(self.lock('checkout'), 1)
        self.assertEqual((self.module / 'file').read_text(), 'local configuration')

    def test_malformed_lock_rejected(self):
        self.assertEqual(self.lock('capture'), 0)
        path = self.parent / 'workspace.lock'
        original = json.loads(path.read_text())
        for field, value in [('path', '../escape'), ('url', 'https://other.test'), ('commit', 'bad')]:
            data = json.loads(json.dumps(original))
            data['modules'][0][field] = value
            path.write_text(json.dumps(data))
            with self.subTest(field=field), self.assertRaises(RuntimeError):
                read_lock(h, self.parent)
        original['modules'] *= 2
        path.write_text(json.dumps(original))
        with self.assertRaises(RuntimeError):
            read_lock(h, self.parent)

    def test_pinned_upstream_tag_need_not_be_on_main(self):
        git(['tag', 'v1'], self.remote)
        git(['branch', '-m', 'upstream-dev'], self.remote)
        manifest = self.parent / 'workspace.ini'
        manifest.write_text(manifest.read_text().replace('branch = main', f'tag = v1\ncommit = {self.base}'))
        self.assertEqual(self.lock('capture', from_main=True), 0)
        self.assertEqual(self.lock('verify', merged=True), 0)

    def test_plan_orders_versions_numerically_and_requires_ancestry(self):
        git(['tag', '5.0.0-rc9'], self.parent)
        git(['tag', '5.0.0-rc10'], self.parent)
        self.assertEqual(release_plan(h, self.parent, 'rc')['version'], '5.0.0-rc11')
        git(['checkout', '--orphan', 'unrelated'], self.parent)
        git(['commit', '-m', 'unrelated'], self.parent)
        with self.assertRaises(RuntimeError):
            release_plan(h, self.parent, 'rc')

    def test_cli_label_validation(self):
        git(['tag', '5.0.0-rc3'], self.parent)
        valid = run([sys.executable, str(GITHELPER), 'release', 'plan', '--labels-json', '[{"name":"release:rc"}]'], self.parent)
        self.assertEqual(json.loads(valid.stdout)['version'], '5.0.0-rc4')
        result = __import__('subprocess').run([sys.executable, str(GITHELPER), 'release', 'plan', '--labels-json', '[{"name":"release:rc"},{"name":"release:stable"}]'], cwd=self.parent, capture_output=True)
        self.assertNotEqual(result.returncode, 0)


class ReleaseArtifactTests(unittest.TestCase):
    def setUp(self):
        from scripts import coordinator_release
        self.release = coordinator_release
        # Normal-publication fixtures stay independent of manual replacement inputs.
        env_patch = patch.dict('os.environ', {'REPLACE_VERSION': '', 'EXPECTED_TAG_SHA': ''})
        env_patch.start()
        self.addCleanup(env_patch.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.patch = patch.object(self.release, 'ROOT', self.root)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def test_package_includes_deployables_and_excludes_ignored_secrets(self):
        import zipfile
        init_repo(self.root)
        (self.root / 'workspace.ini').write_text('[workspace]\n[module.module]\nurl = /test/module\n')
        module = self.root / 'module'
        init_repo(module)
        (module / 'pom.xml').write_text('<project/>')
        git(['add', '.'], module)
        git(['commit', '-m', 'source'], module)
        entry = dict(name='module', path='module', url='/test/module', commit=git(['rev-parse', 'HEAD'], module).stdout.strip())
        (self.root / 'workspace.lock').write_text(json.dumps(dict(schema=1, modules=[entry])))
        (self.root / '.gitignore').write_text('/module/\n/vufind/\n/secret.env\n')
        (self.root / 'vufind').mkdir()
        (self.root / 'vufind/external-application.txt').write_text('external checkout')
        (self.root / 'secret.env').write_text('private')
        (self.root / 'VERSION').write_text('5.0.0-rc4\n')
        (self.root / 'release.json').write_text('{}')
        git(['add', 'workspace.ini', 'workspace.lock', '.gitignore'], self.root)
        for name, jar in [('lareferencia-lrharvester-app', 'harvester.jar'), ('lareferencia-shell', 'lareferencia-shell.jar'), ('lareferencia-entity-rest', 'entity-rest.jar'), ('lareferencia-oai-pmh', 'oai-pmh.jar')]:
            directory = self.root / name
            directory.mkdir()
            (directory / jar).write_bytes(b'jar')
        app = self.root / 'lareferencia-lrharvester-app'
        for name in ['admin-static', 'dashboard-static']:
            (app / name).mkdir()
            (app / name / 'index.html').write_text('<html/>')
        self.release.package('5.0.0-rc4')
        with zipfile.ZipFile(self.root / 'lareferencia-platform-5.0.0-rc4.zip') as archive:
            names = archive.namelist()
        self.assertNotIn('secret.env', names)
        self.assertFalse(any(n.startswith('vufind/') for n in names))
        self.assertFalse(any('.git/' in n for n in names))
        self.assertIn('module/pom.xml', names)
        self.assertIn('lareferencia-lrharvester-app/harvester.jar', names)
        self.assertIn('lareferencia-lrharvester-app/admin-static/index.html', names)
        self.assertIn('VERSION', names)
        import hashlib
        checksum = hashlib.sha256((self.root / 'lareferencia-platform-5.0.0-rc4.zip').read_bytes()).hexdigest()
        self.assertIn(checksum, (self.root / 'SHA256SUMS').read_text())

    def test_publication_uses_prepared_version_and_rejects_stale_number(self):
        init_repo(self.root)
        (self.root / 'pom.xml').write_text('<project xmlns="http://maven.apache.org/POM/4.0.0"><version>5.0.0-rc4</version></project>')
        (self.root / 'VERSION').write_text('5.0.0-rc4\n')
        pr = self.root / 'pr.json'
        pr.write_text(json.dumps({'labels': [{'name': 'release:rc'}]}))
        git(['add', '.'], self.root)
        git(['commit', '-m', 'baseline'], self.root)
        git(['tag', '5.0.0-rc3'], self.root)
        git(['commit', '--allow-empty', '-m', 'prepared coordinator'], self.root)
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.release.plan(str(pr))
        self.assertIn('version=5.0.0-rc4', output.getvalue())
        git(['tag', '5.0.0-rc4'], self.root)
        with contextlib.redirect_stdout(io.StringIO()):
            self.release.plan(str(pr))  # retry on its already-created tag
        git(['commit', '--allow-empty', '-m', 'later coordinator'], self.root)
        with self.assertRaisesRegex(RuntimeError, 'stale'):
            self.release.plan(str(pr))

    def test_published_release_is_preserved(self):
        from types import SimpleNamespace
        sha = 'a' * 40
        responses = [SimpleNamespace(returncode=0, stdout=json.dumps({'object': {'sha': sha}}), stderr=''),
                     SimpleNamespace(returncode=0, stdout=json.dumps({'draft': False}), stderr='')]
        with patch.dict('os.environ', {'GH_REPO': 'org/repo'}), patch.object(self.release, 'run', return_value=sha) as run_mock, patch.object(self.release.subprocess, 'run', side_effect=responses):
            self.release.publish('5.0.0')
        self.assertEqual(run_mock.call_count, 1)

    def test_conflicting_tag_is_never_overwritten(self):
        from types import SimpleNamespace
        response = SimpleNamespace(returncode=0, stdout=json.dumps({'object': {'sha': 'b'*40}}), stderr='')
        with patch.dict('os.environ', {'GH_REPO': 'org/repo'}), patch.object(self.release, 'run', return_value='a'*40) as run_mock, patch.object(self.release.subprocess, 'run', return_value=response), self.assertRaisesRegex(RuntimeError, 'different commit'):
            self.release.publish('5.0.0')
        self.assertEqual(run_mock.call_count, 1)

    def test_new_candidate_is_uploaded_before_publication(self):
        from types import SimpleNamespace
        response = SimpleNamespace(returncode=1, stdout='', stderr='HTTP 404')
        def command(*args):
            if args[:3] == ('gh', 'release', 'create'):
                self.assertEqual(Path(args[args.index('--notes-file') + 1]).read_text(), 'Prepared notes.\n')
            return 'a' * 40
        with patch.dict('os.environ', {'GH_REPO': 'org/repo'}), patch.object(self.release, 'run', side_effect=command) as run_mock, patch.object(self.release.subprocess, 'run', return_value=response), patch.object(self.release, 'release_notes', return_value='Prepared notes.\n'):
            self.release.publish('5.0.0-rc4')
        calls = [call.args for call in run_mock.call_args_list]
        self.assertIn('--prerelease', calls[-2])
        self.assertIn('--draft', calls[-2])
        self.assertEqual(calls[-1], ('gh', 'release', 'edit', '5.0.0-rc4', '--draft=false'))
        self.assertFalse(any('--clobber' in call or 'delete' in call for call in calls))


    def test_label_bootstrap_preserves_existing_labels(self):
        from types import SimpleNamespace
        response = SimpleNamespace(returncode=0, stdout='{}', stderr='')
        with patch.dict('os.environ', {'GH_REPO': 'org/repo'}), patch.object(self.release, 'run') as mutate, patch.object(self.release.subprocess, 'run', return_value=response) as lookup:
            self.release.labels()
        self.assertEqual(lookup.call_count, 5)
        mutate.assert_not_called()

    def test_label_bootstrap_creates_only_missing_labels(self):
        from types import SimpleNamespace
        missing = SimpleNamespace(returncode=1, stdout='', stderr='HTTP 404')
        existing = SimpleNamespace(returncode=0, stdout='{}', stderr='')
        with patch.dict('os.environ', {'GH_REPO': 'org/repo'}), patch.object(self.release, 'run') as mutate, patch.object(self.release.subprocess, 'run', side_effect=[missing, existing, existing, existing, existing]):
            self.release.labels()
        self.assertEqual(mutate.call_count, 1)
        self.assertIn('name=release:rc', mutate.call_args.args)

    def test_label_bootstrap_does_not_treat_auth_failure_as_missing(self):
        from types import SimpleNamespace
        response = SimpleNamespace(returncode=1, stdout='', stderr='HTTP 403')
        with patch.dict('os.environ', {'GH_REPO': 'org/repo'}), patch.object(self.release, 'run') as mutate, patch.object(self.release.subprocess, 'run', return_value=response), self.assertRaisesRegex(RuntimeError, '403'):
            self.release.labels()
        mutate.assert_not_called()


if __name__ == '__main__':
    unittest.main()
