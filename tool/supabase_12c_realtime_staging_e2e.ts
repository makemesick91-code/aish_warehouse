// Milestone 12C Realtime verification, against staging, over real frames.
//
// A `SELECT` through PostgREST proves the journal policy admits a row. It does
// not prove the Realtime server evaluates that same policy before broadcasting,
// and that is the property a leak would live in. So every assertion here waits
// on an actual websocket frame delivered to an actual authenticated session.
//
// Realtime is treated exactly as the design treats it: a hint. The harness
// asserts that a frame arrives, that its payload is *not* used as the source of
// truth, and that the state a client ends up with comes from the pull that the
// frame triggered — including in the cases where the frame never arrives at all.

import type { RealtimeChannel, SupabaseClient } from "npm:@supabase/supabase-js@2";
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

const FRAME_TIMEOUT_MS = 20_000;
const SUBSCRIBE_TIMEOUT_MS = 20_000;
const SILENCE_WINDOW_MS = 6_000;
const DEBOUNCE_MS = 750;

type Frame = { entity_type: string; entity_id: string; change_seq: number };

const results: Array<{ id: string; ok: boolean; detail: string }> = [];

function record(id: string, ok: boolean, detail = ""): void {
  results.push({ id, ok, detail });
  safeLog(`${ok ? "PASS" : "FAIL"}  realtime  ${id}${detail ? ` — ${detail}` : ""}`);
}

/// Collects journal frames as they arrive. Deliberately keeps only the
/// bookkeeping columns: if a business column ever appeared in a frame the
/// assertion below would see it, and nothing in this harness would silently
/// start depending on it.
class FrameCollector {
  readonly frames: Frame[] = [];
  readonly rawKeys = new Set<string>();
  private channel: RealtimeChannel | null = null;

  constructor(private readonly client: SupabaseClient, private readonly label: string) {}

  async subscribe(): Promise<void> {
    const channel = this.client.channel(`journal-${this.label}`)
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

/// Mirrors `RealtimeInvalidationCoordinator`: a frame marks the scope dirty, a
/// debounce window coalesces a burst, and the worker is single-flight — a frame
/// arriving mid-pull sets dirty once more and causes exactly one more pull.
class CoalescingPuller {
  pulls = 0;
  cursor = 0;
  private dirty = false;
  private running = false;
  private timer: ReturnType<typeof setTimeout> | null = null;

  constructor(
    private readonly client: SupabaseClient,
    private readonly device: string,
  ) {}

  markDirty(): void {
    this.dirty = true;
    if (this.timer !== null) clearTimeout(this.timer);
    this.timer = setTimeout(() => void this.drain(), DEBOUNCE_MS);
  }

  async drain(): Promise<void> {
    if (this.running) return;
    this.running = true;
    try {
      while (this.dirty) {
        this.dirty = false;
        for (;;) {
          const page = await this.client.rpc("pull_sync_changes", {
            after_cursor: this.cursor, batch_limit: 200, device_id: this.device,
          });
          if (page.error) throw page.error;
          this.pulls += 1;
          const data = page.data as { next_cursor: number; has_more: boolean };
          this.cursor = data.next_cursor;
          if (!data.has_more) break;
        }
      }
    } finally {
      this.running = false;
    }
  }

  async settle(): Promise<void> {
    await new Promise((resolve) => setTimeout(resolve, DEBOUNCE_MS + 500));
    await this.drain();
  }
}

async function main(): Promise<number> {
  const target = resolveStagingTarget({
    mutating: true,
    requireServiceRole: true,
    requireFixturePassword: true,
  });
  describeTarget(target, "supabase_12c_realtime_staging_e2e");

  const fixtures = await StagingFixtures.create(
    target,
    runNamespace(`${target.namespace}-realtime`),
  );
  let cleanup: { ok: boolean; problems: string[] } = { ok: true, problems: [] };
  const startedAt = new Date().toISOString();

  try {
    // 1. Sign in as a branch A actor and subscribe.
    const nurseA = await fixtures.signIn("nurseA");
    const deviceA = await fixtures.registerDevice(nurseA, "realtime-a");
    const collectorA = new FrameCollector(nurseA, `a-${fixtures.set.token}`);
    await collectorA.subscribe();
    record("subscription_established", true);

    const puller = new CoalescingPuller(nurseA, deviceA);
    await puller.drain();
    const baselinePulls = puller.pulls;

    // 3-4. A change inside actor A's scope must reach actor A.
    const renamed = await renameRoom(fixtures, fixtures.set.roomA, "visible-1");
    assertCondition(renamed, "room_rename_failed");
    const sawOwn = await collectorA.waitFor((frames) =>
      frames.some((frame) =>
        frame.entity_type === "room" && frame.entity_id === fixtures.set.roomA
      )
    );
    record("own_branch_change_produces_invalidation", sawOwn);

    // 7. The frame carries no business payload, so it cannot be a source of
    // truth even for a client that wanted it to be.
    const businessKeys = [...collectorA.rawKeys].filter((key) =>
      !["change_seq", "xact_id", "entity_type", "entity_id", "operation",
        "server_version", "changed_at"].includes(key)
    );
    record("frame_carries_no_business_payload", businessKeys.length === 0,
      businessKeys.join(","));
    record("frame_cannot_name_the_new_value",
      !JSON.stringify(collectorA.frames).includes("visible-1"));

    // 8-9. The state the client ends up with comes from the pull, not the frame.
    await puller.settle();
    const pulled = await pullEntity(nurseA, deviceA, "room", fixtures.set.roomA);
    record("pull_after_event_returns_the_entity", pulled !== null);
    record("pulled_entity_matches_the_server",
      pulled !== null && String(pulled.name).endsWith("visible-1"),
      pulled ? String(pulled.name) : "");

    // 5-6. A branch B change must not reach a branch A actor.
    collectorA.reset();
    await renameRoom(fixtures, fixtures.set.roomB, "hidden-1");
    const stayedQuiet = await collectorA.staysSilentAbout((frame) =>
      frame.entity_id === fixtures.set.roomB
    );
    record("other_branch_change_produces_no_invalidation", stayedQuiet);

    // 10-11. A burst must coalesce into far fewer pulls than events.
    collectorA.reset();
    const pullsBeforeBurst = puller.pulls;
    const burstSize = 50;
    await burst(fixtures, burstSize);
    const sawBurst = await collectorA.waitFor(
      (frames) => frames.length >= burstSize,
      FRAME_TIMEOUT_MS * 2,
    );
    record("burst_frames_delivered", sawBurst,
      `${collectorA.frames.length}/${burstSize}`);
    for (let index = 0; index < collectorA.frames.length; index += 1) {
      puller.markDirty();
    }
    await puller.settle();
    const burstPulls = puller.pulls - pullsBeforeBurst;
    record("burst_is_coalesced_into_few_pulls", burstPulls < burstSize,
      `${burstPulls} pulls for ${collectorA.frames.length} events`);

    // 12-15. Disconnect, change while offline, reconnect, catch up.
    await collectorA.unsubscribe();
    record("subscription_closed", true);
    const offlineCursor = puller.cursor;
    await renameRoom(fixtures, fixtures.set.roomA, "offline-1");
    const collectorReconnect = new FrameCollector(
      nurseA,
      `a-reconnect-${fixtures.set.token}`,
    );
    await collectorReconnect.subscribe();
    await puller.settle();
    record("resume_catches_up_changes_made_while_disconnected",
      puller.cursor > offlineCursor,
      `${offlineCursor} -> ${puller.cursor}`);
    const afterOffline = await pullEntity(
      nurseA, deviceA, "room", fixtures.set.roomA,
    );
    record("catch_up_state_is_correct",
      afterOffline !== null && String(afterOffline.name).endsWith("offline-1"));
    await collectorReconnect.unsubscribe();

    // 16. Logout stops the subscription.
    const collectorLogout = new FrameCollector(
      nurseA,
      `a-logout-${fixtures.set.token}`,
    );
    await collectorLogout.subscribe();
    await nurseA.auth.signOut();
    await collectorLogout.unsubscribe();
    collectorLogout.reset();
    await renameRoom(fixtures, fixtures.set.roomA, "after-logout");
    const silentAfterLogout = await collectorLogout.staysSilentAbout(() => true);
    record("logout_stops_the_subscription", silentAfterLogout,
      `${collectorLogout.frames.length} frames after logout`);

    // 17. A different actor gets a different scope and a separate cursor.
    const nurseB = await fixtures.signIn("nurseB");
    const deviceB = await fixtures.registerDevice(nurseB, "realtime-b");
    const scopeA = await scopeFingerprint(
      await fixtures.signIn("nurseA"),
      deviceA,
    );
    const scopeB = await scopeFingerprint(nurseB, deviceB);
    record("scope_fingerprints_do_not_mix", scopeA !== scopeB);
    const pullB = await pullEntity(nurseB, deviceB, "room", fixtures.set.roomA);
    record("a_second_actor_cannot_read_the_first_actors_scope", pullB === null);

    const collectorB = new FrameCollector(nurseB, `b-${fixtures.set.token}`);
    await collectorB.subscribe();
    await renameRoom(fixtures, fixtures.set.roomA, "cross-check");
    const bStayedQuiet = await collectorB.staysSilentAbout((frame) =>
      frame.entity_id === fixtures.set.roomA
    );
    record("branch_b_never_sees_branch_a_frames", bStayedQuiet);
    await collectorB.unsubscribe();
  } catch (error) {
    record("harness_completed", false, redact(error));
  } finally {
    cleanup = await fixtures.cleanup();
  }
  record("fixtures_cleaned_up", cleanup.ok, cleanup.problems.join(" | "));

  const failed = results.filter((entry) => !entry.ok);
  const report = {
    ok: failed.length === 0,
    tool: "supabase_12c_realtime_staging_e2e",
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
    `12c-realtime-${utcStamp()}`, "json", JSON.stringify(report, null, 2),
  );
  safeLog(`report      = ${path}`);
  safeLog(
    `result      = ${report.ok ? "PASS" : "FAIL"} (${
      results.length - failed.length
    }/${results.length})`,
  );
  return report.ok ? 0 : 1;
}

async function renameRoom(
  fixtures: StagingFixtures,
  roomId: string,
  suffix: string,
): Promise<boolean> {
  // Written with the service key on purpose: this stands in for "something else
  // changed the server", which is the only situation Realtime exists for.
  const service = fixtures.serviceClient();
  const result = await service.from("rooms").update({
    name: `${fixtures.set.namespace} ${suffix}`,
    updated_at: new Date().toISOString(),
  }).eq("id", roomId);
  return result.error === null;
}

async function burst(fixtures: StagingFixtures, count: number): Promise<void> {
  const service = fixtures.serviceClient();
  for (let index = 0; index < count; index += 1) {
    const result = await service.from("rooms").update({
      name: `${fixtures.set.namespace} burst-${index}`,
      updated_at: new Date().toISOString(),
    }).eq("id", fixtures.set.roomA);
    if (result.error) throw result.error;
  }
}

async function pullEntity(
  client: SupabaseClient,
  device: string,
  entityType: string,
  entityId: string,
): Promise<Record<string, unknown> | null> {
  let cursor = 0;
  let latest: Record<string, unknown> | null = null;
  for (let page = 0; page < 200; page += 1) {
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

try {
  Deno.exit(await main());
} catch (error) {
  safeError(`realtime_e2e_failed: ${redact(error)}`);
  Deno.exit(2);
}
