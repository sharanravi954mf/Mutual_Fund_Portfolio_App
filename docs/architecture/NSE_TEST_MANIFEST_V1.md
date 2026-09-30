# NSE Test Manifest V1

`NSE_TEST_MANIFEST_V1.json` is the repository-owned allowlist of NSE TypeScript
test targets. It replaces the assumption that every ordinary NSE application
change needs a new protected runner profile.

## Why this exists

The protected profile-per-task model does not scale: every new endpoint test
would require a privileged runner change, commissioning work, and separate
review even when the change is only an ordinary application test. The manifest
keeps that application-level list visible, versioned, and reviewable alongside
the code it exercises.

The trust split remains deliberate. The protected runner and its pinned offline
toolchain remain immutable. This manifest supplies only approved,
repository-relative regular-file targets. Director still controls the command
shape and the paths changed by a task. The selector validates the manifest
without executing a test command; it simply prints the ordered baseline targets
for a caller already authorized to run them.

## Updating it in a future NSE task

A future NSE task adds each new exact `*_test.ts` path to `baseline_tests` in
the same reviewed application change. No glob or runtime-supplied path is
accepted. If a test belongs to a deployed endpoint, also add the same exact
path under that endpoint's `endpoint_tests` entry. Each endpoint-owned path
must be in `baseline_tests` and under
`supabase/functions/<endpoint-name>/`; shared NSE tests stay in the baseline
without an endpoint entry.

`baseline_tests` is ordered and is the selector output. `endpoint_tests` is a
declarative ownership map for review and future maintenance; it does not enable
discovery or selection by arbitrary endpoint or path.

## Runner commissioning remains separate

This change neither runs tests nor changes the offline or pinned Deno
guarantees. A later privileged commissioning step may teach the protected
runner one generic manifest-backed profile. That commissioning would continue
to own commands and toolchain behavior. This repository change does not modify
`/opt`, and does not commission that generic profile.
