import type {
  NseMasterEvidenceStore,
  NseMasterScope,
} from "../_shared/nse/nse_master_download.ts";

export type MasterClaim =
  | { action: "DONE" }
  | { action: "BUSY" }
  | {
    action: "CAPTURE" | "FINALIZE";
    eventId: string;
    scope: NseMasterScope;
  };
export interface MasterPersistence {
  claim(eventId: string, token: string): Promise<MasterClaim>;
  evidence(eventId: string, token: string): NseMasterEvidenceStore;
  finalize(eventId: string, token: string): Promise<{
    outcome: "STAGED_VALIDATED" | "REJECTED" | "CAPTURE_FAILED" | "ABANDONED";
    snapshot_id: string | null;
  }>;
}
