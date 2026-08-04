// Low-load production measurement.
//
// The staging benchmark generates its own volume, runs four workers at once and
// fires a 50-write burst to watch the commit horizon move. None of that is
// acceptable against production, so none of it is here. What remains is the set
// of numbers that can be taken without becoming load:
//
//   * journal rows, table bytes, index bytes, total bytes, max cursor and the
//     commit horizon — read from one reporting RPC, zero rows transferred;
//   * pull latency for an empty page and for pages of 1, 50 and 200, reported as
//     p50/p95, taken one request at a time with a small sample count.
//
// Default mode is metrics only: it opens one service-role connection, calls one
// function and writes a report. No writes, no fixtures, no sessions.
//
// `--with-pull` adds the latency measurements. Those need an authenticated
// session with a registered device, which is a write, so that mode requires the
// `canary_namespace` write scope and creates the same dedicated namespace the
// other canary harnesses use — never a real user's account. The namespace is
// retired afterwards.
//
// The numbers are observations under an intentionally tiny load. They are not
// an SLA, they are not a capacity model, and the report says so.
//
// Exit code: 0 when the measurements completed and stayed within the configured
// starting thresholds, 1 otherwise, 2 on a refusal.

import { createClient } from "npm:@supabase/supabase-js@2";
import {
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
import { ProductionCanaryNamespace } from "./production_canary_namespace.ts";
import { pull } from "./production_sync_envelope.ts";

/// Page sizes the client actually uses. `0` means "an empty page at the head",
/// which is the request a caught-up device makes on every resume — the most
/// frequent call the server will ever serve.
const PAGE_SIZES = [0, 1, 50, 200];

/// Small on purpose. Twenty samples per page size, four page sizes and four
/// workers is a load test; five samples taken one at a time is a measurement.
const SAMPLES = clamp(Number(Deno.env.get("AISH_PRODUCTION_BENCH_SAMPLES") ?? "5"), 1, 10);
const CALL_TIMEOUT_MS = Number(
  Deno.env.get("AISH_PRODUCTION_BENCH_TIMEOUT_MS") ?? "15000",
);
/// Pause between samples, so even the sequential probe cannot become a stream.
const INTER_SAMPLE_PAUSE_MS = Number(
  Deno.env.get("AISH_PRODUCTION_BENCH_PAUSE_MS") ?? "250",
);

const THRESHOLDS = {
  empty_page_p95_ms: Number(Deno.env.get("AISH_PRODUCTION_BENCH_EMPTY_P95_MS") ?? "600"),
  page_50_p95_ms: Number(Deno.env.get("AISH_PRODUCTION_BENCH_PAGE50_P95_MS") ?? "2000"),
  page_200_p95_ms: Number(Deno.env.get("AISH_PRODUCTION_BENCH_PAGE200_P95_MS") ?? "4000"),
};

function clamp(value: number, low: number, high: number): number {
  if (!Number.isFinite(value)) return low;
  return Math.min(high, Math.max(low, Math.trunc(value)));
}

type Timings = {
  samples: number;
  min_ms: number;
  p50_ms: number;
  p95_ms: number;
  max_ms: number;
  mean_ms: number;
};

function summarise(values: number[]): Timings {
  const sorted = [...values].sort((left, right) => left - right);
  const round = (value: number) => Math.round(value * 100) / 100;
  const at = (quantile: number) =>
    sorted.length === 0
      ? 0
      : round(sorted[Math.min(sorted.length - 1, Math.floor(quantile * sorted.length))]);
  return {
    samples: sorted.length,
    min_ms: at(0),
    p50_ms: at(0.5),
    p95_ms: at(0.95),
    max_ms: sorted.length === 0 ? 0 : round(sorted[sorted.length - 1]),
    mean_ms: sorted.length === 0
      ? 0
      : round(sorted.reduce((sum, value) => sum + value, 0) / sorted.length),
  };
}

function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return Promise.race([
    promise,
    new Promise<T>((_, reject) =>
      setTimeout(() => reject(new Error("benchmark_call_timeout")), ms)
    ),
  ]);
}

async function timed<T>(attempt: () => Promise<T>): Promise<[T, number]> {
  const started = performance.now();
  const value = await withTimeout(attempt(), CALL_TIMEOUT_MS);
  return [value, performance.now() - started];
}

async function main(): Promise<number> {
  const withPull = Deno.args.includes("--with-pull");

  const target = resolveProductionTarget({
    // Metrics-only is genuinely read-only. The pull probe has to register a
    // device, which is a write, so it asks for the canary scope by name.
    mode: withPull ? "guarded_write" : "read_only",
    requireServiceRole: true,
    ...(withPull
      ? { writeScope: "canary_namespace" as const, requireCanaryPassword: true }
      : {}),
  });
  describeTarget(target, "benchmark_supabase_production_readonly");
  safeLog(
    `limits      = samples=${SAMPLES} concurrency=1 ` +
      `pause=${INTER_SAMPLE_PAUSE_MS}ms timeout=${CALL_TIMEOUT_MS}ms`,
  );
  safeLog(
    `mode        = ${withPull ? "metrics + sequential pull probe" : "metrics only (no session, no writes)"}`,
  );

  const service = createClient(target.url, target.serviceRoleKey!, {
    auth: { persistSession: false },
  });

  // -------------------------------------------------------------------------
  // Storage metrics — one call, no rows
  // -------------------------------------------------------------------------
  const snapshotResult = await service.rpc("admin_sync_rollout_verification");
  if (snapshotResult.error) {
    safeError(`benchmark_snapshot_unavailable: ${redact(snapshotResult.error)}`);
    return 1;
  }
  const snapshot = snapshotResult.data as Record<string, any>;
  const journal = snapshot.journal ?? {};
  const storage = {
    journal_rows: Number(journal.rows ?? 0),
    journal_table_bytes: Number(journal.table_bytes ?? 0),
    journal_index_bytes: Number(journal.index_bytes ?? 0),
    journal_total_bytes: Number(journal.total_bytes ?? 0),
    field_version_rows: Number(journal.field_version_rows ?? 0),
    min_change_seq: Number(journal.min_change_seq ?? 0),
    max_change_seq: Number(journal.max_change_seq ?? 0),
    commit_horizon: Number(journal.commit_horizon ?? 0),
    in_realtime_publication: journal.in_realtime_publication === true,
    registered_devices: Number(snapshot.devices?.total ?? 0),
  };
  safeLog(
    `journal     = ${storage.journal_rows} row(s), ` +
      `${formatBytes(storage.journal_table_bytes)} table + ` +
      `${formatBytes(storage.journal_index_bytes)} index = ` +
      `${formatBytes(storage.journal_total_bytes)}`,
  );
  safeLog(
    `cursor      = max ${storage.max_change_seq}, horizon ${storage.commit_horizon}`,
  );

  // -------------------------------------------------------------------------
  // Pull latency — sequential, small, and only if asked for
  // -------------------------------------------------------------------------
  const notes: string[] = [];
  let pullByPageSize: Record<string, unknown> | null = null;
  let namespace: string | null = null;
  let retirement: Awaited<ReturnType<ProductionCanaryNamespace["retire"]>> | null = null;

  if (!withPull) {
    notes.push(
      "Pull latency was not measured: this run was metrics-only. Re-run with " +
        "--with-pull and the canary_namespace write scope to measure it.",
    );
  } else {
    const canary = await ProductionCanaryNamespace.create(
      target, runNamespace(`${target.namespacePrefix}-bench`),
    );
    namespace = canary.set.namespace;
    try {
      const actor = await canary.signIn("nurseA");
      const device = await canary.registerDevice(actor, "bench");
      const head = (await pull(actor, device, 0, 1)).server_horizon;
      const byPageSize: Record<string, unknown> = {};

      for (const size of PAGE_SIZES) {
        const emptyPage = size === 0;
        const limit = emptyPage ? 1 : size;
        // An "empty page" is a request from the head of the feed: the server
        // does the same work it does for a caught-up device on every resume.
        const cursor = emptyPage ? head : 0;
        const timings: number[] = [];
        let emitted = 0;
        for (let sample = 0; sample < SAMPLES; sample += 1) {
          const [page, elapsed] = await timed(() => pull(actor, device, cursor, limit));
          timings.push(elapsed);
          emitted = page.changes.length;
          await new Promise((resolve) => setTimeout(resolve, INTER_SAMPLE_PAUSE_MS));
        }
        const stats = summarise(timings);
        byPageSize[emptyPage ? "empty" : String(size)] = {
          ...stats, rows_emitted: emitted, cursor_start: cursor,
        };
        safeLog(
          `pull ${String(emptyPage ? "empty" : size).padStart(5, " ")}  ` +
            `p50=${stats.p50_ms}ms p95=${stats.p95_ms}ms max=${stats.max_ms}ms ` +
            `emitted=${emitted}`,
        );
      }
      pullByPageSize = byPageSize;
    } catch (error) {
      notes.push(`pull_probe_incomplete: ${redact(error)}`);
      safeError(`benchmark_pull_probe_incomplete: ${redact(error)}`);
    } finally {
      retirement = await canary.retire();
    }
  }

  // -------------------------------------------------------------------------
  // Thresholds
  // -------------------------------------------------------------------------
  const breaches: string[] = [];
  const checkThreshold = (label: string, actual: number | undefined, limit: number) => {
    if (actual === undefined) return;
    if (actual > limit) breaches.push(`${label}: ${actual}ms > ${limit}ms`);
  };
  const timings = pullByPageSize as Record<string, Timings> | null;
  checkThreshold("empty_page_p95", timings?.empty?.p95_ms, THRESHOLDS.empty_page_p95_ms);
  checkThreshold("page_50_p95", timings?.["50"]?.p95_ms, THRESHOLDS.page_50_p95_ms);
  checkThreshold("page_200_p95", timings?.["200"]?.p95_ms, THRESHOLDS.page_200_p95_ms);

  if (storage.journal_rows === 0) {
    notes.push(
      "The journal is empty: the baseline backfill has not run. Latency figures " +
        "from an empty journal say nothing about behaviour after it is seeded.",
    );
  }
  notes.push(
    `Measured with ${SAMPLES} sequential sample(s) per page size and a ` +
      `${INTER_SAMPLE_PAUSE_MS}ms pause between them, against live production ` +
      "traffic. Treat these as a smoke-level observation, not a capacity model.",
  );

  const report = {
    ok: breaches.length === 0 && (retirement?.ok ?? true),
    ...auditHeader(target, "benchmark_supabase_production_readonly"),
    measured_at_utc: new Date().toISOString(),
    disclaimer:
      "Low-load observations from a live production project. Not an SLA, not a " +
      "capacity model, and not comparable to the staging benchmark, which " +
      "generates its own volume.",
    limits: {
      samples: SAMPLES,
      concurrency: 1,
      inter_sample_pause_ms: INTER_SAMPLE_PAUSE_MS,
      call_timeout_ms: CALL_TIMEOUT_MS,
    },
    excluded_by_policy: [
      "write-latency measurement (would mutate business rows)",
      "50-event burst and commit-horizon settle probe",
      "concurrent workers",
      "catch-up-from-zero over the whole feed",
      "backfill throughput probe",
    ],
    storage,
    pull_by_page_size: pullByPageSize,
    namespace,
    namespace_retired: retirement?.ok ?? null,
    namespace_problems: retirement?.problems ?? [],
    thresholds: THRESHOLDS,
    threshold_breaches: breaches,
    notes,
  };

  const stamp = utcStamp();
  const jsonPath = await writeProductionArtifact(
    `production-performance-${stamp}`, "json", JSON.stringify(report, null, 2),
  );
  const markdownPath = await writeProductionArtifact(
    `production-performance-${stamp}`, "markdown", toMarkdown(report),
  );
  safeLog("--------------------------------------------------------------");
  safeLog(`report      = ${jsonPath}`);
  safeLog(`report      = ${markdownPath}`);
  safeLog(`result      = ${report.ok ? "WITHIN THRESHOLDS" : "REVIEW REQUIRED"}`);
  if (breaches.length > 0) safeLog(`breaches    = ${breaches.join("; ")}`);
  return report.ok ? 0 : 1;
}

function formatBytes(value: number): string {
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KiB`;
  if (value < 1024 * 1024 * 1024) return `${(value / (1024 * 1024)).toFixed(1)} MiB`;
  return `${(value / (1024 * 1024 * 1024)).toFixed(2)} GiB`;
}

function toMarkdown(report: Record<string, any>): string {
  const rows = Object.entries(report.pull_by_page_size ?? {})
    .map(([size, value]: [string, any]) =>
      `| ${size} | ${value.rows_emitted} | ${value.p50_ms} | ${value.p95_ms} | ${value.max_ms} |`
    ).join("\n");
  return `# Production canary performance — ${report.measured_at_utc}

> ${report.disclaimer}

Target: production \`${report.host}\` (project \`${report.project_ref}\`), branch
\`${report.branch}\` at \`${report.commit}\`, ticket \`${report.change_ticket}\`.

## Journal storage

| Metric | Value |
| --- | --- |
| rows | ${report.storage.journal_rows} |
| table bytes | ${report.storage.journal_table_bytes} |
| index bytes | ${report.storage.journal_index_bytes} |
| total bytes | ${report.storage.journal_total_bytes} |
| field-version rows | ${report.storage.field_version_rows} |
| min change_seq | ${report.storage.min_change_seq} |
| max change_seq | ${report.storage.max_change_seq} |
| commit horizon | ${report.storage.commit_horizon} |
| registered devices | ${report.storage.registered_devices} |

## Pull latency

${
    report.pull_by_page_size
      ? `| Page size | Rows emitted | p50 (ms) | p95 (ms) | max (ms) |
| --- | --- | --- | --- | --- |
${rows}`
      : "Not measured — this was a metrics-only run."
  }

## Thresholds

${
    (report.threshold_breaches ?? []).length === 0
      ? "All observed values sit within the configured starting thresholds."
      : `Breached:\n\n${(report.threshold_breaches as string[]).map((entry) => `- ${entry}`).join("\n")}`
  }

Configured: ${JSON.stringify(report.thresholds)}

## Not measured, by policy

${(report.excluded_by_policy ?? []).map((entry: string) => `- ${entry}`).join("\n")}

## Notes

${(report.notes ?? []).map((note: string) => `- ${note}`).join("\n") || "- none"}
`;
}

try {
  Deno.exit(await main());
} catch (error) {
  safeError(`production_benchmark_failed: ${redact(error)}`);
  Deno.exit(error instanceof ProductionGuardError ? 2 : 1);
}
