"""Verify the release notes extracted from the platform changelog."""
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from scripts import coordinator_release as release


class ReleaseNotesTests(unittest.TestCase):
    def setUp(self):
        directory = TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)

    def render(self, changelog):
        (self.root / 'CHANGELOG.md').write_text(changelog, encoding='utf-8')
        modules = [{'path': 'tools', 'url': 'https://github.com/org/tools.git', 'commit': 'a' * 40}]
        with patch.object(release, 'ROOT', self.root), patch.object(release, 'read_lock', return_value=modules):
            return release.release_notes('5.0.0-rc5', 'org/platform')

    def test_extracts_only_requested_version_and_pins_documentation(self):
        notes = self.render(
            '## Unreleased\nPending\n\n## 5.0.0-rc5 — 2026-11-23\n\n### Upgrade\n'
            '[Guide](./docs/UPGRADE.md#check) · [Tools](tools/README.md) · [PR](https://github.com/org/platform/pull/115)\n'
            '## 5.0.0-rc4\nPrevious\n'
        )
        self.assertEqual(
            notes,
            '### Upgrade\n[Guide](https://github.com/org/platform/blob/5.0.0-rc5/docs/UPGRADE.md#check)'
            f' · [Tools](https://github.com/org/tools/blob/{"a" * 40}/README.md)'
            ' · [PR](https://github.com/org/platform/pull/115)\n',
        )

    def test_rejects_missing_empty_and_duplicate_sections(self):
        for changelog in (
            '## 5.0.0-rc50\nOther version\n',
            '## 5.0.0-rc5\n\n## 5.0.0-rc4\nPrevious\n',
            '## 5.0.0-rc5\nFirst\n## 5.0.0-rc5 — 2026-11-23\nSecond\n',
        ):
            with self.subTest(changelog=changelog), self.assertRaises(RuntimeError):
                self.render(changelog)
