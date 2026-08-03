// The dedicated canary namespace the production harnesses run inside.
//
// Nothing in the production canary is allowed to read, write, or even name a
// real user's data. So the harnesses do not "pick a quiet branch" — they create
// their own: their own branches, their own rooms and locations, their own
// catalogue, and their own throwaway accounts, all carrying a per-run token in
// a natural key. Every retirement matches on the ids this run recorded, so a
// run cannot touch a row it did not create even if it wanted to.
//
// It is small by construction and asserts its own ceiling. Mass fixture
// generation is not something this rollout does against production, so the
// class refuses to create more rows than the fixed plan describes.
//
// Cleanup is retirement, never deletion:
//
//   * domain rows get `deleted_at` and, where the column exists, `is_active =
//     false`. That is exactly how the product retires master data, it appears in
//     the feed as a tombstone, and it leaves the history intact;
//   * `stock_movements`, `sync_operations`, `sync_conflicts` and `sync_devices`
//     are left alone entirely. They are the ledger and the push audit. Deleting
//     the canary's own rows from them would be removing evidence of what the
//     canary did, which is the opposite of what a production change record is
//     for. What was left behind is listed in the report;
//   * the throwaway Auth identities are banned and their passwords rotated to a
//     random value rather than deleted, because deleting an auth user cascades
//     `user_auth_links` — a hard delete of a row that ties a domain actor to a
//     login.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  type ProductionTarget,
  redact,
  safeError,
  safeLog,
} from "./production_guard.ts";

/// The whole plan. Four actors, two branches, one catalogue — the minimum that
/// can demonstrate branch isolation, role scope and a document push.
const ACTOR_PLAN: ReadonlyArray<{
  key: string;
  role: "perawat" | "kepala_cabang" | "warehouse";
  branch: "A" | "B" | null;
}> = [
  { key: "nurseA", role: "perawat", branch: "A" },
  { key: "headA", role: "kepala_cabang", branch: "A" },
  { key: "nurseB", role: "perawat", branch: "B" },
  { key: "warehouse", role: "warehouse", branch: null },
];

/// Hard ceiling on rows this namespace may create. Chosen to be the exact size
/// of the plan plus a small allowance for the documents a harness pushes.
const MAX_CREATED_ROWS = 24;

export type CanaryActor = {
  readonly key: string;
  readonly authUserId: string;
  readonly domainUserId: string;
  readonly email: string;
  readonly role: string;
  readonly branchId: string | null;
};

export type CanarySet = {
  readonly namespace: string;
  readonly token: string;
  readonly branchA: string;
  readonly branchB: string;
  readonly roomA: string;
  readonly roomB: string;
  readonly locationWarehouse: string;
  readonly locationBranchA: string;
  readonly locationBranchB: string;
  readonly locationRoomA: string;
  readonly locationRoomB: string;
  readonly categoryId: string;
  readonly itemId: string;
  readonly actors: Record<string, CanaryActor>;
};

type Created = { table: string; id: string; hasActiveFlag: boolean };

function nowIso(): string {
  return new Date().toISOString();
}

function base(): Record<string, string> {
  const stamp = nowIso();
  return { created_at: stamp, updated_at: stamp, sync_status: "synced" };
}

export class ProductionCanaryNamespace {
  private readonly created: Created[] = [];

  private constructor(
    private readonly service: SupabaseClient,
    readonly set: CanarySet,
    private readonly password: string,
    private readonly url: string,
    private readonly anonKey: string,
  ) {}

  static async create(
    target: ProductionTarget,
    prefix: string,
  ): Promise<ProductionCanaryNamespace> {
    if (target.mode !== "guarded_write" || target.writeScope !== "canary_namespace") {
      throw new Error("canary_namespace_requires_the_canary_namespace_write_scope");
    }
    if (!target.serviceRoleKey) throw new Error("canary_namespace_requires_service_role");
    if (!target.canaryPassword) throw new Error("canary_namespace_requires_password");

    const service = createClient(target.url, target.serviceRoleKey, {
      auth: { persistSession: false },
    });
    const token = crypto.randomUUID().replaceAll("-", "").slice(0, 10);
    const namespace = `${prefix}-${token}`;
    safeLog(`canary      = ${namespace}`);
    safeLog(`             (a dedicated namespace; no real user data is touched)`);

    const ids = {
      branchA: crypto.randomUUID(),
      branchB: crypto.randomUUID(),
      roomA: crypto.randomUUID(),
      roomB: crypto.randomUUID(),
      locationWarehouse: crypto.randomUUID(),
      locationBranchA: crypto.randomUUID(),
      locationBranchB: crypto.randomUUID(),
      locationRoomA: crypto.randomUUID(),
      locationRoomB: crypto.randomUUID(),
      categoryId: crypto.randomUUID(),
      itemId: crypto.randomUUID(),
    };

    const instance = new ProductionCanaryNamespace(
      service,
      { namespace, token, ...ids, actors: {} },
      target.canaryPassword,
      target.url,
      target.anonKey,
    );

    const fail = (label: string, error: unknown): never => {
      throw new Error(`canary_setup_failed:${label}:${redact(error)}`);
    };

    // Every name and code carries CANARY in plain text, so anyone looking at
    // production data can tell at a glance that these rows are not a customer's.
    const branches = await service.from("branches").insert([
      {
        ...base(), id: ids.branchA, code: `CANARY-${token}-A`,
        name: `CANARY ${namespace} A`, address: `CANARY ${namespace}`, is_active: true,
      },
      {
        ...base(), id: ids.branchB, code: `CANARY-${token}-B`,
        name: `CANARY ${namespace} B`, address: `CANARY ${namespace}`, is_active: true,
      },
    ]);
    if (branches.error) fail("branches", branches.error);
    instance.track("branches", ids.branchA, true);
    instance.track("branches", ids.branchB, true);

    const rooms = await service.from("rooms").insert([
      {
        ...base(), id: ids.roomA, branch_id: ids.branchA, code: "CANARY-R1",
        name: `CANARY ${namespace} room A`, is_active: true,
      },
      {
        ...base(), id: ids.roomB, branch_id: ids.branchB, code: "CANARY-R1",
        name: `CANARY ${namespace} room B`, is_active: true,
      },
    ]);
    if (rooms.error) fail("rooms", rooms.error);
    instance.track("rooms", ids.roomA, true);
    instance.track("rooms", ids.roomB, true);

    const locations = await service.from("stock_locations").insert([
      {
        ...base(), id: ids.locationWarehouse, type: "warehouse",
        branch_id: null, room_id: null, name: `CANARY ${namespace} warehouse`,
      },
      {
        ...base(), id: ids.locationBranchA, type: "branch_store",
        branch_id: ids.branchA, room_id: null, name: `CANARY ${namespace} store A`,
      },
      {
        ...base(), id: ids.locationBranchB, type: "branch_store",
        branch_id: ids.branchB, room_id: null, name: `CANARY ${namespace} store B`,
      },
      {
        ...base(), id: ids.locationRoomA, type: "room",
        branch_id: ids.branchA, room_id: ids.roomA, name: `CANARY ${namespace} room store A`,
      },
      {
        ...base(), id: ids.locationRoomB, type: "room",
        branch_id: ids.branchB, room_id: ids.roomB, name: `CANARY ${namespace} room store B`,
      },
    ]);
    if (locations.error) fail("stock_locations", locations.error);
    for (const id of [
      ids.locationWarehouse, ids.locationBranchA, ids.locationBranchB,
      ids.locationRoomA, ids.locationRoomB,
    ]) instance.track("stock_locations", id, false);

    const category = await service.from("item_categories").insert({
      ...base(), id: ids.categoryId, name: `CANARY ${namespace} category`,
    });
    if (category.error) fail("item_categories", category.error);
    instance.track("item_categories", ids.categoryId, false);

    const item = await service.from("items").insert({
      ...base(), id: ids.itemId, sku: `CANARY-${token}`,
      name: `CANARY ${namespace} item`, category_id: ids.categoryId, unit: "pcs",
      min_stock_room: 0, min_stock_branch: 0, has_expiry: false,
      expiry_alert_days: 30, is_active: true,
    });
    if (item.error) fail("items", item.error);
    instance.track("items", ids.itemId, true);

    const actors: Record<string, CanaryActor> = {};
    for (const plan of ACTOR_PLAN) {
      // `.invalid` is reserved by RFC 2606 and can never be delivered to, so a
      // canary account cannot email a real person even by mistake.
      const email = `canary.${token}.${plan.key.toLowerCase()}@aish-canary.invalid`;
      const account = await service.auth.admin.createUser({
        email, password: target.canaryPassword, email_confirm: true,
      });
      if (account.error || !account.data.user) fail(`auth_user_${plan.key}`, account.error);
      const authUserId = account.data.user!.id;
      const domainUserId = crypto.randomUUID();
      const branchId = plan.branch === "A"
        ? ids.branchA
        : plan.branch === "B"
        ? ids.branchB
        : null;
      const domain = await service.from("users").insert({
        ...base(), id: domainUserId, full_name: `CANARY ${namespace} ${plan.key}`,
        email, role: plan.role, branch_id: branchId, is_active: true,
      });
      if (domain.error) fail(`domain_user_${plan.key}`, domain.error);
      instance.track("users", domainUserId, true);
      const link = await service.from("user_auth_links").insert({
        auth_user_id: authUserId, user_id: domainUserId,
      });
      if (link.error) fail(`link_${plan.key}`, link.error);
      actors[plan.key] = {
        key: plan.key, authUserId, domainUserId, email,
        role: plan.role, branchId,
      };
    }
    (instance.set as { actors: Record<string, CanaryActor> }).actors = actors;

    safeLog(`canary rows = ${instance.created.length} created (ceiling ${MAX_CREATED_ROWS})`);
    return instance;
  }

  /// Records a row so it is retired with the rest. Harnesses call this for the
  /// documents they push, so nothing a canary creates escapes the retirement
  /// list — and the ceiling still applies.
  track(table: string, id: string, hasActiveFlag: boolean): void {
    if (this.created.length >= MAX_CREATED_ROWS) {
      throw new Error(
        `canary_row_ceiling_exceeded: ${MAX_CREATED_ROWS} rows is the whole plan; ` +
          "mass fixture generation is not a production operation",
      );
    }
    this.created.push({ table, id, hasActiveFlag });
  }

  createdRows(): ReadonlyArray<Created> {
    return this.created;
  }

  /// The operator client, for the harness steps that have to stand in for
  /// "something else changed the server". Never used where an actor's own view
  /// is what is under test — a service-role read bypasses RLS and would turn
  /// every isolation assertion into a tautology.
  serviceClient(): SupabaseClient {
    return this.service;
  }

  /// A real authenticated session over HTTPS — the same path the app takes.
  async signIn(actorKey: string): Promise<SupabaseClient> {
    const actor = this.set.actors[actorKey];
    if (!actor) throw new Error(`canary_actor_unknown:${actorKey}`);
    const client = createClient(this.url, this.anonKey, {
      auth: { persistSession: false },
    });
    const result = await client.auth.signInWithPassword({
      email: actor.email, password: this.password,
    });
    if (result.error) {
      throw new Error(`canary_sign_in_failed:${actorKey}:${redact(result.error)}`);
    }
    return client;
  }

  /// The device id is chosen by the client and registered against the session's
  /// own actor, so a harness cannot borrow another actor's device — which is one
  /// of the refusals the pull contract is asserted on.
  async registerDevice(client: SupabaseClient, label: string): Promise<string> {
    const deviceId = crypto.randomUUID();
    const result = await client.rpc("register_sync_device", {
      device_id: deviceId,
      requested_app_install_id: `canary-${this.set.token}-${label}`,
      requested_display_label: `CANARY ${this.set.namespace} ${label}`,
    });
    if (result.error) {
      throw new Error(`canary_device_failed:${label}:${redact(result.error)}`);
    }
    return deviceId;
  }

  /// Retires everything this run created. Never throws: a retirement fault must
  /// not mask the result that preceded it, so it is reported and counted.
  async retire(): Promise<{
    ok: boolean;
    problems: string[];
    retired: number;
    left_in_place: string[];
  }> {
    const problems: string[] = [];
    const note = (label: string, error: unknown) => {
      if (error) problems.push(`${label}:${redact(error)}`);
    };
    const stamp = nowIso();

    // Retire in reverse creation order for readability. Soft deletion has no FK
    // consequences, so the order is not load-bearing.
    const byTable = new Map<string, { ids: string[]; hasActiveFlag: boolean }>();
    for (const row of [...this.created].reverse()) {
      const entry = byTable.get(row.table) ??
        { ids: [], hasActiveFlag: row.hasActiveFlag };
      entry.ids.push(row.id);
      entry.hasActiveFlag = entry.hasActiveFlag || row.hasActiveFlag;
      byTable.set(row.table, entry);
    }

    let retired = 0;
    for (const [table, entry] of byTable) {
      const patch: Record<string, unknown> = { deleted_at: stamp, updated_at: stamp };
      if (entry.hasActiveFlag) patch.is_active = false;
      const result = await this.service.from(table).update(patch).in("id", entry.ids);
      note(table, result.error);
      if (!result.error) retired += entry.ids.length;
    }

    // The Auth identity is the one thing with a real cost to leaving usable: it
    // is a credential. Banning it and rotating the password makes it unusable
    // without hard-deleting the row that ties it to a domain actor.
    for (const actor of Object.values(this.set.actors)) {
      const banned = await this.service.auth.admin.updateUserById(actor.authUserId, {
        password: crypto.randomUUID() + crypto.randomUUID(),
        ban_duration: "876000h",
      });
      note(`auth_user_${actor.key}`, banned.error);
    }

    const leftInPlace = [
      "sync_devices — the canary's device registrations, kept as evidence",
      "sync_operations — the canary's push audit, kept as evidence",
      "sync_conflicts — kept as evidence",
      "sync_change_journal — append-only by design; the canary's entries stay",
      "stock_movements — ledger; the canary posts none, and would not remove any",
    ];

    if (problems.length > 0) {
      safeError(`canary_retirement_incomplete: ${problems.join(" | ")}`);
    } else {
      safeLog(`retired     = ${this.set.namespace}: ${retired} row(s) deactivated`);
    }
    return { ok: problems.length === 0, problems, retired, left_in_place: leftInPlace };
  }
}
