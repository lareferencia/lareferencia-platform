"""Exercise real Git repositories; mock only GitHub's PR metadata/API."""
import argparse
import contextlib
import io
import json
import unittest
from unittest.mock import patch
import test_githelper_workflow as fixtures
from test_githelper import githelper as h, git, init_repo, run, GITHELPER
from githelper_coordination import add, prepare, pull_requests
from githelper_install import switch
import sys


class CoordinationTests(unittest.TestCase):
    setUp = fixtures.WorkflowTests.setUp
    lock = fixtures.WorkflowTests.lock

    def feature(self, mapping=True):
        git(['switch', '-c', 'codex/example'], self.parent)
        h.write_branch_set(self.parent, 'codex/example', {'module': 'codex/example'} if mapping else {})
        git(['add', '.'], self.parent)
        git(['commit', '--allow-empty', '-m', 'feature'], self.parent)

    def test_add_creates_from_remote_main_and_registers(self):
        self.feature(False)
        self.assertEqual(add(h, argparse.Namespace(modules='module')), 0)
        self.assertEqual(git(['rev-parse', 'HEAD'], self.module).stdout.strip(), self.base)
        self.assertEqual(h.load_workspace(self.parent).branch_sets['codex/example']['module'], 'codex/example')
        with self.assertRaises(RuntimeError):
            add(h, argparse.Namespace(modules='module'))

    def test_add_dirty_module_leaves_manifest_and_branch_unchanged(self):
        self.feature(False)
        before = (self.parent / 'workspace.ini').read_text()
        (self.module / 'file').write_text('local')
        with self.assertRaises(RuntimeError):
            add(h, argparse.Namespace(modules='module'))
        self.assertEqual((self.parent / 'workspace.ini').read_text(), before)
        self.assertEqual(h.get_current_branch(self.module), 'main')

    def test_init_downloads_frozen_commit_even_after_remote_advances(self):
        self.assertEqual(self.lock('capture'), 0)
        git(['add', '.'], self.parent)
        git(['commit', '-m', 'lock'], self.parent)
        (self.remote / 'file').write_text('new remote')
        git(['commit', '-am', 'advance main'], self.remote)
        import shutil
        shutil.rmtree(self.module)
        result = run([sys.executable, str(GITHELPER), 'init'], self.parent)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(git(['rev-parse', 'HEAD'], self.module).stdout.strip(), self.base)
        self.assertIsNone(h.get_current_branch(self.module))

    def test_switch_tag_preserves_local_changes(self):
        self.assertEqual(self.lock('capture'), 0)
        git(['add', '.'], self.parent)
        git(['commit', '-m', 'lock'], self.parent)
        git(['tag', '5.0.0-rc3'], self.parent)
        git(['remote', 'add', 'origin', str(self.parent)], self.parent)
        (self.parent / 'local-cache').write_text('generated')
        (self.module / 'file').write_text('local configuration')
        self.assertEqual(switch(h, argparse.Namespace(branch='5.0.0-rc3', modules=None)), 0)
        self.assertIsNone(h.get_current_branch(self.parent))
        self.assertEqual(git(['rev-parse', 'HEAD'], self.module).stdout.strip(), self.base)
        self.assertEqual((self.parent / 'local-cache').read_text(), 'generated')
        self.assertEqual((self.module / 'file').read_text(), 'local configuration')

    def test_pr_rejects_dirty_module_before_any_github_mutation(self):
        self.assertEqual(self.lock('capture'), 0)
        git(['add', '.'], self.parent)
        git(['commit', '-m', 'lock'], self.parent)
        self.feature()
        (self.module / 'file').write_text('dirty')
        with patch('githelper_coordination.gh') as api:
            with self.assertRaises(RuntimeError):
                pull_requests(h, argparse.Namespace())
            api.assert_not_called()

    def test_pr_updates_existing_and_skips_unchanged_module(self):
        self.assertEqual(self.lock('capture'), 0)
        git(['add', '.'], self.parent)
        git(['commit', '-m', 'lock'], self.parent)
        git(['remote', 'add', 'origin', str(self.parent)], self.parent)
        self.feature()
        git(['switch', '-c', 'codex/example'], self.module)
        def api(repo, *args):
            if args[:2] == ('pr', 'list'):
                return '[{"number":12,"url":"https://github.com/test/repo/pull/12"}]'
            return ''
        with patch('githelper_coordination.repository', return_value='test/repo'), patch('githelper_coordination.gh', side_effect=api) as call:
            pull_requests(h, argparse.Namespace())
            edits = [c for c in call.call_args_list if c.args[1:3] == ('pr', 'edit')]
            self.assertEqual(len(edits), 1)  # coordinator only
            self.assertFalse(any(c.args[1:3] == ('pr', 'create') for c in call.call_args_list))

    def test_prepare_is_repeatable_and_refreshes_squash_merge(self):
        ns = 'http://maven.apache.org/POM/4.0.0'
        (self.parent / 'pom.xml').write_text(f'''<project xmlns="{ns}"><modelVersion>4.0.0</modelVersion><groupId>test</groupId><artifactId>parent</artifactId><version>5.0.0-rc3</version><modules><module>module</module></modules><dependencyManagement><dependencies><dependency><groupId>test</groupId><artifactId>module</artifactId><version>${{project.version}}</version></dependency></dependencies></dependencyManagement></project>''')
        (self.remote / 'pom.xml').write_text(f'''<project xmlns="{ns}"><modelVersion>4.0.0</modelVersion><parent><groupId>test</groupId><artifactId>parent</artifactId><version>5.0.0-rc3</version><relativePath>../pom.xml</relativePath></parent><artifactId>module</artifactId></project>''')
        git(['add', '.'], self.remote)
        git(['commit', '-m', 'pom'], self.remote)
        git(['pull', '--ff-only'], self.module)
        self.assertEqual(self.lock('capture'), 0)
        git(['add', '.'], self.parent)
        git(['commit', '-m', 'reactor'], self.parent)
        git(['tag', '5.0.0-rc3'], self.parent)
        git(['remote', 'add', 'origin', str(self.parent)], self.parent)
        self.feature()
        git(['switch', '-c', 'codex/example'], self.module)
        merged = False
        def api(repo, *args):
            return '[{"state":"MERGED"}]' if merged else '[]'
        args = argparse.Namespace(bump='rc')
        with patch('githelper_coordination.gh', side_effect=api), patch('githelper_coordination.repository', return_value='test/module'):
            prepare(h, args)
            head = git(['rev-parse', 'HEAD'], self.module).stdout.strip()
            self.assertEqual((self.parent / 'VERSION').read_text().strip(), '5.0.0-rc4')
            prepare(h, args)
            self.assertEqual(git(['rev-parse', 'HEAD'], self.module).stdout.strip(), head)
            git(['push', 'origin', 'codex/example'], self.module)
            git(['merge', '--squash', 'codex/example'], self.remote)
            git(['commit', '-m', 'squash version PR'], self.remote)
            merged = True
            prepare(h, args)
        self.assertEqual(h.load_workspace(self.parent).branch_sets['codex/example'], {})
        self.assertEqual(self.lock('verify', merged=True), 0)
        self.assertEqual(git(['status', '--porcelain'], self.parent).stdout.strip(), '')

    def test_prepare_creates_a_version_branch_for_python_tools(self):
        name = 'lareferencia-metadata-tools'
        remote = self.root / 'python-remote'
        init_repo(remote)
        (remote / 'pyproject.toml').write_text('[project]\nname = "lareferencia-metadata-tools"\nversion = "5.0.0rc3"\n')
        git(['add', '.'], remote)
        git(['commit', '-m', 'Python project'], remote)
        manifest = self.parent / 'workspace.ini'
        manifest.write_text(manifest.read_text() + f'\n[module.{name}]\nurl = {remote}\nbranch = main\n')
        ignore = self.parent / '.gitignore'
        ignore.write_text(ignore.read_text() + f'/{name}/\n')
        (self.parent / 'pom.xml').write_text('<project xmlns="http://maven.apache.org/POM/4.0.0">'
            '<groupId>test</groupId><artifactId>parent</artifactId><version>5.0.0-rc3</version></project>')
        git(['clone', str(remote), name], self.parent)
        tools = self.parent / name
        git(['config', 'user.name', 'Test'], tools)
        git(['config', 'user.email', 'test@example.com'], tools)
        self.assertEqual(self.lock('capture'), 0)
        git(['add', '.'], self.parent)
        git(['commit', '-m', 'Register Python project'], self.parent)
        git(['tag', '5.0.0-rc3'], self.parent)
        git(['remote', 'add', 'origin', str(self.parent)], self.parent)
        self.feature(False)
        with patch('githelper_coordination.gh', return_value=''):
            self.assertEqual(prepare(h, argparse.Namespace(bump='rc')), 0)
        expected = 'codex/example-version-5.0.0-rc4'
        self.assertEqual(h.get_current_branch(tools), expected)
        self.assertEqual(h.load_workspace(self.parent).branch_sets['codex/example'][name], expected)
        self.assertIn('version = "5.0.0rc4"', (tools / 'pyproject.toml').read_text())
        self.assertEqual(self.lock('verify'), 0)
