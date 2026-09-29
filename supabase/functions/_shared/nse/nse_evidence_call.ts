/**
 * Attempt-local boundary for immutable NSE evidence and its one transport call.
 * Callbacks own persistence and transport details; this helper only preserves
 * their retry and invocation semantics.
 */
export type NseEvidenceCall<Result> = {
  persist: <Value>(callback: () => Promise<Value>) => Promise<Value>;
  submit: () => Promise<Result>;
};

export function createNseEvidenceCall<Result>(
  submit: () => Promise<Result>,
): NseEvidenceCall<Result> {
  let submission: Promise<Result> | undefined;
  return {
    async persist<Value>(callback: () => Promise<Value>): Promise<Value> {
      try {
        return await callback();
      } catch {
        return await callback();
      }
    },
    submit(): Promise<Result> {
      submission ??= submit();
      return submission;
    },
  };
}
