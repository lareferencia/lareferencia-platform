import sqlite3
import tempfile
import unittest
from pathlib import Path

from compare_snapshots import compare


class SnapshotDiffTest(unittest.TestCase):
    def test_explains_rejection_and_checks_originals(self):
        with tempfile.TemporaryDirectory() as tmp:
            paths = [Path(tmp) / key for key in ("before", "after")]
            for i, path in enumerate(paths):
                (path / "catalog").mkdir(parents=True)
                (path / "validation").mkdir()
                with sqlite3.connect(path / "catalog/catalog.db") as db:
                    db.execute("CREATE TABLE oai_record(id, identifier, original_metadata_hash, datestamp, deleted)")
                    db.execute("INSERT INTO oai_record VALUES ('k','oai:id','hash','2020',0)")
                with sqlite3.connect(path / "validation/validation.db") as db:
                    db.execute("CREATE TABLE record_validation(identifier_hash,identifier,published_metadata_hash,is_valid,is_transformed,deleted,rule_1)")
                    db.execute("INSERT INTO record_validation VALUES ('k','oai:id','hash',?,0,0,?)", (1-i, 1-i))
            row, summary = compare(*paths)
            self.assertEqual(row["rules"], {"rule_1": [1, 0]})
            self.assertEqual(summary["summary"]["rejected"], 1)
            with sqlite3.connect(paths[1] / "catalog/catalog.db") as db:
                db.execute("UPDATE oai_record SET original_metadata_hash='other'")
            with self.assertRaisesRegex(ValueError, "originals differ"):
                list(compare(*paths))
