// Partial-setup cleanup matrix for the production canary namespace.
//
// The property under test is the one an audit cannot read off the source: that
// a setup which dies at *any* step leaves nothing usable behind. Every remote
// call the namespace makes goes through `CanaryBackend`, so these tests drive
// that seam with a fake that fails on demand and then assert what the fake was
// asked to do.
//
// No network, no credentials, no Supabase project. `ProductionTarget` is a
// plain record here, and the fake backend is the only thing that could ever
// reach a server — it does not.
//
// Run with:
//   deno test tool/production_canary_namespace_test.ts
//
// Beyond the individual failure points, three invariants are asserted after
// every single case, because they are what "fail-closed" actually means:
//
//   * no delete of any kind was issued;
//   * every update named an explicit, non-empty id list, and every id in it was
//     an id the run had recorded as created;
//   * every Auth identity the server confirmed was banned and rotated, even the
//     one whose actor was never finished.

import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  CANARY_CEILINGS,
  type CanaryBackend,
  pendingRetirement,
  ProductionCanaryNamespace,
} from "./production_canary_namespace.ts";
import type { ProductionTarget } from "./production_guard.ts";

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// Everything the fake was asked to do, in order. The assertions are written
/// against this rather than against the class's own report, so a class that
/// merely *claims* it cleaned up cannot pass.
type Call =
  | { kind: "insert"; table: string; ids: string[] }
  | { kind: "softRetire"; table: string; ids: string[]; patch: Record<string, unknown> }
  | { kind: "createAuthUser"; email: string }
  | { kind: "disableAuthUser"; authUserId: string };

type FakeOptions = {
  /// Fail the nth call to `insert` for this table (1-based), or every call when
  /// the count is omitted.
  failInsert?: { table: string; occurrence?: number };
  /// Fail `createAuthUser` on this 1-based occurrence.
  failAuthUserAt?: number;
  /// Fail `disableAuthUser` for these auth ids.
  failDisableFor?: (authUserId: string) => boolean;
  /// Fail `softRetire` for these tables.
  failRetireFor?: (table: string) => boolean;
  /// Drop this many ids from what `softRetire` reports as updated, simulating a
  /// row that did not match.
  dropFromRetireResult?: (table: string) => number;
};

class FakeBackend implements CanaryBackend {
  readonly calls: Call[] = [];
  /// Ids the fake accepted an insert for — the server's view of what exists.
  readonly insertedIds = new Set<string>();
  readonly createdAuthUserIds: string[] = [];
  private insertCounts = new Map<string, number>();
  private authUserCount = 0;

  constructor(private readonly options: FakeOptions = {}) {}

  // deno-lint-ignore require-await
  async insert(
    table: string,
    rows: ReadonlyArray<Record<string, unknown>>,
  ): Promise<{ error: unknown }> {
    const ids = rows.map((row) => String(row.id ?? row.auth_user_id ?? ""));
    this.calls.push({ kind: "insert", table, ids });
    const seen = (this.insertCounts.get(table) ?? 0) + 1;
    this.insertCounts.set(table, seen);
    const fail = this.options.failInsert;
    if (fail && fail.table === table && (fail.occurrence ?? seen) === seen) {
      return { error: { message: `injected_insert_failure:${table}` } };
    }
    for (const id of ids) if (id) this.insertedIds.add(id);
    return { error: null };
  }

  // deno-lint-ignore require-await
  async softRetire(
    table: string,
    patch: Record<string, unknown>,
    ids: ReadonlyArray<string>,
  ): Promise<{ ids: string[] | null; error: unknown }> {
    this.calls.push({ kind: "softRetire", table, ids: [...ids], patch });
    if (this.options.failRetireFor?.(table)) {
      return { ids: null, error: { message: `injected_retire_failure:${table}` } };
    }
    // Only rows the server actually holds can be updated. This is what makes
    // "the class tried to retire something it never created" observable.
    const present = ids.filter((id) => this.insertedIds.has(id));
    const drop = this.options.dropFromRetireResult?.(table) ?? 0;
    return { ids: present.slice(0, Math.max(present.length - drop, 0)), error: null };
  }

  // deno-lint-ignore require-await
  async createAuthUser(email: string): Promise<{ id: string | null; error: unknown }> {
    this.calls.push({ kind: "createAuthUser", email });
    this.authUserCount += 1;
    if (this.options.failAuthUserAt === this.authUserCount) {
      return { id: null, error: { message: "injected_auth_user_failure" } };
    }
    const id = `auth-${this.authUserCount}-${"0".repeat(30)}`;
    this.createdAuthUserIds.push(id);
    return { id, error: null };
  }

  // deno-lint-ignore require-await
  async disableAuthUser(authUserId: string): Promise<{ error: unknown }> {
    this.calls.push({ kind: "disableAuthUser", authUserId });
    if (this.options.failDisableFor?.(authUserId)) {
      return { error: { message: "injected_ban_failure" } };
    }
    return { error: null };
  }

  retiredIds(): string[] {
    return this.calls.filter((call) => call.kind === "softRetire")
      .flatMap((call) => (call as { ids: string[] }).ids);
  }

  bannedIds(): string[] {
    return this.calls.filter((call) => call.kind === "disableAuthUser")
      .map((call) => (call as { authUserId: string }).authUserId);
  }
}

function target(): ProductionTarget {
  return {
    url: "https://example.supabase.co",
    host: "example.supabase.co",
    projectRef: "exampleprojectref",
    maskedRef: "exa************ef",
    anonKey: "anon-key-placeholder",
    serviceRoleKey: "service-role-key-placeholder",
    canaryPassword: "canary-password-placeholder",
    mode: "guarded_write",
    writeScope: "canary_namespace",
    changeTicket: "AISH-12C",
    maintenanceWindow: {
      raw: "test", startsAtUtc: "2026-08-03T00:00:00Z",
      endsAtUtc: "2026-08-03T23:59:59Z", remainingMinutes: 60,
    },
    backupIdentifier: "test-backup",
    backupChecksum: "PASS",
    restoreRehearsalConfirmed: true,
    operatorAcknowledgement: "test",
    branch: "chore/12c-staging-rollout",
    commit: "0000000",
    treeClean: true,
    expectedRevision: "aish-supabase-003-baseline",
    namespacePrefix: "aish-12c-canary",
  } as ProductionTarget;
}

/// Drives `create()` expecting it to fail, and returns the error plus the fake.
async function setupFailure(
  options: FakeOptions,
): Promise<{ backend: FakeBackend; error: Error }> {
  const backend = new FakeBackend(options);
  try {
    await ProductionCanaryNamespace.create(target(), "aish-12c-canary-test", { backend });
  } catch (error) {
    return { backend, error: error as Error };
  }
  throw new Error("expected create() to fail, but it returned an instance");
}

// ---------------------------------------------------------------------------
// Invariants asserted after every case
// ---------------------------------------------------------------------------

/// The three properties that must hold no matter where setup died.
function assertFailClosed(backend: FakeBackend, error: Error): void {
  // 1. The original fault is still legible, and the caller is told cleanup ran.
  assertStringIncludes(error.message, "canary_setup_failed:");
  assertStringIncludes(error.message, "retirement_ok=");

  // 2. Cleanup only ever touched ids this run created, and never with an empty
  //    or absent filter.
  for (const call of backend.calls) {
    if (call.kind !== "softRetire") continue;
    assert(call.ids.length > 0, `softRetire on ${call.table} with an empty id list`);
    assert(
      call.patch.deleted_at !== undefined,
      `softRetire on ${call.table} without a deleted_at patch`,
    );
    for (const id of call.ids) {
      assert(
        backend.insertedIds.has(id) || !id,
        `softRetire on ${call.table} named ${id}, which this run never created`,
      );
    }
  }

  // 3. Every identity the server confirmed was disabled — including one whose
  //    domain user or auth link never landed.
  assertEquals(
    [...backend.bannedIds()].sort(),
    [...backend.createdAuthUserIds].sort(),
    "an Auth identity that was created was not banned",
  );
}

// ---------------------------------------------------------------------------
// Failure injection — one case per setup step
// ---------------------------------------------------------------------------

Deno.test("a branch insert failure creates nothing and retires nothing", async () => {
  const { backend, error } = await setupFailure({ failInsert: { table: "branches" } });
  assertFailClosed(backend, error);
  assertStringIncludes(error.message, "branches");
  // Nothing was recorded, so nothing was updated. A cleanup that "swept the
  // namespace" anyway would show up right here.
  assertEquals(backend.retiredIds().length, 0);
  assertEquals(backend.createdAuthUserIds.length, 0);
});

Deno.test("a room insert failure retires only the two branches", async () => {
  const { backend, error } = await setupFailure({ failInsert: { table: "rooms" } });
  assertFailClosed(backend, error);
  const retired = backend.calls.filter((call) => call.kind === "softRetire");
  assertEquals(retired.map((call) => (call as { table: string }).table), ["branches"]);
  assertEquals(backend.retiredIds().length, 2);
});

Deno.test("a stock location failure retires branches and rooms only", async () => {
  const { backend, error } = await setupFailure({
    failInsert: { table: "stock_locations" },
  });
  assertFailClosed(backend, error);
  const tables = new Set(
    backend.calls.filter((call) => call.kind === "softRetire")
      .map((call) => (call as { table: string }).table),
  );
  assertEquals(tables, new Set(["branches", "rooms"]));
  assertEquals(backend.retiredIds().length, 4);
});

Deno.test("an item category failure retires the seven rows that exist", async () => {
  const { backend, error } = await setupFailure({
    failInsert: { table: "item_categories" },
  });
  assertFailClosed(backend, error);
  assertEquals(backend.retiredIds().length, 9);
});

Deno.test("an item failure retires the ten rows that exist", async () => {
  const { backend, error } = await setupFailure({ failInsert: { table: "items" } });
  assertFailClosed(backend, error);
  assertEquals(backend.retiredIds().length, 10);
});

Deno.test("a first-actor auth failure leaves no identity and no user row", async () => {
  const { backend, error } = await setupFailure({ failAuthUserAt: 1 });
  assertFailClosed(backend, error);
  assertStringIncludes(error.message, "auth_user_nurseA");
  assertEquals(backend.createdAuthUserIds.length, 0);
  assertEquals(backend.bannedIds().length, 0);
  // The eleven catalogue rows still get retired.
  assertEquals(backend.retiredIds().length, 11);
});

Deno.test("a domain user failure still bans the auth identity that was created", async () => {
  // This is the blocker the audit found: `createUser` succeeded, the domain
  // insert did not, and the identity used to be invisible to cleanup.
  const { backend, error } = await setupFailure({ failInsert: { table: "users" } });
  assertFailClosed(backend, error);
  assertStringIncludes(error.message, "domain_user_nurseA");
  assertEquals(backend.createdAuthUserIds.length, 1);
  assertEquals(backend.bannedIds(), backend.createdAuthUserIds);
  // No `users` row exists, so no `users` retirement was attempted.
  const tables = backend.calls.filter((call) => call.kind === "softRetire")
    .map((call) => (call as { table: string }).table);
  assert(!tables.includes("users"));
});

Deno.test("a user_auth_links failure bans the identity and retires the user row", async () => {
  const { backend, error } = await setupFailure({
    failInsert: { table: "user_auth_links" },
  });
  assertFailClosed(backend, error);
  assertStringIncludes(error.message, "link_nurseA");
  assertEquals(backend.createdAuthUserIds.length, 1);
  assertEquals(backend.bannedIds(), backend.createdAuthUserIds);
  const users = backend.calls.find((call) =>
    call.kind === "softRetire" && (call as { table: string }).table === "users"
  ) as { ids: string[] } | undefined;
  assertEquals(users?.ids.length, 1);
});

Deno.test("a later actor failure bans every identity created so far", async () => {
  for (const occurrence of [2, 3, 4]) {
    const { backend, error } = await setupFailure({ failAuthUserAt: occurrence });
    assertFailClosed(backend, error);
    assertEquals(
      backend.createdAuthUserIds.length,
      occurrence - 1,
      `expected ${occurrence - 1} identity(ies) before the failure`,
    );
    assertEquals(backend.bannedIds(), backend.createdAuthUserIds);
  }
});

Deno.test("a fourth-actor domain failure bans all four identities", async () => {
  const { backend, error } = await setupFailure({
    failInsert: { table: "users", occurrence: 4 },
  });
  assertFailClosed(backend, error);
  assertStringIncludes(error.message, "domain_user_warehouse");
  assertEquals(backend.createdAuthUserIds.length, 4);
  assertEquals(backend.bannedIds().length, 4);
});

Deno.test("a cleanup that itself fails is reported, not swallowed", async () => {
  const { backend, error } = await setupFailure({
    failInsert: { table: "items" },
    failRetireFor: (table) => table === "rooms",
  });
  // The fail-closed invariant on ids still holds; only the outcome differs.
  assertStringIncludes(error.message, "canary_setup_failed:");
  assertStringIncludes(error.message, "retirement_ok=false");
  assertStringIncludes(error.message, "cleanup_problems=");
  assertStringIncludes(error.message, "injected_retire_failure:rooms");
  // The original setup fault is still the primary one.
  assertStringIncludes(error.message, "injected_insert_failure:items");
  // Cleanup carried on to the other tables rather than stopping at the fault.
  const tables = new Set(
    backend.calls.filter((call) => call.kind === "softRetire")
      .map((call) => (call as { table: string }).table),
  );
  assert(tables.has("branches") && tables.has("stock_locations"));
});

Deno.test("a ban failure is reported and does not stop the other bans", async () => {
  const { backend, error } = await setupFailure({
    failInsert: { table: "users", occurrence: 3 },
    failDisableFor: (id) => id.startsWith("auth-1-"),
  });
  assertStringIncludes(error.message, "canary_setup_failed:");
  assertStringIncludes(error.message, "retirement_ok=false");
  assertStringIncludes(error.message, "auth_banned=2/3");
  // All three were attempted even though the first failed.
  assertEquals(backend.bannedIds().length, 3);
});

Deno.test("no failure path issues a delete or an unfiltered update", async () => {
  const cases: FakeOptions[] = [
    { failInsert: { table: "branches" } },
    { failInsert: { table: "rooms" } },
    { failInsert: { table: "stock_locations" } },
    { failInsert: { table: "item_categories" } },
    { failInsert: { table: "items" } },
    { failAuthUserAt: 1 },
    { failInsert: { table: "users" } },
    { failInsert: { table: "user_auth_links" } },
    { failAuthUserAt: 2 },
    { failAuthUserAt: 3 },
    { failAuthUserAt: 4 },
    { failInsert: { table: "users", occurrence: 4 } },
  ];
  for (const option of cases) {
    const { backend, error } = await setupFailure(option);
    assertFailClosed(backend, error);
    // `CanaryBackend` has no delete member at all, so this asserts the shape of
    // what was actually invoked rather than a naming convention.
    for (const call of backend.calls) {
      assert(
        ["insert", "softRetire", "createAuthUser", "disableAuthUser"].includes(call.kind),
        `unexpected backend operation ${call.kind}`,
      );
    }
  }
});

// ---------------------------------------------------------------------------
// Retirement verification
// ---------------------------------------------------------------------------

Deno.test("a successful setup retires exactly what it created", async () => {
  const backend = new FakeBackend();
  const canary = await ProductionCanaryNamespace.create(
    target(), "aish-12c-canary-test", { backend },
  );
  assertEquals(canary.createdRows().length, CANARY_CEILINGS.MAX_SETUP_DOMAIN_ROWS);
  assertEquals(canary.createdAuthUsers().length, CANARY_CEILINGS.MAX_AUTH_USERS);

  const retirement = await canary.retire();
  assert(retirement.ok, retirement.problems.join(" | "));
  assertEquals(retirement.reason, "normal_completion");
  assertEquals(retirement.requested, CANARY_CEILINGS.MAX_SETUP_DOMAIN_ROWS);
  assertEquals(retirement.matched, CANARY_CEILINGS.MAX_SETUP_DOMAIN_ROWS);
  assertEquals(retirement.retired, CANARY_CEILINGS.MAX_SETUP_DOMAIN_ROWS);
  assertEquals(retirement.missing, []);
  assertEquals(retirement.auth_users_banned, CANARY_CEILINGS.MAX_AUTH_USERS);
  assertEquals(retirement.auth_users_failed, []);
});

Deno.test("a row that did not match is missing, not retired", async () => {
  // The regression this replaces: PostgREST returned no error, so the old code
  // counted every requested id as retired without the server ever confirming it.
  const backend = new FakeBackend({
    dropFromRetireResult: (table) => (table === "branches" ? 1 : 0),
  });
  const canary = await ProductionCanaryNamespace.create(
    target(), "aish-12c-canary-test", { backend },
  );
  const retirement = await canary.retire();
  assert(!retirement.ok, "a mismatch must fail the retirement");
  assertEquals(retirement.requested, CANARY_CEILINGS.MAX_SETUP_DOMAIN_ROWS);
  assertEquals(retirement.retired, CANARY_CEILINGS.MAX_SETUP_DOMAIN_ROWS - 1);
  assertEquals(retirement.missing.length, 1);
  assert(retirement.missing[0].startsWith("branches:"));
  assert(retirement.problems.some((p) => p.includes("retirement_incomplete")));
  // The missing row was not chased with a wider filter.
  const branchCalls = backend.calls.filter((call) =>
    call.kind === "softRetire" && (call as { table: string }).table === "branches"
  );
  assertEquals(branchCalls.length, 1);
});

Deno.test("a retirement error marks the rows missing rather than retired", async () => {
  const backend = new FakeBackend({ failRetireFor: (table) => table === "items" });
  const canary = await ProductionCanaryNamespace.create(
    target(), "aish-12c-canary-test", { backend },
  );
  const retirement = await canary.retire();
  assert(!retirement.ok);
  assertEquals(retirement.retired, CANARY_CEILINGS.MAX_SETUP_DOMAIN_ROWS - 1);
  assertEquals(retirement.missing.length, 1);
  assert(retirement.missing[0].startsWith("items:"));
});

Deno.test("a duplicate tracked id is reported and updated once", async () => {
  const backend = new FakeBackend();
  const canary = await ProductionCanaryNamespace.create(
    target(), "aish-12c-canary-test", { backend },
  );
  canary.trackDocument("purchase_requests", canary.set.itemId);
  canary.trackDocument("purchase_requests", canary.set.itemId);
  const retirement = await canary.retire();
  assertEquals(retirement.duplicates.length, 1);
  assert(!retirement.ok);
  const prCall = backend.calls.find((call) =>
    call.kind === "softRetire" && (call as { table: string }).table === "purchase_requests"
  ) as { ids: string[] };
  assertEquals(prCall.ids.length, 1);
});

Deno.test("retire is idempotent and does not repeat its side effects", async () => {
  const backend = new FakeBackend();
  const canary = await ProductionCanaryNamespace.create(
    target(), "aish-12c-canary-test", { backend },
  );
  const first = await canary.retire();
  const callsAfterFirst = backend.calls.length;
  const second = await canary.retire();
  const third = await Promise.all([canary.retire(), canary.retire()]);
  assertEquals(backend.calls.length, callsAfterFirst, "retirement ran twice");
  assertEquals(second, first);
  assertEquals(third[0], first);
  assertEquals(third[1], first);
});

Deno.test("a setup failure's retirement is not repeated by the harness finally block", async () => {
  // `create()` retires on failure and then throws, so the harness never gets an
  // instance in that case. This asserts the other direction: when setup
  // succeeds, the single `finally` call is the only retirement that runs.
  const backend = new FakeBackend();
  const canary = await ProductionCanaryNamespace.create(
    target(), "aish-12c-canary-test", { backend },
  );
  const bansBefore = backend.bannedIds().length;
  assertEquals(bansBefore, 0);
  await canary.retire();
  await canary.retire();
  assertEquals(backend.bannedIds().length, CANARY_CEILINGS.MAX_AUTH_USERS);
});

Deno.test("the retirement report names user_auth_links as left in place", async () => {
  const backend = new FakeBackend();
  const canary = await ProductionCanaryNamespace.create(
    target(), "aish-12c-canary-test", { backend },
  );
  const retirement = await canary.retire();
  const links = retirement.left_in_place_detail.filter((entry) =>
    entry.resource === "user_auth_links"
  );
  assertEquals(links.length, CANARY_CEILINGS.MAX_AUTH_USERS);
  for (const entry of links) assertStringIncludes(entry.reason, "hard delete refused");

  for (const resource of [
    "sync_devices", "sync_operations", "sync_conflicts",
    "sync_change_journal", "stock_movements",
  ]) {
    assert(
      retirement.left_in_place_detail.some((entry) => entry.resource === resource),
      `${resource} is not listed as left in place`,
    );
  }
  // No `user_auth_links` row was ever updated or deleted.
  assert(
    !backend.calls.some((call) =>
      call.kind === "softRetire" && (call as { table: string }).table === "user_auth_links"
    ),
  );
});

Deno.test("the report carries no secret material", async () => {
  const backend = new FakeBackend();
  const canary = await ProductionCanaryNamespace.create(
    target(), "aish-12c-canary-test", { backend },
  );
  const serialised = JSON.stringify(await canary.retire());
  for (const secret of [
    "canary-password-placeholder",
    "service-role-key-placeholder",
    "anon-key-placeholder",
  ]) {
    assert(!serialised.includes(secret), `the report leaked ${secret}`);
  }
});

Deno.test("the pending retirement value is not mistakable for a completed one", () => {
  const pending = pendingRetirement();
  assertEquals(pending.ok, false);
  assertEquals(pending.reason, "not_run");
  assertEquals(pending.retired, 0);
});

// ---------------------------------------------------------------------------
// Ceilings
// ---------------------------------------------------------------------------

Deno.test("the ceilings match the documented plan exactly", () => {
  // 2 branches + 2 rooms + 5 locations + 1 category + 1 item + 4 users.
  assertEquals(CANARY_CEILINGS.MAX_SETUP_DOMAIN_ROWS, 15);
  assertEquals(CANARY_CEILINGS.MAX_AUTH_USERS, 4);
  assertEquals(CANARY_CEILINGS.MAX_DOCUMENT_ROWS, 5);
  assertEquals(CANARY_CEILINGS.MAX_TRACKED_DOMAIN_ROWS, 20);
});

Deno.test("the document ceiling refuses mass fixture generation", async () => {
  const backend = new FakeBackend();
  const canary = await ProductionCanaryNamespace.create(
    target(), "aish-12c-canary-test", { backend },
  );
  // The real canary pushes four: opname, PR, PR line, PR/opname link.
  for (let index = 0; index < CANARY_CEILINGS.MAX_DOCUMENT_ROWS; index += 1) {
    canary.trackDocument("purchase_request_lines", crypto.randomUUID());
  }
  let refused = false;
  try {
    canary.trackDocument("purchase_request_lines", crypto.randomUUID());
  } catch (error) {
    refused = true;
    assertStringIncludes((error as Error).message, "canary_document_ceiling_exceeded");
  }
  assert(refused, "the document ceiling did not refuse an extra row");
});

// ---------------------------------------------------------------------------
// Guard refusals still come first
// ---------------------------------------------------------------------------

Deno.test("the injectable backend does not bypass the write-scope refusals", async () => {
  const backend = new FakeBackend();
  const refusals: Array<[Partial<ProductionTarget>, string]> = [
    [{ writeScope: null }, "canary_namespace_requires_the_canary_namespace_write_scope"],
    [{ mode: "read_only" }, "canary_namespace_requires_the_canary_namespace_write_scope"],
    [{ serviceRoleKey: null }, "canary_namespace_requires_service_role"],
    [{ canaryPassword: null }, "canary_namespace_requires_password"],
  ];
  for (const [override, code] of refusals) {
    let refused = false;
    try {
      await ProductionCanaryNamespace.create(
        { ...target(), ...override } as ProductionTarget,
        "aish-12c-canary-test",
        { backend },
      );
    } catch (error) {
      refused = true;
      assertEquals((error as Error).message, code);
    }
    assert(refused, `expected a refusal for ${code}`);
  }
  // Not one remote call was made behind a refusal.
  assertEquals(backend.calls.length, 0);
});
