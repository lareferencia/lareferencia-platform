"""Explicit RC replacement must preserve the published release until staging is verified."""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from scripts import replace_prerelease as replacement
from scripts import coordinator_release as release
from test_githelper import git, init_repo


class ReplacementTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory();self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.version = '5.0.0-rc4';self.old = 'a' * 40;self.new = 'b' * 40
        (self.root / 'pom.xml').write_text('<project xmlns="http://maven.apache.org/POM/4.0.0"><version>5.0.0-rc4</version></project>')
        (self.root / 'VERSION').write_text(self.version + '\n')
        self.names = ['lareferencia-platform-5.0.0-rc4.zip', 'SHA256SUMS', 'release.json', 'workspace.lock']
        for name in self.names:(self.root / name).write_bytes(b'new verified content')
        self.assets = [{'name':n,'size':20,'state':'uploaded','digest':'sha256:'+hashlib.sha256(b'new verified content').hexdigest()} for n in self.names]
        self.calls=[];self.bad_asset=False;self.tag_changed=False;self.tag_reads=0
        for obj, name, value in [(release, 'ROOT', self.root)]:
            p=patch.object(obj,name,value);p.start();self.addCleanup(p.stop)
        p=patch.dict(os.environ,{'GH_REPO':'test/repo','REPLACE_VERSION':'','EXPECTED_TAG_SHA':''});p.start();self.addCleanup(p.stop)

    def command(self,*args):
        self.calls.append(args)
        if args==('git','rev-parse','HEAD'):return self.new
        if args[:3]==('gh','release','create'):return 'draft created'
        path=args[2];method=args[args.index('--method')+1] if '--method' in args else 'GET'
        if method=='DELETE':return ''
        if method=='PATCH':return json.dumps({'html_url':'https://github.com/test/repo/releases/tag/'+self.version})
        if path.endswith('/git/ref/tags/'+self.version):
            self.tag_reads+=1
            return json.dumps({'object':{'sha':'c'*40 if self.tag_changed and self.tag_reads>1 else self.old}})
        if path.endswith('/releases/tags/'+self.version):return json.dumps({'id':10,'draft':False,'prerelease':True})
        if '/releases/tags/staging/' in path:
            assets=[dict(a) for a in self.assets]
            if self.bad_asset:assets[0]['digest']='sha256:wrong'
            return json.dumps({'id':20,'draft':True,'assets':assets})
        raise AssertionError(args)

    def perform(self):
        with patch.object(release,'run',side_effect=self.command),patch.object(replacement.subprocess,'run',return_value=SimpleNamespace(returncode=1)),contextlib.redirect_stdout(io.StringIO()):
            replacement.replace(self.version,self.old)

    def test_verified_draft_precedes_old_release_deletion_and_tag_swap(self):
        self.perform()
        create=next(i for i,c in enumerate(self.calls) if c[:3]==('gh','release','create'))
        delete=next(i for i,c in enumerate(self.calls) if c[2]=='repos/test/repo/releases/10' and 'DELETE' in c)
        tag=next(i for i,c in enumerate(self.calls) if c[2]=='repos/test/repo/git/refs/tags/'+self.version)
        publish=next(i for i,c in enumerate(self.calls) if c[2]=='repos/test/repo/releases/20')
        self.assertLess(create,delete);self.assertLess(delete,tag);self.assertLess(tag,publish)

    def test_bad_asset_preserves_old_release_and_tag(self):
        self.bad_asset=True
        with self.assertRaisesRegex(RuntimeError,'asset'):self.perform()
        self.assertFalse(any('DELETE' in c or 'PATCH' in c for c in self.calls))

    def test_concurrent_tag_change_preserves_old_release(self):
        self.tag_changed=True
        with self.assertRaisesRegex(RuntimeError,'changed during'):self.perform()
        self.assertFalse(any('DELETE' in c or 'PATCH' in c for c in self.calls))

    def test_stable_version_and_wrong_expected_tag_are_rejected(self):
        with self.assertRaisesRegex(RuntimeError,'numbered RC'):replacement.validate('5.0.0',self.old)
        self.old='c'*40
        with patch.object(release,'run',side_effect=lambda *a:self.new if a[0]=='git' else json.dumps({'id':10,'prerelease':True,'draft':False}) if '/releases/' in a[2] else json.dumps({'object':{'sha':'a'*40}})):
            with self.assertRaisesRegex(RuntimeError,'tag changed'):replacement.replace(self.version,self.old)

    def test_explicit_plan_accepts_current_rc_only_with_expected_old_tag(self):
        init_repo(self.root);git(['add','.'],self.root);git(['commit','-m','old release'],self.root)
        old=git(['rev-parse','HEAD'],self.root).stdout.strip();git(['tag',self.version],self.root)
        git(['commit','--allow-empty','-m','new coordinator'],self.root)
        pr=self.root/'pr.json';pr.write_text('{"labels":[]}')
        with patch.dict(os.environ,{'REPLACE_VERSION':self.version,'EXPECTED_TAG_SHA':old}),contextlib.redirect_stdout(io.StringIO()) as out:
            release.plan(str(pr))
        self.assertIn('version='+self.version,out.getvalue())
        with patch.dict(os.environ,{'REPLACE_VERSION':self.version,'EXPECTED_TAG_SHA':'c'*40}),self.assertRaisesRegex(RuntimeError,'expected old SHA'):
            release.plan(str(pr))
