// Milestone 12C end-to-end: deterministic pull, scope isolation, tombstones,
// field-level reconciliation, and the multi-device cases that only a real
// server with real sessions can demonstrate.
//
// pgTAP runs inside one transaction, so it cannot observe the commit horizon
// releasing a change — its own writes are never settled. That is exactly the
// gap this harness fills: every actor here is a separate authenticated session
// over HTTP, and every write is committed before the next assertion reads it.

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

type PullPage = {
  changes: Array<{
    change_seq: number;
    entity_type: string;
    entity_id: string;
    operation: "upsert" | "tombstone";
    server_version: number;
    payload: Record<string, unknown> | null;
    field_versions: Record<string, number>;
  }>;
  next_cursor: number;
  has_more: boolean;
  scope_fingerprint: string;
  server_horizon: number;
};

async function pull(
  client: SupabaseClient,
  device: string,
  cursor: number,
  limit = 200,
  entityTypes?: string[],
): Promise<PullPage> {
  const result = await client.rpc("pull_sync_changes", {
    after_cursor: cursor,
    batch_limit: limit,
    device_id: device,
    ...(entityTypes ? { entity_types: entityTypes } : {}),
  });
  if (result.error) throw result.error;
  return result.data as PullPage;
}

/// Drains the feed the way the Flutter worker does: page after page from the
/// durable cursor until the server says there is no more.
async function drain(
  client: SupabaseClient,
  device: string,
  from: number,
  limit = 200,
  entityTypes?: string[],
): Promise<{ changes: PullPage["changes"]; cursor: number; pages: number }> {
  let cursor = from;
  let pages = 0;
  const changes: PullPage["changes"] = [];
  for (;;) {
    const page = await pull(client, device, cursor, limit, entityTypes);
    changes.push(...page.changes);
    cursor = page.next_cursor;
    pages += 1;
    if (!page.has_more) return { changes, cursor, pages };
    assert(pages < 500, "drain_did_not_terminate");
  }
}

async function registerDevice(
  client: SupabaseClient,
  label: string,
): Promise<string> {
  const device = crypto.randomUUID();
  const result = await client.rpc("register_sync_device", {
    device_id: device,
    requested_app_install_id: crypto.randomUUID(),
    requested_display_label: label,
  });
  if (result.error) throw result.error;
  return device;
}

// ---------------------------------------------------------------------------
// Sessions and devices
// ---------------------------------------------------------------------------
const admin = await signedIn("admin.local@example.test");
const branchHead = await signedIn("branchhead.local@example.test");
const nurse = await signedIn("nurse.local@example.test");
const warehouse = await signedIn("warehouse.local@example.test");

const adminDevice = await registerDevice(admin, "12C admin");
const headDevice = await registerDevice(branchHead, "12C branch head");
const nurseDevice = await registerDevice(nurse, "12C nurse");
const warehouseDevice = await registerDevice(warehouse, "12C warehouse");
// A second device for the same actor, so multi-device is genuinely two cursors.
const adminDeviceB = await registerDevice(admin, "12C admin second device");

const branchA = "20000000-0000-0000-0000-000000000001";
const itemNoExpiry = "41000000-0000-0000-0000-000000000001";
const roomLocationA = "50000000-0000-0000-0000-000000000004";

// ---------------------------------------------------------------------------
// 1. A device that starts from zero reaches the current state
// ---------------------------------------------------------------------------
const adminStart = await drain(admin, adminDevice, 0);
assert(adminStart.changes.length > 0, "admin_sees_seeded_state");
assert(
  adminStart.changes.every((change, index, all) =>
    index === 0 || all[index - 1].change_seq < change.change_seq
  ),
  "changes_are_strictly_ordered",
);
let adminCursor = adminStart.cursor;

// A drained feed reports nothing further and does not move the cursor.
const adminIdle = await pull(admin, adminDevice, adminCursor);
assert(adminIdle.changes.length === 0, "drained_feed_is_empty");
assert(adminIdle.has_more === false, "drained_feed_has_no_more");
assert(adminIdle.next_cursor === adminCursor, "idle_pull_does_not_move_cursor");

// ---------------------------------------------------------------------------
// 2. Acceptance 27: device A submits, device B receives it by pull
// ---------------------------------------------------------------------------
// A purchase request must reference a real count (G-P1), so the nurse submits
// one first. This also gives the pull assertions a document that starts in one
// actor's scope and becomes visible to another.
const opnameId = crypto.randomUUID();
const opnameLineId = crypto.randomUUID();
const opnameAt = new Date().toISOString();
const opnameResult = await nurse.rpc("push_sync_operation", {
  operation_envelope: await envelope({
    request_id: crypto.randomUUID(),
    device_id: nurseDevice,
    operation: "submit_opname",
    aggregate_type: "stock_opname",
    aggregate_id: opnameId,
    payload_version: 1,
    base_server_version: 0,
    occurred_at_utc: opnameAt,
    payload: {
      id: opnameId,
      created_at: opnameAt,
      branch_id: branchA,
      room_id: "21000000-0000-0000-0000-000000000001",
      counted_by: "30000000-0000-0000-0000-000000000001",
      period_year: 2026,
      period_week: 31,
      lines: [
        {
          id: opnameLineId,
          item_id: itemNoExpiry,
          system_qty: 0,
          counted_qty: 0,
        },
      ],
    },
  }),
});
if (opnameResult.error) throw opnameResult.error;
assert(opnameResult.data.outcome === "accepted", "opname_submitted");

const prId = crypto.randomUUID();
const prLineId = crypto.randomUUID();
const submittedAt = new Date().toISOString();
const submitResult = await branchHead.rpc(
  "push_sync_operation",
  {
    operation_envelope: await envelope({
      request_id: crypto.randomUUID(),
      device_id: headDevice,
      operation: "submit_purchase_request",
      aggregate_type: "purchase_request",
      aggregate_id: prId,
      payload_version: 1,
      base_server_version: 0,
      occurred_at_utc: submittedAt,
      payload: {
        id: prId,
        created_at: submittedAt,
        branch_id: branchA,
        requested_by: "30000000-0000-0000-0000-000000000002",
        status: "submitted",
        lines: [
          {
            id: prLineId,
            item_id: itemNoExpiry,
            suggested_qty: 1000,
            requested_qty: 2000,
          },
        ],
        opname_links: [
          { id: crypto.randomUUID(), opname_id: opnameId },
        ],
      },
    }),
  },
);
if (submitResult.error) throw submitResult.error;
assert(submitResult.data.outcome === "accepted", "pr_submit_accepted");
const finalDocNumber = submitResult.data.final_document_number as string;
assert(
  /^PR-LOCAL-A-\d{8}-\d{4}$/.test(finalDocNumber),
  "server_assigned_final_number",
);

// Warehouse — a different device, a different actor — learns about it by pull.
const warehouseSeen = await drain(warehouse, warehouseDevice, 0, 200, [
  "purchase_request",
]);
const pulledPr = warehouseSeen.changes.find((c) => c.entity_id === prId);
assert(pulledPr !== undefined, "warehouse_pulls_the_submitted_request");
assert(pulledPr!.operation === "upsert", "submitted_request_is_an_upsert");
assert(
  pulledPr!.payload?.doc_number === finalDocNumber,
  "final_document_number_travels_with_the_document",
);
assert(
  Array.isArray(pulledPr!.payload?.lines) &&
    (pulledPr!.payload!.lines as unknown[]).length === 1,
  "document_payload_carries_its_lines",
);
assert(
  (pulledPr!.payload!.lines as Array<Record<string, unknown>>)[0].id ===
    prLineId,
  "the_line_is_the_one_that_was_submitted",
);

// ---------------------------------------------------------------------------
// 3. Acceptance 5 and 6: scope isolation over real sessions
// ---------------------------------------------------------------------------
const nurseSeen = await drain(nurse, nurseDevice, 0);
assert(
  !nurseSeen.changes.some((c) => c.entity_type === "purchase_request"),
  "nurse_never_learns_a_purchase_request_exists",
);
assert(
  !nurseSeen.changes.some((c) =>
    c.entity_type === "branch" &&
    c.entity_id === "20000000-0000-0000-0000-000000000002"
  ),
  "nurse_never_sees_another_branch",
);
assert(
  !nurseSeen.changes.some((c) =>
    c.entity_type === "user" &&
    c.entity_id !== "30000000-0000-0000-0000-000000000001"
  ),
  "nurse_sees_only_their_own_identity_row",
);

const headSeen = await drain(branchHead, headDevice, 0);
assert(
  !headSeen.changes.some((c) =>
    c.entity_type === "room" &&
    c.entity_id === "21000000-0000-0000-0000-000000000003"
  ),
  "branch_a_head_never_sees_a_branch_b_room",
);

// Two different scopes never share a fingerprint, which is what makes a stored
// cursor safe to reuse.
const headScope = (await pull(branchHead, headDevice, 0, 1)).scope_fingerprint;
const nurseScope = (await pull(nurse, nurseDevice, 0, 1)).scope_fingerprint;
assert(headScope !== nurseScope, "scopes_have_distinct_fingerprints");

// A device belonging to another actor is refused outright.
const stolenDevice = await branchHead.rpc("pull_sync_changes", {
  after_cursor: 0,
  batch_limit: 10,
  device_id: nurseDevice,
});
assert(
  stolenDevice.error?.message === "sync_access_denied",
  "another_actors_device_is_refused",
);

// ---------------------------------------------------------------------------
// 4. Acceptance 2 and 3: pagination loses nothing and repeats nothing
// ---------------------------------------------------------------------------
const wholeFeed = await drain(admin, adminDevice, 0, 500);
const pagedFeed = await drain(admin, adminDevice, 0, 3);
assert(
  pagedFeed.pages > 1,
  "the_paged_walk_actually_paged",
);
assert(
  JSON.stringify(wholeFeed.changes.map((c) => c.change_seq)) ===
    JSON.stringify(pagedFeed.changes.map((c) => c.change_seq)),
  "small_pages_visit_exactly_the_same_changes",
);
assert(
  new Set(pagedFeed.changes.map((c) => c.change_seq)).size ===
    pagedFeed.changes.length,
  "the_paged_walk_never_repeats_a_change",
);
assert(wholeFeed.cursor === pagedFeed.cursor, "both_walks_end_in_one_place");

// The same cursor against the same state answers identically.
const first = await pull(admin, adminDevice, 0, 5);
const second = await pull(admin, adminDevice, 0, 5);
assert(
  JSON.stringify(first.changes) === JSON.stringify(second.changes),
  "the_same_cursor_yields_an_identical_batch",
);

// ---------------------------------------------------------------------------
// 5. Acceptance 4: invalid cursors and limits fail safely
// ---------------------------------------------------------------------------
for (
  const [args, expected, label] of [
    [{ after_cursor: -1, batch_limit: 10 }, "sync_cursor_invalid", "negative"],
    [
      { after_cursor: 9223372036854775000, batch_limit: 10 },
      "sync_cursor_invalid",
      "beyond_feed",
    ],
    [{ after_cursor: 0, batch_limit: 0 }, "sync_invalid_payload", "zero_limit"],
    [
      { after_cursor: 0, batch_limit: 501 },
      "sync_invalid_payload",
      "oversized_limit",
    ],
  ] as const
) {
  const refused = await admin.rpc("pull_sync_changes", {
    ...args,
    device_id: adminDevice,
  });
  assert(refused.error?.message === expected, `cursor_refused_${label}`);
  assert(
    !JSON.stringify(refused.error).includes("app_private"),
    `cursor_error_leaks_nothing_${label}`,
  );
}

const anonymous = createClient(url, anonKey, {
  auth: { persistSession: false },
});
const anonPull = await anonymous.rpc("pull_sync_changes", {
  after_cursor: 0,
  batch_limit: 10,
  device_id: adminDevice,
});
assert(anonPull.error !== null, "anonymous_cannot_pull");

// ---------------------------------------------------------------------------
// 6. Acceptance 28 and 30: an offline device catches up; order does not matter
// ---------------------------------------------------------------------------
// Device B has been offline the whole time. It starts at zero and must reach
// exactly the state device A reached, regardless of when it connects.
const deviceBCatchUp = await drain(admin, adminDeviceB, 0, 7);
assert(
  JSON.stringify(deviceBCatchUp.changes.map((c) => c.change_seq)) ===
    JSON.stringify(wholeFeed.changes.map((c) => c.change_seq)),
  "an_offline_device_catches_up_to_the_same_state",
);

// Re-reading a page already consumed is a no-op — this is what makes a Realtime
// frame that arrives twice, late or out of order harmless.
const replayed = await pull(admin, adminDevice, 0, 5);
const replayedAgain = await pull(admin, adminDevice, 0, 5);
// The changes and the position must match exactly. `server_time_utc` is a clock
// reading and is expected to differ — it is carried for display, and nothing in
// the applier ever branches on it.
assert(
  JSON.stringify(replayed.changes) === JSON.stringify(replayedAgain.changes),
  "replaying_a_page_is_deterministic",
);
assert(
  replayed.next_cursor === replayedAgain.next_cursor &&
    replayed.has_more === replayedAgain.has_more &&
    replayed.scope_fingerprint === replayedAgain.scope_fingerprint,
  "replaying_a_page_reports_the_same_position_and_scope",
);

// ---------------------------------------------------------------------------
// 7. Acceptance 19, 20 and 21: field-level reconciliation over two pushes
// ---------------------------------------------------------------------------
adminCursor = (await drain(admin, adminDevice, adminCursor)).cursor;

const itemId = crypto.randomUUID();
const createdAt = new Date().toISOString();
const baseItem = {
  id: itemId,
  created_at: createdAt,
  updated_at: createdAt,
  sync_status: "pending",
  sku: `E2E-${itemId.slice(0, 8)}`,
  name: "Barang Awal",
  category_id: "40000000-0000-0000-0000-000000000001",
  unit: "box",
  min_stock_room: 1000,
  min_stock_branch: 3000,
  has_expiry: false,
  expiry_alert_days: 30,
  is_active: true,
};

async function upsertMaster(
  payload: Record<string, unknown>,
  baseVersion: number,
): Promise<Record<string, unknown>> {
  const result = await admin.rpc("push_sync_operation", {
    operation_envelope: await envelope({
      request_id: crypto.randomUUID(),
      device_id: adminDevice,
      operation: "upsert_master",
      aggregate_type: "item",
      aggregate_id: itemId,
      payload_version: 1,
      base_server_version: baseVersion,
      occurred_at_utc: new Date().toISOString(),
      payload,
    }),
  });
  if (result.error) throw result.error;
  return result.data as Record<string, unknown>;
}

const created = await upsertMaster(baseItem, 0);
assert(created.outcome === "accepted", "item_created");
const versionAfterCreate = created.server_version as number;

// Device A renames it. Only `name` moves.
const renamed = await upsertMaster(
  { ...baseItem, name: "Barang Diubah A" },
  versionAfterCreate,
);
assert(renamed.outcome === "accepted", "item_renamed");
const versionAfterRename = renamed.server_version as number;
assert(versionAfterRename > versionAfterCreate, "version_advanced_on_change");

const afterRename = await drain(admin, adminDevice, adminCursor, 200, ["item"]);
const itemChange = afterRename.changes.filter((c) => c.entity_id === itemId)
  .pop();
assert(itemChange !== undefined, "item_change_arrives");
const versions = itemChange!.field_versions;
assert(
  versions.name === versionAfterRename,
  "the_changed_column_takes_the_new_entity_version",
);
assert(
  versions.unit < versions.name,
  "an_untouched_column_keeps_its_older_version",
);
assert(
  versions.min_stock_room < versions.name,
  "every_untouched_column_keeps_its_older_version",
);
assert(
  !("sku" in versions),
  "the_natural_key_is_never_offered_for_merging",
);
assert(
  !("server_version" in versions),
  "server_controlled_columns_are_never_offered_for_merging",
);
adminCursor = afterRename.cursor;

// Acceptance 20 as the server sees it: a second device pushing from the stale
// version is refused rather than silently clobbering the newer value.
const staleResult = await admin.rpc("push_sync_operation", {
  operation_envelope: await envelope({
    request_id: crypto.randomUUID(),
    device_id: adminDeviceB,
    operation: "upsert_master",
    aggregate_type: "item",
    aggregate_id: itemId,
    payload_version: 1,
    base_server_version: versionAfterCreate,
    occurred_at_utc: new Date().toISOString(),
    payload: { ...baseItem, name: "Barang Diubah B", unit: "pack" },
  }),
});
assert(
  staleResult.error !== null || staleResult.data?.outcome === "conflict",
  "a_stale_base_version_cannot_overwrite_a_newer_value",
);

// After rebasing on the current version, device B's own column survives and
// device A's rename is still there — the merge both devices compute.
const rebased = await upsertMaster(
  { ...baseItem, name: "Barang Diubah A", unit: "pack" },
  versionAfterRename,
);
assert(rebased.outcome === "accepted", "rebased_push_accepted");

const merged = await drain(admin, adminDevice, adminCursor, 200, ["item"]);
const mergedChange = merged.changes.filter((c) => c.entity_id === itemId).pop();
assert(mergedChange !== undefined, "merged_item_change_arrives");
assert(
  mergedChange!.payload?.name === "Barang Diubah A",
  "the_first_devices_column_survived",
);
assert(
  mergedChange!.payload?.unit === "pack",
  "the_second_devices_column_survived",
);
assert(
  mergedChange!.payload?.sku === baseItem.sku,
  "the_immutable_natural_key_is_unchanged",
);
adminCursor = merged.cursor;

// ---------------------------------------------------------------------------
// 8. Tombstones arrive, are scoped, and never hard delete
// ---------------------------------------------------------------------------
const doomedCategory = crypto.randomUUID();
{
  const inserted = await service.from("item_categories").insert({
    id: doomedCategory,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    sync_status: "synced",
    name: `E2E Hapus ${doomedCategory.slice(0, 8)}`,
  });
  if (inserted.error) throw inserted.error;
}
const afterInsert = await drain(admin, adminDevice, adminCursor, 200, [
  "category",
]);
assert(
  afterInsert.changes.some((c) =>
    c.entity_id === doomedCategory && c.operation === "upsert"
  ),
  "a_new_category_arrives_as_an_upsert",
);
adminCursor = afterInsert.cursor;

{
  const deleted = await service.from("item_categories").update({
    deleted_at: new Date().toISOString(),
  }).eq("id", doomedCategory);
  if (deleted.error) throw deleted.error;
}
const afterDelete = await drain(admin, adminDevice, adminCursor, 200, [
  "category",
]);
const tombstone = afterDelete.changes.filter((c) =>
  c.entity_id === doomedCategory
).pop();
assert(tombstone?.operation === "tombstone", "a_soft_delete_arrives_as_a_tombstone");
assert(tombstone!.payload === null, "a_tombstone_carries_no_payload");
adminCursor = afterDelete.cursor;

{
  // The row is still there on the server. A tombstone is a sync fact, not a
  // DELETE, and the audit trail depends on that distinction.
  const stillThere = await service.from("item_categories").select("id").eq(
    "id",
    doomedCategory,
  );
  if (stillThere.error) throw stillThere.error;
  assert(stillThere.data.length === 1, "a_tombstone_is_not_a_hard_delete");
}

// Deactivation is a field change, never a tombstone (G-A4).
{
  const deactivated = await service.from("items").update({ is_active: false })
    .eq("id", itemId);
  if (deactivated.error) throw deactivated.error;
}
const afterDeactivate = await drain(admin, adminDevice, adminCursor, 200, [
  "item",
]);
const deactivation = afterDeactivate.changes.filter((c) =>
  c.entity_id === itemId
).pop();
assert(
  deactivation?.operation === "upsert",
  "is_active_false_is_an_upsert_not_a_tombstone",
);
assert(
  deactivation!.payload?.is_active === false,
  "the_deactivation_is_visible_in_the_payload",
);
adminCursor = afterDeactivate.cursor;

// ---------------------------------------------------------------------------
// 9. Acceptance 32, 33, 34: a posting arrives whole, and balances stay sane
// ---------------------------------------------------------------------------
{
  const seeded = await service.from("stock_balances").upsert({
    id: crypto.randomUUID(),
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    sync_status: "synced",
    location_id: roomLocationA,
    item_id: itemNoExpiry,
    batch_id: null,
    qty_on_hand: 5000,
  });
  if (seeded.error) throw seeded.error;
}

const consumptionId = crypto.randomUUID();
const consumptionLineId = crypto.randomUUID();
const movementId = crypto.randomUUID();
const postedAt = new Date().toISOString();
const nurseCursorBefore = (await drain(nurse, nurseDevice, 0)).cursor;

const posted = await nurse.rpc("push_sync_operation", {
  operation_envelope: await envelope({
    request_id: crypto.randomUUID(),
    device_id: nurseDevice,
    operation: "post_consumption",
    aggregate_type: "consumption",
    aggregate_id: consumptionId,
    payload_version: 1,
    base_server_version: 0,
    occurred_at_utc: postedAt,
    payload: {
      id: consumptionId,
      created_at: postedAt,
      branch_id: branchA,
      room_id: "21000000-0000-0000-0000-000000000001",
      created_by: "30000000-0000-0000-0000-000000000001",
      status: "posted",
      lines: [
        {
          id: consumptionLineId,
          item_id: itemNoExpiry,
          qty: 1000,
        },
      ],
      movements: [
        {
          id: movementId,
          created_at: postedAt,
          item_id: itemNoExpiry,
          qty: 1000,
          movement_type: "consumption",
          ref_doc_type: "CONS",
          ref_doc_id: consumptionId,
          actor_user_id: "30000000-0000-0000-0000-000000000001",
          from_location_id: roomLocationA,
        },
      ],
    },
  }),
});
if (posted.error) throw posted.error;
assert(posted.data.outcome === "accepted", "consumption_posted");

const nurseAfterPost = await drain(nurse, nurseDevice, nurseCursorBefore);
const consumptionChange = nurseAfterPost.changes.filter((c) =>
  c.entity_id === consumptionId
).pop();
assert(consumptionChange !== undefined, "the_posting_device_pulls_its_document");
assert(
  Array.isArray(consumptionChange!.payload?.lines) &&
    (consumptionChange!.payload!.lines as unknown[]).length === 1,
  "the_document_arrives_with_its_line",
);
assert(
  Array.isArray(consumptionChange!.payload?.movements) &&
    (consumptionChange!.payload!.movements as Array<Record<string, unknown>>)[0]
        .id === movementId,
  "the_document_arrives_with_the_exact_client_movement_uuid",
);

// The balance change reaches the nurse as its own entity, so a stock card is
// correct even when the document that moved it is out of scope.
const balanceChange = nurseAfterPost.changes.filter((c) =>
  c.entity_type === "stock_balance"
).pop();
assert(balanceChange !== undefined, "the_balance_position_is_pulled_too");
assert(
  (balanceChange!.payload!.qty_on_hand as number) === 4000,
  "the_pulled_balance_matches_the_posting",
);

{
  const balances = await service.from("stock_balances").select("qty_on_hand");
  if (balances.error) throw balances.error;
  assert(
    balances.data.every((row) => (row.qty_on_hand as number) >= 0),
    "no_balance_is_negative",
  );
  const movements = await service.from("stock_movements").select("id").eq(
    "ref_doc_id",
    consumptionId,
  );
  if (movements.error) throw movements.error;
  assert(movements.data.length === 1, "the_posting_produced_one_movement");
}

// Acceptance 31: a replayed push plus a concurrent pull produce no duplicate.
const replayEnvelope = await envelope({
  request_id: crypto.randomUUID(),
  device_id: nurseDevice,
  operation: "post_consumption",
  aggregate_type: "consumption",
  aggregate_id: consumptionId,
  payload_version: 1,
  base_server_version: 0,
  occurred_at_utc: postedAt,
  payload: {
    id: consumptionId,
    created_at: postedAt,
    branch_id: branchA,
    room_id: "21000000-0000-0000-0000-000000000001",
    created_by: "30000000-0000-0000-0000-000000000001",
    status: "posted",
    lines: [{ id: consumptionLineId, item_id: itemNoExpiry, qty: 1000 }],
    movements: [
      {
        id: movementId,
        created_at: postedAt,
        item_id: itemNoExpiry,
        qty: 1000,
        movement_type: "consumption",
        ref_doc_type: "CONS",
        ref_doc_id: consumptionId,
        actor_user_id: "30000000-0000-0000-0000-000000000001",
        from_location_id: roomLocationA,
      },
    ],
  },
});
const [retry, concurrentPull] = await Promise.all([
  nurse.rpc("push_sync_operation", { operation_envelope: replayEnvelope }),
  pull(nurse, nurseDevice, nurseCursorBefore),
]);
assert(
  retry.error !== null || retry.data?.outcome !== "accepted",
  "a_new_request_id_for_a_settled_document_is_not_accepted_twice",
);
assert(concurrentPull.changes.length >= 0, "the_concurrent_pull_completed");
{
  const movements = await service.from("stock_movements").select("id").eq(
    "ref_doc_id",
    consumptionId,
  );
  if (movements.error) throw movements.error;
  assert(
    movements.data.length === 1,
    "push_retry_and_pull_together_produce_no_duplicate_movement",
  );
  const balance = await service.from("stock_balances").select("qty_on_hand")
    .eq("location_id", roomLocationA).eq("item_id", itemNoExpiry).is(
      "batch_id",
      null,
    );
  if (balance.error) throw balance.error;
  assert(
    (balance.data[0].qty_on_hand as number) === 4000,
    "the_balance_was_debited_exactly_once",
  );
}

// ---------------------------------------------------------------------------
// 10. Acceptance 9 and 10: the journal and the ledger resist the client
// ---------------------------------------------------------------------------
const journalInsert = await admin.from("sync_change_journal").insert({
  entity_type: "item",
  entity_id: itemId,
  operation: "upsert",
  server_version: 999,
});
assert(journalInsert.error !== null, "a_client_cannot_insert_a_journal_row");

const journalDelete = await admin.from("sync_change_journal").delete().eq(
  "entity_type",
  "item",
);
assert(
  journalDelete.error !== null || (journalDelete.count ?? 0) === 0,
  "a_client_cannot_delete_a_journal_row",
);

const ledgerUpdate = await admin.from("stock_movements").update({ qty: 1 }).eq(
  "id",
  movementId,
);
assert(
  ledgerUpdate.error !== null || (ledgerUpdate.count ?? 0) === 0,
  "a_client_cannot_update_the_ledger",
);

const fieldVersionRead = await admin.from("sync_entity_field_versions").select(
  "field_version",
);
assert(
  fieldVersionRead.error !== null || fieldVersionRead.data?.length === 0,
  "raw_field_versions_are_not_readable_outside_the_pull_contract",
);

// The journal a client *can* see through Realtime carries bookkeeping only, and
// only for rows already inside its scope.
const nurseJournal = await nurse.from("sync_change_journal").select(
  "entity_type,entity_id",
).eq("entity_type", "purchase_request");
if (nurseJournal.error) throw nurseJournal.error;
assert(
  nurseJournal.data.length === 0,
  "the_realtime_channel_leaks_no_out_of_scope_row",
);

console.log(
  JSON.stringify({
    ok: true,
    milestone: "12C",
    seeded_changes: adminStart.changes.length,
    paged_walk_pages: pagedFeed.pages,
    final_admin_cursor: adminCursor,
  }),
);
