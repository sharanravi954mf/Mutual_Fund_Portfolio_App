import sys
import re
import subprocess

# Regex to match Conventional Commits format
CONVENTIONAL_PATTERN = re.compile(
    r'^(feat|fix|docs|refactor|perf|style|test|build|ci|chore|revert)(\([^)]+\))?!?: .+'
)

def validate_msg(msg):
    # Ignore standard git merge commits
    if msg.startswith("Merge branch") or msg.startswith("Merge pull request") or msg.startswith("Merge commit"):
        return True
    return bool(CONVENTIONAL_PATTERN.match(msg))

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
        # Validate the last 5 commits locally
        print("Checking recent commits...")
        try:
            commits = subprocess.check_output(
                ["git", "log", "-n", "5", "--format=%s"],
                universal_newlines=True
            ).splitlines()
        except Exception as e:
            print(f"Failed to read git logs: {e}")
            sys.exit(1)

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
