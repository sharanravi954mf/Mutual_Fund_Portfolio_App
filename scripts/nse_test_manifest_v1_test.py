#!/usr/bin/env python3
"""Offline tests for the fixed NSE test manifest validator and selector."""

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parent.parent
SELECTOR = REPOSITORY_ROOT / "scripts" / "nse_test_manifest_v1.py"
MANIFEST = REPOSITORY_ROOT / "supabase/functions/_shared/nse/NSE_TEST_MANIFEST_V1.json"
EXPECTED_BASELINE_TESTS = [
    "supabase/functions/_shared/nse/nse_evidence_call_test.ts",
    "supabase/functions/_shared/nse/nse_auth_test.ts",
    "supabase/functions/_shared/nse/nse_client_test.ts",
    "supabase/functions/_shared/nse/nse_config_test.ts",
    "supabase/functions/_shared/nse/nse_ucc_test.ts",
    "supabase/functions/_shared/nse/nse_ucc_verification_test.ts",
    "supabase/functions/nse-ucc-registration-worker/index_test.ts",
    "supabase/functions/nse-ucc-reconciliation-worker/index_test.ts",
    "supabase/functions/nse-uat-smoke-test/index_test.ts",
    "supabase/functions/_shared/nse/nse_order_status_test.ts",
    "supabase/functions/nse-order-status-worker/index_test.ts",
    "supabase/functions/_shared/nse/nse_prov_orders_test.ts",
    "supabase/functions/nse-prov-orders-worker/index_test.ts",
    "supabase/functions/_shared/nse/nse_client_readiness_test.ts",
    "supabase/functions/nse-client-readiness-worker/index_test.ts",
    "supabase/functions/_shared/nse/nse_order_funding_test.ts",
    "supabase/functions/nse-order-funding-worker/index_test.ts",
    "supabase/functions/_shared/nse/nse_settlement_redemption_test.ts",
    "supabase/functions/nse-settlement-redemption-worker/index_test.ts",
    "supabase/functions/_shared/nse/nse_sip_xsip_reports_test.ts",
    "supabase/functions/nse-sip-xsip-reports-worker/index_test.ts",
    "supabase/functions/_shared/nse/nse_stp_swp_reports_test.ts",
    "supabase/functions/_shared/nse/nse_response_diagnostics_test.ts",
    "supabase/functions/nse-stp-swp-reports-worker/index_test.ts",
    "supabase/functions/_shared/nse/nse_master_download_test.ts",
    "supabase/functions/nse-master-download-worker/index_test.ts"
]
EXPECTED_FMT_CHECK_TARGETS = [
    "supabase/functions/_shared/nse/nse_evidence_call.ts",
    "supabase/functions/_shared/nse/nse_evidence_call_test.ts",
    "supabase/functions/nse-ucc-registration-worker/handler.ts",
    "supabase/functions/nse-ucc-registration-worker/index_test.ts",
    "supabase/functions/nse-ucc-reconciliation-worker/handler.ts",
    "supabase/functions/nse-ucc-reconciliation-worker/index_test.ts",
    "supabase/functions/_shared/nse/nse_order_status.ts",
    "supabase/functions/_shared/nse/nse_order_status_test.ts",
    "supabase/functions/nse-order-status-worker/types.ts",
    "supabase/functions/nse-order-status-worker/adapters.ts",
    "supabase/functions/nse-order-status-worker/handler.ts",
    "supabase/functions/nse-order-status-worker/index.ts",
    "supabase/functions/nse-order-status-worker/index_test.ts",
    "supabase/functions/_shared/nse/nse_prov_orders.ts",
    "supabase/functions/_shared/nse/nse_prov_orders_test.ts",
    "supabase/functions/nse-prov-orders-worker/types.ts",
    "supabase/functions/nse-prov-orders-worker/adapters.ts",
    "supabase/functions/nse-prov-orders-worker/handler.ts",
    "supabase/functions/nse-prov-orders-worker/index.ts",
    "supabase/functions/nse-prov-orders-worker/index_test.ts",
    "supabase/functions/_shared/nse/nse_client_readiness.ts",
    "supabase/functions/_shared/nse/nse_client_readiness_test.ts",
    "supabase/functions/nse-client-readiness-worker/types.ts",
    "supabase/functions/nse-client-readiness-worker/adapters.ts",
    "supabase/functions/nse-client-readiness-worker/handler.ts",
    "supabase/functions/nse-client-readiness-worker/index.ts",
    "supabase/functions/nse-client-readiness-worker/index_test.ts",
    "supabase/functions/_shared/nse/nse_order_funding.ts",
    "supabase/functions/_shared/nse/nse_order_funding_test.ts",
    "supabase/functions/nse-order-funding-worker/types.ts",
    "supabase/functions/nse-order-funding-worker/adapters.ts",
    "supabase/functions/nse-order-funding-worker/handler.ts",
    "supabase/functions/nse-order-funding-worker/index.ts",
    "supabase/functions/nse-order-funding-worker/index_test.ts",
    "supabase/functions/_shared/nse/nse_settlement_redemption.ts",
    "supabase/functions/_shared/nse/nse_settlement_redemption_test.ts",
    "supabase/functions/nse-settlement-redemption-worker/types.ts",
    "supabase/functions/nse-settlement-redemption-worker/adapters.ts",
    "supabase/functions/nse-settlement-redemption-worker/handler.ts",
    "supabase/functions/nse-settlement-redemption-worker/index.ts",
    "supabase/functions/nse-settlement-redemption-worker/index_test.ts",
    "supabase/functions/_shared/nse/nse_sip_xsip_reports.ts",
    "supabase/functions/_shared/nse/nse_sip_xsip_reports_test.ts",
    "supabase/functions/nse-sip-xsip-reports-worker/types.ts",
    "supabase/functions/nse-sip-xsip-reports-worker/adapters.ts",
    "supabase/functions/nse-sip-xsip-reports-worker/handler.ts",
    "supabase/functions/nse-sip-xsip-reports-worker/index.ts",
    "supabase/functions/nse-sip-xsip-reports-worker/index_test.ts",
    "supabase/functions/_shared/nse/nse_stp_swp_reports.ts",
    "supabase/functions/_shared/nse/nse_stp_swp_reports_fixtures.ts",
    "supabase/functions/_shared/nse/nse_stp_swp_reports_test.ts",
    "supabase/functions/_shared/nse/nse_response_diagnostics.ts",
    "supabase/functions/_shared/nse/nse_response_diagnostics_test.ts",
    "supabase/functions/nse-stp-swp-reports-worker/types.ts",
    "supabase/functions/nse-stp-swp-reports-worker/adapters.ts",
    "supabase/functions/nse-stp-swp-reports-worker/handler.ts",
    "supabase/functions/nse-stp-swp-reports-worker/index.ts",
    "supabase/functions/nse-stp-swp-reports-worker/index_test.ts",
    "supabase/functions/_shared/nse/nse_master_download.ts",
    "supabase/functions/_shared/nse/nse_master_evidence.ts",
    "supabase/functions/_shared/nse/nse_master_download_test.ts",
    "supabase/functions/nse-master-download-worker/types.ts",
    "supabase/functions/nse-master-download-worker/adapters.ts",
    "supabase/functions/nse-master-download-worker/handler.ts",
    "supabase/functions/nse-master-download-worker/index.ts",
    "supabase/functions/nse-master-download-worker/index_test.ts",
]


class NSETestManifestV1Tests(unittest.TestCase):
    def run_selector(self, root: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", "-I", "scripts/nse_test_manifest_v1.py", *arguments],
            cwd=root,
            capture_output=True,
            check=False,
            text=True,
        )

    def fixture_root(self) -> tempfile.TemporaryDirectory[str]:
        temporary_directory = tempfile.TemporaryDirectory()
        root = Path(temporary_directory.name)
        target_manifest = root / "supabase/functions/_shared/nse/NSE_TEST_MANIFEST_V1.json"
        target_manifest.parent.mkdir(parents=True)
        (root / "scripts").mkdir()
        shutil.copy2(SELECTOR, root / "scripts/nse_test_manifest_v1.py")
        shutil.copy2(MANIFEST, target_manifest)
        for target_path in [*EXPECTED_BASELINE_TESTS, *EXPECTED_FMT_CHECK_TARGETS]:
            target = root / target_path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.touch()
        return temporary_directory

    def write_manifest(self, root: Path, manifest: dict[str, object]) -> None:
        (root / "supabase/functions/_shared/nse/NSE_TEST_MANIFEST_V1.json").write_text(
            json.dumps(manifest), encoding="utf-8"
        )

    def modified_manifest(self, root: Path) -> dict[str, object]:
        return json.loads(
            (root / "supabase/functions/_shared/nse/NSE_TEST_MANIFEST_V1.json").read_text(
                encoding="utf-8"
            )
        )

    def assert_rejected(self, mutate) -> None:
        with self.fixture_root() as temporary_directory:
            root = Path(temporary_directory)
            manifest = self.modified_manifest(root)
            mutate(root, manifest)
            self.write_manifest(root, manifest)
            self.assertNotEqual(self.run_selector(root, "validate").returncode, 0)

    def test_current_manifest_is_accepted_and_print_order_is_deterministic(self) -> None:
        accepted = self.run_selector(REPOSITORY_ROOT, "validate")
        first_print = self.run_selector(REPOSITORY_ROOT, "print-test")
        second_print = self.run_selector(REPOSITORY_ROOT, "print-test")
        self.assertEqual(accepted.returncode, 0)
        self.assertEqual(first_print.returncode, 0)
        self.assertEqual(first_print.stdout, second_print.stdout)
        self.assertEqual(first_print.stdout.splitlines(), EXPECTED_BASELINE_TESTS)

    def test_fmt_check_targets_are_exactly_the_reviewed_target_order(self) -> None:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        self.assertEqual(manifest["fmt_check_targets"], EXPECTED_FMT_CHECK_TARGETS)
        self.assertEqual(len(manifest["fmt_check_targets"]), 66)

    def test_fmt_check_print_order_is_deterministic(self) -> None:
        first_print = self.run_selector(REPOSITORY_ROOT, "print-fmt-check")
        second_print = self.run_selector(REPOSITORY_ROOT, "print-fmt-check")
        self.assertEqual(first_print.returncode, 0)
        self.assertEqual(first_print.stdout, second_print.stdout)
        self.assertEqual(first_print.stdout.splitlines(), EXPECTED_FMT_CHECK_TARGETS)

    def test_manifest_is_exactly_the_reviewed_twenty_six_suite_set(self) -> None:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        self.assertEqual(manifest["baseline_tests"], EXPECTED_BASELINE_TESTS)
        self.assertEqual(len(manifest["baseline_tests"]), 26)

    def test_duplicate_path_is_rejected(self) -> None:
        self.assert_rejected(lambda _root, manifest: manifest["baseline_tests"].append(manifest["baseline_tests"][0]))

    def test_duplicate_fmt_check_path_is_rejected(self) -> None:
        self.assert_rejected(
            lambda _root, manifest: manifest["fmt_check_targets"].append(
                manifest["fmt_check_targets"][0]
            )
        )

    def test_non_typescript_fmt_check_path_is_rejected(self) -> None:
        self.assert_rejected(
            lambda _root, manifest: manifest["fmt_check_targets"].__setitem__(0, "supabase/functions/_shared/nse/nse_evidence_call.js")
        )

    def test_absolute_path_is_rejected(self) -> None:
        self.assert_rejected(lambda _root, manifest: manifest["baseline_tests"].__setitem__(0, "/tmp/test.ts"))

    def test_traversal_path_is_rejected(self) -> None:
        self.assert_rejected(lambda _root, manifest: manifest["baseline_tests"].__setitem__(0, "supabase/functions/../outside_test.ts"))

    def test_backslash_path_is_rejected(self) -> None:
        self.assert_rejected(lambda _root, manifest: manifest["baseline_tests"].__setitem__(0, "supabase\\functions\\test.ts"))

    def test_glob_and_regex_paths_are_rejected(self) -> None:
        self.assert_rejected(lambda _root, manifest: manifest["baseline_tests"].__setitem__(0, "supabase/functions/_shared/nse/*_test.ts"))
        self.assert_rejected(lambda _root, manifest: manifest["baseline_tests"].__setitem__(0, "supabase/functions/_shared/nse/(.*)_test.ts"))

    def test_outside_scope_path_is_rejected(self) -> None:
        self.assert_rejected(lambda _root, manifest: manifest["baseline_tests"].__setitem__(0, "scripts/nse_test_manifest_v1_test.py"))

    def test_nonexistent_path_is_rejected(self) -> None:
        self.assert_rejected(lambda _root, manifest: manifest["baseline_tests"].__setitem__(0, "supabase/functions/_shared/nse/missing_test.ts"))

    def test_final_file_symlink_is_rejected(self) -> None:
        def mutate(root: Path, manifest: dict[str, object]) -> None:
            link = root / "supabase/functions/_shared/nse/symlink_test.ts"
            link.symlink_to(root / EXPECTED_BASELINE_TESTS[0])
            manifest["baseline_tests"][0] = "supabase/functions/_shared/nse/symlink_test.ts"
        self.assert_rejected(mutate)

    def test_intermediate_directory_symlink_escape_is_rejected(self) -> None:
        def mutate(root: Path, manifest: dict[str, object]) -> None:
            external = root / "external"
            external.mkdir()
            (external / "evil_test.ts").touch()
            link = root / "supabase/functions/escaped"
            link.symlink_to(external, target_is_directory=True)
            manifest["baseline_tests"][0] = "supabase/functions/escaped/evil_test.ts"
        self.assert_rejected(mutate)

    def test_intermediate_directory_symlink_fmt_check_path_is_rejected(self) -> None:
        def mutate(root: Path, manifest: dict[str, object]) -> None:
            external = root / "external"
            external.mkdir()
            (external / "evil.ts").touch()
            link = root / "supabase/functions/escaped"
            link.symlink_to(external, target_is_directory=True)
            manifest["fmt_check_targets"][0] = "supabase/functions/escaped/evil.ts"
        self.assert_rejected(mutate)

    def test_unknown_schema_is_rejected(self) -> None:
        self.assert_rejected(lambda _root, manifest: manifest.__setitem__("schema", "unknown"))

    def test_unsupported_manifest_field_is_rejected(self) -> None:
        self.assert_rejected(lambda _root, manifest: manifest.__setitem__("command", "deno test"))

    def test_endpoint_test_must_be_baseline_and_owned_by_its_endpoint(self) -> None:
        self.assert_rejected(
            lambda _root, manifest: manifest["endpoint_tests"][
                "nse-ucc-registration-worker"
            ].__setitem__(0, "supabase/functions/_shared/nse/nse_auth_test.ts")
        )

        def add_unlisted_endpoint_test(root: Path, manifest: dict[str, object]) -> None:
            path = root / "supabase/functions/nse-ucc-registration-worker/new_test.ts"
            path.touch()
            manifest["endpoint_tests"]["nse-ucc-registration-worker"][0] = (
                "supabase/functions/nse-ucc-registration-worker/new_test.ts"
            )

        self.assert_rejected(add_unlisted_endpoint_test)

    def test_unknown_action_is_rejected(self) -> None:
        result = self.run_selector(REPOSITORY_ROOT, "unknown")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_extra_argument_is_rejected(self) -> None:
        result = self.run_selector(REPOSITORY_ROOT, "validate", "unexpected")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    unittest.main()
