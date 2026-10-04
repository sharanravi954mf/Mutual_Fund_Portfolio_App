import sys
import re
import subprocess
import json
import os

# Regex to match Conventional Commits format
CONVENTIONAL_PATTERN = re.compile(
    r'^(feat|fix|docs|refactor|perf|style|test|build|ci|chore|revert)(\([^)]+\))?!?: .+'
)


def validate_msg(msg):
    # Ignore standard git merge commits
    if msg.startswith("Merge branch") or msg.startswith("Merge pull request") or msg.startswith("Merge commit"):
        return True
    return bool(CONVENTIONAL_PATTERN.match(msg))


def git_lines(*args):
    return subprocess.check_output(
        ["git", *args],
        universal_newlines=True,
    ).splitlines()


def commits_introduced_against_develop(head):
    """Return all commits introduced by head relative to origin/develop."""
    base = subprocess.check_output(
        ["git", "merge-base", head, "origin/develop"],
        universal_newlines=True,
    ).strip()
    if not base:
        raise RuntimeError("Could not determine merge-base against origin/develop")
    if base == head:
        return []
    return git_lines("log", "--format=%s", f"{base}..{head}")


def commits_from_push_event():
    if os.environ.get("GITHUB_EVENT_NAME") != "push":
        return None

    event_path = os.environ.get("GITHUB_EVENT_PATH")
    if not event_path:
        return None

    try:
        with open(event_path, "r", encoding="utf-8") as event_file:
            event = json.load(event_file)
    except Exception as e:
        raise RuntimeError(f"Failed to read GitHub push event payload: {e}") from e

    before = event.get("before")
    after = event.get("after")
    if not after:
        raise RuntimeError("GitHub push event is missing the after commit")

    zero_sha = "0" * 40
    try:
        if not before or before == zero_sha:
            # A branch-creation push has no previous branch tip. Logging only
            # the new head walks the entire repository history and can reject
            # commits already present in develop. Validate exactly what the
            # new branch introduces relative to develop instead.
            return commits_introduced_against_develop(after)
        return git_lines("log", "--format=%s", f"{before}..{after}")
    except Exception as e:
        raise RuntimeError(
            f"Failed to determine pushed commit range for {before or zero_sha}..{after}: {e}"
        ) from e


def commits_from_develop_range():
    try:
        head = subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            universal_newlines=True,
        ).strip()
        commits = commits_introduced_against_develop(head)
        return commits or None
    except Exception as e:
        print(f"Failed to read branch commits against origin/develop: {e}")
        return None


def main():
    if len(sys.argv) > 1:
        # Validate specific input (e.g. PR Title or Git Hook input)
        msg = sys.argv[1].strip()
        if not validate_msg(msg):
            print(f"❌ Invalid format: '{msg}'")
            print("   Expected format: <type>(<scope>): <subject>")
            print("   Allowed types: feat, fix, docs, refactor, perf, style, test, build, ci, chore, revert")
            sys.exit(1)
        print(f"✅ Valid format: '{msg}'")
        sys.exit(0)
    else:
        # Validate only the pushed range in CI. Locally, prefer the branch range
        # against develop before falling back to recent history.
        try:
            commits = commits_from_push_event()
        except RuntimeError as e:
            print(f"❌ {e}")
            sys.exit(1)

        if commits is None:
            commits = commits_from_develop_range()
            if commits is None:
                print("Checking recent commits...")
                try:
                    commits = subprocess.check_output(
                        ["git", "log", "-n", "5", "--format=%s"],
                        universal_newlines=True
                    ).splitlines()
                except Exception as e:
                    print(f"Failed to read git logs: {e}")
                    sys.exit(1)
            else:
                print("Checking branch commits against origin/develop...")
        else:
            print("Checking pushed commits...")

        has_errors = False
        for commit in commits:
            if not validate_msg(commit):
                print(f"❌ Invalid commit message: '{commit}'")
                has_errors = True
            else:
                print(f"✅ Valid commit message: '{commit}'")

        if has_errors:
            print("\n❌ Commit validation FAILED. Please amend your commit messages.")
            sys.exit(1)
        print("\n✅ All checked commits are valid.")
        sys.exit(0)


if __name__ == "__main__":
    main()
