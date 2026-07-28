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
        print(f"Failed to read GitHub push event payload: {e}")
        return None

    before = event.get("before")
    after = event.get("after")
    if not after:
        return None

    zero_sha = "0" * 40
    revision = after if not before or before == zero_sha else f"{before}..{after}"

    try:
        return subprocess.check_output(
            ["git", "log", "--format=%s", revision],
            universal_newlines=True
        ).splitlines()
    except Exception as e:
        print(f"Failed to read pushed commit range {revision}: {e}")
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
        # Validate only the pushed range in CI. Keep the last-5 fallback for local runs.
        commits = commits_from_push_event()
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
