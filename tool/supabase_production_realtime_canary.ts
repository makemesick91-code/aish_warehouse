// Realtime verification against production, over real frames, inside a
// dedicated canary namespace.
//
// A `SELECT` through PostgREST proves the journal policy admits a row. It does
// not prove the Realtime server evaluates that same policy before broadcasting,
// and a cross-tenant leak would live exactly in that gap. So every assertion
// here waits on an actual websocket frame delivered to an actual authenticated
// session.
//
// What this deliberately does NOT do, because it is running against production:
//
//   * no burst. The 50-event coalescing probe stays local and on staging; it is
//     a load generator, and a load generator is not a canary;
//   * no failure injection, no forced disconnect of anything but its own socket;
//   * no traffic against a real user's row. Every entity it touches was created
//     by this run, in this run's own branch, and is retired at the end;
//   * no long-running transaction and no held lock.
//
// Every rename below targets a canary room. A real branch's rows are never
// read, never written, and never subscribed to individually.
//
// Exit code: 0 when every check passed, 1 when any failed, 2 on a refusal.

import type { RealtimeChannel, SupabaseClient } from "npm:@supabase/supabase-js@2";
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
import {
  type CanaryRetirement,
  pendingRetirement,
  ProductionCanaryNamespace,
} from "./production_canary_namespace.ts";

const FRAME_TIMEOUT_MS = 20_000;
const SUBSCRIBE_TIMEOUT_MS = 20_000;
const SILENCE_WINDOW_MS = 6_000;

/// The whole harness makes at most this many writes, all of them renames of a
/// canary room. Asserted rather than trusted.
const MAX_CANARY_WRITES = 6;

const JOURNAL_COLUMNS = [
  "change_seq", "xact_id", "entity_type", "entity_id", "operation",
  "server_version", "changed_at",
];

type Frame = { entity_type: string; entity_id: string; change_seq: number };

const results: Array<{ id: string; ok: boolean; detail: string }> = [];

function record(id: string, ok: boolean, detail = ""): void {
  results.push({ id, ok, detail });
  safeLog(`${ok ? "PASS" : "FAIL"}  realtime  ${id}${detail ? ` — ${detail}` : ""}`);
}

class FrameCollector {
  readonly frames: Frame[] = [];
  readonly rawKeys = new Set<string>();
  private channel: RealtimeChannel | null = null;

  constructor(private readonly client: SupabaseClient, private readonly label: string) {}

  async subscribe(): Promise<void> {
    // The session has to exist before the channel does. supabase-js hands the
    // access token to the Realtime socket on the auth state change, so a
    // channel opened ahead of it is evaluated by Realtime as `anon` — which has
    // no SELECT on the journal and would silently drop every frame while the
    // transport looked healthy. Refusing here turns that into a named failure
    // instead of an empty collector.
    const session = (await this.client.auth.getSession()).data.session;
    if (!session?.access_token) {
      throw new Error(`realtime_session_missing_before_subscribe:${this.label}`);
    }
    const channel = this.client.channel(`canary-journal-${this.label}`)
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "sync_change_journal" },
        (payload) => {
          const row = payload.new as Record<string, unknown>;
          for (const key of Object.keys(row)) this.rawKeys.add(key);
          this.frames.push({
            entity_type: String(row.entity_type),
            entity_id: String(row.entity_id),
            change_seq: Number(row.change_seq),
          });
        },
      );
    this.channel = channel;
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error(`realtime_subscribe_timeout:${this.label}`)),
        SUBSCRIBE_TIMEOUT_MS,
      );
      channel.subscribe((status, error) => {
        if (status === "SUBSCRIBED") {
          clearTimeout(timer);
          resolve();
        } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
          clearTimeout(timer);
          reject(new Error(`realtime_subscribe_failed:${this.label}:${redact(error)}`));
        }
      });
    });
  }

  async unsubscribe(): Promise<void> {
    if (!this.channel) return;
    await this.client.removeChannel(this.channel);
    this.channel = null;
  }

  reset(): void {
    this.frames.length = 0;
  }

  async waitFor(
    predicate: (frames: Frame[]) => boolean,
    timeout = FRAME_TIMEOUT_MS,
  ): Promise<boolean> {
    const deadline = Date.now() + timeout;
    while (Date.now() < deadline) {
      if (predicate(this.frames)) return true;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    return predicate(this.frames);
  }

  /// A negative assertion needs a window, not an instant: "no frame arrived" is
  /// only meaningful after waiting at least as long as a positive one takes.
  async staysSilentAbout(
    predicate: (frame: Frame) => boolean,
    window = SILENCE_WINDOW_MS,
  ): Promise<boolean> {
    const deadline = Date.now() + window;
    while (Date.now() < deadline) {
      if (this.frames.some(predicate)) return false;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    return !this.frames.some(predicate);
  }
}

let canaryWrites = 0;

/// The only write this harness performs, and only ever against a canary room.
async function renameCanaryRoom(
  canary: ProductionCanaryNamespace,
  roomId: string,
  suffix: string,
): Promise<boolean> {
  canaryWrites += 1;
  if (canaryWrites > MAX_CANARY_WRITES) {
    throw new Error("realtime_canary_write_budget_exceeded");
  }
  assertCondition(
    roomId === canary.set.roomA || roomId === canary.set.roomB,
    "realtime_canary_target_is_not_a_canary_room",
  );
  // Written with the service key on purpose: this stands in for "something else
  // changed the server", which is the only situation Realtime exists for.
  const result = await canary.serviceClient().from("rooms").update({
    name: `CANARY ${canary.set.namespace} ${suffix}`,
    updated_at: new Date().toISOString(),
  }).eq("id", roomId);
  return result.error === null;
}

async function pullEntity(
  client: SupabaseClient,
  device: string,
  entityType: string,
  entityId: string,
  maxPages: number,
): Promise<Record<string, unknown> | null> {
  let cursor = 0;
  let latest: Record<string, unknown> | null = null;
  for (let page = 0; page < maxPages; page += 1) {
    const result = await client.rpc("pull_sync_changes", {
      after_cursor: cursor, batch_limit: 200, device_id: device,
      entity_types: [entityType],
    });
    if (result.error) throw result.error;
    const data = result.data as {
      changes: Array<Record<string, any>>;
      next_cursor: number;
      has_more: boolean;
    };
    for (const change of data.changes) {
      if (change.entity_id === entityId && change.payload) {
        latest = change.payload as Record<string, unknown>;
      }
    }
    cursor = data.next_cursor;
    if (!data.has_more) break;
  }
  return latest;
}

async function scopeFingerprint(
  client: SupabaseClient,
  device: string,
): Promise<string> {
  const result = await client.rpc("pull_sync_changes", {
    after_cursor: 0, batch_limit: 1, device_id: device,
  });
  if (result.error) throw result.error;
  return (result.data as { scope_fingerprint: string }).scope_fingerprint;
}

async function main(): Promise<number> {
  const target = resolveProductionTarget({
    mode: "guarded_write",
    writeScope: "canary_namespace",
    requireServiceRole: true,
    requireCanaryPassword: true,
  });
  describeTarget(target, "supabase_production_realtime_canary");
  safeLog(`budget      = at most ${MAX_CANARY_WRITES} canary-room renames, no burst`);

  // How many pages a catch-up drain may spend. Production's feed is as long as
  // production is old, so this is a declared budget rather than a fixed 500.
  const maxPages = Number(Deno.env.get("AISH_PRODUCTION_MAX_PULL_PAGES") ?? "20");

  const canary = await ProductionCanaryNamespace.create(
    target, runNamespace(`${target.namespacePrefix}-realtime`),
  );
  let retirement: CanaryRetirement = pendingRetirement();
  const startedAt = new Date().toISOString();

  try {
    const nurseA = await canary.signIn("nurseA");
    const deviceA = await canary.registerDevice(nurseA, "realtime-a");
    const collectorA = new FrameCollector(nurseA, `a-${canary.set.token}`);
    await collectorA.subscribe();
    record("subscription_established", true);

    // 1. A change inside the canary actor's own scope must reach it.
    const renamed = await renameCanaryRoom(canary, canary.set.roomA, "visible-1");
    assertCondition(renamed, "canary_room_rename_failed");
    const sawOwn = await collectorA.waitFor((frames) =>
      frames.some((frame) =>
        frame.entity_type === "room" && frame.entity_id === canary.set.roomA
      )
    );
    record("own_scope_change_produces_invalidation", sawOwn);

    // 2. The frame carries no business payload, so it cannot become a source of
    // truth even for a client that wanted it to be. On production this is the
    // check that matters most: a business column here is broadcast to every
    // subscribed device that can see the row.
    const businessKeys = [...collectorA.rawKeys].filter((key) =>
      !JOURNAL_COLUMNS.includes(key)
    );
    record("frame_carries_no_business_payload", businessKeys.length === 0,
      businessKeys.join(","));
    record("frame_cannot_name_the_new_value",
      !JSON.stringify(collectorA.frames).includes("visible-1"));

    // 3. The state the client ends up with comes from the pull, not the frame.
    const pulled = await pullEntity(nurseA, deviceA, "room", canary.set.roomA, maxPages);
    record("pull_after_event_returns_the_entity", pulled !== null);
    record("pulled_entity_matches_the_server",
      pulled !== null && String(pulled.name).endsWith("visible-1"),
      pulled ? "matched" : "");

    // 4. A change outside the actor's scope must not reach it.
    collectorA.reset();
    await renameCanaryRoom(canary, canary.set.roomB, "hidden-1");
    const stayedQuiet = await collectorA.staysSilentAbout((frame) =>
      frame.entity_id === canary.set.roomB
    );
    record("out_of_scope_change_produces_no_invalidation", stayedQuiet);

    // 5. Disconnect, change while offline, reconnect, catch up through the pull.
    await collectorA.unsubscribe();
    record("subscription_closed", true);
    const beforeOffline = await scopeCursor(nurseA, deviceA, maxPages);
    await renameCanaryRoom(canary, canary.set.roomA, "offline-1");
    const collectorReconnect = new FrameCollector(
      nurseA, `a-reconnect-${canary.set.token}`,
    );
    await collectorReconnect.subscribe();
    record("subscription_reestablished", true);
    const afterOfflineCursor = await scopeCursor(nurseA, deviceA, maxPages);
    record("resume_catches_up_changes_made_while_disconnected",
      afterOfflineCursor > beforeOffline,
      `${beforeOffline} -> ${afterOfflineCursor}`);
    const afterOffline = await pullEntity(
      nurseA, deviceA, "room", canary.set.roomA, maxPages,
    );
    record("catch_up_state_is_correct",
      afterOffline !== null && String(afterOffline.name).endsWith("offline-1"));
    await collectorReconnect.unsubscribe();

    // 6. Logout stops the subscription.
    const collectorLogout = new FrameCollector(nurseA, `a-logout-${canary.set.token}`);
    await collectorLogout.subscribe();
    await nurseA.auth.signOut();
    await collectorLogout.unsubscribe();
    collectorLogout.reset();
    await renameCanaryRoom(canary, canary.set.roomA, "after-logout");
    const silentAfterLogout = await collectorLogout.staysSilentAbout(() => true);
    record("logout_stops_the_subscription", silentAfterLogout,
      `${collectorLogout.frames.length} frame(s) after logout`);

    // 7. A different actor gets a different scope and never sees the first
    // actor's frames. This is the cross-tenant assertion, made between two
    // canary branches rather than against anyone's real branch.
    const nurseB = await canary.signIn("nurseB");
    const deviceB = await canary.registerDevice(nurseB, "realtime-b");
    const freshA = await canary.signIn("nurseA");
    const scopeA = await scopeFingerprint(freshA, deviceA);
    const scopeB = await scopeFingerprint(nurseB, deviceB);
    record("scope_fingerprints_do_not_mix", scopeA !== scopeB);
    const pullB = await pullEntity(nurseB, deviceB, "room", canary.set.roomA, maxPages);
    record("a_second_actor_cannot_read_the_first_actors_scope", pullB === null);

    const collectorB = new FrameCollector(nurseB, `b-${canary.set.token}`);
    await collectorB.subscribe();
    await renameCanaryRoom(canary, canary.set.roomA, "cross-check");
    const bStayedQuiet = await collectorB.staysSilentAbout((frame) =>
      frame.entity_id === canary.set.roomA
    );
    record("branch_b_never_sees_branch_a_frames", bStayedQuiet);
    await collectorB.unsubscribe();

    record("write_budget_respected", canaryWrites <= MAX_CANARY_WRITES,
      `${canaryWrites}/${MAX_CANARY_WRITES}`);
  } catch (error) {
    record("harness_completed", false, redact(error));
  } finally {
    // Idempotent: `create()` retires a failed setup itself, so a second call
    // here returns that same report rather than repeating its side effects.
    retirement = await canary.retire();
  }
  record("canary_namespace_retired", retirement.ok, retirement.problems.join(" | "));
  record("every_created_row_was_confirmed_retired",
    retirement.retired === retirement.requested && retirement.missing.length === 0,
    `${retirement.retired}/${retirement.requested} matched, ` +
      `${retirement.missing.length} missing`);
  record("every_auth_identity_was_disabled",
    retirement.auth_users_banned === retirement.auth_users_created &&
      retirement.auth_users_failed.length === 0,
    `${retirement.auth_users_banned}/${retirement.auth_users_created} banned`);

  const failed = results.filter((entry) => !entry.ok);
  const report = {
    ok: failed.length === 0,
    ...auditHeader(target, "supabase_production_realtime_canary"),
    namespace: canary.set.namespace,
    started_at_utc: startedAt,
    finished_at_utc: new Date().toISOString(),
    canary_writes: canaryWrites,
    canary_write_budget: MAX_CANARY_WRITES,
    rows_created: canary.createdRows().length,
    rows_requested_for_retirement: retirement.requested,
    rows_retired: retirement.retired,
    rows_missing_after_retirement: retirement.missing,
    retirement_reason: retirement.reason,
    retirement_ok: retirement.ok,
    retirement_problems: retirement.problems,
    auth_users_created: retirement.auth_users_created,
    auth_users_banned: retirement.auth_users_banned,
    auth_users_failed: retirement.auth_users_failed,
    left_in_place: retirement.left_in_place,
    left_in_place_detail: retirement.left_in_place_detail,
    checks_total: results.length,
    checks_failed: failed.length,
    failed_checks: failed.map((entry) => entry.id),
    results,
    excluded_by_policy: [
      "burst / coalescing probe (load generator — local and staging only)",
      "failure injection",
      "benchmark under sustained fan-out",
      "any subscription to a real tenant's rows",
    ],
  };
  const path = await writeProductionArtifact(
    `production-realtime-canary-${utcStamp()}`, "json", JSON.stringify(report, null, 2),
  );
  safeLog(`report      = ${path}`);
  safeLog(
    `result      = ${report.ok ? "PASS" : "FAIL"} (${results.length - failed.length}/${results.length})`,
  );
  return report.ok ? 0 : 1;
}

/// The cursor an actor's own device reaches by draining its scope. Used to show
/// that a disconnected period is recovered by the pull, not by the socket.
async function scopeCursor(
  client: SupabaseClient,
  device: string,
  maxPages: number,
): Promise<number> {
  let cursor = 0;
  for (let page = 0; page < maxPages; page += 1) {
    const result = await client.rpc("pull_sync_changes", {
      after_cursor: cursor, batch_limit: 200, device_id: device,
    });
    if (result.error) throw result.error;
    const data = result.data as { next_cursor: number; has_more: boolean };
    cursor = data.next_cursor;
    if (!data.has_more) break;
  }
  return cursor;
}

try {
  Deno.exit(await main());
} catch (error) {
  safeError(`production_realtime_canary_failed: ${redact(error)}`);
  Deno.exit(error instanceof ProductionGuardError ? 2 : 1);
}
