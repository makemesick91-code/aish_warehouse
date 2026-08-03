// Journal retention *planner*. It proposes a prune boundary and stops there.
//
// Nothing in this file deletes, schedules a delete, or calls
// `app_private.prune_sync_change_journal`. That is not caution for its own
// sake: the number that decides a safe boundary — the lowest cursor across all
// active devices — is stored on the devices, not on the server, so no query can
// establish it. The boundary therefore has to come from a product decision
// about how long a device may stay offline, and this tool's job is to turn that
// decision into a concrete number a human can approve.
//
// Read-only. Requires the service key because the journal is not client
// readable in bulk, but takes no write path at all.

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  describeTarget,
  redact,
  resolveStagingTarget,
  safeError,
  safeLog,
  utcStamp,
  writeArtifact,
} from "./staging_guard.ts";

async function main(): Promise<number> {
  const target = resolveStagingTarget({
    // Read-only, so the branch is not asserted: an operator may want this
    // number from any checkout.
    mutating: false,
    requireServiceRole: true,
  });
  describeTarget(target, "plan_supabase_12c_journal_retention");

  const safetyWindowDays = Number(
    Deno.args.find((entry) => entry.startsWith("--safety-window-days="))
      ?.split("=")[1] ??
      Deno.env.get("AISH_JOURNAL_SAFETY_WINDOW_DAYS") ?? "30",
  );
  if (!Number.isInteger(safetyWindowDays) || safetyWindowDays < 1) {
    safeError("retention_safety_window_invalid");
    return 2;
  }

  const service = createClient(target.url, target.serviceRoleKey!, {
    auth: { persistSession: false },
  });
  const result = await service.rpc("admin_sync_journal_retention_plan", {
    safety_window_days: safetyWindowDays,
  });
  if (result.error) {
    safeError(`retention_plan_failed: ${redact(result.error)}`);
    return 1;
  }
  const plan = result.data as Record<string, any>;

  safeLog("--------------------------------------------------------------");
  safeLog(`current_max_cursor        = ${plan.current_max_cursor}`);
  safeLog(`commit_horizon            = ${plan.commit_horizon}`);
  safeLog(`proposed_keep_through     = ${plan.proposed_keep_through}`);
  safeLog(`rows_eligible             = ${plan.rows_eligible}`);
  safeLog(`rows_total                = ${plan.rows_total}`);
  safeLog(`oldest_change             = ${plan.oldest_change}`);
  safeLog(`safety_window_days        = ${plan.safety_window_days}`);
  safeLog(`registered_devices        = ${plan.active_device_count}`);
  safeLog(`executed                  = ${plan.executed}`);
  safeLog("--------------------------------------------------------------");
  safeLog(
    "current_min_active_cursor = UNKNOWN — cursors live on devices. Confirm " +
      "from client telemetry before approving any boundary.",
  );

  const report = {
    ok: true,
    tool: "plan_supabase_12c_journal_retention",
    environment: "staging",
    project_ref: target.maskedRef,
    host: target.host,
    executed: false,
    // Named explicitly so nobody reads `proposed_keep_through` as approved.
    current_min_active_cursor: null,
    current_min_active_cursor_note:
      "Not derivable server-side. A device stores its own cursor; prune below " +
      "the lowest one and that device receives sync_cursor_invalid and " +
      "resyncs from zero — correct, but expensive and simultaneous.",
    ...plan,
    preconditions: [
      "The product owner has agreed a maximum offline age for a device.",
      "Client telemetry confirms no active device sits below the boundary.",
      "The boundary is below the commit horizon (enforced by the function).",
      "A full backup exists and has been verified restorable.",
      "A resync-from-zero for the affected devices is acceptable if the " +
        "telemetry turns out to be wrong.",
    ],
    generated_at_utc: new Date().toISOString(),
  };

  const path = await writeArtifact(
    `12c-retention-plan-${utcStamp()}`, "json", JSON.stringify(report, null, 2),
  );
  safeLog(`report      = ${path}`);
  safeLog("result      = PROPOSAL ONLY — nothing was pruned or scheduled");
  return 0;
}

try {
  Deno.exit(await main());
} catch (error) {
  safeError(`retention_plan_failed: ${redact(error)}`);
  Deno.exit(2);
}
