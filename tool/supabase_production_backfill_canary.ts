// Production-safe driver for the change-journal baseline backfill.
//
// The database function does the work. This exists to drive it in the smallest
// increments the contract allows, to prove between every one of them that no
// business row moved, and to stop the moment anything disagrees.
//
// What makes it production-safe rather than staging-safe:
//
//   * dry run is the default and `--execute` is the only way out of it;
//   * `--max-batches` is mandatory on every invocation — there is no "run until
//     done" mode, because the operator has to choose how much of the window to
//     spend before the run starts, not after;
//   * `--entity-types` is mandatory for a first run, so the first thing that
//     ever touches production is a named, small slice rather than everything;
//   * the batch size defaults to 25 and is capped at 100;
//   * a full invariant snapshot is taken before and after *every* batch, and a
//     single violation aborts the run at that batch boundary;
//   * a concurrent run is refused twice: by the database's advisory transaction
//     lock inside `app_private.backfill_sync_change_journal`, and by this driver
//     checking the run ledger before it starts;
//   * everything is written to a JSON audit record, none of which carries a key.
//
//   deno run ... tool/supabase_production_backfill_canary.ts \
//     --max-batches=2 --entity-types=category
//   deno run ... tool/supabase_production_backfill_canary.ts \
//     --max-batches=2 --entity-types=category --execute
//   deno run ... tool/supabase_production_backfill_canary.ts \
//     --max-batches=4 --execute --resume <run-id>
//
// Exit code: 0 only when every batch completed with zero failures and zero
// invariant violations. 2 is a refusal — nothing was contacted.

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  assertBatchLimited,
  auditHeader,
  describeTarget,
  ProductionGuardError,
  redact,
  resolveProductionTarget,
  retryTransient,
  safeError,
  safeLog,
  utcStamp,
  writeProductionArtifact,
} from "./production_guard.ts";
import {
  compareSnapshots,
  type InvariantSnapshot,
  ProductionInvariants,
  type Violation,
} from "./production_invariants.ts";

/// Entity type to table, mirroring `app_private.pull_table_for_entity_type`.
/// Kept here so the invariant verifier can watch exactly the tables the run is
/// scoped to, plus the two it always watches.
const ENTITY_TABLES: Record<string, string> = {
  branch: "branches",
  room: "rooms",
  user: "users",
  category: "item_categories",
  item: "items",
  batch: "item_batches",
  stock_location: "stock_locations",
  stock_balance: "stock_balances",
  stock_movement: "stock_movements",
  stock_opname: "stock_opnames",
  purchase_request: "purchase_requests",
  delivery_order: "delivery_orders",
  good_receipt: "good_receipts",
  distribution: "distributions",
  disposal: "disposals",
  consumption: "consumptions",
  goods_return: "goods_returns",
};

const MAX_BATCH_SIZE = 100;
const MAX_BATCHES = 50;
const DEFAULT_BATCH_SIZE = 25;
/// A run ledger row touched more recently than this is treated as live.
const RUN_STALENESS_MINUTES = 30;

type BatchReport = {
  run_id: string;
  backfill_revision: string;
  entity_type: string;
  dry_run: boolean;
  scanned: number;
  inserted: number;
  skipped: number;
  failed: number;
  next_checkpoint: { entity_type: string | null; entity_id: string | null };
  completed: boolean;
  duration_ms: number;
  journal_min_seq: number | null;
  journal_max_seq: number | null;
};

type CallReport = {
  run_id: string;
  backfill_revision: string;
  dry_run: boolean;
  completed: boolean;
  batches: BatchReport[];
};

function flag(name: string): boolean {
  return Deno.args.includes(`--${name}`);
}

function option(name: string): string | undefined {
  const prefix = `--${name}=`;
  const inline = Deno.args.find((entry) => entry.startsWith(prefix));
  if (inline) return inline.slice(prefix.length);
  const index = Deno.args.indexOf(`--${name}`);
  const next = index >= 0 ? Deno.args[index + 1] : undefined;
  if (next && !next.startsWith("--")) return next;
  return undefined;
}

async function main(): Promise<number> {
  const execute = flag("execute");
  // `--dry-run` next to `--execute` is a contradiction, not a preference. It is
  // refused rather than resolved in either direction.
  if (execute && flag("dry-run")) {
    safeError("backfill_conflicting_mode: pass either --dry-run or --execute");
    return 2;
  }
  const dryRun = !execute;

  const target = resolveProductionTarget({
    mode: execute ? "guarded_write" : "dry_run",
    requireServiceRole: true,
    ...(execute ? { writeScope: "journal_baseline" as const } : {}),
  });
  describeTarget(target, "supabase_production_backfill_canary");

  // --- Bounds, all mandatory ------------------------------------------------
  const maxBatchesRaw = option("max-batches");
  if (maxBatchesRaw === undefined) {
    safeError(
      "backfill_max_batches_required: pass --max-batches=<1..50>. " +
        "There is no unbounded run against production.",
    );
    return 2;
  }
  const maxBatches = assertBatchLimited("max-batches", Number(maxBatchesRaw), MAX_BATCHES);
  const batchSize = assertBatchLimited(
    "batch-size",
    Number(
      option("batch-size") ??
        Deno.env.get("AISH_PRODUCTION_BACKFILL_BATCH_SIZE") ?? DEFAULT_BATCH_SIZE,
    ),
    MAX_BATCH_SIZE,
  );

  const resumeRunId = option("resume");
  const rawEntityTypes = option("entity-types");
  if (!resumeRunId && !rawEntityTypes) {
    safeError(
      "backfill_entity_types_required: pass --entity-types=<a,b,c> for a first " +
        "run. The first thing to touch production is a named slice, not the " +
        "whole catalogue.",
    );
    return 2;
  }
  let entityTypes: string[] | null = null;
  if (rawEntityTypes) {
    entityTypes = rawEntityTypes.split(",").map((entry) => entry.trim())
      .filter((entry) => entry.length > 0);
    if (entityTypes.length === 0) {
      safeError("backfill_entity_types_empty");
      return 2;
    }
    const unknown = entityTypes.filter((entry) => !(entry in ENTITY_TABLES));
    if (unknown.length > 0) {
      safeError(`backfill_entity_type_unknown: ${unknown.join(",")}`);
      return 2;
    }
  }

  const revision = option("revision") ??
    Deno.env.get("AISH_BACKFILL_REVISION") ?? "aish-supabase-003-baseline";
  const runId = resumeRunId ?? option("run-id") ?? crypto.randomUUID();

  safeLog(
    `bounds      = max-batches=${maxBatches} batch-size=${batchSize} ` +
      `entity-types=${entityTypes?.join(",") ?? "(from resumed run)"}`,
  );
  safeLog(`revision    = ${revision}`);
  safeLog(`run id      = ${runId}`);

  const service = createClient(target.url, target.serviceRoleKey!, {
    auth: { persistSession: false },
  });

  // --- Driver-level lock ----------------------------------------------------
  // `app_private.backfill_sync_change_journal` already takes a transactional
  // advisory lock, so two concurrent calls cannot interleave. That lock is held
  // for one call, though, and a canary is many calls with invariant checks in
  // between. Checking the run ledger first turns "the second operator's batch
  // fails with 55006 halfway through" into "the second operator is told before
  // anything starts".
  const openRuns = await retryTransient("backfill_open_run_scan", async () => {
    const result = await service
      .from("sync_change_journal_backfill_runs")
      .select("run_id, backfill_revision, entity_types, updated_at, completed, failed")
      .eq("backfill_revision", revision)
      .eq("completed", false);
    if (result.error) throw result.error;
    return (result.data ?? []) as Array<Record<string, unknown>>;
  });
  const foreign = openRuns.filter((run) => String(run.run_id) !== runId);
  const live = foreign.filter((run) => {
    const touched = Date.parse(String(run.updated_at ?? ""));
    if (Number.isNaN(touched)) return true;
    return Date.now() - touched < RUN_STALENESS_MINUTES * 60_000;
  });
  if (live.length > 0) {
    safeError(
      `backfill_run_in_progress: another run is open under this revision ` +
        `(${live.map((run) => String(run.run_id)).join(",")}). ` +
        "Resume it with --resume instead of starting a second one.",
    );
    return 2;
  }
  if (foreign.length > 0) {
    safeLog(
      `warning     = ${foreign.length} stale open run(s) under this revision; ` +
        "they are older than the staleness window and are not blocking",
    );
  }

  // --- Resume ---------------------------------------------------------------
  // The resume position comes from the server's own ledger, never from a local
  // file: the server is the only party that knows what actually committed.
  let checkpointType: string | null = null;
  let checkpointId: string | null = null;
  if (resumeRunId) {
    const existing = await service
      .from("sync_change_journal_backfill_runs")
      .select("run_id, backfill_revision, entity_types, last_entity_type, last_entity_id, completed, failed")
      .eq("run_id", resumeRunId)
      .maybeSingle();
    if (existing.error) {
      safeError(`backfill_resume_lookup_failed: ${redact(existing.error)}`);
      return 1;
    }
    if (!existing.data) {
      safeError(`backfill_resume_unknown_run: ${resumeRunId}`);
      return 2;
    }
    const row = existing.data as Record<string, unknown>;
    if (String(row.backfill_revision) !== revision) {
      safeError("backfill_resume_revision_mismatch");
      return 2;
    }
    if (row.completed === true) {
      safeLog(`run ${resumeRunId} is already complete; nothing to resume`);
      return 0;
    }
    const recorded = (row.entity_types ?? null) as string[] | null;
    if (entityTypes && recorded && JSON.stringify(entityTypes) !== JSON.stringify(recorded)) {
      safeError(
        "backfill_resume_scope_mismatch: --entity-types does not match the " +
          "scope this run was started with",
      );
      return 2;
    }
    entityTypes = entityTypes ?? recorded;
    checkpointType = row.last_entity_type === null ? null : String(row.last_entity_type);
    checkpointId = row.last_entity_id === null ? null : String(row.last_entity_id);
    safeLog(
      `resuming    = ${checkpointType ?? "(start)"} / ${checkpointId ?? "(start)"}`,
    );
  }

  // --- Invariants -----------------------------------------------------------
  const watchedTables = (entityTypes ?? Object.keys(ENTITY_TABLES))
    .map((entry) => ENTITY_TABLES[entry]);
  const invariants = ProductionInvariants.forTables(
    service,
    revision,
    watchedTables,
    Number(Deno.env.get("AISH_PRODUCTION_INVARIANT_SAMPLE") ?? "5000"),
  );
  safeLog(`invariants  = watching ${watchedTables.join(", ")} (+ ledger, balances)`);

  const startedAt = new Date().toISOString();
  const coverageBefore = await invariants.coverage();
  let snapshotBefore = await invariants.snapshot("run_start", resumeRunId ?? null);
  snapshotBefore = withDuplicateMarks(snapshotBefore, coverageBefore);
  safeLog(
    `baseline    = journal ${snapshotBefore.journal_rows} row(s), ` +
      `marks ${snapshotBefore.marks_for_revision}, ` +
      `movements ${snapshotBefore.movements.rows}, ` +
      `balances ${snapshotBefore.balances.total_rows} ` +
      `(${snapshotBefore.balances.method})`,
  );
  const runStartSnapshot = snapshotBefore;

  const batches: Array<Record<string, unknown>> = [];
  const totals = { scanned: 0, inserted: 0, skipped: 0, failed: 0 };
  const violations: Array<{ batch: number; violations: Violation[] }> = [];
  let completed = false;
  let calls = 0;
  let abortReason: string | null = null;

  while (calls < maxBatches) {
    calls += 1;

    let result: CallReport;
    try {
      result = await retryTransient(`backfill_batch_${calls}`, async () => {
        const response = await service.rpc("admin_backfill_sync_change_journal", {
          run_id: runId,
          backfill_revision: revision,
          entity_types: entityTypes,
          batch_size: batchSize,
          // One batch per round trip. `max_batches: 1` is what makes the
          // invariant check between batches possible at all — a call that ran
          // several batches would only let us check the ends.
          max_batches: 1,
          after_entity_type: checkpointType,
          after_entity_id: checkpointId,
          dry_run: dryRun,
        });
        if (response.error) throw response.error;
        return response.data as CallReport;
      });
    } catch (error) {
      abortReason = `batch_call_failed:${redact(error)}`;
      safeError(`backfill_batch_failed: ${redact(error)}`);
      break;
    }

    if (result.batches.length === 0) {
      completed = result.completed;
      break;
    }

    let batchInserted = 0;
    let expectedCheckpoint: BatchReport["next_checkpoint"] | null = null;
    for (const batch of result.batches) {
      totals.scanned += batch.scanned;
      totals.inserted += batch.inserted;
      totals.skipped += batch.skipped;
      totals.failed += batch.failed;
      batchInserted += batch.inserted;
      expectedCheckpoint = batch.next_checkpoint;
      checkpointType = batch.next_checkpoint.entity_type;
      checkpointId = batch.next_checkpoint.entity_id;
      safeLog(
        `batch ${String(calls).padStart(3, " ")} ${batch.entity_type.padEnd(16, " ")} ` +
          `scanned=${batch.scanned} ${dryRun ? "would_insert" : "inserted"}=${batch.inserted} ` +
          `skipped=${batch.skipped} failed=${batch.failed} ` +
          `seq=${batch.journal_min_seq ?? "-"}..${batch.journal_max_seq ?? "-"} ` +
          `${batch.duration_ms}ms`,
      );
    }

    // --- The invariant check, after every batch ----------------------------
    const duplicatesInRun = dryRun ? 0 : await duplicateMarkCount(
      invariants, runId, Math.min(totals.inserted + batchSize, 1000),
    );
    let snapshotAfter = await invariants.snapshot(`after_batch_${calls}`, dryRun ? null : runId);
    snapshotAfter = { ...snapshotAfter, duplicate_marks: duplicatesInRun };

    const batchViolations = compareSnapshots(snapshotBefore, snapshotAfter, {
      journalInserted: dryRun ? 0 : batchInserted,
      expectedCheckpoint,
      dryRun,
    });

    batches.push({
      call: calls,
      reports: result.batches,
      invariants_before: snapshotBefore,
      invariants_after: snapshotAfter,
      invariant_violations: batchViolations,
    });

    if (batchViolations.length > 0) {
      violations.push({ batch: calls, violations: batchViolations });
      for (const violation of batchViolations) {
        safeError(
          `INVARIANT  ${violation.invariant}: ${violation.detail} ` +
            `(${JSON.stringify(violation.before)} -> ${JSON.stringify(violation.after)})`,
        );
      }
      abortReason = "invariant_violation";
      break;
    }
    safeLog(`invariant ${String(calls).padStart(3, " ")} all business invariants held`);

    if (totals.failed > 0) {
      // Stop on the first failure rather than grinding through the rest: the
      // checkpoint is parked on the last success, so a resume retries exactly
      // the entity that broke instead of stepping over it.
      abortReason = "entity_failure";
      safeError(
        `backfill_entity_failed: stopping at checkpoint ` +
          `${checkpointType ?? "(start)"} / ${checkpointId ?? "(start)"}`,
      );
      break;
    }

    snapshotBefore = snapshotAfter;
    if (result.completed) {
      completed = true;
      break;
    }
  }

  if (!completed && abortReason === null && calls >= maxBatches) {
    safeLog(
      `budget      = --max-batches=${maxBatches} spent; resume with --resume ${runId}`,
    );
  }

  // --- Run-level invariants -------------------------------------------------
  const coverageAfter = await invariants.coverage();
  let finalSnapshot = await invariants.snapshot("run_end", dryRun ? null : runId);
  finalSnapshot = withDuplicateMarks(finalSnapshot, coverageAfter);
  const runViolations = compareSnapshots(runStartSnapshot, finalSnapshot, {
    journalInserted: dryRun ? 0 : totals.inserted,
    expectedCheckpoint: null,
    dryRun,
  });
  for (const violation of runViolations) {
    safeError(`INVARIANT  run/${violation.invariant}: ${violation.detail}`);
  }

  const ok = totals.failed === 0 && violations.length === 0 &&
    runViolations.length === 0 && abortReason === null;

  const report = {
    ok,
    ...auditHeader(target, "supabase_production_backfill_canary"),
    run_id: runId,
    backfill_revision: revision,
    dry_run: dryRun,
    entity_types: entityTypes,
    batch_size: batchSize,
    max_batches: maxBatches,
    started_at_utc: startedAt,
    finished_at_utc: new Date().toISOString(),
    calls,
    completed,
    abort_reason: abortReason,
    totals,
    final_checkpoint: { entity_type: checkpointType, entity_id: checkpointId },
    invariants_at_start: runStartSnapshot,
    invariants_at_end: finalSnapshot,
    run_level_violations: runViolations,
    per_batch_violations: violations,
    coverage_before: coverageBefore,
    coverage_after: coverageAfter,
    batches,
    guarantees: [
      "dry run is the default; --execute is the only way out of it",
      "--max-batches is mandatory; there is no unbounded production run",
      "batch size is capped at 100 and defaults to 25",
      "one batch per round trip, so every batch commits on its own",
      "business row counts, updated_at, server_version, movement count and " +
        "balances are compared before and after every batch",
      "the run aborts at the batch boundary on the first violation",
      "no business column is written by this tool or by the RPC it calls",
    ],
  };

  const path = await writeProductionArtifact(
    `production-backfill-${dryRun ? "dryrun" : "execute"}-${utcStamp()}`,
    "json",
    JSON.stringify(report, null, 2),
  );
  safeLog("--------------------------------------------------------------");
  safeLog(`report      = ${path}`);
  safeLog(
    `result      = ${ok ? "OK" : "STOPPED"} scanned=${totals.scanned} ` +
      `${dryRun ? "would_insert" : "inserted"}=${totals.inserted} ` +
      `skipped=${totals.skipped} failed=${totals.failed} ` +
      `violations=${violations.length + runViolations.length}`,
  );
  if (!completed) safeLog(`resume      = --resume ${runId}`);
  return ok ? 0 : 1;
}

/// The batch's own marks, read back and checked for duplication directly rather
/// than inferred. The marks primary key makes this structurally impossible, so
/// a non-zero answer means the schema is not what the migration says it is.
async function duplicateMarkCount(
  invariants: ProductionInvariants,
  runId: string,
  limit: number,
): Promise<number> {
  try {
    const marks = await invariants.marksForRun(runId, limit);
    const seen = new Set<string>();
    let duplicates = 0;
    for (const mark of marks) {
      const key = `${mark.entity_type}/${mark.entity_id}`;
      if (seen.has(key)) duplicates += 1;
      seen.add(key);
    }
    return duplicates;
  } catch (error) {
    safeError(`duplicate_mark_scan_unavailable: ${redact(error)}`);
    // Unknown, not zero. `null` would be silently accepted by the comparison, so
    // return a value that fails the check instead of one that passes it.
    return -1;
  }
}

function withDuplicateMarks(
  snapshot: InvariantSnapshot,
  coverage: Record<string, unknown> | null,
): InvariantSnapshot {
  if (!coverage) return snapshot;
  const duplicates = Number(coverage.duplicate_marks ?? 0);
  return { ...snapshot, duplicate_marks: Number.isFinite(duplicates) ? duplicates : null };
}

try {
  Deno.exit(await main());
} catch (error) {
  safeError(`production_backfill_canary_failed: ${redact(error)}`);
  Deno.exit(error instanceof ProductionGuardError ? 2 : 1);
}
