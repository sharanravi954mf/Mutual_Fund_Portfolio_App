#!/usr/bin/env python3
"""Validate and print the fixed, repository-owned NSE test manifest."""

import json
import stat
import sys
from pathlib import Path


SCHEMA = "MB_NSE_TEST_MANIFEST_V1"
REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
FUNCTIONS_ROOT = REPOSITORY_ROOT / "supabase" / "functions"
MANIFEST_PATH = FUNCTIONS_ROOT / "_shared" / "nse" / "NSE_TEST_MANIFEST_V1.json"
PREFIX = "supabase/functions/"
PATTERN_METACHARACTERS = set("*?[]{}!^$()+|")


class ManifestError(ValueError):
    """Raised when the fixed manifest is not safe and valid."""


def is_within(path: Path, parent: Path) -> bool:
    """Return whether an already-resolved path is contained by parent."""
    try:
        path.relative_to(parent)
    except ValueError:
        return False
    return True


def safe_functions_root(repository_root: Path) -> Path:
    """Resolve the fixed functions root only after rejecting symlink components."""
    root = repository_root
    try:
        if root.lstat() and root.is_symlink():
            raise ManifestError("repository root must not be a symlink")
        for component in ("supabase", "functions"):
            root = root / component
            if root.is_symlink():
                raise ManifestError("supabase/functions must not contain symlinks")
        if not root.is_dir():
            raise ManifestError("supabase/functions must be an existing directory")
        resolved_root = root.resolve(strict=True)
    except OSError as error:
        raise ManifestError("supabase/functions cannot be safely resolved") from error
    if not is_within(resolved_root, repository_root.resolve(strict=True)):
        raise ManifestError("supabase/functions must remain inside the repository")
    return resolved_root


def validate_path(value: object, repository_root: Path, *, test: bool) -> str:
    """Return a validated, exact repository-relative regular-file path."""
    path_kind = "test path" if test else "fmt/check path"
    if not isinstance(value, str) or not value:
        raise ManifestError(f"{path_kind} must be a non-empty string")
    if value.startswith("/") or "\\" in value:
        raise ManifestError(f"{path_kind} must be relative and use forward slashes")
    if any(character in PATTERN_METACHARACTERS for character in value):
        raise ManifestError(f"{path_kind} must not contain glob or regex metacharacters")
    components = value.split("/")
    if any(component in ("", ".", "..") for component in components):
        raise ManifestError(f"{path_kind} contains an invalid component")
    if not value.startswith(PREFIX):
        raise ManifestError(f"{path_kind} must be under supabase/functions/")
    if test and not value.endswith("_test.ts"):
        raise ManifestError("test path must name a TypeScript test file")
    if not test and not value.endswith(".ts"):
        raise ManifestError("fmt/check path must name a TypeScript file")

    resolved_functions_root = safe_functions_root(repository_root)
    candidate = repository_root.joinpath(*components)
    current = repository_root
    try:
        for component in components:
            current = current / component
            if current.is_symlink():
                raise ManifestError(f"{path_kind} must not contain symlinks")
        candidate_status = candidate.stat()
        if not stat.S_ISREG(candidate_status.st_mode):
            raise ManifestError(f"{path_kind} must name an existing regular file")
        resolved_candidate = candidate.resolve(strict=True)
    except OSError as error:
        raise ManifestError(f"{path_kind} cannot be safely resolved") from error
    if not is_within(resolved_candidate, resolved_functions_root):
        raise ManifestError(f"{path_kind} must resolve inside supabase/functions")
    return value


def validate_manifest(manifest: object, repository_root: Path) -> tuple[list[str], list[str]]:
    """Validate manifest data and return ordered fmt/check and test paths."""
    if not isinstance(manifest, dict) or manifest.get("schema") != SCHEMA:
        raise ManifestError("manifest schema must be MB_NSE_TEST_MANIFEST_V1")
    if set(manifest) != {"schema", "fmt_check_targets", "baseline_tests", "endpoint_tests"}:
        raise ManifestError("manifest contains unsupported fields")
    fmt_check_targets = manifest.get("fmt_check_targets")
    if not isinstance(fmt_check_targets, list) or not fmt_check_targets:
        raise ManifestError("fmt_check_targets must be a non-empty array")
    validated_fmt_check: list[str] = []
    seen_fmt_check: set[str] = set()
    for fmt_check_path in fmt_check_targets:
        validated_path = validate_path(fmt_check_path, repository_root, test=False)
        if validated_path in seen_fmt_check:
            raise ManifestError("fmt_check_targets must contain unique paths")
        seen_fmt_check.add(validated_path)
        validated_fmt_check.append(validated_path)
    baseline_tests = manifest.get("baseline_tests")
    if not isinstance(baseline_tests, list) or not baseline_tests:
        raise ManifestError("baseline_tests must be a non-empty array")
    validated_baseline: list[str] = []
    seen_baseline: set[str] = set()
    for test_path in baseline_tests:
        validated_path = validate_path(test_path, repository_root, test=True)
        if validated_path in seen_baseline:
            raise ManifestError("baseline_tests must contain unique paths")
        seen_baseline.add(validated_path)
        validated_baseline.append(validated_path)
    endpoint_tests = manifest.get("endpoint_tests")
    if not isinstance(endpoint_tests, dict):
        raise ManifestError("endpoint_tests must be an object")
    for endpoint, tests in endpoint_tests.items():
        if (not isinstance(endpoint, str) or not endpoint or "/" in endpoint
                or "\\" in endpoint
                or any(character in PATTERN_METACHARACTERS for character in endpoint)):
            raise ManifestError("endpoint ownership key is invalid")
        if not isinstance(tests, list) or not tests:
            raise ManifestError("endpoint test lists must be non-empty arrays")
        endpoint_prefix = f"supabase/functions/{endpoint}/"
        seen_endpoint: set[str] = set()
        for test_path in tests:
            validated_path = validate_path(test_path, repository_root, test=True)
            if validated_path in seen_endpoint:
                raise ManifestError("endpoint test lists must contain unique paths")
            if not validated_path.startswith(endpoint_prefix):
                raise ManifestError("endpoint test must be owned by its endpoint")
            if validated_path not in seen_baseline:
                raise ManifestError("endpoint test must also be in baseline_tests")
            seen_endpoint.add(validated_path)
    return validated_fmt_check, validated_baseline


def load_and_validate() -> tuple[list[str], list[str]]:
    """Load only the fixed manifest path and validate it."""
    try:
        with MANIFEST_PATH.open(encoding="utf-8") as manifest_file:
            manifest = json.load(manifest_file)
    except (OSError, json.JSONDecodeError) as error:
        raise ManifestError(f"unable to load fixed manifest: {error}") from error
    return validate_manifest(manifest, REPOSITORY_ROOT)


def main(argv: list[str]) -> int:
    if argv not in (["validate"], ["print-fmt-check"], ["print-test"]):
        return 2
    try:
        fmt_check_targets, tests = load_and_validate()
    except ManifestError:
        return 1
    if argv == ["print-fmt-check"]:
        sys.stdout.write("\n".join(fmt_check_targets) + "\n")
    if argv == ["print-test"]:
        sys.stdout.write("\n".join(tests) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
