#!/usr/bin/env bash
# All SDK transport is mocked. SQL entry point creates its own disposable DB.
set -euo pipefail
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
flutter_bin=${MONEYBOWL_FLUTTER_BIN:-/home/ubuntu/.local/share/flutter-moneybowl/bin/flutter}
"$flutter_bin" test --no-pub --reporter expanded \
  test/platform_mfa_controller_test.dart test/platform_mfa_widget_test.dart \
  test/platform_mfa_sdk_test.dart test/platform_mfa_session_integration_test.dart \
  test/authentication/ \
  test/platform_administration_screen_test.dart test/mfd_application_test.dart
