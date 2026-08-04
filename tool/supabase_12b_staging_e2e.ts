// Milestone 12B push path, re-verified against staging after the 12C rollout.
//
// The question this answers is narrow: did adding the change journal, its 26
// triggers and the backfill break the write path? Every assertion is a 12B
// invariant, not a 12C one — idempotency, canonical hash, RBAC, atomicity, the
// append-only ledger and non-negative balances.
//
// It is not the local runner pointed at a remote host. The local runner assumes
// `supabase db reset` and the deterministic dev seed; this one creates its own
// namespaced fixtures on a project that already has data in it, and retires
// them afterwards without touching anything else.

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
import { envelope, push, sha256Text } from "./staging_sync_envelope.ts";

const results: Array<{ id: string; ok: boolean; detail: string }> = [];

function record(id: string, ok: boolean, detail = ""): void {
  results.push({ id, ok, detail });
  safeLog(`${ok ? "PASS" : "FAIL"}  12b  ${id}${detail ? ` — ${detail}` : ""}`);
}

async function expectRefusal(
  attempt: () => Promise<unknown>,
  id: string,
  detail = "",
): Promise<void> {
  try {
    await attempt();
    record(id, false, `${detail} ACCEPTED`.trim());
  } catch (error) {
    record(id, true, detail || String((error as { message?: string }).message ?? ""));
  }
}

async function main(): Promise<number> {
  const target = resolveStagingTarget({
    mutating: true,
    requireServiceRole: true,
    requireFixturePassword: true,
  });
  describeTarget(target, "supabase_12b_staging_e2e");

  const fixtures = await StagingFixtures.create(
    target,
    runNamespace(`${target.namespace}-12b`),
  );
  const service = fixtures.serviceClient();
  let cleanup: { ok: boolean; problems: string[] } = { ok: true, problems: [] };
  const startedAt = new Date().toISOString();
  const occurredAt = new Date().toISOString();

  try {
    const head = await fixtures.signIn("headA");
    const warehouse = await fixtures.signIn("warehouse");
    const nurse = await fixtures.signIn("nurseA");
    const headDevice = await fixtures.registerDevice(head, "12b-head");
    const warehouseDevice = await fixtures.registerDevice(warehouse, "12b-wh");
    const nurseDevice = await fixtures.registerDevice(nurse, "12b-nurse");
    record("devices_registered", true);

    // Stock to ship. Seeded through the operator client because it stands in
    // for warehouse inventory that predates this run.
    const openingBalance = crypto.randomUUID();
    const seeded = await service.from("stock_balances").insert({
      id: openingBalance,
      created_at: occurredAt, updated_at: occurredAt, sync_status: "synced",
      location_id: fixtures.set.locationWarehouse,
      item_id: fixtures.set.itemPlain, batch_id: null, qty_on_hand: 5000,
    });
    assertCondition(!seeded.error, `opening_balance_failed:${redact(seeded.error)}`);

    // -----------------------------------------------------------------------
    // Idempotency
    // -----------------------------------------------------------------------
    const categoryId = crypto.randomUUID();
    const masterRequest = crypto.randomUUID();
    const masterPayload = {
      id: categoryId,
      created_at: occurredAt,
      updated_at: occurredAt,
      sync_status: "pending",
      name: `${fixtures.set.namespace} pushed`,
    };
    const master = await envelope({
      request_id: masterRequest,
      device_id: headDevice,
      operation: "upsert_master",
      aggregate_type: "category",
      aggregate_id: categoryId,
      payload_version: 1,
      base_server_version: 0,
      occurred_at_utc: occurredAt,
      payload: masterPayload,
    });

    const concurrent = await Promise.all([
      head.rpc("push_sync_operation", { operation_envelope: master }),
      head.rpc("push_sync_operation", { operation_envelope: master }),
    ]);
    const outcomes = concurrent.map((entry) => entry.data?.outcome).sort().join(",");
    record("concurrent_duplicate_is_accepted_exactly_once",
      outcomes === "accepted,replayed", outcomes);

    const replay = await push(head, master, "master_replay");
    record("replaying_a_request_id_is_a_replay", replay.outcome === "replayed",
      replay.outcome);

    // A different payload under the same request id is a client bug, not a
    // retry, and the server has to say so rather than pick a winner.
    const mutated: Record<string, unknown> = {
      ...master,
      payload: { ...masterPayload, name: `${fixtures.set.namespace} mutated` },
    };
    delete mutated.payload_hash;
    mutated.payload_hash = await sha256Text(mutated);
    const reused = await head.rpc("push_sync_operation", {
      operation_envelope: mutated,
    });
    record("reusing_a_request_id_for_a_different_payload_is_refused",
      reused.error?.message === "sync_request_id_reused",
      String(reused.error?.message ?? "ACCEPTED"));

    // A tampered hash must not be accepted even though every other field is
    // well formed.
    const tampered = { ...master, request_id: crypto.randomUUID(), payload_hash: "0".repeat(64) };
    const tamperResult = await head.rpc("push_sync_operation", {
      operation_envelope: tampered,
    });
    record("a_payload_hash_mismatch_is_refused", tamperResult.error !== null,
      String(tamperResult.error?.message ?? "ACCEPTED"));

    // -----------------------------------------------------------------------
    // RBAC and branch isolation, proven against a real second branch
    // -----------------------------------------------------------------------
    await expectRefusal(
      () => push(nurse, {
        ...master,
        request_id: crypto.randomUUID(),
        device_id: nurseDevice,
      }, "nurse_master"),
      "a_nurse_cannot_push_master_data",
    );

    const headB = await fixtures.signIn("headB");
    const headBDevice = await fixtures.registerDevice(headB, "12b-headb");

    // -----------------------------------------------------------------------
    // The transactional workflow: PR -> DO -> GR
    // -----------------------------------------------------------------------
    const opnameId = crypto.randomUUID();
    const opname = await service.from("stock_opnames").insert({
      id: opnameId, created_at: occurredAt, updated_at: occurredAt,
      sync_status: "synced",
      doc_number: `SO-${fixtures.set.token}`,
      branch_id: fixtures.set.branchA, room_id: fixtures.set.roomA,
      period_year: 2026, period_week: 31,
      counted_by: fixtures.set.actors.nurseA.domainUserId,
      status: "submitted", submitted_at: occurredAt,
    });
    assertCondition(!opname.error, `opname_fixture_failed:${redact(opname.error)}`);

    const prId = crypto.randomUUID();
    const prLineId = crypto.randomUUID();
    const prPayload = {
      id: prId,
      created_at: occurredAt,
      branch_id: fixtures.set.branchA,
      requested_by: fixtures.set.actors.headA.domainUserId,
      status: "submitted",
      lines: [{
        id: prLineId,
        item_id: fixtures.set.itemPlain,
        suggested_qty: 1000,
        requested_qty: 1000,
      }],
      opname_links: [{ id: crypto.randomUUID(), opname_id: opnameId }],
    };

    // Two different request ids for the same aggregate, pushed together: the
    // uniqueness index on an open PR per branch has to make exactly one win.
    const raceEnvelopes = await Promise.all(
      [crypto.randomUUID(), crypto.randomUUID()].map((requestId) =>
        envelope({
          request_id: requestId, device_id: headDevice,
          operation: "submit_purchase_request",
          aggregate_type: "purchase_request", aggregate_id: prId,
          payload_version: 1, base_server_version: 0,
          occurred_at_utc: occurredAt, payload: prPayload,
        })
      ),
    );
    const raced = await Promise.all(raceEnvelopes.map((entry) =>
      head.rpc("push_sync_operation", { operation_envelope: entry })
    ));
    const accepted = raced.filter((entry) => entry.data?.outcome === "accepted");
    record("a_concurrent_duplicate_aggregate_is_serialised",
      accepted.length === 1,
      raced.map((entry) => entry.data?.outcome ?? entry.error?.message).join(","));

    const prRows = await service.from("purchase_requests").select("id, status, doc_number")
      .eq("id", prId);
    record("the_purchase_request_exists_exactly_once",
      (prRows.data ?? []).length === 1);
    record("the_server_assigned_the_document_number",
      typeof prRows.data?.[0]?.doc_number === "string" &&
        prRows.data[0].doc_number.length > 0,
      String(prRows.data?.[0]?.doc_number ?? ""));

    // A branch B head must not be able to act on branch A's request.
    await expectRefusal(
      () => push(headB, {
        ...raceEnvelopes[0],
        request_id: crypto.randomUUID(),
        device_id: headBDevice,
      }, "cross_branch_pr"),
      "a_branch_b_head_cannot_push_a_branch_a_request",
    );

    const deliveryId = crypto.randomUUID();
    const deliveryLineId = crypto.randomUUID();
    const shipmentMovementId = crypto.randomUUID();
    const deliveryEnvelope = await envelope({
      request_id: crypto.randomUUID(), device_id: warehouseDevice,
      operation: "ship_delivery_order", aggregate_type: "delivery_order",
      aggregate_id: deliveryId, payload_version: 1, base_server_version: 0,
      occurred_at_utc: occurredAt,
      payload: {
        id: deliveryId, created_at: occurredAt, pr_id: prId, status: "shipped",
        lines: [{
          id: deliveryLineId, pr_line_id: prLineId,
          item_id: fixtures.set.itemPlain, shipped_qty: 1000,
        }],
        movements: [{
          id: shipmentMovementId, created_at: occurredAt,
          item_id: fixtures.set.itemPlain,
          from_location_id: fixtures.set.locationWarehouse,
          qty: 1000, movement_type: "shipment",
          ref_doc_type: "DO", ref_doc_id: deliveryId,
        }],
      },
    });
    const delivery = await push(warehouse, deliveryEnvelope, "ship_do");
    record("the_delivery_order_ships", delivery.outcome === "accepted",
      delivery.outcome);
    const deliveryReplay = await push(warehouse, deliveryEnvelope, "ship_do_replay");
    record("replaying_the_shipment_is_a_replay",
      deliveryReplay.outcome === "replayed", deliveryReplay.outcome);

    const shipmentMovements = await service.from("stock_movements")
      .select("id").eq("ref_doc_id", deliveryId);
    record("the_replay_created_no_second_movement",
      (shipmentMovements.data ?? []).length === 1,
      `${(shipmentMovements.data ?? []).length} movement(s)`);

    const receiptId = crypto.randomUUID();
    const receiptEnvelope = await envelope({
      request_id: crypto.randomUUID(), device_id: headDevice,
      operation: "post_good_receipt", aggregate_type: "good_receipt",
      aggregate_id: receiptId, payload_version: 1, base_server_version: 0,
      occurred_at_utc: occurredAt,
      payload: {
        id: receiptId, created_at: occurredAt, do_id: deliveryId,
        status: "posted",
        lines: [{
          id: crypto.randomUUID(), do_line_id: deliveryLineId,
          item_id: fixtures.set.itemPlain, shipped_qty: 1000,
          received_qty: 1000, line_status: "checked",
        }],
        movements: [{
          id: crypto.randomUUID(), created_at: occurredAt,
          item_id: fixtures.set.itemPlain,
          to_location_id: fixtures.set.locationBranchA,
          qty: 1000, movement_type: "good_receipt",
          ref_doc_type: "GR", ref_doc_id: receiptId,
        }],
      },
    });
    const receipt = await push(head, receiptEnvelope, "post_gr");
    record("the_good_receipt_posts", receipt.outcome === "accepted",
      receipt.outcome);

    // -----------------------------------------------------------------------
    // Invariants that must survive the 12C triggers
    // -----------------------------------------------------------------------
    const balances = await service.from("stock_balances")
      .select("id, location_id, item_id, qty_on_hand")
      .in("location_id", [
        fixtures.set.locationWarehouse, fixtures.set.locationBranchA,
      ]);
    const warehouseBalance = (balances.data ?? []).find((row) =>
      row.location_id === fixtures.set.locationWarehouse
    );
    const branchBalance = (balances.data ?? []).find((row) =>
      row.location_id === fixtures.set.locationBranchA
    );
    record("the_shipment_left_the_warehouse",
      Number(warehouseBalance?.qty_on_hand) === 4000,
      `${warehouseBalance?.qty_on_hand}`);
    record("the_receipt_arrived_at_the_branch",
      Number(branchBalance?.qty_on_hand) === 1000,
      `${branchBalance?.qty_on_hand}`);
    record("no_balance_is_negative",
      (balances.data ?? []).every((row) => Number(row.qty_on_hand) >= 0));

    const allMovements = await service.from("stock_movements")
      .select("id, item_id, qty, movement_type, ref_doc_id")
      .eq("item_id", fixtures.set.itemPlain);
    const movementIds = (allMovements.data ?? []).map((row) => row.id);
    record("no_duplicate_movement_uuid",
      new Set(movementIds).size === movementIds.length,
      `${movementIds.length} movement(s)`);
    record("the_shipment_kept_the_client_chosen_uuid",
      movementIds.includes(shipmentMovementId));

    // The ledger is append-only at the server, whatever a client asks for.
    const ledgerUpdate = await service.from("stock_movements")
      .update({ qty: 1 }).eq("id", shipmentMovementId);
    record("the_ledger_refuses_an_update", ledgerUpdate.error !== null,
      String(ledgerUpdate.error?.message ?? "ACCEPTED"));
    const ledgerDelete = await service.from("stock_movements")
      .delete().eq("id", shipmentMovementId);
    record("the_ledger_refuses_a_delete", ledgerDelete.error !== null,
      String(ledgerDelete.error?.message ?? "ACCEPTED"));

    // Over-shipping must be refused rather than driving a balance negative.
    const overshipId = crypto.randomUUID();
    const overship = await envelope({
      request_id: crypto.randomUUID(), device_id: warehouseDevice,
      operation: "ship_delivery_order", aggregate_type: "delivery_order",
      aggregate_id: overshipId, payload_version: 1, base_server_version: 0,
      occurred_at_utc: occurredAt,
      payload: {
        id: overshipId, created_at: occurredAt, pr_id: prId, status: "shipped",
        lines: [{
          id: crypto.randomUUID(), pr_line_id: prLineId,
          item_id: fixtures.set.itemPlain, shipped_qty: 1_000_000,
        }],
        movements: [{
          id: crypto.randomUUID(), created_at: occurredAt,
          item_id: fixtures.set.itemPlain,
          from_location_id: fixtures.set.locationWarehouse,
          qty: 1_000_000, movement_type: "shipment",
          ref_doc_type: "DO", ref_doc_id: overshipId,
        }],
      },
    });
    await expectRefusal(
      () => push(warehouse, overship, "overship"),
      "shipping_more_than_is_on_hand_is_refused",
    );
    const afterOvership = await service.from("stock_balances")
      .select("qty_on_hand").eq("id", warehouseBalance?.id ?? openingBalance)
      .maybeSingle();
    record("the_refused_shipment_left_the_balance_alone",
      Number(afterOvership.data?.qty_on_hand) === 4000,
      `${afterOvership.data?.qty_on_hand}`);

    // -----------------------------------------------------------------------
    // The write path still feeds the journal
    // -----------------------------------------------------------------------
    const journalled = await service.from("sync_change_journal")
      .select("entity_type, entity_id")
      .in("entity_id", [prId, deliveryId, receiptId]);
    record("every_pushed_aggregate_reached_the_journal",
      new Set((journalled.data ?? []).map((row) => row.entity_id)).size === 3,
      `${new Set((journalled.data ?? []).map((row) => row.entity_id)).size}/3`);
  } catch (error) {
    record("harness_completed", false, redact(error));
  } finally {
    cleanup = await fixtures.cleanup();
  }
  record("fixtures_cleaned_up", cleanup.ok, cleanup.problems.join(" | "));

  const failed = results.filter((entry) => !entry.ok);
  const report = {
    ok: failed.length === 0,
    tool: "supabase_12b_staging_e2e",
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
    `12b-staging-e2e-${utcStamp()}`, "json", JSON.stringify(report, null, 2),
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
  safeError(`12b_staging_e2e_failed: ${redact(error)}`);
  Deno.exit(2);
}
