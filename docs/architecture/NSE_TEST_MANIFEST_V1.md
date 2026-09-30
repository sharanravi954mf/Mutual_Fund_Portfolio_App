# NSE Test Manifest V1

`NSE_TEST_MANIFEST_V1.json` is the repository-owned allowlist of exact NSE
TypeScript test targets. It removes the need to commission a protected runner
profile for every ordinary NSE application test addition.

## Trust split

The protected Deno runner and its pinned offline toolchain remain immutable.
The repository manifest defines the reviewed, exact application test targets;
it cannot supply commands, shell fragments, or runtime-selected paths.
Director still controls the command shape and the paths a task may change. The
selector only validates this fixed manifest and prints its ordered targets. It
does not run tests.

## Maintaining the manifest

For a future ordinary NSE task, add every new exact `*_test.ts` path to the
ordered `baseline_tests` list in the same reviewed application change. Do not
use globbing or discovery. If a test belongs to a deployed endpoint, add the
same exact path to that endpoint's `endpoint_tests` entry. Endpoint-owned paths
must already be baseline paths and must be beneath
`supabase/functions/<endpoint-name>/`. Shared NSE tests remain baseline-only.

The selector rejects traversal, absolute paths, backslashes, metacharacters,
missing files, symlinks in any candidate path component, and resolved targets
outside `supabase/functions`. This keeps the manifest a precise repository
allowlist rather than a filesystem escape hatch.

## Protected-runner commissioning

This task does not modify `/opt` and does not commission the future generic
manifest-backed protected profile. A later privileged commissioning step may
teach the protected runner one generic profile while retaining ownership of the
command and toolchain behavior.
