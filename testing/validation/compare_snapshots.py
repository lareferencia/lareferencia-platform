"""Compare two completed, offline validations of the same harvested catalog."""
import argparse
from collections import Counter
from contextlib import ExitStack, closing
import json
from itertools import zip_longest
from pathlib import Path
import sqlite3


def open_copy(stack, path):
    wal = path.with_name(path.name + "-wal")
    if not path.is_file() or (wal.is_file() and wal.stat().st_size):
        raise ValueError(f"Expected a checkpointed database copy at {path}")
    db = stack.enter_context(closing(sqlite3.connect(path.resolve().as_uri() + "?mode=ro&immutable=1", uri=True)))
    db.row_factory = sqlite3.Row
    return db


def validation_rows(stack, snapshot):
    catalog = open_copy(stack, snapshot / "catalog/catalog.db")
    validation = open_copy(stack, snapshot / "validation/validation.db")
    originals = catalog.execute("SELECT id, identifier, original_metadata_hash, datestamp FROM oai_record WHERE deleted=0 ORDER BY id")
    results = validation.execute("SELECT * FROM record_validation WHERE deleted=0 ORDER BY identifier_hash")
    rules = {description[0] for description in results.description if description[0].startswith("rule_")}

    def joined():
        for original, result in zip_longest(originals, results):
            if original is None or result is None or original["id"] != result["identifier_hash"]:
                raise ValueError(f"Validation does not cover every active original in {snapshot}")
            yield tuple(original), result

    return rules, joined()


def compare(before, after):
    counts = Counter(dict.fromkeys(("records", "previous_transformed", "current_transformed",
                                     "accepted", "rejected", "is_valid", "identifier",
                                     "published_metadata_hash", "is_transformed"), 0))
    rule_counts = Counter()
    with ExitStack() as stack:
        old_rules, old = validation_rows(stack, before)
        new_rules, new = validation_rows(stack, after)
        for pair in zip_longest(old, new):
            left, right = pair
            if left is None or right is None or left[0] != right[0]:
                raise ValueError("The harvested originals differ between copies")
            original, a = left
            _, b = right
            counts["records"] += 1
            counts["previous_transformed"] += int(a["is_transformed"])
            counts["current_transformed"] += int(b["is_transformed"])
            changes = {}
            for key in ("is_valid", "identifier", "published_metadata_hash", "is_transformed"):
                if a[key] != b[key]:
                    changes[key] = [a[key], b[key]]
                    counts[key] += 1
            if a["is_valid"] != b["is_valid"]:
                counts["accepted" if b["is_valid"] else "rejected"] += 1
            rules = {r: [a[r], b[r]] for r in sorted(old_rules & new_rules) if a[r] != b[r]}
            for r in sorted(new_rules - old_rules):
                if b[r] == 0:
                    rules[r] = [None, b[r]]
            for r in sorted(old_rules - new_rules):
                if a[r] == 0:
                    rules[r] = [a[r], None]
            rule_counts.update(rules.keys())
            if changes or rules:
                yield {"identifier_hash": original[0], "original_identifier": original[1], "changes": changes, "rules": rules}
        yield {"summary": dict(counts), "rule_differences": dict(rule_counts),
               "added_rules": sorted(new_rules - old_rules), "removed_rules": sorted(old_rules - new_rules)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    args = parser.parse_args()
    for item in compare(args.before, args.after):
        print(json.dumps(item, ensure_ascii=False))
