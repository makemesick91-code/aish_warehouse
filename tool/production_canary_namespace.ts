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
// Setup is fail-closed. `create()` builds the instance *before* the first
// remote write, records every resource the instant the server confirms it, and
// runs the whole setup inside a try that retires a partial namespace on any
// fault. A setup that dies halfway therefore leaves nothing usable behind, and
// the caller still sees the original error — with the cleanup outcome attached
// rather than substituted.
//
// Cleanup is retirement, never deletion:
//
//   * domain rows get `deleted_at` and, where the column exists, `is_active =
//     false`. That is exactly how the product retires master data, it appears in
//     the feed as a tombstone, and it leaves the history intact. The update
//     returns the ids it actually matched, and a row that did not come back is
//     reported as missing rather than counted as retired;
//   * `stock_movements`, `sync_operations`, `sync_conflicts`, `sync_devices` and
//     `sync_change_journal` are left alone entirely. They are the ledger and the
//     push audit. Deleting the canary's own rows from them would be removing
//     evidence of what the canary did, which is the opposite of what a
//     production change record is for. What was left behind is listed in the
//     report;
//   * `user_auth_links` has no `deleted_at`, no `updated_at` and no `is_active`
//     — its primary key is `auth_user_id` and it cascades from `auth.users`.
//     There is no soft-delete for it, so it is left in place and reported. The
//     credential is neutralised at the Auth identity instead;
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

/// Ceilings, split by what they actually bound. One number covering everything
/// hid the fact that the auth identities and the harness's documents grow for
/// different reasons; a breach in one should not be payable out of the other's
/// slack.
///
/// Setup creates exactly 15 domain rows: 2 branches, 2 rooms, 5 stock
/// locations, 1 category, 1 item, 4 domain users. The harnesses add at most 5
/// document rows: 1 stock opname, 1 purchase request, 1 purchase request line,
/// 1 purchase-request/opname link, and one row of slack. Nothing here posts a
/// stock movement and nothing here runs a burst.
const MAX_SETUP_DOMAIN_ROWS = 15;
const MAX_DOCUMENT_ROWS = 5;
const MAX_TRACKED_DOMAIN_ROWS = MAX_SETUP_DOMAIN_ROWS + MAX_DOCUMENT_ROWS;
const MAX_AUTH_USERS = ACTOR_PLAN.length;

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

/// A soft-deletable row this run created. `kind` is what the ceilings are
/// counted against.
export type TrackedRow = {
  readonly table: string;
  readonly id: string;
  readonly hasActiveFlag: boolean;
  readonly kind: "setup" | "document";
};

/// An Auth identity that `createUser` confirmed. Recorded the instant the
/// server returns, before the domain user or the auth link exists, because a
/// credential that was created is a credential that has to be neutralised
/// whether or not the rest of the actor was ever finished.
///
/// Deliberately distinct from `CanaryActor`: an actor is an identity that was
/// *fully* configured, and only fully configured actors can sign in.
export type CreatedAuthUser = {
  readonly authUserId: string;
  readonly actorKey: string;
  readonly email: string;
};

/// Something the canary created and is not retiring, with the reason. This is
/// evidence, not an oversight, so it is enumerated rather than summarised.
export type LeftInPlace = {
  readonly resource: string;
  readonly reason: string;
  readonly reference: string;
};

export type CanaryRetirement = {
  readonly ok: boolean;
  readonly reason: string;
  readonly problems: string[];
  /// Distinct ids this run recorded and asked the server to retire.
  readonly requested: number;
  /// Ids the server confirmed it actually updated.
  readonly matched: number;
  /// Rows genuinely retired. Never inferred from `requested`.
  readonly retired: number;
  /// Requested ids the server did not return. Each one is a problem.
  readonly missing: string[];
  /// Ids recorded more than once. A tracking bug, reported rather than hidden.
  readonly duplicates: string[];
  readonly auth_users_created: number;
  readonly auth_users_banned: number;
  readonly auth_users_failed: string[];
  readonly left_in_place: string[];
  readonly left_in_place_detail: LeftInPlace[];
};

/// The narrow set of remote operations the namespace performs. Narrow on
/// purpose: it is the entire surface through which this class can affect
/// production, it contains no delete of any kind, and its retirement primitive
/// cannot express an unfiltered update — the id list is a required argument.
///
/// It is also the seam the failure-injection tests drive, which is the only way
/// to prove the partial-setup cleanup works without creating rows in a real
/// project.
export type CanaryBackend = {
  insert(
    table: string,
    rows: ReadonlyArray<Record<string, unknown>>,
  ): Promise<{ error: unknown }>;
  /// Applies `patch` to exactly `ids` and returns the ids the server reports it
  /// updated. Implementations must not widen the filter.
  softRetire(
    table: string,
    patch: Record<string, unknown>,
    ids: ReadonlyArray<string>,
  ): Promise<{ ids: string[] | null; error: unknown }>;
  createAuthUser(
    email: string,
    password: string,
  ): Promise<{ id: string | null; error: unknown }>;
  /// Bans the identity and rotates its password. Never deletes it.
  disableAuthUser(
    authUserId: string,
    password: string,
  ): Promise<{ error: unknown }>;
};

function nowIso(): string {
  return new Date().toISOString();
}

function base(): Record<string, string> {
  const stamp = nowIso();
  return { created_at: stamp, updated_at: stamp, sync_status: "synced" };
}

/// Enough of an id to correlate against a report, not enough to be a handle.
function maskId(id: string): string {
  return id.length <= 8 ? id : `${id.slice(0, 8)}…`;
}

/// The production implementation of the backend. The only place in this file
/// that talks to Supabase.
function supabaseBackend(service: SupabaseClient): CanaryBackend {
  return {
    async insert(table, rows) {
      const result = await service.from(table).insert(rows as Record<string, unknown>[]);
      return { error: result.error };
    },
    async softRetire(table, patch, ids) {
      // `.in("id", ids)` with an explicit, non-empty id list is the only filter
      // this class ever applies to an update. `.select("id")` is what turns the
      // result from "PostgREST did not complain" into "these rows changed".
      const result = await service.from(table).update(patch).in("id", [...ids])
        .select("id");
      const rows = (result.data ?? []) as Array<{ id: string }>;
      return {
        ids: result.error ? null : rows.map((row) => String(row.id)),
        error: result.error,
      };
    },
    async createAuthUser(email, password) {
      const result = await service.auth.admin.createUser({
        email, password, email_confirm: true,
      });
      return { id: result.data?.user?.id ?? null, error: result.error };
    },
    async disableAuthUser(authUserId, password) {
      const result = await service.auth.admin.updateUserById(authUserId, {
        password, ban_duration: "876000h",
      });
      return { error: result.error };
    },
  };
}

export class ProductionCanaryNamespace {
  /// Soft-deletable rows, recorded the instant the server confirms each one.
  private readonly created: TrackedRow[] = [];
  /// Auth identities, recorded the instant `createUser` returns — see
  /// `CreatedAuthUser`.
  private readonly authIdentities: CreatedAuthUser[] = [];
  /// Rows that exist and cannot be soft-deleted. Reported, never deleted.
  private readonly leftInPlace: LeftInPlace[] = [];
  /// Set once, so two callers racing `retire()` cannot double-ban an identity or
  /// issue a second unfiltered-looking update.
  private retirementPromise: Promise<CanaryRetirement> | null = null;

  private constructor(
    private readonly backend: CanaryBackend,
    private readonly service: SupabaseClient | null,
    readonly set: CanarySet,
    private readonly password: string,
    private readonly url: string,
    private readonly anonKey: string,
  ) {}

  /// Builds the namespace. The instance exists — and is already capable of
  /// retiring whatever it has recorded — before the first remote write, so
  /// there is no window in which a created resource has no owner.
  ///
  /// `options.backend` is the failure-injection seam. It replaces *how* remote
  /// calls are made, never *whether* they are permitted: the target checks below
  /// run first and unconditionally.
  static async create(
    target: ProductionTarget,
    prefix: string,
    options: { backend?: CanaryBackend } = {},
  ): Promise<ProductionCanaryNamespace> {
    if (target.mode !== "guarded_write" || target.writeScope !== "canary_namespace") {
      throw new Error("canary_namespace_requires_the_canary_namespace_write_scope");
    }
    if (!target.serviceRoleKey) throw new Error("canary_namespace_requires_service_role");
    if (!target.canaryPassword) throw new Error("canary_namespace_requires_password");

    const service = options.backend
      ? null
      : createClient(target.url, target.serviceRoleKey, {
        auth: { persistSession: false },
      });
    const backend = options.backend ?? supabaseBackend(service!);

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
      backend,
      service,
      { namespace, token, ...ids, actors: {} },
      target.canaryPassword,
      target.url,
      target.anonKey,
    );

    try {
      await instance.setup(target.canaryPassword);
    } catch (setupError) {
      // The namespace is half-built. Retire what exists before anything else,
      // then surface the original fault — the cleanup outcome is attached to it,
      // not substituted for it, so a caller can never read a setup failure as a
      // setup success.
      const retirement = await instance.retire({ reason: "setup_failure" });
      throw new Error(
        `canary_setup_failed:${redact(setupError)}:` +
          `retirement_ok=${retirement.ok}:` +
          `retired=${retirement.retired}/${retirement.requested}:` +
          `auth_banned=${retirement.auth_users_banned}/${retirement.auth_users_created}:` +
          `left_in_place=${retirement.left_in_place.length}` +
          (retirement.problems.length > 0
            ? `:cleanup_problems=${retirement.problems.join(" | ")}`
            : ""),
      );
    }

    safeLog(
      `canary rows = ${instance.created.length} created ` +
        `(ceiling ${MAX_TRACKED_DOMAIN_ROWS}), ` +
        `${instance.authIdentities.length} auth identity(ies) ` +
        `(ceiling ${MAX_AUTH_USERS})`,
    );
    return instance;
  }

  /// Every remote write of the setup, in order. Each `track*` call sits
  /// immediately after the call that created the thing it records, so the gap
  /// between "exists on the server" and "will be cleaned up" is never wider than
  /// one statement.
  private async setup(password: string): Promise<void> {
    const ids = this.set;
    const token = ids.token;
    const namespace = ids.namespace;

    const fail = (label: string, error: unknown): never => {
      throw new Error(`${label}:${redact(error)}`);
    };

    // Every name and code carries CANARY in plain text, so anyone looking at
    // production data can tell at a glance that these rows are not a customer's.
    const branches = await this.backend.insert("branches", [
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
    this.track("branches", ids.branchA, true);
    this.track("branches", ids.branchB, true);

    const rooms = await this.backend.insert("rooms", [
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
    this.track("rooms", ids.roomA, true);
    this.track("rooms", ids.roomB, true);

    const locations = await this.backend.insert("stock_locations", [
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
    ]) this.track("stock_locations", id, false);

    const category = await this.backend.insert("item_categories", [{
      ...base(), id: ids.categoryId, name: `CANARY ${namespace} category`,
    }]);
    if (category.error) fail("item_categories", category.error);
    this.track("item_categories", ids.categoryId, false);

    const item = await this.backend.insert("items", [{
      ...base(), id: ids.itemId, sku: `CANARY-${token}`,
      name: `CANARY ${namespace} item`, category_id: ids.categoryId, unit: "pcs",
      min_stock_room: 0, min_stock_branch: 0, has_expiry: false,
      expiry_alert_days: 30, is_active: true,
    }]);
    if (item.error) fail("items", item.error);
    this.track("items", ids.itemId, true);

    const actors: Record<string, CanaryActor> = {};
    for (const plan of ACTOR_PLAN) {
      // `.invalid` is reserved by RFC 2606 and can never be delivered to, so a
      // canary account cannot email a real person even by mistake.
      const email = `canary.${token}.${plan.key.toLowerCase()}@aish-canary.invalid`;
      const account = await this.backend.createAuthUser(email, password);
      if (account.error || !account.id) fail(`auth_user_${plan.key}`, account.error);
      // Recorded here, and not one line later: from this point the identity
      // exists on the server, so from this point it is banned and rotated by
      // cleanup — whether or not the two inserts below ever succeed.
      const authUserId = account.id!;
      this.trackAuthUser({ authUserId, actorKey: plan.key, email });

      const domainUserId = crypto.randomUUID();
      const branchId = plan.branch === "A"
        ? ids.branchA
        : plan.branch === "B"
        ? ids.branchB
        : null;
      const domain = await this.backend.insert("users", [{
        ...base(), id: domainUserId, full_name: `CANARY ${namespace} ${plan.key}`,
        email, role: plan.role, branch_id: branchId, is_active: true,
      }]);
      if (domain.error) fail(`domain_user_${plan.key}`, domain.error);
      this.track("users", domainUserId, true);

      const link = await this.backend.insert("user_auth_links", [{
        auth_user_id: authUserId, user_id: domainUserId,
      }]);
      if (link.error) fail(`link_${plan.key}`, link.error);
      // `user_auth_links` has no `deleted_at`, no `updated_at` and no
      // `is_active`, and its primary key is `auth_user_id` rather than `id`. It
      // cannot be soft-deleted and it will not be hard-deleted, so it is
      // recorded as evidence the moment it exists.
      this.trackLeftInPlace({
        resource: "user_auth_links",
        reason:
          "no deleted_at/updated_at/is_active column and no soft-delete contract; " +
          "hard delete refused — the Auth identity is banned and rotated instead",
        reference: `auth_user_id=${maskId(authUserId)} user_id=${maskId(domainUserId)}`,
      });

      // Only now is the actor complete enough to sign in.
      actors[plan.key] = {
        key: plan.key, authUserId, domainUserId, email,
        role: plan.role, branchId,
      };
    }
    (this.set as { actors: Record<string, CanaryActor> }).actors = actors;
  }

  /// Records a row so it is retired with the rest. Harnesses call this for the
  /// documents they push — including child rows, whose ids the client supplies
  /// in the push payload — so nothing a canary creates escapes the retirement
  /// list, and the ceiling still applies.
  track(
    table: string,
    id: string,
    hasActiveFlag: boolean,
    kind: "setup" | "document" = "setup",
  ): void {
    // The narrower ceiling is checked first, so a harness that over-pushes is
    // told which budget it actually broke rather than being handed the generic
    // total — the two are deliberately aligned, and the total alone would
    // always be the one to trip.
    if (
      kind === "document" &&
      this.created.filter((row) => row.kind === "document").length >= MAX_DOCUMENT_ROWS
    ) {
      throw new Error(
        `canary_document_ceiling_exceeded: ${MAX_DOCUMENT_ROWS} document row(s) is the ` +
          "whole plan; the canary pushes one purchase request and posts no movement",
      );
    }
    if (this.created.length >= MAX_TRACKED_DOMAIN_ROWS) {
      throw new Error(
        `canary_row_ceiling_exceeded: ${MAX_TRACKED_DOMAIN_ROWS} rows is the whole plan; ` +
          "mass fixture generation is not a production operation",
      );
    }
    this.created.push({ table, id, hasActiveFlag, kind });
  }

  /// Records a document row a harness pushed. Separate entry point so the
  /// document ceiling is applied by construction rather than by remembering to
  /// pass an argument.
  trackDocument(table: string, id: string, hasActiveFlag = false): void {
    this.track(table, id, hasActiveFlag, "document");
  }

  private trackAuthUser(identity: CreatedAuthUser): void {
    if (this.authIdentities.length >= MAX_AUTH_USERS) {
      throw new Error(
        `canary_auth_user_ceiling_exceeded: ${MAX_AUTH_USERS} identity(ies) is the whole plan`,
      );
    }
    this.authIdentities.push(identity);
  }

  private trackLeftInPlace(entry: LeftInPlace): void {
    this.leftInPlace.push(entry);
  }

  createdRows(): ReadonlyArray<TrackedRow> {
    return this.created;
  }

  /// Auth identities this run created, whether or not their actor was ever
  /// finished. Cleanup works from this list, never from `set.actors`.
  createdAuthUsers(): ReadonlyArray<CreatedAuthUser> {
    return this.authIdentities;
  }

  /// The operator client, for the harness steps that have to stand in for
  /// "something else changed the server". Never used where an actor's own view
  /// is what is under test — a service-role read bypasses RLS and would turn
  /// every isolation assertion into a tautology.
  serviceClient(): SupabaseClient {
    if (!this.service) throw new Error("canary_service_client_unavailable");
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
  ///
  /// Idempotent. `create()` already calls it on a failed setup, and the
  /// harnesses call it from `finally`; running the bans and the updates twice
  /// would be a second set of side effects for no benefit, so the first call's
  /// promise is what every later call receives.
  retire(options: { reason?: string } = {}): Promise<CanaryRetirement> {
    this.retirementPromise ??= this.runRetirement(options.reason ?? "normal_completion");
    return this.retirementPromise;
  }

  private async runRetirement(reason: string): Promise<CanaryRetirement> {
    const problems: string[] = [];
    const note = (label: string, error: unknown) => {
      if (error) problems.push(`${label}:${redact(error)}`);
    };
    const stamp = nowIso();

    // Retire in reverse creation order for readability. Soft deletion has no FK
    // consequences, so the order is not load-bearing.
    const byTable = new Map<string, { ids: string[]; hasActiveFlag: boolean }>();
    const duplicates: string[] = [];
    const seen = new Set<string>();
    for (const row of [...this.created].reverse()) {
      const fingerprint = `${row.table}:${row.id}`;
      if (seen.has(fingerprint)) {
        duplicates.push(fingerprint);
        continue;
      }
      seen.add(fingerprint);
      const entry = byTable.get(row.table) ??
        { ids: [], hasActiveFlag: row.hasActiveFlag };
      entry.ids.push(row.id);
      entry.hasActiveFlag = entry.hasActiveFlag || row.hasActiveFlag;
      byTable.set(row.table, entry);
    }
    if (duplicates.length > 0) {
      problems.push(`duplicate_tracked_ids:${duplicates.join(",")}`);
    }

    let requested = 0;
    let matched = 0;
    let retired = 0;
    const missing: string[] = [];

    for (const [table, entry] of byTable) {
      // An empty id list would make `.in("id", [])` a filter that matches
      // nothing on PostgREST — but relying on that is relying on a client
      // detail to prevent an unfiltered update. Skip instead.
      if (entry.ids.length === 0) continue;
      requested += entry.ids.length;

      const patch: Record<string, unknown> = { deleted_at: stamp, updated_at: stamp };
      if (entry.hasActiveFlag) patch.is_active = false;
      const result = await this.backend.softRetire(table, patch, entry.ids);
      note(table, result.error);
      if (result.error) {
        // The rows were requested and their fate is unknown. They are not
        // retired, and saying otherwise is the bug this replaced.
        for (const id of entry.ids) missing.push(`${table}:${maskId(id)}`);
        continue;
      }

      // What actually changed, compared as a set against what was asked for.
      const returned = new Set(result.ids ?? []);
      const wanted = new Set(entry.ids);
      const confirmed = [...wanted].filter((id) => returned.has(id));
      const absent = [...wanted].filter((id) => !returned.has(id));
      const unexpected = [...returned].filter((id) => !wanted.has(id));

      matched += confirmed.length;
      retired += confirmed.length;
      for (const id of absent) missing.push(`${table}:${maskId(id)}`);
      if (absent.length > 0) {
        problems.push(
          `${table}:retirement_incomplete:` +
            `requested=${entry.ids.length}:matched=${confirmed.length}`,
        );
      }
      if (unexpected.length > 0) {
        // Cannot happen through `.in("id", exactIds)`. If it ever does, the
        // filter is not doing what this class believes it is, and that is a
        // failure — not something to reconcile by widening the search.
        problems.push(
          `${table}:retirement_matched_unrequested_rows:${unexpected.length}`,
        );
      }
    }

    // The Auth identity is the one thing with a real cost to leaving usable: it
    // is a credential. Banning it and rotating the password makes it unusable
    // without hard-deleting the row that ties it to a domain actor.
    //
    // Driven from `authIdentities`, not `set.actors`: an identity whose domain
    // user or auth link never landed is exactly the one that must not be
    // skipped.
    let banned = 0;
    const authFailed: string[] = [];
    for (const identity of this.authIdentities) {
      const result = await this.backend.disableAuthUser(
        identity.authUserId,
        crypto.randomUUID() + crypto.randomUUID(),
      );
      if (result.error) {
        authFailed.push(identity.actorKey);
        note(`auth_user_${identity.actorKey}`, result.error);
        continue;
      }
      banned += 1;
    }

    const leftInPlaceDetail: LeftInPlace[] = [
      {
        resource: "sync_devices",
        reason: "the canary's device registrations, kept as evidence",
        reference: `namespace=${this.set.namespace}`,
      },
      {
        resource: "sync_operations",
        reason: "the canary's push audit, kept as evidence",
        reference: `namespace=${this.set.namespace}`,
      },
      {
        resource: "sync_conflicts",
        reason: "kept as evidence",
        reference: `namespace=${this.set.namespace}`,
      },
      {
        resource: "sync_change_journal",
        reason: "append-only by design; the canary's entries stay",
        reference: `namespace=${this.set.namespace}`,
      },
      {
        resource: "sync_entity_field_versions",
        reason: "server-maintained field version bookkeeping; not the canary's to retire",
        reference: `namespace=${this.set.namespace}`,
      },
      {
        resource: "stock_movements",
        reason: "ledger; the canary posts none, and would not remove any",
        reference: `namespace=${this.set.namespace}`,
      },
      ...this.leftInPlace,
    ];

    const ok = problems.length === 0;
    if (!ok) {
      safeError(`canary_retirement_incomplete: ${problems.join(" | ")}`);
    } else {
      safeLog(
        `retired     = ${this.set.namespace}: ${retired}/${requested} row(s) deactivated, ` +
          `${banned}/${this.authIdentities.length} auth identity(ies) banned`,
      );
    }
    return {
      ok,
      reason,
      problems,
      requested,
      matched,
      retired,
      missing,
      duplicates,
      auth_users_created: this.authIdentities.length,
      auth_users_banned: banned,
      auth_users_failed: authFailed,
      left_in_place: leftInPlaceDetail.map((entry) =>
        `${entry.resource} — ${entry.reason} (${entry.reference})`
      ),
      left_in_place_detail: leftInPlaceDetail,
    };
  }
}

/// The value a harness holds before `retire()` has run. Explicitly *not* an
/// `ok: true` default that could be mistaken for a completed cleanup — nothing
/// was created, nothing was retired, and the reason says so.
export function pendingRetirement(): CanaryRetirement {
  return {
    ok: false,
    reason: "not_run",
    problems: ["retirement_did_not_run"],
    requested: 0,
    matched: 0,
    retired: 0,
    missing: [],
    duplicates: [],
    auth_users_created: 0,
    auth_users_banned: 0,
    auth_users_failed: [],
    left_in_place: [],
    left_in_place_detail: [],
  };
}

export const CANARY_CEILINGS = {
  MAX_SETUP_DOMAIN_ROWS,
  MAX_DOCUMENT_ROWS,
  MAX_TRACKED_DOMAIN_ROWS,
  MAX_AUTH_USERS,
} as const;
