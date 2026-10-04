import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import validate_commits


class CommitRangeSelectionTests(unittest.TestCase):
    def push_event(self, before, after):
        handle = tempfile.NamedTemporaryFile("w", delete=False, encoding="utf-8")
        json.dump({"before": before, "after": after}, handle)
        handle.close()
        self.addCleanup(lambda: Path(handle.name).unlink(missing_ok=True))
        return handle.name

    @mock.patch.dict(os.environ, {"GITHUB_EVENT_NAME": "push"}, clear=False)
    @mock.patch("validate_commits.commits_introduced_against_develop")
    def test_new_branch_push_uses_develop_merge_base(self, introduced):
        after = "a" * 40
        introduced.return_value = [
            "fix(auth): correction",
            "feat(auth): implementation",
        ]
        os.environ["GITHUB_EVENT_PATH"] = self.push_event("0" * 40, after)

        commits = validate_commits.commits_from_push_event()

        self.assertEqual(
            commits,
            ["fix(auth): correction", "feat(auth): implementation"],
        )
        introduced.assert_called_once_with(after)

    @mock.patch.dict(os.environ, {"GITHUB_EVENT_NAME": "push"}, clear=False)
    @mock.patch("validate_commits.commits_introduced_against_develop")
    def test_new_branch_invalid_introduced_commit_still_fails_validation(self, introduced):
        after = "a" * 40
        introduced.return_value = ["Commit"]
        os.environ["GITHUB_EVENT_PATH"] = self.push_event("0" * 40, after)

        commits = validate_commits.commits_from_push_event()

        self.assertEqual(commits, ["Commit"])
        self.assertFalse(validate_commits.validate_msg(commits[0]))

    @mock.patch.dict(os.environ, {"GITHUB_EVENT_NAME": "push"}, clear=False)
    @mock.patch("validate_commits.git_lines")
    @mock.patch("validate_commits.commits_introduced_against_develop")
    def test_existing_branch_push_uses_exact_before_after_range(
        self, introduced, git_lines
    ):
        before = "b" * 40
        after = "c" * 40
        git_lines.return_value = ["fix(ci): scope commit validation"]
        os.environ["GITHUB_EVENT_PATH"] = self.push_event(before, after)

        commits = validate_commits.commits_from_push_event()

        self.assertEqual(commits, ["fix(ci): scope commit validation"])
        git_lines.assert_called_once_with(
            "log", "--format=%s", f"{before}..{after}"
        )
        introduced.assert_not_called()

    @mock.patch("validate_commits.git_lines")
    @mock.patch("validate_commits.subprocess.check_output")
    def test_new_branch_range_validates_all_commits_after_merge_base(
        self, check_output, git_lines
    ):
        head = "d" * 40
        base = "e" * 40
        check_output.return_value = f"{base}\n"
        git_lines.return_value = [
            "fix(auth): correction",
            "feat(auth): implementation",
        ]

        commits = validate_commits.commits_introduced_against_develop(head)

        self.assertEqual(len(commits), 2)
        check_output.assert_called_once_with(
            ["git", "merge-base", head, "origin/develop"],
            universal_newlines=True,
        )
        git_lines.assert_called_once_with(
            "log", "--format=%s", f"{base}..{head}"
        )

    @mock.patch("validate_commits.subprocess.check_output")
    def test_new_branch_without_develop_merge_base_fails_closed(self, check_output):
        error = subprocess.CalledProcessError(1, ["git", "merge-base"])
        check_output.side_effect = error

        with self.assertRaises(subprocess.CalledProcessError) as raised:
            validate_commits.commits_introduced_against_develop("f" * 40)

        self.assertIs(raised.exception, error)


if __name__ == "__main__":
    unittest.main()
