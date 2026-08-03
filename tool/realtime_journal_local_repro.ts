// Local-only reproduction of the Realtime journal invalidation path.
//
// Why this exists. On 2026-08-03 the production E2E canary failed exactly one
// check — `realtime/a_scope_change_produces_an_invalidation` — while
// `subscription_established` passed and the pull that followed still supplied
// the state. The canary recorded a bare boolean and no diagnostic detail, so
// the report could not distinguish "the journal row was never written" from
// "it was written but Realtime's RLS check dropped it" from "the frame simply
// arrived late". Worse, the local stack had `[realtime] enabled = false`, so
// the entire Realtime path had never been exercised anywhere except a remote
// project. A production-only code path is a production-only failure mode.
//
// This harness closes that gap locally. It reproduces the production sequence
// as closely as an isolated stack allows and measures each hop separately:
//
//   subscribe -> SUBSCRIBED -> service-role mutation -> journal row committed
//   -> actor can SELECT the journal row under RLS -> Realtime frame delivered
//
// so a failure lands in one named bucket instead of one anonymous `false`.
//
// It refuses to run against anything that is not a loopback stack. There is no
// flag, no environment variable and no escape hatch that makes it target a
// remote project: see `assertLocalTarget`.
//
// Exit code: 0 when every iteration delivered a frame, 1 when any did not,
// 2 on a refusal.

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  classifyRealtimeOutcome,
  type FrameObservation,
  type RealtimeOutcome,
  summariseLatencies,
} from "./realtime_diagnostics.ts";

/// Bounded on purpose. This is a diagnostic, not a load generator: the incident
/// runbook forbids bursts, storms and benchmarks, and a reproduction that
/// hammers the socket would measure the harness rather than the contract.
const ITERATIONS = Math.min(
  Number(Deno.env.get("AISH_REPRO_ITERATIONS") ?? "10"),
  25,
);
const SUBSCRIBE_TIMEOUT_MS = 20_000;
const FRAME_TIMEOUT_MS = 20_000;
/// After the timeout expires the harness keeps listening for a short, bounded
/// window purely to tell "never arrived" apart from "arrived late". The verdict
/// is already decided by then; a late frame is still a failure.
const GRACE_WINDOW_MS = 10_000;

const SEED_ACTOR = "branchhead.local@example.test";
const SEED_PASSWORD = "LocalOnly!12345";
const SEED_ROOM = "21000000-0000-0000-0000-000000000001";

type Iteration = {
  index: number;
  statuses: Array<{ status: string; at_ms: number }>;
  subscribed_at_ms: number | null;
  mutation_at_ms: number | null;
  journal_confirmed_at_ms: number | null;
  journal_change_seq: number | null;
  actor_select_visible: boolean | null;
  actor_select_at_ms: number | null;
  first_frame_at_ms: number | null;
  frame_count: number;
  frame_entity_ids: string[];
  late_frame_at_ms: number | null;
  delivery_latency_ms: number | null;
  pull_supplied_state: boolean | null;
  channel_error: string | null;
  outcome: RealtimeOutcome;
};

/// A refusal, not an assertion. The harness must be unable to point at a
/// managed project even if the environment is wrong or hostile.
function assertLocalTarget(url: string): void {
  const host = new URL(url).hostname;
  const local = host === "127.0.0.1" || host === "localhost" || host === "::1" ||
    host === "0.0.0.0";
  if (!local) {
    console.error(
      `refused: realtime_repro_is_local_only (host=${host}). This harness ` +
        `never targets a remote or managed project.`,
    );
    Deno.exit(2);
  }
  if (/supabase\.(co|in|net)$/i.test(host)) {
    console.error("refused: realtime_repro_is_local_only (managed host)");
    Deno.exit(2);
  }
}

function ms(from: number): number {
  return Math.round(performance.now() - from);
}

async function runIteration(
  index: number,
  url: string,
  anonKey: string,
  service: SupabaseClient,
): Promise<Iteration> {
  const it: Iteration = {
    index,
    statuses: [],
    subscribed_at_ms: null,
    mutation_at_ms: null,
    journal_confirmed_at_ms: null,
    journal_change_seq: null,
    actor_select_visible: null,
    actor_select_at_ms: null,
    first_frame_at_ms: null,
    frame_count: 0,
    frame_entity_ids: [],
    late_frame_at_ms: null,
    delivery_latency_ms: null,
    pull_supplied_state: null,
    channel_error: null,
    outcome: "channel_error",
  };

  const t0 = performance.now();

  // A real authenticated session, the same path the app takes. The session must
  // exist *before* the channel is created: supabase-js only propagates the
  // access token to the Realtime socket on the auth state change, and a channel
  // opened first would be evaluated by Realtime as `anon`.
  const client = createClient(url, anonKey, { auth: { persistSession: false } });
  const signIn = await client.auth.signInWithPassword({
    email: SEED_ACTOR,
    password: SEED_PASSWORD,
  });
  if (signIn.error) throw new Error(`local_sign_in_failed:${signIn.error.message}`);
  const session = (await client.auth.getSession()).data.session;
  if (!session?.access_token) throw new Error("local_session_missing");

  const device = crypto.randomUUID();
  const registered = await client.rpc("register_sync_device", {
    device_id: device,
    requested_app_install_id: `repro-${index}-${crypto.randomUUID()}`,
    requested_display_label: `REPRO ${index}`,
  });
  if (registered.error) throw new Error(`local_device_failed:${registered.error.message}`);

  const cursorBefore = Number(
    (await client.rpc("pull_sync_changes", {
      after_cursor: 0,
      batch_limit: 500,
      device_id: device,
    })).data?.next_cursor ?? 0,
  );

  const channel = client.channel(`repro-${index}-${crypto.randomUUID()}`)
    .on(
      "postgres_changes",
      { event: "INSERT", schema: "public", table: "sync_change_journal" },
      (payload) => {
        const row = payload.new as Record<string, unknown>;
        it.frame_count += 1;
        it.frame_entity_ids.push(String(row.entity_id));
        if (String(row.entity_id) === SEED_ROOM) {
          if (it.first_frame_at_ms === null) it.first_frame_at_ms = ms(t0);
          else it.late_frame_at_ms ??= ms(t0);
        }
      },
    );

  const subscribed = await new Promise<boolean>((resolve) => {
    const timer = setTimeout(() => resolve(false), SUBSCRIBE_TIMEOUT_MS);
    channel.subscribe((status, error) => {
      it.statuses.push({ status: String(status), at_ms: ms(t0) });
      if (error) it.channel_error = String(error).slice(0, 200);
      if (status === "SUBSCRIBED") {
        it.subscribed_at_ms = ms(t0);
        clearTimeout(timer);
        resolve(true);
      } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        clearTimeout(timer);
        resolve(false);
      }
    });
  });

  if (!subscribed) {
    it.outcome = "channel_error";
    await client.removeChannel(channel);
    return it;
  }

  // The mutation. Service role, exactly as the production canary does it.
  const marker = `REPRO ${index} invalidated ${crypto.randomUUID().slice(0, 8)}`;
  const renamed = await service.from("rooms")
    .update({ name: marker, updated_at: new Date().toISOString() })
    .eq("id", SEED_ROOM);
  if (renamed.error) throw new Error(`local_rename_failed:${renamed.error.message}`);
  it.mutation_at_ms = ms(t0);

  // Hop 1: did the trigger write a journal row at all? Service role, so this
  // answers the question without RLS in the way.
  const journal = await service.from("sync_change_journal")
    .select("change_seq")
    .eq("entity_id", SEED_ROOM)
    .gt("change_seq", cursorBefore)
    .order("change_seq", { ascending: false })
    .limit(1);
  if (journal.data && journal.data.length > 0) {
    it.journal_confirmed_at_ms = ms(t0);
    it.journal_change_seq = Number(journal.data[0].change_seq);
  }

  // Hop 2: can the subscribing actor SELECT that row under RLS? This is the
  // exact predicate Realtime evaluates per subscriber, and — importantly — no
  // check in the production canary exercises it: the pull RPC is SECURITY
  // DEFINER and bypasses the journal policy entirely.
  if (it.journal_change_seq !== null) {
    const visible = await client.from("sync_change_journal")
      .select("change_seq")
      .eq("change_seq", it.journal_change_seq);
    it.actor_select_visible = !visible.error && (visible.data?.length ?? 0) > 0;
    it.actor_select_at_ms = ms(t0);
  }

  // Hop 3: the frame.
  const deadline = performance.now() + FRAME_TIMEOUT_MS;
  while (performance.now() < deadline && it.first_frame_at_ms === null) {
    await new Promise((r) => setTimeout(r, 50));
  }
  const timedOut = it.first_frame_at_ms === null;
  if (timedOut) {
    // Bounded grace observation, for diagnosis only. The verdict is already
    // decided: a frame that lands here is late, and late is a failure.
    const graceDeadline = performance.now() + GRACE_WINDOW_MS;
    while (performance.now() < graceDeadline && it.first_frame_at_ms === null) {
      await new Promise((r) => setTimeout(r, 100));
    }
    if (it.first_frame_at_ms !== null) {
      it.late_frame_at_ms = it.first_frame_at_ms;
      it.first_frame_at_ms = null;
    }
  }

  if (it.first_frame_at_ms !== null && it.mutation_at_ms !== null) {
    it.delivery_latency_ms = it.first_frame_at_ms - it.mutation_at_ms;
  }

  const after = await client.rpc("pull_sync_changes", {
    after_cursor: cursorBefore,
    batch_limit: 200,
    device_id: device,
  });
  it.pull_supplied_state = !after.error &&
    (after.data?.changes ?? []).some((c: Record<string, unknown>) =>
      c.entity_id === SEED_ROOM &&
      String((c.payload as Record<string, unknown> ?? {}).name ?? "") === marker
    );

  it.outcome = classifyRealtimeOutcome({
    subscribed: true,
    channelError: it.channel_error,
    journalCreated: it.journal_change_seq !== null,
    actorSelectVisible: it.actor_select_visible,
    frameSeen: it.first_frame_at_ms !== null,
    lateFrameSeen: it.late_frame_at_ms !== null,
  } satisfies FrameObservation);

  await client.removeChannel(channel);
  await client.auth.signOut();
  return it;
}

async function main(): Promise<number> {
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) {
    console.error("refused: local_supabase_env_missing");
    return 2;
  }
  assertLocalTarget(url);

  // Refuse to run if a production contract is loaded in the same environment.
  if ((Deno.env.get("AISH_TARGET_ENV") ?? "").toLowerCase() === "production") {
    console.error("refused: production_environment_loaded");
    return 2;
  }

  const service = createClient(url, serviceKey, { auth: { persistSession: false } });

  const originalName = (await service.from("rooms").select("name").eq("id", SEED_ROOM)
    .single()).data?.name as string | undefined;

  const iterations: Iteration[] = [];
  try {
    for (let i = 1; i <= ITERATIONS; i += 1) {
      const it = await runIteration(i, url, anonKey, service);
      iterations.push(it);
      console.log(
        `iter ${String(i).padStart(2, " ")}  ${it.outcome.padEnd(38, " ")} ` +
          `subscribed=${it.subscribed_at_ms}ms mutation=${it.mutation_at_ms}ms ` +
          `journal=${it.journal_confirmed_at_ms}ms actor_select=${it.actor_select_visible} ` +
          `frame=${it.first_frame_at_ms}ms latency=${it.delivery_latency_ms}ms ` +
          `frames=${it.frame_count}`,
      );
    }
  } finally {
    // Local fixture restored. The seed row is shared with the local 12C
    // harness, whose cursor arithmetic assumes a known name.
    if (originalName) {
      await service.from("rooms").update({ name: originalName }).eq("id", SEED_ROOM);
    }
  }

  const latencies = iterations
    .map((it) => it.delivery_latency_ms)
    .filter((v): v is number => v !== null);
  const stats = summariseLatencies(latencies);
  const delivered = iterations.filter((it) => it.outcome === "delivered").length;

  const report = {
    tool: "realtime_journal_local_repro",
    environment: "local",
    target_host: new URL(url).hostname,
    iterations: ITERATIONS,
    delivered,
    timed_out: iterations.filter((it) => it.first_frame_at_ms === null).length,
    outcomes: Object.fromEntries(
      [...new Set(iterations.map((it) => it.outcome))].map((
        o,
      ) => [o, iterations.filter((it) => it.outcome === o).length]),
    ),
    latency_ms: stats,
    detail: iterations,
  };
  console.log("\n" + JSON.stringify(report, null, 2));
  return delivered === ITERATIONS ? 0 : 1;
}

Deno.exit(await main());
