"""Version changes must follow inheritance and leave retired repositories untouched."""
import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

from platform_versioning import active_modules, read_version, set_platform_version, version_changes
from githelper_workflow import stamp

NS = '{http://maven.apache.org/POM/4.0.0}'


class InheritedVersionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.parent = self.root / 'pom.xml'
        self.parent.write_text('''<project xmlns="http://maven.apache.org/POM/4.0.0">
<modelVersion>4.0.0</modelVersion><groupId>org.lareferencia</groupId><artifactId>lareferencia-parent</artifactId><version>5.0.0-rc3</version>
<parent><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-parent</artifactId><version>3.5.0</version></parent>
<dependencyManagement><dependencies>
<dependency><groupId>org.lareferencia</groupId><artifactId>core</artifactId><version>${project.version}</version></dependency>
<dependency><groupId>org.lareferencia</groupId><artifactId>web</artifactId><version>${project.version}</version><type>pom</type></dependency>
</dependencies></dependencyManagement>
<modules><module>core</module><module>lareferencia-contrib-rcaap</module><module>vufind</module></modules>
<profiles><profile><id>frontends</id><modules><module>web</module></modules></profile></profiles></project>''')
        self.poms = []
        for name in ['core', 'web']:
            directory = self.root / name
            directory.mkdir()
            pom = directory / 'pom.xml'
            pom.write_text('''<project xmlns="http://maven.apache.org/POM/4.0.0">
<modelVersion>4.0.0</modelVersion><artifactId>'''+name+'''</artifactId>
<parent><groupId>org.lareferencia</groupId><artifactId>lareferencia-parent</artifactId><version>5.0.0-rc3</version><relativePath>../pom.xml</relativePath></parent>
<dependencies><dependency><groupId>org.lareferencia</groupId><artifactId>lareferencia-contrib-rcaap</artifactId><version>4.2.6</version></dependency>
<dependency><groupId>third.party</groupId><artifactId>external</artifactId><version>5.0.0-rc3</version></dependency></dependencies></project>''')
            self.poms.append(pom)
        self.npm = self.root / 'web/angular'
        self.npm.mkdir()
        (self.npm / 'package.json').write_text('{"name":"frontend","version":"0.1.0"}\n')
        (self.npm / 'package-lock.json').write_text('{"name":"frontend","version":"0.1.0","packages":{"":{"version":"0.1.0"},"node_modules/external":{"version":"0.1.0"}}}\n')
        self.excluded = []
        for name in ['lareferencia-contrib-rcaap', 'vufind']:
            p = self.root / name
            p.mkdir()
            for filename in ['pom.xml', 'package.json']:
                file = p / filename
                file.write_text('original legacy or external content')
                self.excluded.append(file)

    def test_stamp_updates_react_dashboard_package_and_lock(self):
        frontend = self.root / 'web/web'
        frontend.mkdir()
        for name in ('package.json', 'package-lock.json'):
            (frontend / name).write_bytes((self.npm / name).read_bytes())
        stamp(self.root, '5.0.0-rc5', [])
        self.assertEqual(json.loads((frontend / 'package.json').read_text())['version'], '5.0.0-rc5')
        lock = json.loads((frontend / 'package-lock.json').read_text())
        self.assertEqual(lock['version'], lock['packages']['']['version'])
        self.assertEqual(lock['version'], '5.0.0-rc5')

    def test_release_stamp_updates_only_inherited_platform_version_and_npm(self):
        old_excluded = {p:p.read_bytes() for p in self.excluded}
        stamp(self.root, '5.0.0-rc4', [{'path':'lareferencia-contrib-rcaap'}, {'path':'vufind'}])
        self.assertEqual(read_version(self.root), '5.0.0-rc4')
        self.assertIn('${project.version}', self.parent.read_text())
        self.assertIn('<version>3.5.0</version>', self.parent.read_text())
        for pom in self.poms:
            tree = ET.parse(pom).getroot()
            self.assertIsNone(tree.find(NS+'version'))
            self.assertEqual(tree.findtext(NS+'parent/'+NS+'version'), '5.0.0-rc4')
            self.assertIn('<version>4.2.6</version>', pom.read_text())
            self.assertIn('<version>5.0.0-rc3</version>', pom.read_text())
        lock = json.loads((self.npm/'package-lock.json').read_text())
        self.assertEqual(lock['version'], '5.0.0-rc4')
        self.assertEqual(lock['packages']['']['version'], '5.0.0-rc4')
        self.assertEqual(lock['packages']['node_modules/external']['version'], '0.1.0')
        self.assertEqual(json.loads((self.npm/'package.json').read_text())['version'], '5.0.0-rc4')
        self.assertEqual(old_excluded, {p:p.read_bytes() for p in self.excluded})
        self.assertEqual((self.root/'VERSION').read_text(), '5.0.0-rc4\n')

    def test_sync_checks_drift_without_writing(self):
        before = (self.npm/'package.json').read_bytes()
        self.assertTrue(version_changes(self.root, read_version(self.root)))
        self.assertEqual(before, (self.npm/'package.json').read_bytes())
        set_platform_version(self.root, '5.0.0-rc3')
        self.assertEqual(version_changes(self.root, '5.0.0-rc3'), {})

    def test_active_set_includes_frontends_but_excludes_legacy_and_vufind(self):
        self.assertEqual(active_modules(self.root), ['core','web'])

    def test_missing_module_fails_before_changing_any_version(self):
        self.poms[-1].unlink()
        old = self.parent.read_bytes()
        with self.assertRaisesRegex(RuntimeError, 'Missing active module'):
            set_platform_version(self.root, '5.0.0-rc4')
        self.assertEqual(self.parent.read_bytes(), old)

    def test_own_child_version_is_rejected(self):
        p = self.poms[0]
        p.write_text(p.read_text().replace('<artifactId>core</artifactId>', '<artifactId>core</artifactId><version>5.0.0-rc3</version>', 1))
        with self.assertRaisesRegex(RuntimeError, 'must inherit its version'):
            set_platform_version(self.root, '5.0.0-rc4')

    def test_internal_explicit_version_is_rejected(self):
        p = self.poms[1]
        p.write_text(p.read_text().replace('<dependencies>', '<dependencies><dependency><groupId>org.lareferencia</groupId><artifactId>core</artifactId><version>5.0.0-rc3</version></dependency>'))
        with self.assertRaisesRegex(RuntimeError, 'must use parent dependencyManagement'):
            set_platform_version(self.root, '5.0.0-rc4')

    def test_invalid_parent_is_rejected(self):
        p = self.poms[0]
        p.write_text(p.read_text().replace('<relativePath>../pom.xml</relativePath>', '<relativePath/>'))
        with self.assertRaisesRegex(RuntimeError, 'relativePath'):
            set_platform_version(self.root, '5.0.0-rc4')

    def test_non_centralized_dependency_management_is_rejected(self):
        self.parent.write_text(self.parent.read_text().replace('${project.version}', '5.0.0-rc3'))
        with self.assertRaisesRegex(RuntimeError, 'dependencyManagement'):
            set_platform_version(self.root, '5.0.0-rc4')

    def test_development_version_is_aligned_and_invalid_npm_version_is_rejected(self):
        set_platform_version(self.root, '5.0.0-rc4-SNAPSHOT')
        self.assertEqual(read_version(self.root), '5.0.0-rc4-SNAPSHOT')
        with self.assertRaisesRegex(RuntimeError, 'npm semver'):
            set_platform_version(self.root, '5.0.0_rc4')


if __name__ == '__main__':
    unittest.main()
