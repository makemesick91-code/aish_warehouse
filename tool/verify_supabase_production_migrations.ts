// Production-safe migration verification.
//
// The staging equivalent (`verify_supabase_12c_staging.ts`) proves behaviour by
// creating fixture actors and paging the feed as each of them. That is the
// right thing to do on staging and the wrong thing to do on production, so this
// tool does not do it. What it verifies instead is everything that can be
// established without writing a row:
//
//   * which migrations are applied, and that the server revision still matches
//     the client contract;
//   * that the pull RPC's signature and security context are unchanged, so a
//     released client is still talking to the function it was built against;
//   * the grant table — who may call what;
//   * the journal's RLS, policy shape, columns, triggers and publication;
//   * and, over the wire with a real anon key, that the refusals the grant
//     table promises are the refusals the running server actually gives.
//
// The last group is the only part that touches the network as a client. It uses
// the anonymous key, asks for operations that must be refused, and asserts they
// were. A refusal is not a mutation, so this remains read-only in the sense
// that matters: no row in this database is different afterwards.
//
// Exit code: 0 when every check passed, 1 when any failed, 2 on a refusal.

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

type Check = { id: string; group: string; ok: boolean; detail: string };

const checks: Check[] = [];

function check(group: string, id: string, ok: boolean, detail = ""): void {
  checks.push({ id, group, ok: Boolean(ok), detail });
  safeLog(
    `${ok ? "PASS" : "FAIL"}  ${group.padEnd(11, " ")} ${id}${detail ? ` — ${detail}` : ""}`,
  );
}

/// The seven bookkeeping columns. An eighth means a business value is being
/// broadcast to every subscribed client through Realtime.
const EXPECTED_JOURNAL_COLUMNS = [
  "change_seq", "xact_id", "entity_type", "entity_id", "operation",
  "server_version", "changed_at",
];

/// The signature a released 12C client was compiled against. A change here is a
/// client-breaking change even when the name is the same.
const EXPECTED_PULL_SIGNATURE =
  "after_cursor bigint, batch_limit integer, device_id uuid, entity_types text[]";

const REQUIRED_MIGRATIONS = [
  "20260802000100", "20260802000200", "20260802000300", "20260802000400",
  "20260802000500", "20260802000600", "20260802000700", "20260802000800",
  "20260802000900", "20260803000100", "20260803000200",
];

async function main(): Promise<number> {
  const target = resolveProductionTarget({
    mode: "read_only",
    requireServiceRole: true,
  });
  describeTarget(target, "verify_supabase_production_migrations");

  const service = createClient(target.url, target.serviceRoleKey!, {
    auth: { persistSession: false },
  });

  const snapshotResult = await service.rpc("admin_sync_rollout_verification");
  if (snapshotResult.error) {
    safeError(`verification_snapshot_unavailable: ${redact(snapshotResult.error)}`);
    return 1;
  }
  const snapshot = snapshotResult.data as Record<string, any>;

  // -------------------------------------------------------------------------
  // Migrations and revision
  // -------------------------------------------------------------------------
  const migrations: string[] = snapshot.migrations ?? [];
  for (const required of REQUIRED_MIGRATIONS) {
    check("migration", `applied_${required}`, migrations.includes(required));
  }
  // An unexpected migration is not an error — it is something a reviewer has to
  // have seen before a canary runs against it.
  const unexpected = migrations.filter((entry) =>
    !REQUIRED_MIGRATIONS.some((required) => entry.startsWith(required))
  );
  check("migration", "no_unreviewed_migration_is_applied", unexpected.length === 0,
    unexpected.join(","));
  check("revision", "server_revision_matches_client_contract",
    snapshot.server_revision === target.expectedRevision,
    String(snapshot.server_revision));

  // -------------------------------------------------------------------------
  // Contract surface
  // -------------------------------------------------------------------------
  check("contract", "pull_rpc_present", snapshot.pull_rpc_present === true);
  check("contract", "pull_rpc_signature_unchanged",
    snapshot.pull_rpc_signature === EXPECTED_PULL_SIGNATURE,
    String(snapshot.pull_rpc_signature));
  check("contract", "pull_rpc_is_security_definer",
    snapshot.pull_rpc_is_definer === true);

  // -------------------------------------------------------------------------
  // Privilege, from the grant table
  // -------------------------------------------------------------------------
  const privileges = snapshot.privileges ?? {};
  check("privilege", "authenticated_may_pull", privileges.authenticated_pull_rpc === true);
  check("privilege", "anon_may_not_pull", privileges.anon_pull_rpc === false);
  check("privilege", "visibility_oracle_stays_private",
    privileges.authenticated_pull_entity_visible === false);
  check("privilege", "no_private_helper_is_exposed",
    Number(privileges.exposed_private_helper_count ?? -1) === 0,
    JSON.stringify(privileges.exposed_private_helpers ?? []));
  check("privilege", "authenticated_may_not_backfill",
    privileges.authenticated_backfill === false);
  check("privilege", "anon_may_not_backfill", privileges.anon_backfill === false);

  // -------------------------------------------------------------------------
  // Privilege, over the wire
  // -------------------------------------------------------------------------
  // The grant table is a description. These are the running server's answers.
  // Every call below is one the server must refuse, so a pass leaves nothing
  // behind and a fail is the finding.
  const anon = createClient(target.url, target.anonKey, {
    auth: { persistSession: false },
  });
  const anonPull = await anon.rpc("pull_sync_changes", {
    after_cursor: 0, batch_limit: 1, device_id: crypto.randomUUID(),
  });
  check("wire", "anon_pull_is_refused", anonPull.error !== null,
    anonPull.error ? "refused" : "ACCEPTED");
  const anonBackfill = await anon.rpc("admin_backfill_sync_change_journal", {
    run_id: crypto.randomUUID(), dry_run: true,
  });
  check("wire", "anon_backfill_is_refused", anonBackfill.error !== null,
    anonBackfill.error ? "refused" : "ACCEPTED");
  const anonVerification = await anon.rpc("admin_sync_rollout_verification");
  check("wire", "anon_rollout_verification_is_refused", anonVerification.error !== null,
    anonVerification.error ? "refused" : "ACCEPTED");
  const anonJournal = await anon.from("sync_change_journal").select("change_seq").limit(1);
  check("wire", "anon_journal_select_is_refused",
    anonJournal.error !== null || (anonJournal.data ?? []).length === 0,
    anonJournal.error ? "refused" : `${(anonJournal.data ?? []).length} row(s)`);
  const anonMarks = await anon.from("sync_change_journal_backfill_marks")
    .select("entity_id").limit(1);
  check("wire", "anon_backfill_marks_select_is_refused",
    anonMarks.error !== null || (anonMarks.data ?? []).length === 0,
    anonMarks.error ? "refused" : `${(anonMarks.data ?? []).length} row(s)`);

  // -------------------------------------------------------------------------
  // Journal shape
  // -------------------------------------------------------------------------
  const journal = snapshot.journal ?? {};
  check("journal", "rls_enabled", journal.rls_enabled === true);
  check("journal", "rls_forced", journal.rls_forced === true);
  const policies: Array<{ name: string; command: string; roles: string[] }> =
    journal.policies ?? [];
  check("journal", "only_a_select_policy_exists",
    policies.length === 1 && policies[0].command === "SELECT",
    policies.map((policy) => `${policy.name}:${policy.command}`).join(","));
  check("journal", "select_policy_targets_authenticated",
    policies.length === 1 && policies[0].roles.includes("authenticated"));
  check("journal", "authenticated_may_select", journal.authenticated_select === true);
  check("journal", "authenticated_may_not_insert", journal.authenticated_insert === false);
  check("journal", "authenticated_may_not_update", journal.authenticated_update === false);
  check("journal", "authenticated_may_not_delete", journal.authenticated_delete === false);
  check("journal", "anon_may_not_select", journal.anon_select === false);
  check("journal", "immutability_trigger_active", journal.immutable_trigger === true);
  check("journal", "carries_no_business_payload",
    JSON.stringify(journal.columns) === JSON.stringify(EXPECTED_JOURNAL_COLUMNS),
    JSON.stringify(journal.columns));
  check("journal", "change_triggers_installed",
    Number(journal.journal_trigger_count) === 26,
    `${journal.journal_trigger_count}/26`);
  check("journal", "field_version_triggers_installed",
    Number(journal.field_version_trigger_count) === 7,
    `${journal.field_version_trigger_count}/7`);
  check("journal", "max_cursor_is_at_or_above_horizon",
    Number(journal.max_change_seq) >= Number(journal.commit_horizon),
    `max=${journal.max_change_seq} horizon=${journal.commit_horizon}`);
  // Absence is a note, not a failure: the design is correct without Realtime,
  // only slower. It is recorded so the canary knows which behaviour to expect.
  check("journal", "realtime_publication_recorded", true,
    journal.in_realtime_publication === true ? "present" : "absent");

  const rollout = snapshot.rollout_tables ?? {};
  check("journal", "rollout_tables_present",
    rollout.marks_present === true && rollout.runs_present === true);
  check("journal", "rollout_tables_hidden_from_clients",
    rollout.authenticated_marks_select === false &&
      rollout.authenticated_runs_select === false);

  // -------------------------------------------------------------------------
  // Summary
  // -------------------------------------------------------------------------
  const failed = checks.filter((entry) => !entry.ok);
  const report = {
    ok: failed.length === 0,
    ...auditHeader(target, "verify_supabase_production_migrations"),
    checked_at_utc: new Date().toISOString(),
    server_revision: snapshot.server_revision,
    migrations,
    realtime_publication: journal.in_realtime_publication === true,
    journal_rows: Number(journal.rows ?? 0),
    journal_max_change_seq: Number(journal.max_change_seq ?? 0),
    journal_commit_horizon: Number(journal.commit_horizon ?? 0),
    journal_table_bytes: Number(journal.table_bytes ?? 0),
    journal_index_bytes: Number(journal.index_bytes ?? 0),
    checks_total: checks.length,
    checks_failed: failed.length,
    failed_checks: failed.map((entry) => `${entry.group}/${entry.id}`),
    checks,
    coverage_note:
      "Structural and privilege verification only. Feed behaviour under real " +
      "actors is verified by the canary E2E, which uses a dedicated canary " +
      "namespace; it is never verified against a real user's data.",
  };

  const path = await writeProductionArtifact(
    `production-migration-verification-${utcStamp()}`,
    "json",
    JSON.stringify(report, null, 2),
  );
  safeLog("--------------------------------------------------------------");
  safeLog(`report      = ${path}`);
  safeLog(
    `result      = ${report.ok ? "PASS" : "FAIL"} (${checks.length - failed.length}/${checks.length} checks)`,
  );
  if (!report.ok) safeLog(`failed      = ${report.failed_checks.join(", ")}`);
  return report.ok ? 0 : 1;
}

try {
  Deno.exit(await main());
} catch (error) {
  safeError(`production_migration_verification_failed: ${redact(error)}`);
  Deno.exit(error instanceof ProductionGuardError ? 2 : 1);
}
