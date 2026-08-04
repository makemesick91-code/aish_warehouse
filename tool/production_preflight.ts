// Production canary preflight — the gate every other production tool sits
// behind, and the record the change ticket is closed against.
//
// Read-only. It opens exactly one authenticated connection, calls one
// service-role reporting RPC, and writes an audit artifact. It never writes a
// row, never creates a fixture and has no `--execute`.
//
// Two jobs, and they belong together because they answer the same question:
//
//   1. Is this operator authorised, right now, against this exact project?
//      Exact project ref, exact host, git branch, commit, clean tree, change
//      ticket, maintenance window, backup identifier, restore rehearsal,
//      operator acknowledgement. The guard refuses if any is missing; this tool
//      records what it refused on and what it accepted.
//
//   2. Is the server currently in a state where the canary may proceed? That is
//      the stop-condition table from the runbook, evaluated against the live
//      project rather than from memory.
//
// Exit code: 0 when every preflight item passed and no stop condition is
// triggered, 1 when something failed, 2 on a configuration refusal.

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  auditHeader,
  describeTarget,
  ProductionGuardError,
  redact,
  resolveProductionTarget,
  safeError,
  safeLog,
  utcStamp,
  writeProductionArtifact,
} from "./production_guard.ts";

type Item = {
  id: string;
  group: string;
  ok: boolean;
  detail: string;
};

const items: Item[] = [];

function item(group: string, id: string, ok: boolean, detail = ""): void {
  items.push({ id, group, ok: Boolean(ok), detail });
  safeLog(
    `${ok ? "PASS" : "FAIL"}  ${group.padEnd(12, " ")} ${id}${detail ? ` — ${detail}` : ""}`,
  );
}

type StopCondition = {
  id: string;
  triggered: boolean;
  detail: string;
  action: string;
};

const stopConditions: StopCondition[] = [];

function stopCondition(
  id: string,
  triggered: boolean,
  action: string,
  detail = "",
): void {
  stopConditions.push({ id, triggered, detail, action });
  if (triggered) {
    safeLog(`STOP  ${id}${detail ? ` — ${detail}` : ""}`);
    safeLog(`      action: ${action}`);
  }
}

async function main(): Promise<number> {
  const target = resolveProductionTarget({
    mode: "read_only",
    requireServiceRole: true,
  });
  describeTarget(target, "production_preflight");

  // ---------------------------------------------------------------------
  // 1. Authorisation record
  // ---------------------------------------------------------------------
  // Reaching this line means the guard already accepted every one of these.
  // Recording them individually is what makes the artifact a change record
  // rather than a claim that "the script ran".
  item("identity", "target_env_is_production", true, "AISH_TARGET_ENV=production");
  item("identity", "production_confirmation_given", true, "token matched");
  item("identity", "second_confirmation_given", true, "project ref restated");
  item("identity", "project_ref_matches_url_exactly", true, target.maskedRef);
  item("identity", "host_matches_allowlist_exactly", true, target.host);
  item("identity", "connection_is_https", target.url.startsWith("https://"));
  item("identity", "no_staging_environment_loaded", true);
  item("change", "change_ticket_recorded", true, target.changeTicket);
  item(
    "change",
    "inside_maintenance_window",
    target.maintenanceWindow.remainingMinutes >= 0,
    `${target.maintenanceWindow.remainingMinutes} minute(s) remaining`,
  );
  item("change", "operator_acknowledged", true, target.operatorAcknowledgement);
  item("backup", "backup_identifier_recorded", true, target.backupIdentifier);
  item(
    "backup",
    "backup_checksum_recorded",
    target.backupChecksum !== null,
    target.backupChecksum ?? "not supplied (optional, but recommended)",
  );
  item("backup", "restore_rehearsal_confirmed", true);
  item("git", "branch_is_the_authorised_one", true, target.branch);
  item("git", "commit_recorded", true, target.commit);
  item("git", "working_tree_clean", target.treeClean);
  item("mode", "tool_is_read_only", target.mode === "read_only");
  item(
    "mode",
    "no_write_scope_granted_for_this_run",
    target.writeScope === null,
    target.writeScope ?? "none",
  );

  // A window with less than this left is not enough to run a canary, take a
  // decision and still have room to stop. Reported, not refused: the operator
  // decides whether to extend the window or defer.
  const MIN_USEFUL_MINUTES = 30;
  if (target.maintenanceWindow.remainingMinutes < MIN_USEFUL_MINUTES) {
    stopCondition(
      "maintenance_window_nearly_closed",
      true,
      "extend the window or defer the canary; do not start work you cannot stop",
      `${target.maintenanceWindow.remainingMinutes} minute(s) left`,
    );
  }

  // ---------------------------------------------------------------------
  // 2. Server state
  // ---------------------------------------------------------------------
  const service = createClient(target.url, target.serviceRoleKey!, {
    auth: { persistSession: false },
  });

  const snapshotResult = await service.rpc("admin_sync_rollout_verification");
  if (snapshotResult.error) {
    item("server", "rollout_verification_reachable", false, redact(snapshotResult.error));
    return await finish(target, null);
  }
  const snapshot = snapshotResult.data as Record<string, any>;
  item("server", "rollout_verification_reachable", true);

  const migrations: string[] = snapshot.migrations ?? [];
  const journal = snapshot.journal ?? {};
  const privileges = snapshot.privileges ?? {};
  const rollout = snapshot.rollout_tables ?? {};
  const devices = snapshot.devices ?? {};

  item(
    "server",
    "server_revision_matches_contract",
    snapshot.server_revision === target.expectedRevision,
    String(snapshot.server_revision),
  );
  item("server", "pull_migration_applied", migrations.includes("20260803000100"));
  item("server", "rollout_migration_applied", migrations.includes("20260803000200"));
  item("server", "last_applied_migration_recorded", migrations.length > 0,
    migrations.at(-1) ?? "none");
  item("server", "registered_devices_recorded", true, `${devices.total ?? 0} device(s)`);
  item("server", "journal_rows_recorded", true, `${journal.rows ?? 0} row(s)`);
  item("server", "max_cursor_recorded", true, String(journal.max_change_seq ?? 0));
  item("server", "commit_horizon_recorded", true, String(journal.commit_horizon ?? 0));
  item(
    "server",
    "realtime_publication_state_recorded",
    true,
    journal.in_realtime_publication === true ? "present" : "absent",
  );

  // ---------------------------------------------------------------------
  // 3. Stop conditions
  // ---------------------------------------------------------------------
  // Each one is a reason to halt the canary rather than proceed carefully.
  // They are evaluated here so the decision is made before anything is touched,
  // and re-evaluated by the same tool after each canary step.
  stopCondition(
    "private_helper_reachable_from_a_session",
    Number(privileges.exposed_private_helper_count ?? 0) !== 0,
    "halt; a client session can reach an internal helper — fix before any canary",
    JSON.stringify(privileges.exposed_private_helpers ?? []),
  );
  stopCondition(
    "admin_rpc_reachable_from_a_session",
    privileges.authenticated_backfill === true || privileges.anon_backfill === true,
    "halt; revoke execute on the admin RPCs from authenticated and anon",
  );
  stopCondition(
    "anon_can_pull",
    privileges.anon_pull_rpc === true,
    "halt; revoke execute on public.pull_sync_changes from anon",
  );
  stopCondition(
    "journal_rls_not_forced",
    journal.rls_enabled !== true || journal.rls_forced !== true,
    "halt; the journal read policy is the Realtime filter — it must be forced",
    `enabled=${journal.rls_enabled} forced=${journal.rls_forced}`,
  );
  const policies: Array<{ command: string }> = journal.policies ?? [];
  stopCondition(
    "journal_has_a_non_select_policy",
    policies.some((policy) => policy.command !== "SELECT"),
    "halt; a write policy on the journal makes it forgeable by a client",
    policies.map((policy) => policy.command).join(","),
  );
  stopCondition(
    "journal_carries_a_business_column",
    JSON.stringify(journal.columns) !== JSON.stringify([
      "change_seq", "xact_id", "entity_type", "entity_id", "operation",
      "server_version", "changed_at",
    ]),
    "halt; a business column in the journal leaks through Realtime frames",
    JSON.stringify(journal.columns ?? []),
  );
  stopCondition(
    "journal_immutability_trigger_absent",
    journal.immutable_trigger !== true,
    "halt; without it a journal row can be rewritten after devices have read it",
  );
  stopCondition(
    "max_cursor_below_commit_horizon",
    Number(journal.max_change_seq ?? 0) < Number(journal.commit_horizon ?? 0),
    "investigate; the feed head is behind the horizon it is supposed to lead",
    `max=${journal.max_change_seq} horizon=${journal.commit_horizon}`,
  );
  stopCondition(
    "rollout_tables_visible_to_clients",
    rollout.authenticated_marks_select === true ||
      rollout.authenticated_runs_select === true,
    "halt; the backfill bookkeeping must not be readable by a session",
  );
  stopCondition(
    "rollout_tables_missing",
    rollout.marks_present !== true || rollout.runs_present !== true,
    "halt; apply 20260803000200 before running the backfill canary",
  );

  const runs: Array<Record<string, any>> = rollout.runs ?? [];
  const failedRuns = runs.filter((run) => Number(run.failed ?? 0) > 0);
  stopCondition(
    "a_previous_backfill_run_reported_failures",
    failedRuns.length > 0,
    "halt; resume the failed run and clear it before starting a new one",
    failedRuns.map((run) => String(run.run_id)).join(","),
  );
  const openRuns = runs.filter((run) => run.completed !== true);
  stopCondition(
    "an_incomplete_backfill_run_exists",
    openRuns.length > 0,
    "resume that run id rather than starting a second one",
    openRuns.map((run) => String(run.run_id)).join(","),
  );

  return await finish(target, snapshot);
}

async function finish(
  target: ReturnType<typeof resolveProductionTarget>,
  snapshot: Record<string, any> | null,
): Promise<number> {
  const failed = items.filter((entry) => !entry.ok);
  const triggered = stopConditions.filter((entry) => entry.triggered);
  const ok = failed.length === 0 && triggered.length === 0;

  const report = {
    ok,
    ...auditHeader(target, "production_preflight"),
    checked_at_utc: new Date().toISOString(),
    server_revision: snapshot?.server_revision ?? null,
    migrations: snapshot?.migrations ?? [],
    devices_total: snapshot?.devices?.total ?? null,
    journal: snapshot?.journal
      ? {
        rows: snapshot.journal.rows,
        min_change_seq: snapshot.journal.min_change_seq,
        max_change_seq: snapshot.journal.max_change_seq,
        commit_horizon: snapshot.journal.commit_horizon,
        table_bytes: snapshot.journal.table_bytes,
        index_bytes: snapshot.journal.index_bytes,
        total_bytes: snapshot.journal.total_bytes,
        in_realtime_publication: snapshot.journal.in_realtime_publication,
      }
      : null,
    items_total: items.length,
    items_failed: failed.length,
    failed_items: failed.map((entry) => `${entry.group}/${entry.id}`),
    items,
    stop_conditions_triggered: triggered.length,
    stop_conditions: stopConditions,
  };

  const path = await writeProductionArtifact(
    `production-preflight-${utcStamp()}`,
    "json",
    JSON.stringify(report, null, 2),
  );
  safeLog("--------------------------------------------------------------");
  safeLog(`report      = ${path}`);
  safeLog(
    `result      = ${ok ? "GO" : "NO-GO"} (${items.length - failed.length}/${items.length} preflight items, ` +
      `${triggered.length} stop condition(s) triggered)`,
  );
  if (failed.length > 0) safeLog(`failed      = ${report.failed_items.join(", ")}`);
  if (triggered.length > 0) {
    safeLog(`stop        = ${triggered.map((entry) => entry.id).join(", ")}`);
  }
  return ok ? 0 : 1;
}

try {
  Deno.exit(await main());
} catch (error) {
  safeError(`production_preflight_failed: ${redact(error)}`);
  Deno.exit(error instanceof ProductionGuardError ? 2 : 1);
}
