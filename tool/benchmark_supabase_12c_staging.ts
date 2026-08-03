// Journal and pull-RPC measurement against staging.
//
// The numbers this produces are *observations*, not an SLA. They come from a
// staging project whose data volume is whatever it happens to be, and the
// report says so explicitly rather than letting a reader infer a guarantee. Its
// purpose is to answer the questions §3 of `supabase_12c_remote_handoff.md`
// leaves open: what does one journal INSERT per mutation cost, how does the
// pull RPC scale with page size, and what does the commit horizon do when a
// long transaction holds the queue head.
//
// Bounded by construction: a concurrency cap, a per-call timeout, a fixture
// ceiling, and cleanup in a `finally`. It never holds a lock on staging for
// longer than the head-of-line probe it declares.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
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
import { pull } from "./staging_sync_envelope.ts";

const PAGE_SIZES = [0, 1, 50, 200, 500];
const SAMPLES = Number(Deno.env.get("AISH_BENCH_SAMPLES") ?? "20");
const MAX_FIXTURE_WRITES = Number(
  Deno.env.get("AISH_BENCH_MAX_FIXTURE_WRITES") ?? "600",
);
const CONCURRENCY_CAP = Number(Deno.env.get("AISH_BENCH_CONCURRENCY") ?? "4");
const CALL_TIMEOUT_MS = Number(Deno.env.get("AISH_BENCH_TIMEOUT_MS") ?? "30000");

// Starting thresholds, deliberately generous. They exist so a regression has
// something to trip over, not because these are the numbers the product needs.
const THRESHOLDS = {
  empty_page_p95_ms: Number(Deno.env.get("AISH_BENCH_EMPTY_P95_MS") ?? "400"),
  page_200_p95_ms: Number(Deno.env.get("AISH_BENCH_PAGE200_P95_MS") ?? "2500"),
  page_500_p95_ms: Number(Deno.env.get("AISH_BENCH_PAGE500_P95_MS") ?? "5000"),
  catch_up_from_zero_p95_ms: Number(
    Deno.env.get("AISH_BENCH_CATCHUP_P95_MS") ?? "15000",
  ),
};

type Timings = {
  samples: number;
  min_ms: number;
  p50_ms: number;
  p95_ms: number;
  p99_ms: number;
  max_ms: number;
  mean_ms: number;
};

function summarise(values: number[]): Timings {
  const sorted = [...values].sort((left, right) => left - right);
  const at = (quantile: number) =>
    sorted.length === 0
      ? 0
      : Math.round(sorted[Math.min(sorted.length - 1, Math.floor(quantile * sorted.length))] * 100) /
        100;
  return {
    samples: sorted.length,
    min_ms: at(0),
    p50_ms: at(0.5),
    p95_ms: at(0.95),
    p99_ms: at(0.99),
    max_ms: at(0.999),
    mean_ms: sorted.length === 0
      ? 0
      : Math.round((sorted.reduce((sum, value) => sum + value, 0) / sorted.length) * 100) / 100,
  };
}

async function timed<T>(attempt: () => Promise<T>): Promise<[T, number]> {
  const started = performance.now();
  const value = await withTimeout(attempt(), CALL_TIMEOUT_MS);
  return [value, performance.now() - started];
}

function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return Promise.race([
    promise,
    new Promise<T>((_, reject) =>
      setTimeout(() => reject(new Error("benchmark_call_timeout")), ms)
    ),
  ]);
}

/// Runs `tasks` with a hard concurrency cap, so a benchmark can never become an
/// unintentional load test against a shared staging project.
async function bounded<T>(
  tasks: Array<() => Promise<T>>,
  cap: number,
): Promise<T[]> {
  const output: T[] = new Array(tasks.length);
  let next = 0;
  const workers = Array.from({ length: Math.min(cap, tasks.length) }, async () => {
    for (;;) {
      const index = next;
      next += 1;
      if (index >= tasks.length) return;
      output[index] = await tasks[index]();
    }
  });
  await Promise.all(workers);
  return output;
}

async function main(): Promise<number> {
  const target = resolveStagingTarget({
    mutating: true,
    requireServiceRole: true,
    requireFixturePassword: true,
  });
  describeTarget(target, "benchmark_supabase_12c_staging");
  safeLog(
    `limits      = samples=${SAMPLES} fixtures<=${MAX_FIXTURE_WRITES} ` +
      `concurrency<=${CONCURRENCY_CAP} timeout=${CALL_TIMEOUT_MS}ms`,
  );

  const fixtures = await StagingFixtures.create(
    target,
    runNamespace(`${target.namespace}-bench`),
  );
  const service = fixtures.serviceClient();
  let cleanup: { ok: boolean; problems: string[] } = { ok: true, problems: [] };
  const startedAt = new Date().toISOString();
  const measurements: Record<string, unknown> = {};
  const notes: string[] = [];

  try {
    const before = await snapshot(service);
    measurements.journal_before = before.journal;

    const nurse = await fixtures.signIn("nurseA");
    const device = await fixtures.registerDevice(nurse, "bench");

    // -----------------------------------------------------------------------
    // Journal growth per workflow step
    // -----------------------------------------------------------------------
    const growthStart = Number(before.journal.rows);
    const writes = Math.min(MAX_FIXTURE_WRITES, 200);
    const writeTimings: number[] = [];
    for (let index = 0; index < writes; index += 1) {
      const [, elapsed] = await timed(async () => {
        const result = await service.from("rooms").update({
          name: `${fixtures.set.namespace} bench-${index}`,
          updated_at: new Date().toISOString(),
        }).eq("id", fixtures.set.roomA);
        if (result.error) throw result.error;
      });
      writeTimings.push(elapsed);
    }
    const afterWrites = await snapshot(service);
    measurements.write_with_journal_trigger = summarise(writeTimings);
    measurements.journal_growth = {
      writes,
      rows_added: Number(afterWrites.journal.rows) - growthStart,
      rows_per_write:
        Math.round(
          ((Number(afterWrites.journal.rows) - growthStart) / writes) * 100,
        ) / 100,
      bytes_added: Number(afterWrites.journal.total_bytes) -
        Number(before.journal.total_bytes),
    };

    // -----------------------------------------------------------------------
    // Pull latency by page size
    // -----------------------------------------------------------------------
    const head = (await pull(nurse, device, 0, 1)).server_horizon;
    const byPageSize: Record<string, unknown> = {};
    for (const size of PAGE_SIZES) {
      const emptyPage = size === 0;
      const limit = emptyPage ? 1 : size;
      const cursor = emptyPage ? head : 0;
      const timings: number[] = [];
      let emitted = 0;
      const tasks = Array.from({ length: SAMPLES }, () => async () => {
        const [page, elapsed] = await timed(() =>
          pull(nurse, device, cursor, limit)
        );
        timings.push(elapsed);
        emitted = page.changes.length;
      });
      await bounded(tasks, CONCURRENCY_CAP);
      byPageSize[emptyPage ? "empty" : String(size)] = {
        ...summarise(timings),
        rows_emitted: emitted,
        cursor_start: cursor,
      };
      safeLog(
        `pull ${String(emptyPage ? "empty" : size).padStart(5, " ")}  ` +
          `p50=${summarise(timings).p50_ms}ms p95=${summarise(timings).p95_ms}ms ` +
          `p99=${summarise(timings).p99_ms}ms emitted=${emitted}`,
      );
    }
    measurements.pull_by_page_size = byPageSize;

    // -----------------------------------------------------------------------
    // Catch-up: a fresh device from zero, and a caught-up device at the head
    // -----------------------------------------------------------------------
    const [fromZero, fromZeroMs] = await timed(async () => {
      let cursor = 0;
      let pages = 0;
      let rows = 0;
      for (;;) {
        const page = await pull(nurse, device, cursor, 500);
        rows += page.changes.length;
        cursor = page.next_cursor;
        pages += 1;
        if (!page.has_more || pages >= 500) break;
      }
      return { pages, rows, cursor };
    });
    measurements.catch_up_from_zero = { ...fromZero, elapsed_ms: Math.round(fromZeroMs) };

    const atHead: number[] = [];
    for (let index = 0; index < SAMPLES; index += 1) {
      const [, elapsed] = await timed(() =>
        pull(nurse, device, fromZero.cursor, 500)
      );
      atHead.push(elapsed);
    }
    measurements.catch_up_from_head = summarise(atHead);

    // -----------------------------------------------------------------------
    // Head-of-line: what a long transaction does to the horizon
    // -----------------------------------------------------------------------
    // Bounded and declared. PostgREST gives no way to hold a transaction open
    // across requests, so this measures the horizon's *reaction* to a burst
    // rather than to an artificially held lock — which is the honest thing this
    // harness can measure without a database connection it is not allowed to
    // have.
    const horizonBefore = (await pull(nurse, device, 0, 1)).server_horizon;
    const burstSize = Math.min(50, MAX_FIXTURE_WRITES - writes);
    const burstTasks = Array.from({ length: burstSize }, (_, index) => async () => {
      const result = await service.from("rooms").update({
        name: `${fixtures.set.namespace} burst-${index}`,
        updated_at: new Date().toISOString(),
      }).eq("id", fixtures.set.roomA);
      if (result.error) throw result.error;
    });
    const [, burstMs] = await timed(() => bounded(burstTasks, CONCURRENCY_CAP));
    let horizonAfter = horizonBefore;
    let horizonSettleMs = 0;
    const settleStart = performance.now();
    for (let attempt = 0; attempt < 50; attempt += 1) {
      const page = await pull(nurse, device, 0, 1);
      horizonAfter = page.server_horizon;
      if (horizonAfter >= horizonBefore + burstSize) break;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    horizonSettleMs = performance.now() - settleStart;
    measurements.head_of_line = {
      burst_size: burstSize,
      burst_elapsed_ms: Math.round(burstMs),
      horizon_before: horizonBefore,
      horizon_after: horizonAfter,
      horizon_settle_ms: Math.round(horizonSettleMs),
      horizon_advanced: horizonAfter > horizonBefore,
    };

    // Realtime burst is measured by the dedicated Realtime harness, which owns
    // the websocket. Saying so here beats reporting a number this tool did not
    // take.
    notes.push(
      "Realtime burst and coalescing are measured by " +
        "tool/supabase_12c_realtime_staging_e2e.ts, not here.",
    );

    // -----------------------------------------------------------------------
    // Backfill throughput
    // -----------------------------------------------------------------------
    const [backfillDry, backfillMs] = await timed(async () => {
      const result = await service.rpc("admin_backfill_sync_change_journal", {
        run_id: crypto.randomUUID(),
        backfill_revision: Deno.env.get("AISH_BACKFILL_REVISION") ??
          "aish-supabase-003-baseline",
        batch_size: 500, max_batches: 1, dry_run: true,
      });
      if (result.error) throw result.error;
      return result.data as { batches: Array<Record<string, number>> };
    });
    const scanned = backfillDry.batches?.[0]?.scanned ?? 0;
    measurements.backfill_throughput = {
      mode: "dry_run",
      batch_scanned: scanned,
      elapsed_ms: Math.round(backfillMs),
      rows_per_second: backfillMs > 0
        ? Math.round((scanned / backfillMs) * 1000)
        : 0,
    };

    const after = await snapshot(service);
    measurements.journal_after = after.journal;

    if (Number(after.journal.rows) < 500) {
      notes.push(
        `Staging holds only ${after.journal.rows} journal rows. These figures ` +
          "describe a small dataset and must not be read as production " +
          "behaviour; re-measure once staging carries a realistic volume.",
      );
    }
  } catch (error) {
    notes.push(`benchmark_incomplete: ${redact(error)}`);
    safeError(`benchmark_incomplete: ${redact(error)}`);
  } finally {
    cleanup = await fixtures.cleanup();
  }

  const breaches: string[] = [];
  const pullResults = measurements.pull_by_page_size as Record<string, Timings> | undefined;
  const checkThreshold = (label: string, actual: number | undefined, limit: number) => {
    if (actual === undefined) return;
    if (actual > limit) breaches.push(`${label}: ${actual}ms > ${limit}ms`);
  };
  checkThreshold("empty_page_p95", pullResults?.empty?.p95_ms, THRESHOLDS.empty_page_p95_ms);
  checkThreshold("page_200_p95", pullResults?.["200"]?.p95_ms, THRESHOLDS.page_200_p95_ms);
  checkThreshold("page_500_p95", pullResults?.["500"]?.p95_ms, THRESHOLDS.page_500_p95_ms);
  checkThreshold(
    "catch_up_from_zero",
    (measurements.catch_up_from_zero as { elapsed_ms?: number } | undefined)?.elapsed_ms,
    THRESHOLDS.catch_up_from_zero_p95_ms,
  );

  const report = {
    ok: breaches.length === 0 && cleanup.ok,
    tool: "benchmark_supabase_12c_staging",
    environment: "staging",
    project_ref: target.maskedRef,
    host: target.host,
    branch: target.branch,
    commit: target.commit,
    namespace: fixtures.set.namespace,
    started_at_utc: startedAt,
    finished_at_utc: new Date().toISOString(),
    disclaimer:
      "Baseline observations from a staging project. Not an SLA and not a " +
      "production projection.",
    limits: {
      samples: SAMPLES,
      max_fixture_writes: MAX_FIXTURE_WRITES,
      concurrency_cap: CONCURRENCY_CAP,
      call_timeout_ms: CALL_TIMEOUT_MS,
    },
    thresholds: THRESHOLDS,
    threshold_breaches: breaches,
    notes,
    cleanup_ok: cleanup.ok,
    cleanup_problems: cleanup.problems,
    measurements,
  };

  const stamp = utcStamp();
  const jsonPath = await writeArtifact(
    `12c-performance-${stamp}`, "json", JSON.stringify(report, null, 2),
  );
  const markdownPath = await writeArtifact(
    `12c-performance-${stamp}`, "markdown", toMarkdown(report),
  );
  safeLog(`report      = ${jsonPath}`);
  safeLog(`report      = ${markdownPath}`);
  safeLog(`result      = ${report.ok ? "WITHIN THRESHOLDS" : "REVIEW REQUIRED"}`);
  if (breaches.length > 0) safeLog(`breaches    = ${breaches.join("; ")}`);
  return report.ok ? 0 : 1;
}

async function snapshot(
  service: SupabaseClient,
): Promise<{ journal: Record<string, unknown> }> {
  const result = await service.rpc("admin_sync_rollout_verification");
  if (result.error) throw result.error;
  const data = result.data as { journal: Record<string, unknown> };
  return { journal: data.journal };
}

function toMarkdown(report: Record<string, any>): string {
  const measurements = report.measurements ?? {};
  const pageRows = Object.entries(measurements.pull_by_page_size ?? {})
    .map(([size, value]: [string, any]) =>
      `| ${size} | ${value.rows_emitted} | ${value.p50_ms} | ${value.p95_ms} | ${value.p99_ms} | ${value.max_ms} |`
    ).join("\n");
  return `# Milestone 12C staging performance — ${report.finished_at_utc}

> ${report.disclaimer}

Target: staging \`${report.host}\` (project \`${report.project_ref}\`), branch
\`${report.branch}\` at \`${report.commit}\`.

## Journal

| Metric | Before | After |
| --- | --- | --- |
| rows | ${measurements.journal_before?.rows ?? "-"} | ${measurements.journal_after?.rows ?? "-"} |
| table bytes | ${measurements.journal_before?.table_bytes ?? "-"} | ${measurements.journal_after?.table_bytes ?? "-"} |
| index bytes | ${measurements.journal_before?.index_bytes ?? "-"} | ${measurements.journal_after?.index_bytes ?? "-"} |
| total bytes | ${measurements.journal_before?.total_bytes ?? "-"} | ${measurements.journal_after?.total_bytes ?? "-"} |
| max change_seq | ${measurements.journal_before?.max_change_seq ?? "-"} | ${measurements.journal_after?.max_change_seq ?? "-"} |

Growth per business write: ${measurements.journal_growth?.rows_per_write ?? "-"}
journal row(s) over ${measurements.journal_growth?.writes ?? "-"} writes
(${measurements.journal_growth?.bytes_added ?? "-"} bytes).

Write latency with the journal trigger active:
p50 ${measurements.write_with_journal_trigger?.p50_ms ?? "-"} ms,
p95 ${measurements.write_with_journal_trigger?.p95_ms ?? "-"} ms.

## Pull RPC

| Page size | Rows emitted | p50 (ms) | p95 (ms) | p99 (ms) | max (ms) |
| --- | --- | --- | --- | --- | --- |
${pageRows}

Catch-up from cursor 0: ${measurements.catch_up_from_zero?.rows ?? "-"} rows over
${measurements.catch_up_from_zero?.pages ?? "-"} pages in
${measurements.catch_up_from_zero?.elapsed_ms ?? "-"} ms.

Catch-up from the head (empty result):
p50 ${measurements.catch_up_from_head?.p50_ms ?? "-"} ms,
p95 ${measurements.catch_up_from_head?.p95_ms ?? "-"} ms.

## Commit horizon

Burst of ${measurements.head_of_line?.burst_size ?? "-"} writes committed in
${measurements.head_of_line?.burst_elapsed_ms ?? "-"} ms; the horizon advanced
from ${measurements.head_of_line?.horizon_before ?? "-"} to
${measurements.head_of_line?.horizon_after ?? "-"} after
${measurements.head_of_line?.horizon_settle_ms ?? "-"} ms.

## Backfill

Dry-run scan of ${measurements.backfill_throughput?.batch_scanned ?? "-"} rows in
${measurements.backfill_throughput?.elapsed_ms ?? "-"} ms
(~${measurements.backfill_throughput?.rows_per_second ?? "-"} rows/s).

## Thresholds

${
    (report.threshold_breaches ?? []).length === 0
      ? "All observed values sit within the configured starting thresholds."
      : `Breached:\n\n${(report.threshold_breaches as string[]).map((entry) => `- ${entry}`).join("\n")}`
  }

Configured: ${JSON.stringify(report.thresholds)}

## Notes

${(report.notes ?? []).map((note: string) => `- ${note}`).join("\n") || "- none"}
`;
}

try {
  Deno.exit(await main());
} catch (error) {
  safeError(`benchmark_failed: ${redact(error)}`);
  Deno.exit(2);
}
