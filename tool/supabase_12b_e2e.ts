import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL");
const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!url || !anonKey || !serviceKey) {
  throw new Error("local_supabase_env_missing");
}

const password = "LocalOnly!12345";
const service = createClient(url, serviceKey, {
  auth: { persistSession: false },
});

async function signedIn(email: string): Promise<SupabaseClient> {
  const client = createClient(url!, anonKey!, {
    auth: { persistSession: false },
  });
  const result = await client.auth.signInWithPassword({ email, password });
  if (result.error) throw result.error;
  return client;
}

function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0)
        .map(([key, entry]) => [key, canonical(entry)]),
    );
  }
  return value;
}

async function sha256Text(value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify(canonical(value)));
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return Array.from(digest).map((part) => part.toString(16).padStart(2, "0"))
    .join("");
}

async function envelope(
  input: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  return { ...input, payload_hash: await sha256Text(input) };
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(`e2e_assertion_failed:${message}`);
}

const admin = await signedIn("admin.local@example.test");
const branchHead = await signedIn("branchhead.local@example.test");
const device = crypto.randomUUID();
const registered = await admin.rpc("register_sync_device", {
  device_id: device,
  requested_app_install_id: crypto.randomUUID(),
  requested_display_label: "12B E2E",
});
if (registered.error) throw registered.error;

const categoryId = crypto.randomUUID();
const masterRequest = crypto.randomUUID();
const occurredAt = new Date().toISOString();
const masterPayload = {
  id: categoryId,
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "pending",
  name: `E2E-${categoryId.slice(0, 8)}`,
};
const master = await envelope({
  request_id: masterRequest,
  device_id: device,
  operation: "upsert_master",
  aggregate_type: "category",
  aggregate_id: categoryId,
  payload_version: 1,
  base_server_version: 0,
  occurred_at_utc: occurredAt,
  payload: masterPayload,
});
const concurrentDuplicate = await Promise.all([
  admin.rpc("push_sync_operation", { operation_envelope: master }),
  admin.rpc("push_sync_operation", { operation_envelope: master }),
]);
for (const result of concurrentDuplicate) if (result.error) throw result.error;
assert(
  concurrentDuplicate.map((result) => result.data.outcome).sort().join(",") ===
    "accepted,replayed",
  "concurrent duplicate request is accepted exactly once",
);
const replay = await admin.rpc("push_sync_operation", {
  operation_envelope: master,
});
if (replay.error) throw replay.error;
assert(replay.data.outcome === "replayed", "same request replayed");

const changedMaster = await envelope({
  ...master,
  payload: { ...masterPayload, name: "different" },
  payload_hash: undefined,
});
delete changedMaster.payload_hash;
changedMaster.payload_hash = await sha256Text(changedMaster);
const reused = await admin.rpc("push_sync_operation", {
  operation_envelope: changedMaster,
});
assert(
  reused.error?.message === "sync_request_id_reused",
  "reused key rejected",
);

const headDevice = crypto.randomUUID();
const headRegistration = await branchHead.rpc("register_sync_device", {
  device_id: headDevice,
  requested_app_install_id: crypto.randomUUID(),
  requested_display_label: "12B concurrent E2E",
});
if (headRegistration.error) throw headRegistration.error;

const opnameId = crypto.randomUUID();
const fixture = await service.from("stock_opnames").insert({
  id: opnameId,
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  doc_number: `SO-E2E-${opnameId.slice(0, 8)}`,
  branch_id: "20000000-0000-0000-0000-000000000001",
  room_id: "21000000-0000-0000-0000-000000000001",
  period_year: 2026,
  period_week: 31,
  counted_by: "30000000-0000-0000-0000-000000000001",
  status: "submitted",
  submitted_at: occurredAt,
});
if (fixture.error) throw fixture.error;

const prId = crypto.randomUUID();
const prPayload = {
  id: prId,
  created_at: occurredAt,
  branch_id: "20000000-0000-0000-0000-000000000001",
  requested_by: "30000000-0000-0000-0000-000000000002",
  status: "submitted",
  lines: [{
    id: crypto.randomUUID(),
    item_id: "41000000-0000-0000-0000-000000000001",
    suggested_qty: 1000,
    requested_qty: 1000,
  }, {
    id: crypto.randomUUID(),
    item_id: "41000000-0000-0000-0000-000000000002",
    suggested_qty: 1000,
    requested_qty: 1000,
  }],
  opname_links: [{ id: crypto.randomUUID(), opname_id: opnameId }],
};
const concurrentInputs = await Promise.all(
  [crypto.randomUUID(), crypto.randomUUID()].map((requestId) =>
    envelope({
      request_id: requestId,
      device_id: headDevice,
      operation: "submit_purchase_request",
      aggregate_type: "purchase_request",
      aggregate_id: prId,
      payload_version: 1,
      base_server_version: 0,
      occurred_at_utc: occurredAt,
      payload: prPayload,
    })
  ),
);
const concurrent = await Promise.all(
  concurrentInputs.map((operationEnvelope) =>
    branchHead.rpc("push_sync_operation", {
      operation_envelope: operationEnvelope,
    })
  ),
);
for (const result of concurrent) if (result.error) throw result.error;
assert(
  concurrent.map((result) => result.data.outcome).sort().join(",") ===
    "accepted,replayed",
  "concurrent equivalent final operation is accepted once",
);
assert(
  new Set(concurrent.map((result) => result.data.final_document_number))
    .size === 1,
  "concurrent replay returns one final number",
);

const warehouse = await signedIn("warehouse.local@example.test");
const warehouseDevice = crypto.randomUUID();
const warehouseRegistration = await warehouse.rpc("register_sync_device", {
  device_id: warehouseDevice,
  requested_app_install_id: crypto.randomUUID(),
  requested_display_label: "12B warehouse E2E",
});
if (warehouseRegistration.error) throw warehouseRegistration.error;
const processEnvelope = await envelope({
  request_id: crypto.randomUUID(),
  device_id: warehouseDevice,
  operation: "process_purchase_request",
  aggregate_type: "purchase_request",
  aggregate_id: prId,
  payload_version: 1,
  base_server_version: 0,
  occurred_at_utc: occurredAt,
  payload: { id: prId, status: "processing" },
});
const processed = await warehouse.rpc("push_sync_operation", {
  operation_envelope: processEnvelope,
});
if (processed.error) throw processed.error;
assert(processed.data.outcome === "accepted", "PR processed by warehouse");

const warehouseBalance = await service.from("stock_balances").insert([{
  id: crypto.randomUUID(),
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  location_id: "50000000-0000-0000-0000-000000000001",
  item_id: "41000000-0000-0000-0000-000000000001",
  qty_on_hand: 3000,
}, {
  id: crypto.randomUUID(),
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  location_id: "50000000-0000-0000-0000-000000000001",
  item_id: "41000000-0000-0000-0000-000000000002",
  batch_id: "42000000-0000-0000-0000-000000000001",
  qty_on_hand: 3000,
}]);
if (warehouseBalance.error) throw warehouseBalance.error;
const deliveryId = crypto.randomUUID();
const deliveryLineIds = [crypto.randomUUID(), crypto.randomUUID()];
const deliveryMovementIds = [crypto.randomUUID(), crypto.randomUUID()];
const deliveryPayload = {
  id: deliveryId,
  created_at: occurredAt,
  pr_id: prId,
  status: "shipped",
  lines: [{
    id: deliveryLineIds[0],
    pr_line_id: prPayload.lines[0].id,
    item_id: "41000000-0000-0000-0000-000000000001",
    shipped_qty: 1000,
  }, {
    id: deliveryLineIds[1],
    pr_line_id: prPayload.lines[1].id,
    item_id: "41000000-0000-0000-0000-000000000002",
    batch_id: "42000000-0000-0000-0000-000000000001",
    shipped_qty: 1000,
  }],
  movements: [{
    id: deliveryMovementIds[0],
    created_at: occurredAt,
    item_id: "41000000-0000-0000-0000-000000000001",
    from_location_id: "50000000-0000-0000-0000-000000000001",
    qty: 1000,
    movement_type: "shipment",
    ref_doc_type: "DO",
    ref_doc_id: deliveryId,
  }, {
    id: deliveryMovementIds[1],
    created_at: occurredAt,
    item_id: "41000000-0000-0000-0000-000000000002",
    batch_id: "42000000-0000-0000-0000-000000000001",
    from_location_id: "50000000-0000-0000-0000-000000000001",
    qty: 1000,
    movement_type: "shipment",
    ref_doc_type: "DO",
    ref_doc_id: deliveryId,
  }],
};
const deliveryEnvelope = await envelope({
  request_id: crypto.randomUUID(),
  device_id: warehouseDevice,
  operation: "ship_delivery_order",
  aggregate_type: "delivery_order",
  aggregate_id: deliveryId,
  payload_version: 1,
  base_server_version: 0,
  occurred_at_utc: occurredAt,
  payload: deliveryPayload,
});
const delivery = await warehouse.rpc("push_sync_operation", {
  operation_envelope: deliveryEnvelope,
});
if (delivery.error) throw delivery.error;
assert(delivery.data.outcome === "accepted", "delivery shipment accepted");
assert(
  /^DO-WH-[0-9]{8}-[0-9]{4}$/.test(delivery.data.final_document_number),
  "delivery receives final server number",
);
const deliveryReplay = await warehouse.rpc("push_sync_operation", {
  operation_envelope: deliveryEnvelope,
});
if (deliveryReplay.error) throw deliveryReplay.error;
assert(
  deliveryReplay.data.outcome === "replayed",
  "delivery replay is idempotent",
);
assert(
  deliveryReplay.data.final_document_number ===
    delivery.data.final_document_number,
  "delivery replay keeps final number",
);
const shipmentMovementRows = await service.from("stock_movements").select(
  "id",
  { count: "exact" },
)
  .in("id", deliveryMovementIds);
if (shipmentMovementRows.error) throw shipmentMovementRows.error;
assert(
  shipmentMovementRows.count === 2,
  "delivery reuses exact movement UUIDs once",
);

const receiptId = crypto.randomUUID();
const receiptCheckedLine = crypto.randomUUID();
const receiptRejectedLine = crypto.randomUUID();
const receiptMovementId = crypto.randomUUID();
const receiptPayload = {
  id: receiptId,
  created_at: occurredAt,
  do_id: deliveryId,
  status: "posted",
  lines: [{
    id: receiptCheckedLine,
    do_line_id: deliveryLineIds[0],
    item_id: "41000000-0000-0000-0000-000000000001",
    shipped_qty: 1000,
    received_qty: 1000,
    line_status: "checked",
  }, {
    id: receiptRejectedLine,
    do_line_id: deliveryLineIds[1],
    item_id: "41000000-0000-0000-0000-000000000002",
    batch_id: "42000000-0000-0000-0000-000000000001",
    shipped_qty: 1000,
    received_qty: 0,
    line_status: "rejected",
    reject_reason: "Rusak",
  }],
  movements: [{
    id: receiptMovementId,
    created_at: occurredAt,
    item_id: "41000000-0000-0000-0000-000000000001",
    to_location_id: "50000000-0000-0000-0000-000000000002",
    qty: 1000,
    movement_type: "good_receipt",
    ref_doc_type: "GR",
    ref_doc_id: receiptId,
  }],
};
const receiptEnvelope = await envelope({
  request_id: crypto.randomUUID(),
  device_id: headDevice,
  operation: "post_good_receipt",
  aggregate_type: "good_receipt",
  aggregate_id: receiptId,
  payload_version: 1,
  base_server_version: 0,
  occurred_at_utc: occurredAt,
  payload: receiptPayload,
});
const receipt = await branchHead.rpc("push_sync_operation", {
  operation_envelope: receiptEnvelope,
});
if (receipt.error) throw receipt.error;
assert(receipt.data.outcome === "accepted", "good receipt chain accepted");
const receiptMovement = await service.from("stock_movements").select("id")
  .eq("id", receiptMovementId).single();
if (receiptMovement.error) throw receiptMovement.error;

const returnId = crypto.randomUUID();
const returnLineId = crypto.randomUUID();
const shippedReturnEnvelope = await envelope({
  request_id: crypto.randomUUID(),
  device_id: headDevice,
  operation: "ship_goods_return",
  aggregate_type: "goods_return",
  aggregate_id: returnId,
  payload_version: 1,
  base_server_version: 0,
  occurred_at_utc: occurredAt,
  payload: {
    id: returnId,
    created_at: occurredAt,
    gr_id: receiptId,
    branch_id: "20000000-0000-0000-0000-000000000001",
    created_by: "30000000-0000-0000-0000-000000000002",
    status: "shipped",
    lines: [{
      id: returnLineId,
      gr_line_id: receiptRejectedLine,
      item_id: "41000000-0000-0000-0000-000000000002",
      batch_id: "42000000-0000-0000-0000-000000000001",
      qty: 1000,
      reject_reason_snapshot: "Rusak",
    }],
    movements: [],
  },
});
const shippedReturn = await branchHead.rpc("push_sync_operation", {
  operation_envelope: shippedReturnEnvelope,
});
if (shippedReturn.error) throw shippedReturn.error;
assert(shippedReturn.data.outcome === "accepted", "goods return shipped");
const returnMovementId = crypto.randomUUID();
const receivedReturnEnvelope = await envelope({
  request_id: crypto.randomUUID(),
  device_id: warehouseDevice,
  operation: "receive_goods_return",
  aggregate_type: "goods_return",
  aggregate_id: returnId,
  payload_version: 1,
  base_server_version: 0,
  occurred_at_utc: occurredAt,
  payload: {
    id: returnId,
    status: "received",
    movements: [{
      id: returnMovementId,
      created_at: occurredAt,
      item_id: "41000000-0000-0000-0000-000000000002",
      batch_id: "42000000-0000-0000-0000-000000000001",
      to_location_id: "50000000-0000-0000-0000-000000000001",
      qty: 1000,
      movement_type: "return",
      ref_doc_type: "RET",
      ref_doc_id: returnId,
      note: "Rusak",
    }],
  },
});
const receivedReturn = await warehouse.rpc("push_sync_operation", {
  operation_envelope: receivedReturnEnvelope,
});
if (receivedReturn.error) throw receivedReturn.error;
assert(receivedReturn.data.outcome === "accepted", "goods return received");
const closedChain = await service.from("purchase_requests").select("status")
  .eq("id", prId).single();
if (closedChain.error) throw closedChain.error;
assert(
  closedChain.data.status === "closed",
  "PR to DO to GR chain closes atomically",
);

const room2LocationId = crypto.randomUUID();
const room2Location = await service.from("stock_locations").insert({
  id: room2LocationId,
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  type: "room",
  branch_id: "20000000-0000-0000-0000-000000000001",
  room_id: "21000000-0000-0000-0000-000000000002",
  name: "Ruang Lokal A2 E2E",
});
if (room2Location.error) throw room2Location.error;
const distributionItem = crypto.randomUUID();
const distributionItemFixture = await service.from("items").insert({
  id: distributionItem,
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  sku: `DIST-${distributionItem.slice(0, 8)}`,
  name: "Fixture distribution 12B",
  category_id: "40000000-0000-0000-0000-000000000001",
  unit: "pcs",
  min_stock_room: 0,
  min_stock_branch: 0,
  has_expiry: false,
  expiry_alert_days: 30,
  is_active: true,
});
if (distributionItemFixture.error) throw distributionItemFixture.error;
const distributionSourceBalance = await service.from("stock_balances").insert({
  id: crypto.randomUUID(),
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  location_id: "50000000-0000-0000-0000-000000000002",
  item_id: distributionItem,
  qty_on_hand: 3000,
});
if (distributionSourceBalance.error) throw distributionSourceBalance.error;
const distributionId = crypto.randomUUID();
const distributionMovementIds = [crypto.randomUUID(), crypto.randomUUID()];
const distributionPayload = {
  id: distributionId,
  created_at: occurredAt,
  branch_id: "20000000-0000-0000-0000-000000000001",
  status: "posted",
  lines: [{
    id: crypto.randomUUID(),
    room_id: "21000000-0000-0000-0000-000000000001",
    item_id: distributionItem,
    qty: 1000,
  }, {
    id: crypto.randomUUID(),
    room_id: "21000000-0000-0000-0000-000000000002",
    item_id: distributionItem,
    qty: 1000,
  }],
  movements: [{
    id: distributionMovementIds[0],
    created_at: occurredAt,
    item_id: distributionItem,
    from_location_id: "50000000-0000-0000-0000-000000000002",
    to_location_id: "50000000-0000-0000-0000-000000000004",
    qty: 1000,
    movement_type: "distribution",
    ref_doc_type: "DIST",
    ref_doc_id: distributionId,
  }, {
    id: distributionMovementIds[1],
    created_at: occurredAt,
    item_id: distributionItem,
    from_location_id: "50000000-0000-0000-0000-000000000002",
    to_location_id: room2LocationId,
    qty: 1000,
    movement_type: "distribution",
    ref_doc_type: "DIST",
    ref_doc_id: distributionId,
  }],
};
const distributionEnvelope = await envelope({
  request_id: crypto.randomUUID(),
  device_id: headDevice,
  operation: "post_distribution",
  aggregate_type: "distribution",
  aggregate_id: distributionId,
  payload_version: 1,
  base_server_version: 0,
  occurred_at_utc: occurredAt,
  payload: distributionPayload,
});
const distribution = await branchHead.rpc("push_sync_operation", {
  operation_envelope: distributionEnvelope,
});
if (distribution.error) throw distribution.error;
assert(
  distribution.data.outcome === "accepted",
  "multi-room distribution accepted",
);
const differentFinalDistribution = await envelope({
  ...distributionEnvelope,
  request_id: crypto.randomUUID(),
  payload_hash: undefined,
  payload: { ...distributionPayload, note: "different final payload" },
});
delete differentFinalDistribution.payload_hash;
differentFinalDistribution.payload_hash = await sha256Text(
  differentFinalDistribution,
);
const finalConflict = await branchHead.rpc("push_sync_operation", {
  operation_envelope: differentFinalDistribution,
});
if (finalConflict.error) throw finalConflict.error;
assert(
  finalConflict.data.outcome === "conflict" &&
    finalConflict.data.code === "sync_final_state_conflict",
  "different final payload is a server-wins conflict",
);
const reusedMovementAggregate = crypto.randomUUID();
const reusedMovementEnvelope = await envelope({
  request_id: crypto.randomUUID(),
  device_id: headDevice,
  operation: "post_distribution",
  aggregate_type: "distribution",
  aggregate_id: reusedMovementAggregate,
  payload_version: 1,
  base_server_version: 0,
  occurred_at_utc: occurredAt,
  payload: {
    id: reusedMovementAggregate,
    created_at: occurredAt,
    branch_id: "20000000-0000-0000-0000-000000000001",
    status: "posted",
    lines: [{
      id: crypto.randomUUID(),
      room_id: "21000000-0000-0000-0000-000000000001",
      item_id: distributionItem,
      qty: 500,
    }],
    movements: [{
      id: distributionMovementIds[0],
      created_at: occurredAt,
      item_id: distributionItem,
      from_location_id: "50000000-0000-0000-0000-000000000002",
      to_location_id: "50000000-0000-0000-0000-000000000004",
      qty: 500,
      movement_type: "distribution",
      ref_doc_type: "DIST",
      ref_doc_id: reusedMovementAggregate,
    }],
  },
});
const reusedMovement = await branchHead.rpc("push_sync_operation", {
  operation_envelope: reusedMovementEnvelope,
});
assert(
  reusedMovement.error?.message === "sync_movement_plan_mismatch",
  "same movement UUID with different business payload is rejected",
);
const rolledBackReusedMovement = await service.from("distributions")
  .select("id", { count: "exact" }).eq("id", reusedMovementAggregate);
if (rolledBackReusedMovement.error) throw rolledBackReusedMovement.error;
assert(
  rolledBackReusedMovement.count === 0,
  "movement UUID mismatch leaves no partial document",
);

const expiredBatchId = crypto.randomUUID();
const expiredBatch = await service.from("item_batches").insert({
  id: expiredBatchId,
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  item_id: "41000000-0000-0000-0000-000000000002",
  batch_no: `EXPIRED-${expiredBatchId.slice(0, 8)}`,
  expiry_date: "2020-01-01",
});
if (expiredBatch.error) throw expiredBatch.error;
const expiredBalance = await service.from("stock_balances").insert({
  id: crypto.randomUUID(),
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  location_id: "50000000-0000-0000-0000-000000000001",
  item_id: "41000000-0000-0000-0000-000000000002",
  batch_id: expiredBatchId,
  qty_on_hand: 2000,
});
if (expiredBalance.error) throw expiredBalance.error;
const disposalId = crypto.randomUUID();
const disposalPayload = {
  id: disposalId,
  created_at: occurredAt,
  source_location_id: "50000000-0000-0000-0000-000000000001",
  reason: "Kedaluwarsa",
  status: "posted",
  lines: [{
    id: crypto.randomUUID(),
    item_id: "41000000-0000-0000-0000-000000000002",
    batch_id: expiredBatchId,
    qty: 1000,
  }],
  movements: [{
    id: crypto.randomUUID(),
    created_at: occurredAt,
    item_id: "41000000-0000-0000-0000-000000000002",
    batch_id: expiredBatchId,
    from_location_id: "50000000-0000-0000-0000-000000000001",
    qty: 1000,
    movement_type: "disposal",
    ref_doc_type: "DSP",
    ref_doc_id: disposalId,
    note: "Kedaluwarsa",
  }],
};
const wrongRoleDisposal = await envelope({
  request_id: crypto.randomUUID(),
  device_id: headDevice,
  operation: "post_disposal",
  aggregate_type: "disposal",
  aggregate_id: disposalId,
  payload_version: 1,
  base_server_version: 0,
  occurred_at_utc: occurredAt,
  payload: disposalPayload,
});
const wrongRole = await branchHead.rpc("push_sync_operation", {
  operation_envelope: wrongRoleDisposal,
});
assert(
  wrongRole.error?.message === "sync_access_denied",
  "wrong role is denied",
);
const disposalEnvelope = await envelope({
  ...wrongRoleDisposal,
  request_id: crypto.randomUUID(),
  device_id: warehouseDevice,
  payload_hash: undefined,
});
delete disposalEnvelope.payload_hash;
disposalEnvelope.payload_hash = await sha256Text(disposalEnvelope);
const disposal = await warehouse.rpc("push_sync_operation", {
  operation_envelope: disposalEnvelope,
});
if (disposal.error) throw disposal.error;
assert(disposal.data.outcome === "accepted", "warehouse disposal accepted");

const staleEnvelope = await envelope({
  request_id: crypto.randomUUID(),
  device_id: warehouseDevice,
  operation: "reject_purchase_request",
  aggregate_type: "purchase_request",
  aggregate_id: prId,
  payload_version: 1,
  base_server_version: 999999,
  occurred_at_utc: occurredAt,
  payload: { reject_reason: "stale fixture" },
});
const stale = await warehouse.rpc("push_sync_operation", {
  operation_envelope: staleEnvelope,
});
if (stale.error) throw stale.error;
assert(
  stale.data.outcome === "conflict" && stale.data.code === "sync_stale_version",
  "stale non-final version is recorded as conflict",
);

const nurse = await signedIn("nurse.local@example.test");
const nurseDevice = crypto.randomUUID();
const nurseRegistration = await nurse.rpc("register_sync_device", {
  device_id: nurseDevice,
  requested_app_install_id: crypto.randomUUID(),
  requested_display_label: "12B stock contention E2E",
});
if (nurseRegistration.error) throw nurseRegistration.error;
const crossBranchAggregate = crypto.randomUUID();
const crossBranchEnvelope = await envelope({
  request_id: crypto.randomUUID(),
  device_id: nurseDevice,
  operation: "post_consumption",
  aggregate_type: "consumption",
  aggregate_id: crossBranchAggregate,
  payload_version: 1,
  base_server_version: 0,
  occurred_at_utc: occurredAt,
  payload: {
    id: crossBranchAggregate,
    created_at: occurredAt,
    branch_id: "20000000-0000-0000-0000-000000000002",
    room_id: "21000000-0000-0000-0000-000000000003",
    created_by: "30000000-0000-0000-0000-000000000001",
    status: "posted",
    lines: [{ id: crypto.randomUUID(), item_id: distributionItem, qty: 1000 }],
    movements: [],
  },
});
const crossBranch = await nurse.rpc("push_sync_operation", {
  operation_envelope: crossBranchEnvelope,
});
assert(
  crossBranch.error?.message === "sync_access_denied",
  "cross-branch push is denied",
);
const inactive = await signedIn("inactive.local@example.test");
const inactiveRegistration = await inactive.rpc("register_sync_device", {
  device_id: crypto.randomUUID(),
  requested_app_install_id: crypto.randomUUID(),
  requested_display_label: "must fail",
});
assert(
  inactiveRegistration.error?.message === "sync_user_inactive",
  "inactive user is denied",
);
const contentionItem = crypto.randomUUID();
const itemFixture = await service.from("items").insert({
  id: contentionItem,
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  sku: `CONTEND-${contentionItem.slice(0, 8)}`,
  name: "Fixture contention 12B",
  category_id: "40000000-0000-0000-0000-000000000001",
  unit: "pcs",
  min_stock_room: 0,
  min_stock_branch: 0,
  has_expiry: false,
  expiry_alert_days: 30,
  is_active: true,
});
if (itemFixture.error) throw itemFixture.error;
const contentionBalance = await service.from("stock_balances").insert({
  id: crypto.randomUUID(),
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  location_id: "50000000-0000-0000-0000-000000000004",
  item_id: contentionItem,
  qty_on_hand: 1500,
});
if (contentionBalance.error) throw contentionBalance.error;
const contentionAggregates = [crypto.randomUUID(), crypto.randomUUID()];
const contentionInputs = await Promise.all(
  contentionAggregates.map(async (aggregateId) => {
    const movementId = crypto.randomUUID();
    return envelope({
      request_id: crypto.randomUUID(),
      device_id: nurseDevice,
      operation: "post_consumption",
      aggregate_type: "consumption",
      aggregate_id: aggregateId,
      payload_version: 1,
      base_server_version: 0,
      occurred_at_utc: occurredAt,
      payload: {
        id: aggregateId,
        created_at: occurredAt,
        branch_id: "20000000-0000-0000-0000-000000000001",
        room_id: "21000000-0000-0000-0000-000000000001",
        created_by: "30000000-0000-0000-0000-000000000001",
        status: "posted",
        lines: [{
          id: crypto.randomUUID(),
          item_id: contentionItem,
          qty: 1000,
        }],
        movements: [{
          id: movementId,
          created_at: occurredAt,
          item_id: contentionItem,
          from_location_id: "50000000-0000-0000-0000-000000000004",
          qty: 1000,
          movement_type: "consumption",
          ref_doc_type: "CONS",
          ref_doc_id: aggregateId,
        }],
      },
    });
  }),
);
const contentionResults = await Promise.all(
  contentionInputs.map((operationEnvelope) =>
    nurse.rpc("push_sync_operation", { operation_envelope: operationEnvelope })
  ),
);
assert(
  contentionResults.filter((result) => result.data?.outcome === "accepted")
    .length === 1,
  "exactly one stock contender wins",
);
assert(
  contentionResults.filter((result) =>
    result.error?.message === "sync_insufficient_stock"
  ).length === 1,
  "losing stock contender is rejected without retry ambiguity",
);
const finalContentionBalance = await service.from("stock_balances").select(
  "qty_on_hand",
)
  .eq("location_id", "50000000-0000-0000-0000-000000000004")
  .eq("item_id", contentionItem).is("batch_id", null).single();
if (finalContentionBalance.error) throw finalContentionBalance.error;
assert(
  finalContentionBalance.data.qty_on_hand === 500,
  "contention never makes balance negative",
);
const contentionMovements = await service.from("stock_movements").select("id", {
  count: "exact",
})
  .eq("item_id", contentionItem).eq("movement_type", "consumption");
if (contentionMovements.error) throw contentionMovements.error;
assert(
  contentionMovements.count === 1,
  "contention creates no partial or duplicate movement",
);

// Consumption rejects expired batches by domain rule, while disposal requires
// them. Launch both requests against the same room position to prove that the
// validation/ledger boundary cannot create a partial consumption or overdraw.
const expiryRaceBatchId = crypto.randomUUID();
const expiryRaceBatch = await service.from("item_batches").insert({
  id: expiryRaceBatchId,
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  item_id: "41000000-0000-0000-0000-000000000002",
  batch_no: `EXP-RACE-${expiryRaceBatchId.slice(0, 8)}`,
  expiry_date: "2020-01-01",
});
if (expiryRaceBatch.error) throw expiryRaceBatch.error;
const expiryRaceBalance = await service.from("stock_balances").insert({
  id: crypto.randomUUID(),
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  location_id: "50000000-0000-0000-0000-000000000004",
  item_id: "41000000-0000-0000-0000-000000000002",
  batch_id: expiryRaceBatchId,
  qty_on_hand: 1500,
});
if (expiryRaceBalance.error) throw expiryRaceBalance.error;
const expiryRaceDisposalId = crypto.randomUUID();
const expiryRaceConsumptionId = crypto.randomUUID();
const [expiryRaceDisposalEnvelope, expiryRaceConsumptionEnvelope] =
  await Promise.all([
    envelope({
      request_id: crypto.randomUUID(),
      device_id: headDevice,
      operation: "post_disposal",
      aggregate_type: "disposal",
      aggregate_id: expiryRaceDisposalId,
      payload_version: 1,
      base_server_version: 0,
      occurred_at_utc: occurredAt,
      payload: {
        id: expiryRaceDisposalId,
        created_at: occurredAt,
        source_location_id: "50000000-0000-0000-0000-000000000004",
        reason: "Kedaluwarsa",
        status: "posted",
        lines: [{
          id: crypto.randomUUID(),
          item_id: "41000000-0000-0000-0000-000000000002",
          batch_id: expiryRaceBatchId,
          qty: 1000,
        }],
        movements: [{
          id: crypto.randomUUID(),
          created_at: occurredAt,
          item_id: "41000000-0000-0000-0000-000000000002",
          batch_id: expiryRaceBatchId,
          from_location_id: "50000000-0000-0000-0000-000000000004",
          qty: 1000,
          movement_type: "disposal",
          ref_doc_type: "DSP",
          ref_doc_id: expiryRaceDisposalId,
          note: "Kedaluwarsa",
        }],
      },
    }),
    envelope({
      request_id: crypto.randomUUID(),
      device_id: nurseDevice,
      operation: "post_consumption",
      aggregate_type: "consumption",
      aggregate_id: expiryRaceConsumptionId,
      payload_version: 1,
      base_server_version: 0,
      occurred_at_utc: occurredAt,
      payload: {
        id: expiryRaceConsumptionId,
        created_at: occurredAt,
        branch_id: "20000000-0000-0000-0000-000000000001",
        room_id: "21000000-0000-0000-0000-000000000001",
        created_by: "30000000-0000-0000-0000-000000000001",
        status: "posted",
        lines: [{
          id: crypto.randomUUID(),
          item_id: "41000000-0000-0000-0000-000000000002",
          batch_id: expiryRaceBatchId,
          qty: 1000,
        }],
        movements: [{
          id: crypto.randomUUID(),
          created_at: occurredAt,
          item_id: "41000000-0000-0000-0000-000000000002",
          batch_id: expiryRaceBatchId,
          from_location_id: "50000000-0000-0000-0000-000000000004",
          qty: 1000,
          movement_type: "consumption",
          ref_doc_type: "CONS",
          ref_doc_id: expiryRaceConsumptionId,
        }],
      },
    }),
  ]);
const [expiryRaceDisposalResult, expiryRaceConsumptionResult] = await Promise
  .all([
    branchHead.rpc("push_sync_operation", {
      operation_envelope: expiryRaceDisposalEnvelope,
    }),
    nurse.rpc("push_sync_operation", {
      operation_envelope: expiryRaceConsumptionEnvelope,
    }),
  ]);
if (expiryRaceDisposalResult.error) throw expiryRaceDisposalResult.error;
assert(
  expiryRaceDisposalResult.data.outcome === "accepted",
  "disposal wins same-source expired-batch race",
);
assert(
  expiryRaceConsumptionResult.error?.message === "sync_batch_invalid",
  "consumption rejects the expired batch in the same-source race",
);
const expiryRaceFinalBalance = await service.from("stock_balances")
  .select("qty_on_hand")
  .eq("location_id", "50000000-0000-0000-0000-000000000004")
  .eq("item_id", "41000000-0000-0000-0000-000000000002")
  .eq("batch_id", expiryRaceBatchId)
  .single();
if (expiryRaceFinalBalance.error) throw expiryRaceFinalBalance.error;
assert(
  expiryRaceFinalBalance.data.qty_on_hand === 500,
  "same-source disposal/consumption race leaves exact non-negative balance",
);
const expiryRaceConsumptionDocument = await service.from("consumptions")
  .select("id", { count: "exact" })
  .eq("id", expiryRaceConsumptionId);
if (expiryRaceConsumptionDocument.error) {
  throw expiryRaceConsumptionDocument.error;
}
assert(
  expiryRaceConsumptionDocument.count === 0,
  "invalid concurrent consumption leaves no partial document",
);

const doContentionItem = crypto.randomUUID();
const doContentionItemFixture = await service.from("items").insert({
  id: doContentionItem,
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  sku: `DO-RACE-${doContentionItem.slice(0, 8)}`,
  name: "Fixture DO contention 12B",
  category_id: "40000000-0000-0000-0000-000000000001",
  unit: "pcs",
  min_stock_room: 0,
  min_stock_branch: 0,
  has_expiry: false,
  expiry_alert_days: 30,
  is_active: true,
});
if (doContentionItemFixture.error) throw doContentionItemFixture.error;
const doContentionBalance = await service.from("stock_balances").insert({
  id: crypto.randomUUID(),
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  location_id: "50000000-0000-0000-0000-000000000001",
  item_id: doContentionItem,
  qty_on_hand: 1500,
});
if (doContentionBalance.error) throw doContentionBalance.error;
const racePrIds = [crypto.randomUUID(), crypto.randomUUID()];
const racePrLineIds = [crypto.randomUUID(), crypto.randomUUID()];
const racePrFixtures = await service.from("purchase_requests").insert(
  racePrIds.map((id, index) => ({
    id,
    created_at: occurredAt,
    updated_at: occurredAt,
    sync_status: "synced",
    doc_number: `PR-RACE-${id.slice(0, 8)}`,
    branch_id: index === 0
      ? "20000000-0000-0000-0000-000000000001"
      : "20000000-0000-0000-0000-000000000002",
    requested_by: "30000000-0000-0000-0000-000000000002",
    status: "processing",
    submitted_at: occurredAt,
    processing_at: occurredAt,
    processed_by: "30000000-0000-0000-0000-000000000003",
  })),
);
if (racePrFixtures.error) throw racePrFixtures.error;
const racePrLines = await service.from("purchase_request_lines").insert(
  racePrLineIds.map((id, index) => ({
    id,
    created_at: occurredAt,
    updated_at: occurredAt,
    sync_status: "synced",
    pr_id: racePrIds[index],
    item_id: doContentionItem,
    suggested_qty: 1000,
    requested_qty: 1000,
  })),
);
if (racePrLines.error) throw racePrLines.error;
const raceDoIds = [crypto.randomUUID(), crypto.randomUUID()];
const raceDoEnvelopes = await Promise.all(
  raceDoIds.map((aggregateId, index) => {
    const movementId = crypto.randomUUID();
    return envelope({
      request_id: crypto.randomUUID(),
      device_id: warehouseDevice,
      operation: "ship_delivery_order",
      aggregate_type: "delivery_order",
      aggregate_id: aggregateId,
      payload_version: 1,
      base_server_version: 0,
      occurred_at_utc: occurredAt,
      payload: {
        id: aggregateId,
        created_at: occurredAt,
        pr_id: racePrIds[index],
        status: "shipped",
        lines: [{
          id: crypto.randomUUID(),
          pr_line_id: racePrLineIds[index],
          item_id: doContentionItem,
          shipped_qty: 1000,
        }],
        movements: [{
          id: movementId,
          created_at: occurredAt,
          item_id: doContentionItem,
          from_location_id: "50000000-0000-0000-0000-000000000001",
          qty: 1000,
          movement_type: "shipment",
          ref_doc_type: "DO",
          ref_doc_id: aggregateId,
        }],
      },
    });
  }),
);
const raceDoResults = await Promise.all(
  raceDoEnvelopes.map((operationEnvelope) =>
    warehouse.rpc("push_sync_operation", {
      operation_envelope: operationEnvelope,
    })
  ),
);
assert(
  raceDoResults.filter((result) => result.data?.outcome === "accepted")
    .length === 1,
  "exactly one competing DO wins warehouse stock",
);
assert(
  raceDoResults.filter((result) =>
    result.error?.message === "sync_insufficient_stock"
  ).length === 1,
  "competing DO loser rolls back for insufficient stock",
);
const raceDoBalance = await service.from("stock_balances").select("qty_on_hand")
  .eq("location_id", "50000000-0000-0000-0000-000000000001")
  .eq("item_id", doContentionItem).is("batch_id", null).single();
if (raceDoBalance.error) throw raceDoBalance.error;
assert(
  raceDoBalance.data.qty_on_hand === 500,
  "DO contention leaves non-negative stock",
);
const raceDoDocuments = await service.from("delivery_orders").select("id", {
  count: "exact",
})
  .in("id", raceDoIds);
if (raceDoDocuments.error) throw raceDoDocuments.error;
assert(
  raceDoDocuments.count === 1,
  "DO contention leaves no partial loser document",
);

const distributionRaceItem = crypto.randomUUID();
const distributionRaceItemFixture = await service.from("items").insert({
  id: distributionRaceItem,
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  sku: `DIST-RACE-${distributionRaceItem.slice(0, 8)}`,
  name: "Fixture distribution contention 12B",
  category_id: "40000000-0000-0000-0000-000000000001",
  unit: "pcs",
  min_stock_room: 0,
  min_stock_branch: 0,
  has_expiry: true,
  expiry_alert_days: 30,
  is_active: true,
});
if (distributionRaceItemFixture.error) throw distributionRaceItemFixture.error;
const distributionRaceBatchId = crypto.randomUUID();
const distributionRaceBatch = await service.from("item_batches").insert({
  id: distributionRaceBatchId,
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  item_id: distributionRaceItem,
  batch_no: `DIST-RACE-${distributionRaceBatchId.slice(0, 8)}`,
  expiry_date: "2099-12-31",
});
if (distributionRaceBatch.error) throw distributionRaceBatch.error;
const distributionRaceBalance = await service.from("stock_balances").insert({
  id: crypto.randomUUID(),
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  location_id: "50000000-0000-0000-0000-000000000002",
  item_id: distributionRaceItem,
  batch_id: distributionRaceBatchId,
  qty_on_hand: 1500,
});
if (distributionRaceBalance.error) throw distributionRaceBalance.error;
const distributionRaceIds = [crypto.randomUUID(), crypto.randomUUID()];
const distributionRaceEnvelopes = await Promise.all(
  distributionRaceIds.map((aggregateId) =>
    envelope({
      request_id: crypto.randomUUID(),
      device_id: headDevice,
      operation: "post_distribution",
      aggregate_type: "distribution",
      aggregate_id: aggregateId,
      payload_version: 1,
      base_server_version: 0,
      occurred_at_utc: occurredAt,
      payload: {
        id: aggregateId,
        created_at: occurredAt,
        branch_id: "20000000-0000-0000-0000-000000000001",
        status: "posted",
        lines: [{
          id: crypto.randomUUID(),
          room_id: "21000000-0000-0000-0000-000000000001",
          item_id: distributionRaceItem,
          batch_id: distributionRaceBatchId,
          qty: 1000,
        }],
        movements: [{
          id: crypto.randomUUID(),
          created_at: occurredAt,
          item_id: distributionRaceItem,
          batch_id: distributionRaceBatchId,
          from_location_id: "50000000-0000-0000-0000-000000000002",
          to_location_id: "50000000-0000-0000-0000-000000000004",
          qty: 1000,
          movement_type: "distribution",
          ref_doc_type: "DIST",
          ref_doc_id: aggregateId,
        }],
      },
    })
  ),
);
const distributionRaceResults = await Promise.all(
  distributionRaceEnvelopes.map((operationEnvelope) =>
    branchHead.rpc("push_sync_operation", {
      operation_envelope: operationEnvelope,
    })
  ),
);
assert(
  distributionRaceResults.filter((result) =>
    result.data?.outcome === "accepted"
  ).length === 1,
  "exactly one competing distribution wins branch stock",
);
assert(
  distributionRaceResults.filter((result) =>
    result.error?.message === "sync_insufficient_stock"
  ).length === 1,
  "competing distribution loser rolls back",
);

const reverseItems = [crypto.randomUUID(), crypto.randomUUID()];
const reverseItemFixtures = await service.from("items").insert(
  reverseItems.map((id, index) => ({
    id,
    created_at: occurredAt,
    updated_at: occurredAt,
    sync_status: "synced",
    sku: `LOCK-${index}-${id.slice(0, 8)}`,
    name: `Fixture reverse lock ${index}`,
    category_id: "40000000-0000-0000-0000-000000000001",
    unit: "pcs",
    min_stock_room: 0,
    min_stock_branch: 0,
    has_expiry: false,
    expiry_alert_days: 30,
    is_active: true,
  })),
);
if (reverseItemFixtures.error) throw reverseItemFixtures.error;
const reverseBalances = await service.from("stock_balances").insert(
  reverseItems.map((itemId) => ({
    id: crypto.randomUUID(),
    created_at: occurredAt,
    updated_at: occurredAt,
    sync_status: "synced",
    location_id: "50000000-0000-0000-0000-000000000002",
    item_id: itemId,
    qty_on_hand: 2000,
  })),
);
if (reverseBalances.error) throw reverseBalances.error;
const reverseAggregateIds = [crypto.randomUUID(), crypto.randomUUID()];
const reverseOrderEnvelopes = await Promise.all(
  reverseAggregateIds.map((aggregateId, requestIndex) => {
    const orderedItems = requestIndex === 0
      ? reverseItems
      : [...reverseItems].reverse();
    return envelope({
      request_id: crypto.randomUUID(),
      device_id: headDevice,
      operation: "post_distribution",
      aggregate_type: "distribution",
      aggregate_id: aggregateId,
      payload_version: 1,
      base_server_version: 0,
      occurred_at_utc: occurredAt,
      payload: {
        id: aggregateId,
        created_at: occurredAt,
        branch_id: "20000000-0000-0000-0000-000000000001",
        status: "posted",
        lines: orderedItems.map((itemId) => ({
          id: crypto.randomUUID(),
          room_id: "21000000-0000-0000-0000-000000000001",
          item_id: itemId,
          qty: 500,
        })),
        movements: orderedItems.map((itemId) => ({
          id: crypto.randomUUID(),
          created_at: occurredAt,
          item_id: itemId,
          from_location_id: "50000000-0000-0000-0000-000000000002",
          to_location_id: "50000000-0000-0000-0000-000000000004",
          qty: 500,
          movement_type: "distribution",
          ref_doc_type: "DIST",
          ref_doc_id: aggregateId,
        })),
      },
    });
  }),
);
const reverseOrderResults = await Promise.all(
  reverseOrderEnvelopes.map((operationEnvelope) =>
    branchHead.rpc("push_sync_operation", {
      operation_envelope: operationEnvelope,
    })
  ),
);
for (const result of reverseOrderResults) if (result.error) throw result.error;
assert(
  reverseOrderResults.every((result) => result.data.outcome === "accepted"),
  "reverse payload lock order completes without deadlock",
);

const receiptRaceItem = crypto.randomUUID();
const receiptRaceItemFixture = await service.from("items").insert({
  id: receiptRaceItem,
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  sku: `GR-RACE-${receiptRaceItem.slice(0, 8)}`,
  name: "Fixture GR versus distribution 12B",
  category_id: "40000000-0000-0000-0000-000000000001",
  unit: "pcs",
  min_stock_room: 0,
  min_stock_branch: 0,
  has_expiry: false,
  expiry_alert_days: 30,
  is_active: true,
});
if (receiptRaceItemFixture.error) throw receiptRaceItemFixture.error;
const receiptRacePrId = crypto.randomUUID();
const receiptRacePrLineId = crypto.randomUUID();
const receiptRaceDoId = crypto.randomUUID();
const receiptRaceDoLineId = crypto.randomUUID();
const receiptRacePr = await service.from("purchase_requests").insert({
  id: receiptRacePrId,
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  doc_number: `PR-GR-RACE-${receiptRacePrId.slice(0, 8)}`,
  branch_id: "20000000-0000-0000-0000-000000000001",
  requested_by: "30000000-0000-0000-0000-000000000002",
  status: "shipped",
  submitted_at: occurredAt,
  processing_at: occurredAt,
  processed_by: "30000000-0000-0000-0000-000000000003",
});
if (receiptRacePr.error) throw receiptRacePr.error;
const receiptRacePrLine = await service.from("purchase_request_lines").insert({
  id: receiptRacePrLineId,
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  pr_id: receiptRacePrId,
  item_id: receiptRaceItem,
  suggested_qty: 1000,
  requested_qty: 1000,
});
if (receiptRacePrLine.error) throw receiptRacePrLine.error;
const receiptRaceDo = await service.from("delivery_orders").insert({
  id: receiptRaceDoId,
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  doc_number: `DO-GR-RACE-${receiptRaceDoId.slice(0, 8)}`,
  pr_id: receiptRacePrId,
  prepared_by: "30000000-0000-0000-0000-000000000003",
  status: "shipped",
  shipped_at: occurredAt,
  shipped_by: "30000000-0000-0000-0000-000000000003",
});
if (receiptRaceDo.error) throw receiptRaceDo.error;
const receiptRaceDoLine = await service.from("delivery_order_lines").insert({
  id: receiptRaceDoLineId,
  created_at: occurredAt,
  updated_at: occurredAt,
  sync_status: "synced",
  do_id: receiptRaceDoId,
  pr_line_id: receiptRacePrLineId,
  item_id: receiptRaceItem,
  shipped_qty: 1000,
});
if (receiptRaceDoLine.error) throw receiptRaceDoLine.error;
const receiptRaceReceiptId = crypto.randomUUID();
const receiptRaceDistributionId = crypto.randomUUID();
const [receiptRaceReceiptEnvelope, receiptRaceDistributionEnvelope] =
  await Promise.all([
    envelope({
      request_id: crypto.randomUUID(),
      device_id: headDevice,
      operation: "post_good_receipt",
      aggregate_type: "good_receipt",
      aggregate_id: receiptRaceReceiptId,
      payload_version: 1,
      base_server_version: 0,
      occurred_at_utc: occurredAt,
      payload: {
        id: receiptRaceReceiptId,
        created_at: occurredAt,
        do_id: receiptRaceDoId,
        status: "posted",
        lines: [{
          id: crypto.randomUUID(),
          do_line_id: receiptRaceDoLineId,
          item_id: receiptRaceItem,
          shipped_qty: 1000,
          received_qty: 1000,
          line_status: "checked",
        }],
        movements: [{
          id: crypto.randomUUID(),
          created_at: occurredAt,
          item_id: receiptRaceItem,
          to_location_id: "50000000-0000-0000-0000-000000000002",
          qty: 1000,
          movement_type: "good_receipt",
          ref_doc_type: "GR",
          ref_doc_id: receiptRaceReceiptId,
        }],
      },
    }),
    envelope({
      request_id: crypto.randomUUID(),
      device_id: headDevice,
      operation: "post_distribution",
      aggregate_type: "distribution",
      aggregate_id: receiptRaceDistributionId,
      payload_version: 1,
      base_server_version: 0,
      occurred_at_utc: occurredAt,
      payload: {
        id: receiptRaceDistributionId,
        created_at: occurredAt,
        branch_id: "20000000-0000-0000-0000-000000000001",
        status: "posted",
        lines: [{
          id: crypto.randomUUID(),
          room_id: "21000000-0000-0000-0000-000000000001",
          item_id: receiptRaceItem,
          qty: 1000,
        }],
        movements: [{
          id: crypto.randomUUID(),
          created_at: occurredAt,
          item_id: receiptRaceItem,
          from_location_id: "50000000-0000-0000-0000-000000000002",
          to_location_id: "50000000-0000-0000-0000-000000000004",
          qty: 1000,
          movement_type: "distribution",
          ref_doc_type: "DIST",
          ref_doc_id: receiptRaceDistributionId,
        }],
      },
    }),
  ]);
const [receiptRaceReceiptResult, receiptRaceDistributionResult] = await Promise
  .all([
    branchHead.rpc("push_sync_operation", {
      operation_envelope: receiptRaceReceiptEnvelope,
    }),
    branchHead.rpc("push_sync_operation", {
      operation_envelope: receiptRaceDistributionEnvelope,
    }),
  ]);
if (receiptRaceReceiptResult.error) throw receiptRaceReceiptResult.error;
assert(
  receiptRaceReceiptResult.data.outcome === "accepted",
  "GR add is accepted while distribution reads the same position",
);
const receiptRaceDistributionAccepted =
  receiptRaceDistributionResult.data?.outcome === "accepted";
assert(
  receiptRaceDistributionAccepted ||
    receiptRaceDistributionResult.error?.message === "sync_insufficient_stock",
  "concurrent distribution deterministically accepts or reports insufficient stock",
);
const receiptRaceBalance = await service.from("stock_balances")
  .select("qty_on_hand")
  .eq("location_id", "50000000-0000-0000-0000-000000000002")
  .eq("item_id", receiptRaceItem)
  .is("batch_id", null)
  .single();
if (receiptRaceBalance.error) throw receiptRaceBalance.error;
assert(
  receiptRaceBalance.data.qty_on_hand ===
    (receiptRaceDistributionAccepted ? 0 : 1000),
  "GR/distribution race leaves the serializable exact balance",
);
const receiptRaceDistributionDocument = await service.from("distributions")
  .select("id", { count: "exact" })
  .eq("id", receiptRaceDistributionId);
if (receiptRaceDistributionDocument.error) {
  throw receiptRaceDistributionDocument.error;
}
assert(
  receiptRaceDistributionDocument.count ===
    (receiptRaceDistributionAccepted ? 1 : 0),
  "GR/distribution race leaves no partial distribution document",
);

const fileBytes = new TextEncoder().encode(
  "PK\u0003\u0004 trusted local fixture",
);
const fileHash = await sha256Bytes(fileBytes);
const uploadEntity = crypto.randomUUID();
const intent = await admin.functions.invoke("trusted-upload-intent", {
  body: {
    request_id: crypto.randomUUID(),
    entity_type: "import_audit",
    entity_id: uploadEntity,
    original_file_name: "fixture.xlsx",
    expected_sha256: fileHash,
    expected_size_bytes: fileBytes.byteLength,
    mime_type:
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  },
});
if (intent.error) {
  throw new Error(
    `trusted_intent_failed:${await functionErrorCode(intent.error)}`,
  );
}
const intentData = intent.data as Record<string, string>;
const uploaded = await admin.storage.from(intentData.bucket_id)
  .uploadToSignedUrl(
    intentData.object_key,
    intentData.token,
    fileBytes,
    {
      contentType:
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      upsert: false,
    },
  );
if (uploaded.error) throw uploaded.error;
let finalized = await admin.functions.invoke("trusted-upload-finalize", {
  body: { intent_id: intentData.intent_id },
});
for (let attempt = 0; attempt < 2; attempt++) {
  const status = (finalized.error as { context?: Response } | null)?.context
    ?.status;
  if (!finalized.error || (status !== undefined && status < 500)) break;
  await new Promise((resolve) => setTimeout(resolve, 100 * (attempt + 1)));
  finalized = await admin.functions.invoke("trusted-upload-finalize", {
    body: { intent_id: intentData.intent_id },
  });
}
if (finalized.error) {
  const finalizeFailure = finalized.error as {
    message?: string;
    context?: Response;
  };
  throw new Error(
    `trusted_finalize_failed:${await functionErrorCode(finalized.error)}:` +
      `${finalizeFailure.context?.status ?? "no-status"}:` +
      `${finalizeFailure.message ?? "no-message"}`,
  );
}
assert(
  typeof finalized.data.object_id === "string",
  "trusted upload finalized",
);

const denied = await branchHead.functions.invoke("trusted-upload-finalize", {
  body: { intent_id: intentData.intent_id },
});
assert(
  await functionErrorCode(denied.error) === "sync_upload_not_authorized",
  "cross-user finalize denied",
);

const mismatchIntent = await admin.functions.invoke("trusted-upload-intent", {
  body: {
    request_id: crypto.randomUUID(),
    entity_type: "import_audit",
    entity_id: crypto.randomUUID(),
    original_file_name: "mismatch.xlsx",
    expected_sha256: "0".repeat(64),
    expected_size_bytes: fileBytes.byteLength,
    mime_type:
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  },
});
if (mismatchIntent.error) throw mismatchIntent.error;
const mismatch = mismatchIntent.data as Record<string, string>;
await admin.storage.from(mismatch.bucket_id).uploadToSignedUrl(
  mismatch.object_key,
  mismatch.token,
  fileBytes,
  {
    contentType:
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    upsert: false,
  },
);
const mismatchFinalize = await admin.functions.invoke(
  "trusted-upload-finalize",
  {
    body: { intent_id: mismatch.intent_id },
  },
);
const mismatchCode = await functionErrorCode(mismatchFinalize.error) ??
  (mismatchFinalize.data as { code?: string } | null)?.code;
assert(
  mismatchCode === "sync_upload_hash_mismatch",
  `hash mismatch rejected (${mismatchCode})`,
);
const mismatchKeyParts = mismatch.object_key.split("/");
const mismatchObjectName = mismatchKeyParts.pop() ?? "";
const mismatchObjects = await service.storage.from(mismatch.bucket_id).list(
  mismatchKeyParts.join("/"),
  { search: mismatchObjectName },
);
if (mismatchObjects.error) throw mismatchObjects.error;
assert(
  !mismatchObjects.data.some((object) => object.name === mismatchObjectName),
  "invalid upload object is deleted best-effort",
);

console.log(
  "12B local E2E PASS: all workflows, full concurrency matrix, replay/conflicts, RBAC/scope, trusted upload",
);

async function sha256Bytes(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", Uint8Array.from(bytes).buffer),
  );
  return Array.from(digest).map((part) => part.toString(16).padStart(2, "0"))
    .join("");
}

async function functionErrorCode(error: unknown): Promise<string | null> {
  const response = (error as { context?: Response } | null)?.context;
  if (!response) return null;
  const body = await response.clone().json() as { code?: string };
  return body.code ?? null;
}
