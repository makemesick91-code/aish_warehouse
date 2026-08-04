// Namespaced fixture bootstrap for the Milestone 12C staging harnesses.
//
// Every row a staging run creates carries a per-run token in a natural key, and
// cleanup matches on that token alone. A run therefore cannot remove a row it
// did not create, which is the property that makes it safe to point these
// harnesses at a shared staging project rather than a throwaway one.
//
// Cleanup is not a `DELETE` sweep, deliberately. `stock_movements` and
// `export_logs` are append-only at the server (`reject_immutable_mutation`) and
// domain users cannot be deleted at all (`reject_domain_user_delete`), because
// they are historical business actors. Removing them would be a schema-level
// lie about what happened. So fixtures are retired the way the product retires
// master data — `is_active = false` and `deleted_at` set, which is a tombstone
// in the feed and an intentional part of what the harnesses assert. Only the
// rows with no audit value at all are hard-deleted: sync operations, conflicts,
// devices, and the throwaway Auth identities.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { redact, safeError, safeLog, type StagingTarget } from "./staging_guard.ts";

export type FixtureActor = {
  readonly key: string;
  readonly authUserId: string;
  readonly domainUserId: string;
  readonly email: string;
  readonly role: "perawat" | "kepala_cabang" | "warehouse" | "super_admin";
  readonly branchId: string | null;
  readonly isActive: boolean;
};

export type FixtureSet = {
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
  readonly itemPlain: string;
  readonly itemExpiring: string;
  readonly batchId: string;
  readonly actors: Record<string, FixtureActor>;
};

const ROLE_PLAN: ReadonlyArray<{
  key: string;
  role: FixtureActor["role"];
  branch: "A" | "B" | null;
  active: boolean;
}> = [
  { key: "nurseA", role: "perawat", branch: "A", active: true },
  { key: "headA", role: "kepala_cabang", branch: "A", active: true },
  { key: "nurseB", role: "perawat", branch: "B", active: true },
  { key: "headB", role: "kepala_cabang", branch: "B", active: true },
  { key: "warehouse", role: "warehouse", branch: null, active: true },
  { key: "admin", role: "super_admin", branch: null, active: true },
  { key: "inactiveA", role: "perawat", branch: "A", active: false },
];

function nowIso(): string {
  return new Date().toISOString();
}

function base(): Record<string, string> {
  const stamp = nowIso();
  return {
    created_at: stamp,
    updated_at: stamp,
    sync_status: "synced",
  };
}

export function fixtureToken(): string {
  return crypto.randomUUID().replaceAll("-", "").slice(0, 12);
}

export class StagingFixtures {
  private constructor(
    private readonly service: SupabaseClient,
    readonly set: FixtureSet,
    private readonly password: string,
    private readonly url: string,
    private readonly anonKey: string,
  ) {}

  static async create(
    target: StagingTarget,
    prefix: string,
  ): Promise<StagingFixtures> {
    if (!target.serviceRoleKey) throw new Error("fixtures_require_service_role");
    if (!target.fixturePassword) throw new Error("fixtures_require_password");
    const service = createClient(target.url, target.serviceRoleKey, {
      auth: { persistSession: false },
    });
    const token = fixtureToken();
    const namespace = `${prefix}-${token}`;
    safeLog(`fixtures    = ${namespace}`);

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
      itemPlain: crypto.randomUUID(),
      itemExpiring: crypto.randomUUID(),
      batchId: crypto.randomUUID(),
    };

    const fail = (label: string, error: unknown) => {
      throw new Error(`fixture_setup_failed:${label}:${redact(error)}`);
    };

    const branches = await service.from("branches").insert([
      { ...base(), id: ids.branchA, code: `S12C${token}A`, name: `${namespace} A`, address: namespace, is_active: true },
      { ...base(), id: ids.branchB, code: `S12C${token}B`, name: `${namespace} B`, address: namespace, is_active: true },
    ]);
    if (branches.error) fail("branches", branches.error);

    const rooms = await service.from("rooms").insert([
      { ...base(), id: ids.roomA, branch_id: ids.branchA, code: "R1", name: `${namespace} room A`, is_active: true },
      { ...base(), id: ids.roomB, branch_id: ids.branchB, code: "R1", name: `${namespace} room B`, is_active: true },
    ]);
    if (rooms.error) fail("rooms", rooms.error);

    const locations = await service.from("stock_locations").insert([
      { ...base(), id: ids.locationWarehouse, type: "warehouse", branch_id: null, room_id: null, name: `${namespace} warehouse` },
      { ...base(), id: ids.locationBranchA, type: "branch_store", branch_id: ids.branchA, room_id: null, name: `${namespace} store A` },
      { ...base(), id: ids.locationBranchB, type: "branch_store", branch_id: ids.branchB, room_id: null, name: `${namespace} store B` },
      { ...base(), id: ids.locationRoomA, type: "room", branch_id: ids.branchA, room_id: ids.roomA, name: `${namespace} room store A` },
      { ...base(), id: ids.locationRoomB, type: "room", branch_id: ids.branchB, room_id: ids.roomB, name: `${namespace} room store B` },
    ]);
    if (locations.error) fail("stock_locations", locations.error);

    const category = await service.from("item_categories").insert({
      ...base(), id: ids.categoryId, name: `${namespace} category`,
    });
    if (category.error) fail("item_categories", category.error);

    const items = await service.from("items").insert([
      { ...base(), id: ids.itemPlain, sku: `S12C-${token}-1`, name: `${namespace} plain`, category_id: ids.categoryId, unit: "pcs", min_stock_room: 10, min_stock_branch: 30, has_expiry: false, expiry_alert_days: 30, is_active: true },
      { ...base(), id: ids.itemExpiring, sku: `S12C-${token}-2`, name: `${namespace} expiring`, category_id: ids.categoryId, unit: "box", min_stock_room: 10, min_stock_branch: 30, has_expiry: true, expiry_alert_days: 30, is_active: true },
    ]);
    if (items.error) fail("items", items.error);

    const batch = await service.from("item_batches").insert({
      ...base(), id: ids.batchId, item_id: ids.itemExpiring,
      batch_no: `B-${token}`, expiry_date: "2027-12-31",
    });
    if (batch.error) fail("item_batches", batch.error);

    const actors: Record<string, FixtureActor> = {};
    for (const plan of ROLE_PLAN) {
      const email = `${token}.${plan.key.toLowerCase()}@aish-staging.invalid`;
      const created = await service.auth.admin.createUser({
        email,
        password: target.fixturePassword,
        email_confirm: true,
      });
      if (created.error || !created.data.user) {
        fail(`auth_user_${plan.key}`, created.error);
      }
      const authUserId = created.data.user!.id;
      const domainUserId = crypto.randomUUID();
      const branchId = plan.branch === "A"
        ? ids.branchA
        : plan.branch === "B"
        ? ids.branchB
        : null;
      const domain = await service.from("users").insert({
        ...base(),
        id: domainUserId,
        full_name: `${namespace} ${plan.key}`,
        email,
        role: plan.role,
        branch_id: branchId,
        is_active: plan.active,
      });
      if (domain.error) fail(`domain_user_${plan.key}`, domain.error);
      const link = await service.from("user_auth_links").insert({
        auth_user_id: authUserId,
        user_id: domainUserId,
      });
      if (link.error) fail(`link_${plan.key}`, link.error);
      actors[plan.key] = {
        key: plan.key,
        authUserId,
        domainUserId,
        email,
        role: plan.role,
        branchId,
        isActive: plan.active,
      };
    }

    return new StagingFixtures(
      service,
      { namespace, token, ...ids, actors },
      target.fixturePassword,
      target.url,
      target.anonKey,
    );
  }

  /// The operator client, for the harness steps that have to stand in for
  /// "something else changed the server". Never used where an actor's own view
  /// is what is under test — a service-role read bypasses RLS and would turn
  /// every isolation assertion into a tautology.
  serviceClient(): SupabaseClient {
    return this.service;
  }

  /// A real authenticated session over HTTPS — the same path the app takes.
  /// Nothing in the harnesses is allowed to assert against a service-role client
  /// where an actor's own view is what is being tested.
  async signIn(actorKey: string): Promise<SupabaseClient> {
    const actor = this.set.actors[actorKey];
    if (!actor) throw new Error(`fixture_actor_unknown:${actorKey}`);
    const client = createClient(this.url, this.anonKey, {
      auth: { persistSession: false },
    });
    const result = await client.auth.signInWithPassword({
      email: actor.email,
      password: this.password,
    });
    if (result.error) {
      throw new Error(`fixture_sign_in_failed:${actorKey}:${redact(result.error)}`);
    }
    return client;
  }

  /// The device id is chosen by the client and registered against the session's
  /// own actor, so a harness cannot accidentally borrow another actor's device —
  /// which is one of the refusals the pull contract is asserted on.
  async registerDevice(client: SupabaseClient, label: string): Promise<string> {
    const deviceId = crypto.randomUUID();
    const result = await client.rpc("register_sync_device", {
      device_id: deviceId,
      requested_app_install_id: `${this.set.token}-${label}`,
      requested_display_label: `${this.set.namespace}-${label}`,
    });
    if (result.error) {
      throw new Error(`fixture_device_failed:${label}:${redact(result.error)}`);
    }
    return deviceId;
  }

  /// Retires everything this run created. Never throws: a cleanup fault must
  /// not mask the test result that preceded it, so it is reported and counted.
  async cleanup(): Promise<{ ok: boolean; problems: string[] }> {
    const problems: string[] = [];
    const note = (label: string, error: unknown) => {
      if (error) problems.push(`${label}:${redact(error)}`);
    };
    const actorIds = Object.values(this.set.actors).map((a) => a.domainUserId);
    const stamp = nowIso();

    const devices = await this.service.from("sync_devices").select("id")
      .in("actor_user_id", actorIds);
    note("device_lookup", devices.error);
    const deviceIds = (devices.data ?? []).map((row) => row.id as string);

    if (deviceIds.length > 0) {
      note(
        "sync_operations",
        (await this.service.from("sync_operations").delete().in("device_id", deviceIds)).error,
      );
    }
    note(
      "sync_conflicts",
      (await this.service.from("sync_conflicts").delete().in("actor_user_id", actorIds)).error,
    );
    if (deviceIds.length > 0) {
      note(
        "sync_devices",
        (await this.service.from("sync_devices").delete().in("id", deviceIds)).error,
      );
    }

    // Domain rows are retired, not removed. Order matters only for readability
    // here — soft deletion has no FK consequences.
    const retire = async (
      table: string,
      ids: string[],
      withActiveFlag: boolean,
    ) => {
      if (ids.length === 0) return;
      const patch: Record<string, unknown> = {
        deleted_at: stamp,
        updated_at: stamp,
      };
      if (withActiveFlag) patch.is_active = false;
      note(table, (await this.service.from(table).update(patch).in("id", ids)).error);
    };

    await retire("stock_balances", await this.balanceIds(), false);
    await retire("item_batches", [this.set.batchId], false);
    await retire("items", [this.set.itemPlain, this.set.itemExpiring], true);
    await retire("item_categories", [this.set.categoryId], false);
    await retire("stock_locations", [
      this.set.locationWarehouse, this.set.locationBranchA,
      this.set.locationBranchB, this.set.locationRoomA, this.set.locationRoomB,
    ], false);
    await retire("rooms", [this.set.roomA, this.set.roomB], true);
    await retire("users", actorIds, true);
    await retire("branches", [this.set.branchA, this.set.branchB], true);

    // The Auth identity is the one thing with no audit value and a real cost to
    // leaving behind: it is a credential. `user_auth_links` cascades with it.
    for (const actor of Object.values(this.set.actors)) {
      const removed = await this.service.auth.admin.deleteUser(actor.authUserId);
      note(`auth_user_${actor.key}`, removed.error);
    }

    if (problems.length > 0) {
      safeError(`fixture_cleanup_incomplete: ${problems.join(" | ")}`);
    } else {
      safeLog(`cleanup     = ${this.set.namespace} retired`);
    }
    return { ok: problems.length === 0, problems };
  }

  private async balanceIds(): Promise<string[]> {
    const result = await this.service.from("stock_balances").select("id").in(
      "location_id",
      [
        this.set.locationWarehouse, this.set.locationBranchA,
        this.set.locationBranchB, this.set.locationRoomA, this.set.locationRoomB,
      ],
    );
    return (result.data ?? []).map((row) => row.id as string);
  }
}
