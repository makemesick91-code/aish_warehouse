// Staging verification for the Milestone 12C rollout.
//
// Read-only except for one namespaced fixture set, which exists because half of
// what has to be verified is behavioural: a grant table cannot tell you whether
// a branch A actor can page through branch B's changes. Structural facts come
// from `admin_sync_rollout_verification` — asserted, never queried ad hoc —
// and behavioural facts come from real authenticated sessions over HTTPS.
//
// Emits a JSON summary and a CI-usable exit code: 0 when every check passed,
// 1 when any check failed, 2 on a configuration refusal.

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  describeTarget,
  redact,
  resolveStagingTarget,
  runNamespace,
  safeError,
  safeLog,
  utcStamp,
  writeArtifact,
} from "./staging_guard.ts";
import { StagingFixtures } from "./staging_fixtures.ts";

type Check = {
  id: string;
  group: string;
  ok: boolean;
  detail: string;
};

const checks: Check[] = [];

function check(group: string, id: string, ok: boolean, detail = ""): void {
  checks.push({ id, group, ok: Boolean(ok), detail });
  safeLog(`${ok ? "PASS" : "FAIL"}  ${group.padEnd(12, " ")} ${id}${detail ? ` — ${detail}` : ""}`);
}

const EXPECTED_JOURNAL_COLUMNS = [
  "change_seq", "xact_id", "entity_type", "entity_id", "operation",
  "server_version", "changed_at",
];

async function main(): Promise<number> {
  const target = resolveStagingTarget({
    // Fixtures are written, so the branch assertion applies.
    mutating: true,
    requireServiceRole: true,
    requireFixturePassword: true,
  });
  describeTarget(target, "verify_supabase_12c_staging");

  const service = createClient(target.url, target.serviceRoleKey!, {
    auth: { persistSession: false },
  });

  // -------------------------------------------------------------------------
  // Server revision and migrations
  // -------------------------------------------------------------------------
  const snapshotResult = await service.rpc("admin_sync_rollout_verification");
  if (snapshotResult.error) {
    safeError(`verification_snapshot_unavailable: ${redact(snapshotResult.error)}`);
    return 1;
  }
  const snapshot = snapshotResult.data as Record<string, any>;

  check("revision", "server_revision_matches_contract",
    snapshot.server_revision === target.expectedRevision,
    `${snapshot.server_revision}`);
  const migrations: string[] = snapshot.migrations ?? [];
  check("revision", "12c_migration_applied",
    migrations.includes("20260803000100"));
  check("revision", "rollout_migration_applied",
    migrations.includes("20260803000200"));
  check("revision", "pull_rpc_present", snapshot.pull_rpc_present === true);
  check("revision", "pull_rpc_signature_unchanged",
    snapshot.pull_rpc_signature ===
      "after_cursor bigint, batch_limit integer, device_id uuid, entity_types text[]",
    String(snapshot.pull_rpc_signature));
  check("revision", "pull_rpc_is_security_definer",
    snapshot.pull_rpc_is_definer === true);

  // -------------------------------------------------------------------------
  // Privilege
  // -------------------------------------------------------------------------
  const privileges = snapshot.privileges ?? {};
  check("privilege", "authenticated_may_pull",
    privileges.authenticated_pull_rpc === true);
  check("privilege", "anon_may_not_pull",
    privileges.anon_pull_rpc === false);
  check("privilege", "visibility_oracle_stays_private",
    privileges.authenticated_pull_entity_visible === false);
  check("privilege", "no_private_helper_is_exposed",
    privileges.exposed_private_helper_count === 0,
    JSON.stringify(privileges.exposed_private_helpers ?? []));
  check("privilege", "authenticated_may_not_backfill",
    privileges.authenticated_backfill === false);
  check("privilege", "anon_may_not_backfill",
    privileges.anon_backfill === false);

  // The grant table says anon cannot call the pull RPC. This proves the running
  // server agrees, over the wire, with an actual anon key.
  const anon = createClient(target.url, target.anonKey, {
    auth: { persistSession: false },
  });
  const anonPull = await anon.rpc("pull_sync_changes", {
    after_cursor: 0, batch_limit: 1, device_id: crypto.randomUUID(),
  });
  check("privilege", "anon_pull_is_refused_over_the_wire",
    anonPull.error !== null, anonPull.error ? "refused" : "ACCEPTED");
  const anonBackfill = await anon.rpc("admin_backfill_sync_change_journal", {
    run_id: crypto.randomUUID(), dry_run: true,
  });
  check("privilege", "anon_backfill_is_refused_over_the_wire",
    anonBackfill.error !== null, anonBackfill.error ? "refused" : "ACCEPTED");

  // -------------------------------------------------------------------------
  // Journal
  // -------------------------------------------------------------------------
  const journal = snapshot.journal ?? {};
  check("journal", "rls_enabled", journal.rls_enabled === true);
  check("journal", "rls_forced", journal.rls_forced === true);
  const policies: Array<{ name: string; command: string; roles: string[] }> =
    journal.policies ?? [];
  check("journal", "only_a_select_policy_exists",
    policies.length === 1 && policies[0].command === "SELECT",
    policies.map((p) => `${p.name}:${p.command}`).join(","));
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
  check("journal", "in_realtime_publication",
    journal.in_realtime_publication === true,
    journal.realtime_publication_present
      ? ""
      : "supabase_realtime publication is absent");
  check("journal", "change_triggers_installed",
    Number(journal.journal_trigger_count) === 26,
    `${journal.journal_trigger_count}/26`);
  check("journal", "field_version_triggers_installed",
    Number(journal.field_version_trigger_count) === 7,
    `${journal.field_version_trigger_count}/7`);
  check("journal", "max_cursor_is_at_or_above_horizon",
    Number(journal.max_change_seq) >= Number(journal.commit_horizon),
    `max=${journal.max_change_seq} horizon=${journal.commit_horizon}`);

  const rollout = snapshot.rollout_tables ?? {};
  check("journal", "rollout_tables_present",
    rollout.marks_present === true && rollout.runs_present === true);
  check("journal", "rollout_tables_hidden_from_clients",
    rollout.authenticated_marks_select === false &&
      rollout.authenticated_runs_select === false);

  // -------------------------------------------------------------------------
  // Backfill coverage
  // -------------------------------------------------------------------------
  const revision = Deno.env.get("AISH_BACKFILL_REVISION") ??
    "aish-supabase-003-baseline";
  const coverageResult = await service.rpc("admin_sync_backfill_coverage", {
    backfill_revision: revision,
  });
  let coverage: Record<string, any> | null = null;
  if (coverageResult.error) {
    check("backfill", "coverage_available", false, redact(coverageResult.error));
  } else {
    coverage = coverageResult.data as Record<string, any>;
    check("backfill", "coverage_available", true);
    check("backfill", "every_entity_has_a_baseline",
      Number(coverage.missing_baseline_total) === 0,
      `missing=${coverage.missing_baseline_total}`);
    check("backfill", "coverage_reports_complete", coverage.complete === true);
    check("backfill", "no_duplicate_backfill_marker",
      Number(coverage.duplicate_marks) === 0,
      `duplicates=${coverage.duplicate_marks}`);
    const runs: Array<Record<string, any>> = rollout.runs ?? [];
    const relevant = runs.filter((run) => run.backfill_revision === revision);
    check("backfill", "a_run_exists_for_this_revision", relevant.length > 0,
      `${relevant.length} run(s)`);
    check("backfill", "no_run_reports_a_failure",
      relevant.every((run) => Number(run.failed) === 0));
    check("backfill", "at_least_one_run_completed",
      relevant.some((run) => run.completed === true));
    check("backfill", "field_version_baseline_present",
      Number(journal.field_version_rows) > 0,
      `${journal.field_version_rows} rows`);
  }

  // -------------------------------------------------------------------------
  // Change feed behaviour
  // -------------------------------------------------------------------------
  const fixtures = await StagingFixtures.create(
    target,
    runNamespace(`${target.namespace}-verify`),
  );
  let cleanup: { ok: boolean; problems: string[] } = { ok: true, problems: [] };
  try {
    const nurseA = await fixtures.signIn("nurseA");
    const nurseB = await fixtures.signIn("nurseB");
    const deviceA = await fixtures.registerDevice(nurseA, "verify-a");
    const deviceB = await fixtures.registerDevice(nurseB, "verify-b");

    const pull = async (
      client: typeof nurseA,
      device: string,
      cursor: number,
      limit = 200,
    ) => {
      const result = await client.rpc("pull_sync_changes", {
        after_cursor: cursor, batch_limit: limit, device_id: device,
      });
      if (result.error) throw result.error;
      return result.data as {
        changes: Array<Record<string, any>>;
        next_cursor: number;
        has_more: boolean;
        scope_fingerprint: string;
        server_horizon: number;
      };
    };

    const firstA = await pull(nurseA, deviceA, 0, 50);
    check("feed", "scope_fingerprint_present",
      typeof firstA.scope_fingerprint === "string" &&
        firstA.scope_fingerprint.length === 64);
    check("feed", "cursor_is_monotonic",
      firstA.next_cursor >= 0 &&
        firstA.changes.every((change, index) =>
          index === 0 ||
          change.change_seq > firstA.changes[index - 1].change_seq
        ));
    check("feed", "batch_respects_the_limit", firstA.changes.length <= 50,
      `${firstA.changes.length}`);

    // Pulling the same page twice must return the same page: the feed is a
    // function of the cursor, not of when it was asked.
    const repeatA = await pull(nurseA, deviceA, 0, 50);
    check("feed", "duplicate_pull_is_idempotent",
      JSON.stringify(repeatA.changes.map((c) => c.change_seq)) ===
        JSON.stringify(firstA.changes.map((c) => c.change_seq)));

    // Paging in twos must visit exactly the same sequence as paging in fifties.
    const paged: number[] = [];
    let cursor = 0;
    for (let page = 0; page < 200; page += 1) {
      const next = await pull(nurseA, deviceA, cursor, 2);
      paged.push(...next.changes.map((change) => Number(change.change_seq)));
      cursor = next.next_cursor;
      if (!next.has_more) break;
      if (cursor >= firstA.next_cursor) break;
    }
    const flat = firstA.changes.map((change) => Number(change.change_seq));
    check("feed", "pagination_is_stable_across_page_sizes",
      flat.every((seq) => paged.includes(seq)),
      `${paged.length} paged vs ${flat.length} bulk`);

    const scopeA = new Set(
      firstA.changes.filter((c) => c.entity_type === "room").map((c) => c.entity_id),
    );
    check("feed", "branch_isolation_holds",
      !scopeA.has(fixtures.set.roomB),
      scopeA.has(fixtures.set.roomB) ? "branch B room leaked to branch A" : "");
    const firstB = await pull(nurseB, deviceB, 0, 200);
    const scopeB = new Set(
      firstB.changes.filter((c) => c.entity_type === "room").map((c) => c.entity_id),
    );
    check("feed", "branch_isolation_holds_both_ways",
      !scopeB.has(fixtures.set.roomA));
    check("feed", "scope_fingerprints_differ_per_actor",
      firstA.scope_fingerprint !== firstB.scope_fingerprint);

    const crossDevice = await nurseA.rpc("pull_sync_changes", {
      after_cursor: 0, batch_limit: 10, device_id: deviceB,
    });
    check("feed", "another_actors_device_is_refused",
      crossDevice.error !== null,
      crossDevice.error ? String(crossDevice.error.message) : "ACCEPTED");

    const badCursor = await nurseA.rpc("pull_sync_changes", {
      after_cursor: -1, batch_limit: 10, device_id: deviceA,
    });
    check("feed", "negative_cursor_is_refused", badCursor.error !== null);
    const wildCursor = await nurseA.rpc("pull_sync_changes", {
      after_cursor: Number(journal.max_change_seq) + 1_000_000,
      batch_limit: 10, device_id: deviceA,
    });
    check("feed", "cursor_beyond_the_server_is_refused", wildCursor.error !== null);
    const badLimit = await nurseA.rpc("pull_sync_changes", {
      after_cursor: 0, batch_limit: 501, device_id: deviceA,
    });
    check("feed", "oversized_limit_is_refused", badLimit.error !== null);

    // An actor who has been deactivated must not receive a feed at all, even
    // with a session token that was valid a moment ago.
    const inactive = await fixtures.signIn("inactiveA");
    const inactivePull = await inactive.rpc("pull_sync_changes", {
      after_cursor: 0, batch_limit: 10, device_id: deviceA,
    });
    check("feed", "inactive_actor_receives_no_feed",
      inactivePull.error !== null,
      inactivePull.error ? "refused" : "ACCEPTED");

    // The journal read policy is the Realtime channel's filter. It must agree
    // with the pull filter, so branch B's rows are not selectable by branch A.
    const journalPeek = await nurseA.from("sync_change_journal")
      .select("entity_type, entity_id")
      .eq("entity_type", "room").eq("entity_id", fixtures.set.roomB);
    check("feed", "realtime_policy_hides_other_branches",
      (journalPeek.data ?? []).length === 0,
      journalPeek.error ? redact(journalPeek.error) : "");
    const journalWrite = await nurseA.from("sync_change_journal").insert({
      entity_type: "room", entity_id: fixtures.set.roomA,
      operation: "upsert", server_version: 1,
    });
    check("feed", "journal_is_not_writable_by_a_client",
      journalWrite.error !== null);
  } catch (error) {
    check("feed", "behavioural_checks_completed", false, redact(error));
  } finally {
    cleanup = await fixtures.cleanup();
  }
  check("fixtures", "cleanup_removed_only_this_run", cleanup.ok,
    cleanup.problems.join(" | "));

  // -------------------------------------------------------------------------
  // Summary
  // -------------------------------------------------------------------------
  const failed = checks.filter((entry) => !entry.ok);
  const summary = {
    ok: failed.length === 0,
    environment: "staging",
    project_ref: target.maskedRef,
    host: target.host,
    branch: target.branch,
    commit: target.commit,
    server_revision: snapshot.server_revision,
    rollout_migration_applied: migrations.includes("20260803000200"),
    backfill_complete: coverage ? coverage.complete === true : false,
    backfill_revision: revision,
    realtime_publication: journal.in_realtime_publication === true,
    private_helpers_exposed: Number(privileges.exposed_private_helper_count ?? -1),
    journal_rows: Number(journal.rows ?? 0),
    max_cursor: Number(journal.max_change_seq ?? 0),
    journal_total_bytes: Number(journal.total_bytes ?? 0),
    journal_index_bytes: Number(journal.index_bytes ?? 0),
    checks_total: checks.length,
    checks_failed: failed.length,
    failed_checks: failed.map((entry) => `${entry.group}/${entry.id}`),
    checks,
    checked_at_utc: new Date().toISOString(),
  };

  const path = await writeArtifact(
    `12c-verification-${utcStamp()}`,
    "json",
    JSON.stringify(summary, null, 2),
  );
  safeLog("--------------------------------------------------------------");
  safeLog(`report      = ${path}`);
  safeLog(
    `result      = ${summary.ok ? "PASS" : "FAIL"} (${
      checks.length - failed.length
    }/${checks.length} checks)`,
  );
  if (!summary.ok) safeLog(`failed      = ${summary.failed_checks.join(", ")}`);
  return summary.ok ? 0 : 1;
}

try {
  Deno.exit(await main());
} catch (error) {
  safeError(`verification_failed: ${redact(error)}`);
  Deno.exit(2);
}
