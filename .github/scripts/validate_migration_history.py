#!/usr/bin/env python3
"""Reject edits to migration files already recorded in production."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MIGRATION_ROOT = REPOSITORY_ROOT / "supabase" / "migrations"
MANIFEST_PATH = REPOSITORY_ROOT / ".github" / "migration-history.json"
MIGRATION_PATTERN = re.compile(r"^(\d{14})_.+\.sql$")


def git_blob_sha(path: Path) -> str:
    return subprocess.check_output(
        ["git", "hash-object", "--", str(path)],
        cwd=REPOSITORY_ROOT,
        text=True,
    ).strip()


def main() -> int:
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    boundary = manifest["boundary"]
    expected = manifest["migrations"]

    frozen_on_disk: dict[str, Path] = {}
    malformed: list[str] = []

    for path in MIGRATION_ROOT.glob("*.sql"):
        match = MIGRATION_PATTERN.match(path.name)
        if match is None:
            malformed.append(path.name)
            continue
        if match.group(1) <= boundary:
            frozen_on_disk[path.name] = path

    errors: list[str] = []

    if malformed:
        errors.append(
            "Migration filenames must start with a 14-digit version: "
            + ", ".join(sorted(malformed))
        )

    missing = sorted(set(expected) - set(frozen_on_disk))
    unexpected = sorted(set(frozen_on_disk) - set(expected))

    if missing:
        errors.append("Frozen migrations missing: " + ", ".join(missing))
    if unexpected:
        errors.append(
            "Unmanifested migration at or before the production boundary: "
            + ", ".join(unexpected)
        )

    for name in sorted(set(expected) & set(frozen_on_disk)):
        actual_hash = git_blob_sha(frozen_on_disk[name])
        if actual_hash != expected[name]:
            errors.append(
                f"Applied migration changed: {name} "
                f"(expected {expected[name]}, got {actual_hash})"
            )

    if errors:
        print("Migration history validation FAILED:")
        for error in errors:
            print(f"- {error}")
        return 1

    print(
        f"Migration history validation passed: "
        f"{len(expected)} files frozen through {boundary}."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
