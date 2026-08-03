// Minimal end-to-end canary against production.
//
// Seven things, and nothing else:
//
//   1. a 12B push still works, and a replay is still a replay;
//   2. the 12C pull is deterministic — the same cursor sees the same page, and
//      page size does not change what is seen;
//   3. branch isolation holds, asserted between two canary branches;
//   4. a Realtime frame invalidates, and the pull is what supplies the state;
//   5. a disconnected device catches up from its cursor;
//   6. duplicate movements: zero;
//   7. negative stock: zero.
//
// It runs inside a dedicated canary namespace and pushes exactly one document —
// a purchase request, chosen because submitting one posts no stock movement.
// The canary therefore never writes to the ledger, which is what lets checks 6
// and 7 be about production's real health rather than about the canary's own
// leftovers.
//
// Explicitly out of scope, and staying that way: bursts, failure injection,
// benchmarks, long transactions, and anything touching a real tenant's rows.
//
// Exit code: 0 when every check passed, 1 when any failed, 2 on a refusal.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  assertCondition,
  auditHeader,
  describeTarget,
  ProductionGuardError,
  redact,
  resolveProductionTarget,
  runNamespace,
  safeError,
  safeLog,
  utcStamp,
  writeProductionArtifact,
} from "./production_guard.ts";
import { ProductionCanaryNamespace } from "./production_canary_namespace.ts";
import { drain, envelope, pull, push } from "./production_sync_envelope.ts";
import { ProductionInvariants } from "./production_invariants.ts";

/// How many pages a canary drain may spend. Production's feed is as long as
/// production is old; a drain has to be a budget, not a loop that ends when the
/// server says so.
const MAX_PULL_PAGES = Number(
  Deno.env.get("AISH_PRODUCTION_MAX_PULL_PAGES") ?? "20",
);

/// How far back the duplicate-movement scan reaches. Bounded on purpose: this
/// is a canary, not a full ledger audit, and the report says how much of the
/// ledger it actually covered.
const MOVEMENT_SCAN_ROWS = Number(
  Deno.env.get("AISH_PRODUCTION_MOVEMENT_SCAN") ?? "1000",
);

const FRAME_TIMEOUT_MS = 20_000;

const results: Array<{ id: string; group: string; ok: boolean; detail: string }> = [];

function record(group: string, id: string, ok: boolean, detail = ""): void {
  results.push({ id, group, ok: Boolean(ok), detail });
  safeLog(
    `${ok ? "PASS" : "FAIL"}  ${group.padEnd(10, " ")} ${id}${detail ? ` — ${detail}` : ""}`,
  );
}

async function main(): Promise<number> {
  const target = resolveProductionTarget({
    mode: "guarded_write",
    writeScope: "canary_namespace",
    requireServiceRole: true,
    requireCanaryPassword: true,
  });
  describeTarget(target, "supabase_production_canary_e2e");
  safeLog(
    `budget      = ${MAX_PULL_PAGES} pull page(s) per drain, ` +
      `${MOVEMENT_SCAN_ROWS} ledger row(s) scanned, one document pushed`,
  );

  const canary = await ProductionCanaryNamespace.create(
    target, runNamespace(`${target.namespacePrefix}-e2e`),
  );
  const service = canary.serviceClient();
  const invariants = ProductionInvariants.forTables(
    service,
    Deno.env.get("AISH_BACKFILL_REVISION") ?? "aish-supabase-003-baseline",
    ["stock_movements", "stock_balances"],
    Number(Deno.env.get("AISH_PRODUCTION_INVARIANT_SAMPLE") ?? "5000"),
  );

  let retirement: Awaited<ReturnType<ProductionCanaryNamespace["retire"]>> = {
    ok: true, problems: [], retired: 0, left_in_place: [],
  };
  const startedAt = new Date().toISOString();
  const occurredAt = new Date().toISOString();
  let ledgerScan: Record<string, unknown> = {};

  const ledgerBefore = await invariants.snapshot("e2e_start", null);
  safeLog(
    `ledger      = ${ledgerBefore.movements.rows} movement(s), ` +
      `${ledgerBefore.balances.total_rows} balance(s) before the canary`,
  );

  try {
    const headA = await canary.signIn("headA");
    const nurseA = await canary.signIn("nurseA");
    const nurseB = await canary.signIn("nurseB");
    const deviceHead = await canary.registerDevice(headA, "e2e-head");
    const deviceB = await canary.registerDevice(nurseB, "e2e-b");

    // ---------------------------------------------------------------------
    // 1. 12B push
    // ---------------------------------------------------------------------
    // A purchase request needs an opname to link to. It is a canary document in
    // a canary branch, counted against the namespace ceiling and retired with
    // everything else.
    const opnameId = crypto.randomUUID();
    const opname = await service.from("stock_opnames").insert({
      id: opnameId, created_at: occurredAt, updated_at: occurredAt,
      sync_status: "synced", doc_number: `CANARY-SO-${canary.set.token}`,
      branch_id: canary.set.branchA, room_id: canary.set.roomA,
      period_year: new Date().getUTCFullYear(), period_week: 1,
      counted_by: canary.set.actors.nurseA.domainUserId,
      status: "submitted", submitted_at: occurredAt,
    });
    assertCondition(!opname.error, `canary_opname_failed:${redact(opname.error)}`);
    canary.track("stock_opnames", opnameId, false);

    const prId = crypto.randomUUID();
    const prLineId = crypto.randomUUID();
    const requestId = crypto.randomUUID();
    const prEnvelope = await envelope({
      request_id: requestId, device_id: deviceHead,
      operation: "submit_purchase_request",
      aggregate_type: "purchase_request", aggregate_id: prId,
      payload_version: 1, base_server_version: 0, occurred_at_utc: occurredAt,
      payload: {
        id: prId, created_at: occurredAt, branch_id: canary.set.branchA,
        requested_by: canary.set.actors.headA.domainUserId,
        status: "submitted",
        lines: [{
          id: prLineId, item_id: canary.set.itemId,
          suggested_qty: 1000, requested_qty: 1000,
        }],
        opname_links: [{ id: crypto.randomUUID(), opname_id: opnameId }],
      },
    });
    const submitted = await push(headA, prEnvelope, "canary_submit_pr");
    record("push", "a_12b_push_is_accepted", submitted.outcome === "accepted",
      submitted.outcome);
    if (submitted.outcome === "accepted") canary.track("purchase_requests", prId, false);
    record("push", "the_server_assigned_the_document_number",
      typeof submitted.final_document_number === "string" &&
        submitted.final_document_number.length > 0);

    // The same envelope again must be recognised, not performed a second time.
    // On production this is the difference between an idempotent retry and a
    // duplicate document.
    const replay = await push(headA, prEnvelope, "canary_replay_pr");
    record("push", "an_identical_replay_is_recognised",
      replay.outcome === "replayed", replay.outcome);

    // ---------------------------------------------------------------------
    // 2. Deterministic pull
    // ---------------------------------------------------------------------
    const bulk = await drain(headA, deviceHead, 0, 200, MAX_PULL_PAGES);
    record("pull", "a_drain_from_zero_terminates_within_budget", !bulk.truncated,
      `${bulk.pages} page(s), ${bulk.changes.length} change(s)`);
    const bulkSeq = bulk.changes.map((change) => Number(change.change_seq));
    record("pull", "the_cursor_advances_monotonically",
      bulkSeq.every((seq, index) => index === 0 || seq > bulkSeq[index - 1]));
    record("pull", "the_feed_includes_this_runs_own_document",
      bulk.changes.some((change) => change.entity_id === prId));
    record("pull", "every_upsert_carries_a_payload",
      bulk.changes.every((change) =>
        change.operation === "tombstone" || change.payload !== null
      ));

    const repeat = await drain(headA, deviceHead, 0, 200, MAX_PULL_PAGES);
    record("pull", "draining_twice_returns_the_same_sequence",
      JSON.stringify(repeat.changes.map((c) => Number(c.change_seq))) ===
        JSON.stringify(bulkSeq));

    // Page size must not change what is seen. Seven is deliberately awkward.
    const odd = await drain(headA, deviceHead, 0, 7, MAX_PULL_PAGES);
    const oddSeq = odd.changes.map((change) => Number(change.change_seq));
    record("pull", "an_odd_page_size_repeats_nothing",
      new Set(oddSeq).size === oddSeq.length);
    record("pull", "an_odd_page_size_skips_nothing_it_reached",
      odd.truncated
        ? oddSeq.every((seq) => bulkSeq.includes(seq))
        : JSON.stringify(oddSeq) === JSON.stringify(bulkSeq),
      odd.truncated ? "page budget reached; compared as a prefix" : "");

    const atHead = await pull(headA, deviceHead, bulk.cursor, 200);
    record("pull", "a_cursor_at_the_head_returns_an_empty_page",
      atHead.changes.length === 0 && !atHead.has_more,
      `${atHead.changes.length} change(s)`);

    const beyond = await headA.rpc("pull_sync_changes", {
      after_cursor: bulk.cursor + 1_000_000, batch_limit: 10, device_id: deviceHead,
    });
    record("pull", "a_cursor_beyond_the_server_is_refused", beyond.error !== null,
      beyond.error ? "refused" : "ACCEPTED");

    // ---------------------------------------------------------------------
    // 3. Branch isolation
    // ---------------------------------------------------------------------
    const feedB = await drain(nurseB, deviceB, 0, 200, MAX_PULL_PAGES);
    const idsB = new Set(feedB.changes.map((change) => change.entity_id));
    const idsHead = new Set(bulk.changes.map((change) => change.entity_id));
    record("isolation", "branch_b_never_sees_branch_as_room",
      !idsB.has(canary.set.roomA));
    record("isolation", "branch_b_never_sees_branch_as_store",
      !idsB.has(canary.set.locationBranchA));
    record("isolation", "branch_b_never_sees_branch_as_document",
      !idsB.has(prId));
    record("isolation", "branch_a_never_sees_branch_bs_room",
      !idsHead.has(canary.set.roomB));

    const firstA = await pull(headA, deviceHead, 0, 1);
    const firstB = await pull(nurseB, deviceB, 0, 1);
    record("isolation", "scope_fingerprints_differ_between_actors",
      firstA.scope_fingerprint !== firstB.scope_fingerprint);

    const crossDevice = await headA.rpc("pull_sync_changes", {
      after_cursor: 0, batch_limit: 10, device_id: deviceB,
    });
    record("isolation", "another_actors_device_is_refused", crossDevice.error !== null,
      crossDevice.error ? "refused" : "ACCEPTED");

    const journalWrite = await nurseA.from("sync_change_journal").insert({
      entity_type: "room", entity_id: canary.set.roomA,
      operation: "upsert", server_version: 1,
    });
    record("isolation", "a_client_cannot_write_the_journal", journalWrite.error !== null);

    // ---------------------------------------------------------------------
    // 4. Realtime invalidation — one event, no burst
    // ---------------------------------------------------------------------
    const frames: Array<{ entity_id: string }> = [];
    const channel = headA.channel(`canary-e2e-${canary.set.token}`)
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "sync_change_journal" },
        (payload) => {
          frames.push({ entity_id: String((payload.new as Record<string, unknown>).entity_id) });
        },
      );
    const subscribed = await new Promise<boolean>((resolve) => {
      const timer = setTimeout(() => resolve(false), FRAME_TIMEOUT_MS);
      channel.subscribe((status) => {
        if (status === "SUBSCRIBED") {
          clearTimeout(timer);
          resolve(true);
        } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
          clearTimeout(timer);
          resolve(false);
        }
      });
    });
    record("realtime", "subscription_established", subscribed);

    const cursorBeforeEvent = bulk.cursor;
    const renamed = await service.from("rooms").update({
      name: `CANARY ${canary.set.namespace} invalidated`,
      updated_at: new Date().toISOString(),
    }).eq("id", canary.set.roomA);
    assertCondition(!renamed.error, `canary_rename_failed:${redact(renamed.error)}`);

    const sawFrame = await waitFor(
      () => frames.some((frame) => frame.entity_id === canary.set.roomA),
      FRAME_TIMEOUT_MS,
    );
    record("realtime", "a_scope_change_produces_an_invalidation", sawFrame);
    const afterEvent = await drain(headA, deviceHead, cursorBeforeEvent, 200, MAX_PULL_PAGES);
    record("realtime", "the_pull_triggered_by_the_frame_supplies_the_state",
      afterEvent.changes.some((change) =>
        change.entity_id === canary.set.roomA &&
        String((change.payload ?? {}).name ?? "").endsWith("invalidated")
      ));

    // ---------------------------------------------------------------------
    // 5. Disconnect and catch up
    // ---------------------------------------------------------------------
    await headA.removeChannel(channel);
    record("catchup", "subscription_closed", true);
    const offlineCursor = afterEvent.cursor;
    const offline = await service.from("rooms").update({
      name: `CANARY ${canary.set.namespace} offline-1`,
      updated_at: new Date().toISOString(),
    }).eq("id", canary.set.roomA);
    assertCondition(!offline.error, `canary_offline_edit_failed:${redact(offline.error)}`);

    const caughtUp = await drain(headA, deviceHead, offlineCursor, 200, MAX_PULL_PAGES);
    record("catchup", "a_disconnected_device_catches_up_from_its_cursor",
      caughtUp.changes.length > 0, `${caughtUp.changes.length} change(s)`);
    record("catchup", "the_cursor_advanced", caughtUp.cursor > offlineCursor,
      `${offlineCursor} -> ${caughtUp.cursor}`);
    const latest = caughtUp.changes.filter((change) =>
      change.entity_id === canary.set.roomA && change.payload
    ).at(-1);
    record("catchup", "the_caught_up_state_is_the_servers_current_state",
      String(latest?.payload?.name ?? "").endsWith("offline-1"));

    // ---------------------------------------------------------------------
    // 6 & 7. Ledger health
    // ---------------------------------------------------------------------
    ledgerScan = await scanLedger(service);
    record("ledger", "duplicate_movements_are_zero",
      Number(ledgerScan.duplicate_groups) === 0,
      `${ledgerScan.duplicate_groups} duplicate group(s) in the last ` +
        `${ledgerScan.scanned} movement(s)`);
    record("ledger", "negative_stock_balances_are_zero",
      Number(ledgerScan.negative_balances) === 0,
      `${ledgerScan.negative_balances} row(s)`);

    const ledgerAfter = await invariants.snapshot("e2e_end", null);
    record("ledger", "the_canary_posted_no_stock_movement",
      ledgerAfter.movements.rows === ledgerBefore.movements.rows,
      `${ledgerBefore.movements.rows} -> ${ledgerAfter.movements.rows}`);
    record("ledger", "the_canary_changed_no_stock_balance",
      ledgerAfter.balances.total_rows === ledgerBefore.balances.total_rows &&
        ledgerAfter.balances.qty_sum === ledgerBefore.balances.qty_sum,
      `${ledgerBefore.balances.qty_sum} -> ${ledgerAfter.balances.qty_sum}`);
  } catch (error) {
    record("harness", "harness_completed", false, redact(error));
  } finally {
    retirement = await canary.retire();
  }
  record("harness", "canary_namespace_retired", retirement.ok,
    retirement.problems.join(" | "));

  const failed = results.filter((entry) => !entry.ok);
  const report = {
    ok: failed.length === 0,
    ...auditHeader(target, "supabase_production_canary_e2e"),
    namespace: canary.set.namespace,
    started_at_utc: startedAt,
    finished_at_utc: new Date().toISOString(),
    pull_page_budget: MAX_PULL_PAGES,
    movement_scan_rows: MOVEMENT_SCAN_ROWS,
    ledger_scan: ledgerScan,
    ledger_before: {
      movements: ledgerBefore.movements.rows,
      balances: ledgerBefore.balances.total_rows,
      balance_qty_sum: ledgerBefore.balances.qty_sum,
      balance_method: ledgerBefore.balances.method,
    },
    rows_created: canary.createdRows().length,
    rows_retired: retirement.retired,
    left_in_place: retirement.left_in_place,
    checks_total: results.length,
    checks_failed: failed.length,
    failed_checks: failed.map((entry) => `${entry.group}/${entry.id}`),
    results,
    excluded_by_policy: [
      "50-event burst and coalescing (load generator — local and staging only)",
      "failure injection and forced conflict storms",
      "heavy benchmark and long transactions",
      "any operation that posts to the stock ledger",
    ],
  };
  const path = await writeProductionArtifact(
    `production-canary-e2e-${utcStamp()}`, "json", JSON.stringify(report, null, 2),
  );
  safeLog("--------------------------------------------------------------");
  safeLog(`report      = ${path}`);
  safeLog(
    `result      = ${report.ok ? "PASS" : "FAIL"} (${results.length - failed.length}/${results.length})`,
  );
  if (!report.ok) safeLog(`failed      = ${report.failed_checks.join(", ")}`);
  return report.ok ? 0 : 1;
}

async function waitFor(predicate: () => boolean, timeout: number): Promise<boolean> {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (predicate()) return true;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  return predicate();
}

/// Bounded duplicate-movement scan.
///
/// A duplicate movement is what a non-idempotent retry produces: the same
/// document posting the same quantity of the same item between the same two
/// locations twice. The primary key cannot catch it — the two rows have
/// different ids — so it has to be found by shape.
///
/// This reads the most recent `MOVEMENT_SCAN_ROWS` movements and groups them.
/// It is a canary-sized window, not a full ledger audit, and the report says how
/// many rows it actually covered. Reversals are excluded: a reversal is a
/// legitimate second movement mirroring the first.
async function scanLedger(service: SupabaseClient): Promise<Record<string, unknown>> {
  const movements = await service
    .from("stock_movements")
    .select(
      "id, item_id, batch_id, from_location_id, to_location_id, qty, " +
        "movement_type, ref_doc_type, ref_doc_id, created_at, reversal_of_movement_id",
    )
    .order("created_at", { ascending: false })
    .limit(MOVEMENT_SCAN_ROWS);
  if (movements.error) throw movements.error;
  const rows = (movements.data ?? []) as unknown as Array<Record<string, unknown>>;

  const groups = new Map<string, number>();
  for (const row of rows) {
    if (row.movement_type === "reversal" || row.reversal_of_movement_id !== null) continue;
    if (row.ref_doc_id === null) continue;
    const key = [
      row.ref_doc_type, row.ref_doc_id, row.item_id, row.batch_id,
      row.from_location_id, row.to_location_id, row.qty, row.movement_type,
    ].join("|");
    groups.set(key, (groups.get(key) ?? 0) + 1);
  }
  const duplicates = [...groups.entries()].filter(([, count]) => count > 1);

  const negative = await service
    .from("stock_balances")
    .select("*", { count: "exact", head: true })
    .lt("qty_on_hand", 0);
  if (negative.error) throw negative.error;

  return {
    scanned: rows.length,
    scan_limit: MOVEMENT_SCAN_ROWS,
    covers_whole_ledger: rows.length < MOVEMENT_SCAN_ROWS,
    duplicate_groups: duplicates.length,
    duplicate_examples: duplicates.slice(0, 5).map(([key, count]) => ({ key, count })),
    negative_balances: Number(negative.count ?? 0),
  };
}

try {
  Deno.exit(await main());
} catch (error) {
  safeError(`production_canary_e2e_failed: ${redact(error)}`);
  Deno.exit(error instanceof ProductionGuardError ? 2 : 1);
}
