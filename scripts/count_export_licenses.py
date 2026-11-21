#!/usr/bin/env python3
"""Write unique license values and their record counts as JSONL."""

import argparse
from collections import Counter
import gzip
import json
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit


EXCLUDED_VOCABULARIES = re.compile(
    r"^(?:info:eu-repo(?:/|$)|(?:https?://)?(?:www\.)?"
    r"(?:purl\.org/coar|vocabularies\.coar-repositories\.org)(?:[/?#]|$))",
    re.IGNORECASE,
)


def is_web_url(value):
    if any(character.isspace() for character in value):
        return False
    try:
        url = urlsplit(value)
        return url.scheme in {"http", "https"} and bool(url.hostname)
    except ValueError:
        return False


def count_licenses(package, max_text_length):
    manifest = json.loads((package / "manifest.json").read_text(encoding="utf-8"))
    if manifest["status"] != "COMPLETE" or manifest["options"]["format"] != "jsonl":
        raise ValueError("Expected a COMPLETE JSONL export package")
    mapping = json.loads((package / "mapping.json").read_text(encoding="utf-8"))
    if "licenses" not in mapping.get("fields", {}):
        raise ValueError("The export mapping has no licenses field")

    counts = Counter()
    rows = 0
    for entry in manifest["files"]:
        relative = Path(entry["path"])
        if relative.name == "errors.jsonl" or not relative.name.endswith((".jsonl", ".jsonl.gz")):
            continue
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"Invalid part path: {relative}")
        part = package / relative
        open_part = gzip.open if part.suffix == ".gz" else open
        with open_part(part, "rt", encoding="utf-8") as stream:
            for line_number, line in enumerate(stream, 1):
                try:
                    values = json.loads(line)["data"]["licenses"]
                    if not isinstance(values, list) or not all(isinstance(v, str) for v in values):
                        raise ValueError("data.licenses must be an array of strings")
                except (TypeError, KeyError, ValueError) as error:
                    raise ValueError(f"{relative}:{line_number}: {error}") from error
                distinct = {value.strip() for value in values}
                counts.update(
                    value for value in distinct
                    if value and not EXCLUDED_VOCABULARIES.match(value)
                    and (len(value) <= max_text_length or is_web_url(value))
                )
                rows += 1
    expected = manifest["counts"]["exported"]
    if rows != expected:
        raise ValueError(f"Read {rows} records but the manifest reports {expected}")
    return counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path, help="export directory containing manifest.json")
    parser.add_argument("--max-text-length", type=int, default=120,
                        help="maximum Unicode code points for plain text (default: 120)")
    args = parser.parse_args()
    if args.max_text_length < 0:
        parser.error("--max-text-length must be nonnegative")
    try:
        counts = count_licenses(args.package, args.max_text_length)
    except (OSError, TypeError, KeyError, ValueError) as error:
        parser.exit(1, f"{parser.prog}: {error}\n")
    for value, count in sorted(counts.items(), key=lambda item: (-item[1], item[0])):
        print(json.dumps({"value": value, "recordCount": count}, ensure_ascii=False))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
