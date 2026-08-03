// Milestone 12C pull path, against staging.
//
// What this covers that pgTAP structurally cannot: the commit horizon only
// releases a change once its transaction has settled, so every assertion about
// what a cursor sees needs committed writes and separate sessions. That is also
// why the baseline-from-zero and page-boundary checks live here rather than in
// `supabase/tests/database/journal_backfill.test.sql`.
//
// It runs against a project with other data in it, so nothing here asserts an
// absolute count. Assertions are about the run's own namespaced entities and
// about ordering properties that hold regardless of what else is in the feed.

import {
  assertCondition,
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
import { drain, envelope, pull, push } from "./staging_sync_envelope.ts";

const results: Array<{ id: string; ok: boolean; detail: string }> = [];

function record(id: string, ok: boolean, detail = ""): void {
  results.push({ id, ok, detail });
  safeLog(`${ok ? "PASS" : "FAIL"}  12c  ${id}${detail ? ` — ${detail}` : ""}`);
}

async function main(): Promise<number> {
  const target = resolveStagingTarget({
    mutating: true,
    requireServiceRole: true,
    requireFixturePassword: true,
  });
  describeTarget(target, "supabase_12c_staging_e2e");

  const fixtures = await StagingFixtures.create(
    target,
    runNamespace(`${target.namespace}-12c`),
  );
  const service = fixtures.serviceClient();
  let cleanup: { ok: boolean; problems: string[] } = { ok: true, problems: [] };
  const startedAt = new Date().toISOString();
  const occurredAt = new Date().toISOString();

  try {
    const head = await fixtures.signIn("headA");
    const nurseA = await fixtures.signIn("nurseA");
    const nurseB = await fixtures.signIn("nurseB");
    const warehouse = await fixtures.signIn("warehouse");
    const deviceHead = await fixtures.registerDevice(head, "12c-head");
    const deviceA = await fixtures.registerDevice(nurseA, "12c-a");
    const deviceA2 = await fixtures.registerDevice(nurseA, "12c-a2");
    const deviceB = await fixtures.registerDevice(nurseB, "12c-b");
    const deviceWarehouse = await fixtures.registerDevice(warehouse, "12c-wh");

    // -----------------------------------------------------------------------
    // A cursor of zero reaches the whole baseline
    // -----------------------------------------------------------------------
    const baseline = await drain(nurseA, deviceA, 0, 200);
    record("a_cursor_from_zero_drains_without_looping", baseline.pages < 500,
      `${baseline.pages} page(s), ${baseline.changes.length} change(s)`);
    const seen = new Set(baseline.changes.map((change) => change.entity_id));
    record("the_baseline_includes_this_runs_own_master_data",
      seen.has(fixtures.set.itemPlain) && seen.has(fixtures.set.categoryId),
      `item=${seen.has(fixtures.set.itemPlain)} category=${
        seen.has(fixtures.set.categoryId)
      }`);
    record("cursor_advances_monotonically",
      baseline.changes.every((change, index) =>
        index === 0 || change.change_seq > baseline.changes[index - 1].change_seq
      ));
    record("every_upsert_carries_a_payload",
      baseline.changes.every((change) =>
        change.operation === "tombstone" || change.payload !== null
      ));
    record("no_change_carries_a_field_version_map_for_the_ledger",
      baseline.changes.filter((change) =>
        change.entity_type === "stock_movement"
      ).every((change) => Object.keys(change.field_versions).length === 0));

    // -----------------------------------------------------------------------
    // Deterministic pagination: page size must not change what is seen
    // -----------------------------------------------------------------------
    const byOne = await drain(nurseA, deviceA, 0, 1);
    const bulkSeq = baseline.changes.map((change) => change.change_seq);
    const pagedSeq = byOne.changes.map((change) => change.change_seq);
    record("paging_one_at_a_time_sees_every_bulk_entry",
      bulkSeq.every((seq) => pagedSeq.includes(seq)),
      `${pagedSeq.length} vs ${bulkSeq.length}`);
    record("paging_one_at_a_time_repeats_nothing",
      new Set(pagedSeq).size === pagedSeq.length);
    record("both_page_sizes_land_on_the_same_cursor",
      byOne.cursor >= baseline.cursor,
      `${byOne.cursor} vs ${baseline.cursor}`);

    const oddSize = await drain(nurseA, deviceA, 0, 7);
    record("an_odd_page_size_neither_skips_nor_repeats",
      new Set(oddSize.changes.map((c) => c.change_seq)).size ===
        oddSize.changes.length &&
        bulkSeq.every((seq) =>
          oddSize.changes.some((change) => change.change_seq === seq)
        ));

    // A second device for the same actor is a second, independent cursor.
    const secondDevice = await drain(nurseA, deviceA2, 0, 200);
    record("a_second_device_has_its_own_cursor_and_sees_the_same_scope",
      new Set(secondDevice.changes.map((c) => c.entity_id)).size === seen.size,
      `${secondDevice.changes.length} vs ${baseline.changes.length}`);

    // -----------------------------------------------------------------------
    // Branch and role isolation, over the real feed
    // -----------------------------------------------------------------------
    const feedB = await drain(nurseB, deviceB, 0, 200);
    const idsB = new Set(feedB.changes.map((change) => change.entity_id));
    record("branch_a_never_sees_branch_bs_room", !seen.has(fixtures.set.roomB));
    record("branch_b_never_sees_branch_as_room", !idsB.has(fixtures.set.roomA));
    record("branch_a_never_sees_branch_bs_store",
      !seen.has(fixtures.set.locationBranchB));
    record("branch_b_never_sees_branch_as_store",
      !idsB.has(fixtures.set.locationBranchA));

    const firstPageA = await pull(nurseA, deviceA, 0, 1);
    const firstPageB = await pull(nurseB, deviceB, 0, 1);
    record("scope_fingerprints_differ_between_actors",
      firstPageA.scope_fingerprint !== firstPageB.scope_fingerprint);

    const crossDevice = await nurseA.rpc("pull_sync_changes", {
      after_cursor: 0, batch_limit: 10, device_id: deviceB,
    });
    record("another_actors_device_is_refused", crossDevice.error !== null,
      String(crossDevice.error?.message ?? "ACCEPTED"));

    const inactive = await fixtures.signIn("inactiveA");
    const inactivePull = await inactive.rpc("pull_sync_changes", {
      after_cursor: 0, batch_limit: 10, device_id: deviceA,
    });
    record("a_deactivated_actor_receives_no_feed", inactivePull.error !== null,
      String(inactivePull.error?.message ?? "ACCEPTED"));

    // -----------------------------------------------------------------------
    // Idempotent re-apply
    // -----------------------------------------------------------------------
    const repeat = await drain(nurseA, deviceA, 0, 200);
    record("draining_twice_returns_the_same_sequence",
      JSON.stringify(repeat.changes.map((c) => c.change_seq)) ===
        JSON.stringify(bulkSeq));
    const atHead = await pull(nurseA, deviceA, baseline.cursor, 200);
    record("a_cursor_at_the_head_returns_an_empty_page",
      atHead.changes.length === 0 && !atHead.has_more,
      `${atHead.changes.length} change(s)`);

    const badCursor = await nurseA.rpc("pull_sync_changes", {
      after_cursor: baseline.cursor + 1_000_000, batch_limit: 10,
      device_id: deviceA,
    });
    record("a_cursor_beyond_the_server_is_refused", badCursor.error !== null,
      String(badCursor.error?.message ?? "ACCEPTED"));

    // -----------------------------------------------------------------------
    // Offline catch-up
    // -----------------------------------------------------------------------
    const offlineCursor = baseline.cursor;
    for (let index = 0; index < 5; index += 1) {
      const changed = await service.from("items").update({
        name: `${fixtures.set.namespace} offline-${index}`,
        updated_at: new Date().toISOString(),
      }).eq("id", fixtures.set.itemPlain);
      assertCondition(!changed.error, `offline_edit_failed:${redact(changed.error)}`);
    }
    const caughtUp = await drain(nurseA, deviceA, offlineCursor, 200);
    record("catch_up_from_an_old_cursor_returns_the_missed_changes",
      caughtUp.changes.length >= 5, `${caughtUp.changes.length} change(s)`);
    record("catch_up_advances_the_cursor", caughtUp.cursor > offlineCursor,
      `${offlineCursor} -> ${caughtUp.cursor}`);
    const latest = caughtUp.changes.filter((change) =>
      change.entity_id === fixtures.set.itemPlain && change.payload
    ).at(-1);
    record("the_last_applied_state_is_the_servers_current_state",
      String(latest?.payload?.name ?? "").endsWith("offline-4"),
      String(latest?.payload?.name ?? ""));

    // Applying an old page again must reach the same end state, because the
    // payload is always read as of now rather than as of the entry.
    const replayed = await drain(nurseA, deviceA, offlineCursor, 1);
    const replayLatest = replayed.changes.filter((change) =>
      change.entity_id === fixtures.set.itemPlain && change.payload
    ).at(-1);
    record("replaying_an_old_page_converges_on_the_same_state",
      String(replayLatest?.payload?.name ?? "") ===
        String(latest?.payload?.name ?? ""));

    // -----------------------------------------------------------------------
    // Field-level reconciliation signal
    // -----------------------------------------------------------------------
    const withVersions = caughtUp.changes.find((change) =>
      change.entity_id === fixtures.set.itemPlain && change.payload
    );
    const versions = withVersions?.field_versions ?? {};
    record("a_changed_field_version_outruns_an_untouched_one",
      Number(versions.name ?? 0) > Number(versions.unit ?? 0),
      `name=${versions.name} unit=${versions.unit}`);
    record("field_versions_are_the_entity_version_not_a_counter",
      Number(versions.name ?? 0) === Number(withVersions?.server_version ?? -1),
      `${versions.name} vs ${withVersions?.server_version}`);

    // -----------------------------------------------------------------------
    // Tombstone
    // -----------------------------------------------------------------------
    const beforeTombstone = caughtUp.cursor;
    const tombstoned = await service.from("item_categories").update({
      deleted_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", fixtures.set.categoryId);
    assertCondition(!tombstoned.error, `tombstone_failed:${redact(tombstoned.error)}`);
    const afterTombstone = await drain(nurseA, deviceA, beforeTombstone, 200);
    const tombstoneEntry = afterTombstone.changes.find((change) =>
      change.entity_id === fixtures.set.categoryId
    );
    record("a_soft_delete_arrives_as_a_tombstone",
      tombstoneEntry?.operation === "tombstone",
      String(tombstoneEntry?.operation ?? "missing"));
    record("a_tombstone_carries_no_payload",
      tombstoneEntry !== undefined && tombstoneEntry.payload === null);
    record("a_tombstone_carries_the_server_version_that_retired_it",
      Number(tombstoneEntry?.server_version ?? 0) > 0);

    // -----------------------------------------------------------------------
    // Final conflict recovery: the server wins outright
    // -----------------------------------------------------------------------
    const opnameId = crypto.randomUUID();
    const opnameFixture = await service.from("stock_opnames").insert({
      id: opnameId, created_at: occurredAt, updated_at: occurredAt,
      sync_status: "synced", doc_number: `SO-12C-${fixtures.set.token}`,
      branch_id: fixtures.set.branchA, room_id: fixtures.set.roomA,
      period_year: 2026, period_week: 32,
      counted_by: fixtures.set.actors.nurseA.domainUserId,
      status: "submitted", submitted_at: occurredAt,
    });
    assertCondition(!opnameFixture.error,
      `opname_failed:${redact(opnameFixture.error)}`);

    const prId = crypto.randomUUID();
    const prLineId = crypto.randomUUID();
    const prEnvelope = await envelope({
      request_id: crypto.randomUUID(), device_id: deviceHead,
      operation: "submit_purchase_request",
      aggregate_type: "purchase_request", aggregate_id: prId,
      payload_version: 1, base_server_version: 0, occurred_at_utc: occurredAt,
      payload: {
        id: prId, created_at: occurredAt, branch_id: fixtures.set.branchA,
        requested_by: fixtures.set.actors.headA.domainUserId,
        status: "submitted",
        lines: [{
          id: prLineId, item_id: fixtures.set.itemPlain,
          suggested_qty: 1000, requested_qty: 1000,
        }],
        opname_links: [{ id: crypto.randomUUID(), opname_id: opnameId }],
      },
    });
    const submitted = await push(head, prEnvelope, "12c_submit_pr");
    record("a_document_can_still_be_pushed_after_the_rollout",
      submitted.outcome === "accepted", submitted.outcome);

    const headCursorBefore = (await drain(head, deviceHead, 0, 200)).cursor;

    // The warehouse moves the document to a final state. A stale client pushing
    // against the pre-final version must lose, and the feed must carry the
    // final state the server settled on — including the document number, which
    // the client never gets to choose.
    const finalise = await service.from("purchase_requests")
      .update({ status: "processing", updated_at: new Date().toISOString() })
      .eq("id", prId);
    assertCondition(!finalise.error, `finalise_failed:${redact(finalise.error)}`);

    const stale = await envelope({
      request_id: crypto.randomUUID(), device_id: deviceHead,
      operation: "submit_purchase_request",
      aggregate_type: "purchase_request", aggregate_id: prId,
      payload_version: 1, base_server_version: 1, occurred_at_utc: occurredAt,
      payload: {
        id: prId, created_at: occurredAt, branch_id: fixtures.set.branchA,
        requested_by: fixtures.set.actors.headA.domainUserId,
        status: "submitted",
        lines: [{
          id: prLineId, item_id: fixtures.set.itemPlain,
          suggested_qty: 9999, requested_qty: 9999,
        }],
        opname_links: [],
      },
    });
    const staleResult = await head.rpc("push_sync_operation", {
      operation_envelope: stale,
    });
    const staleLost = staleResult.error !== null ||
      staleResult.data?.outcome === "conflict";
    record("a_stale_push_against_a_moved_document_loses", staleLost,
      String(staleResult.error?.message ?? staleResult.data?.outcome));

    const afterFinal = await drain(head, deviceHead, headCursorBefore, 200);
    const finalEntry = afterFinal.changes.filter((change) =>
      change.entity_id === prId && change.payload
    ).at(-1);
    record("the_feed_carries_the_servers_final_state",
      String(finalEntry?.payload?.status) === "processing",
      String(finalEntry?.payload?.status ?? "missing"));
    record("the_final_document_number_is_the_servers",
      typeof finalEntry?.payload?.doc_number === "string" &&
        String(finalEntry.payload.doc_number).length > 0,
      String(finalEntry?.payload?.doc_number ?? ""));
    record("the_refused_push_never_reached_the_document",
      Number((finalEntry?.payload?.lines as Array<Record<string, unknown>>)
        ?.[0]?.requested_qty) === 1000,
      String((finalEntry?.payload?.lines as Array<Record<string, unknown>>)
        ?.[0]?.requested_qty));

    // The warehouse actor is a different scope and must reach the same document
    // through its own cursor rather than through the branch head's.
    const warehouseFeed = await drain(warehouse, deviceWarehouse, 0, 200);
    record("a_warehouse_actor_reaches_the_same_document_via_its_own_cursor",
      warehouseFeed.changes.some((change) => change.entity_id === prId));
    record("the_warehouse_actor_does_not_inherit_the_branch_heads_cursor",
      warehouseFeed.cursor !== headCursorBefore ||
        warehouseFeed.changes.length !== afterFinal.changes.length);

    // -----------------------------------------------------------------------
    // The journal itself is closed to clients
    // -----------------------------------------------------------------------
    const journalWrite = await nurseA.from("sync_change_journal").insert({
      entity_type: "room", entity_id: fixtures.set.roomA,
      operation: "upsert", server_version: 1,
    });
    record("a_client_cannot_write_the_journal", journalWrite.error !== null);
    const journalDelete = await nurseA.from("sync_change_journal").delete()
      .eq("entity_id", fixtures.set.roomA);
    record("a_client_cannot_delete_from_the_journal",
      journalDelete.error !== null || (journalDelete.count ?? 0) === 0);
    const helperProbe = await nurseA.rpc("pull_entity_visible", {
      requested_entity_type: "room", requested_entity_id: fixtures.set.roomB,
    });
    record("the_visibility_oracle_is_unreachable_from_a_session",
      helperProbe.error !== null);
  } catch (error) {
    record("harness_completed", false, redact(error));
  } finally {
    cleanup = await fixtures.cleanup();
  }
  record("fixtures_cleaned_up", cleanup.ok, cleanup.problems.join(" | "));

  const failed = results.filter((entry) => !entry.ok);
  const report = {
    ok: failed.length === 0,
    tool: "supabase_12c_staging_e2e",
    environment: "staging",
    project_ref: target.maskedRef,
    host: target.host,
    branch: target.branch,
    commit: target.commit,
    namespace: fixtures.set.namespace,
    started_at_utc: startedAt,
    finished_at_utc: new Date().toISOString(),
    checks_total: results.length,
    checks_failed: failed.length,
    failed_checks: failed.map((entry) => entry.id),
    results,
  };
  const path = await writeArtifact(
    `12c-staging-e2e-${utcStamp()}`, "json", JSON.stringify(report, null, 2),
  );
  safeLog(`report      = ${path}`);
  safeLog(
    `result      = ${report.ok ? "PASS" : "FAIL"} (${
      results.length - failed.length
    }/${results.length})`,
  );
  return report.ok ? 0 : 1;
}

try {
  Deno.exit(await main());
} catch (error) {
  safeError(`12c_staging_e2e_failed: ${redact(error)}`);
  Deno.exit(2);
}
