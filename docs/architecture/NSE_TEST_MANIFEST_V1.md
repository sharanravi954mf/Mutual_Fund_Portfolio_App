# NSE Test Manifest V1

`NSE_TEST_MANIFEST_V1.json` is the repository-owned allowlist of exact NSE
TypeScript fmt/check and test targets. It removes the need to commission a
protected runner profile for every ordinary NSE application test addition.

## Trust split

The protected Deno runner and its pinned offline toolchain remain immutable.
The repository manifest defines the reviewed, exact application test targets;
it cannot supply commands, shell fragments, or runtime-selected paths.
Director still controls the command shape and the paths a task may change. The
selector only validates this fixed manifest and prints its ordered fmt/check or
test targets. It does not run checks or tests.

The repository selector is not the protected runner's security boundary.
`env-003` independently validates the JSON before accepting a selected list.

## Maintaining the manifest

For a future ordinary NSE task, add each exact source or test `.ts` file that
needs fmt/check to the ordered `fmt_check_targets` list in the same reviewed
application change. Add every test `*_test.ts` path to `baseline_tests`. If a
test belongs to a deployed endpoint, add the same exact path to that endpoint's
`endpoint_tests` entry. Endpoint-owned paths must already be baseline paths and
must be beneath `supabase/functions/<endpoint-name>/`. Shared NSE tests remain
baseline-only.

The selector rejects traversal, absolute paths, backslashes, metacharacters,
missing files, symlinks in any candidate path component, and resolved targets
outside `supabase/functions`. This keeps the manifest a precise repository
allowlist rather than a filesystem escape hatch.

## Protected-runner commissioning

This task does not modify `/opt` and does not commission the future generic
manifest-backed protected profile. A later privileged commissioning step may
teach the protected runner one generic profile while retaining ownership of the
command and toolchain behavior.
