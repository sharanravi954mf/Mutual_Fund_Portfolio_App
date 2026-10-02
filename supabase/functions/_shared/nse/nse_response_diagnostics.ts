/** Compatibility only: callers MUST independently validate envelope, count, schema and scope.
 * No fuzzy matching, diagnostic normalization, fallback, database editing or retries.
 * Unknown rules return null; the endpoint decides its existing fail-closed category.
 */
import policy from "./nse_response_diagnostics_v1.json" with { type: "json" };
export function matchNseResponseDiagnostic(
  stableApi: string,
  nativeStatus: unknown,
  diagnostic: unknown,
  count: number,
  rows: unknown,
): { outcome: string; category: string; retry: false; ruleId: string } | null {
  if (
    !Number.isSafeInteger(count) || !Array.isArray(rows) ||
    rows.length !== count
  ) return null;
  const rule = policy.rules.find((r) =>
    r.api === stableApi && r.native_status === nativeStatus &&
    r.diagnostic === diagnostic && r.count === count &&
    r.shape === "empty_array" && rows.length === 0
  );
  return rule
    ? {
      outcome: rule.outcome,
      category: rule.category,
      retry: false,
      ruleId: rule.id,
    }
    : null;
}
