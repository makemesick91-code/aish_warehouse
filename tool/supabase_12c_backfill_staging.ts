// Operator driver for the Milestone 12C change-journal baseline backfill.
//
// The database function does the work; this exists to drive it one batch per
// round trip so each batch commits on its own, and to stop the moment anything
// looks wrong. It is the only 12C tool that writes to staging, so it is also
// the strictest: service key required, branch asserted, `--execute` required
// before it stops being a dry run.
//
//   deno run ... tool/supabase_12c_backfill_staging.ts --dry-run
//   deno run ... tool/supabase_12c_backfill_staging.ts --execute
//   deno run ... tool/supabase_12c_backfill_staging.ts --execute --resume <run-id>
//
// Exit code is 0 only when the server reported `completed` with zero failures.

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  describeTarget,
  redact,
  resolveStagingTarget,
  retryTransient,
  safeError,
  safeLog,
  utcStamp,
  writeArtifact,
} from "./staging_guard.ts";

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

function option(name: string, fallback?: string): string | undefined {
  const prefix = `--${name}=`;
  const inline = Deno.args.find((entry) => entry.startsWith(prefix));
  if (inline) return inline.slice(prefix.length);
  const index = Deno.args.indexOf(`--${name}`);
  if (index >= 0 && Deno.args[index + 1] && !Deno.args[index + 1].startsWith("--")) {
    return Deno.args[index + 1];
  }
  return fallback;
}

async function main(): Promise<number> {
  const execute = flag("execute");
  // Dry run is the default and has to be turned off explicitly. `--dry-run`
  // alongside `--execute` is a contradiction rather than a preference, so it is
  // refused instead of being resolved in either direction.
  if (execute && flag("dry-run")) {
    safeError("backfill_conflicting_mode: pass either --dry-run or --execute");
    return 2;
  }
  const dryRun = !execute;

  const target = resolveStagingTarget({
    mutating: execute,
    requireServiceRole: true,
  });
  describeTarget(target, "supabase_12c_backfill_staging");
  safeLog(`mode        = ${dryRun ? "DRY RUN (writes nothing)" : "EXECUTE"}`);

  const revision = option("revision") ??
    Deno.env.get("AISH_BACKFILL_REVISION") ?? "aish-supabase-003-baseline";
  const batchSize = Number(
    option("batch-size") ?? Deno.env.get("AISH_BACKFILL_BATCH_SIZE") ?? "500",
  );
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 5000) {
    safeError("backfill_batch_size_invalid");
    return 2;
  }
  const maxCalls = Number(option("max-batches") ?? "10000");
  const entityTypes = option("entity-types")?.split(",").map((entry) =>
    entry.trim()
  ).filter((entry) => entry.length > 0) ?? null;
  const runId = option("resume") ?? option("run-id") ?? crypto.randomUUID();

  const service = createClient(target.url, target.serviceRoleKey!, {
    auth: { persistSession: false },
  });

  // Resume position comes from the server's own run ledger, not from a local
  // file: the server is the only place that knows what actually committed.
  let checkpointType: string | null = null;
  let checkpointId: string | null = null;
  if (option("resume")) {
    const existing = await service
      .from("sync_change_journal_backfill_runs")
      .select("run_id, backfill_revision, last_entity_type, last_entity_id, completed")
      .eq("run_id", runId)
      .maybeSingle();
    if (existing.error) {
      safeError(`backfill_resume_lookup_failed: ${redact(existing.error)}`);
      return 1;
    }
    if (!existing.data) {
      safeError(`backfill_resume_unknown_run: ${runId}`);
      return 2;
    }
    if (existing.data.backfill_revision !== revision) {
      safeError("backfill_resume_revision_mismatch");
      return 2;
    }
    if (existing.data.completed) {
      safeLog(`run ${runId} is already complete; nothing to resume`);
      return 0;
    }
    checkpointType = existing.data.last_entity_type;
    checkpointId = existing.data.last_entity_id;
    safeLog(
      `resuming ${runId} from ${checkpointType ?? "(start)"} / ${
        checkpointId ?? "(start)"
      }`,
    );
  }

  const startedAt = new Date().toISOString();
  const batches: BatchReport[] = [];
  const totals = { scanned: 0, inserted: 0, skipped: 0, failed: 0 };
  let completed = false;
  let calls = 0;

  while (calls < maxCalls) {
    calls += 1;
    const result = await retryTransient(
      `backfill_batch_${calls}`,
      async () => {
        const response = await service.rpc(
          "admin_backfill_sync_change_journal",
          {
            run_id: runId,
            backfill_revision: revision,
            entity_types: entityTypes,
            batch_size: batchSize,
            max_batches: 1,
            after_entity_type: checkpointType,
            after_entity_id: checkpointId,
            dry_run: dryRun,
          },
        );
        if (response.error) throw response.error;
        return response.data as CallReport;
      },
    );

    if (result.batches.length === 0) {
      completed = result.completed;
      break;
    }
    for (const batch of result.batches) {
      batches.push(batch);
      totals.scanned += batch.scanned;
      totals.inserted += batch.inserted;
      totals.skipped += batch.skipped;
      totals.failed += batch.failed;
      safeLog(
        `batch ${String(calls).padStart(4, " ")} ${
          batch.entity_type.padEnd(16, " ")
        } scanned=${batch.scanned} ${
          dryRun ? "would_insert" : "inserted"
        }=${batch.inserted} skipped=${batch.skipped} failed=${batch.failed} ` +
          `seq=${batch.journal_min_seq ?? "-"}..${batch.journal_max_seq ?? "-"} ` +
          `${batch.duration_ms}ms`,
      );
      checkpointType = batch.next_checkpoint.entity_type;
      checkpointId = batch.next_checkpoint.entity_id;
    }

    if (totals.failed > 0) {
      // Stop on the first failure rather than grinding through the rest: the
      // checkpoint is parked on the last success, so a resume retries exactly
      // the entity that broke instead of stepping over it.
      safeError(
        `backfill_batch_failed: stopping with checkpoint ${
          checkpointType ?? "(start)"
        } / ${checkpointId ?? "(start)"}`,
      );
      break;
    }
    if (result.completed) {
      completed = true;
      break;
    }
  }

  if (!completed && totals.failed === 0 && calls >= maxCalls) {
    safeError(`backfill_max_batches_reached: resume with --resume ${runId}`);
  }

  let coverage: unknown = null;
  const coverageResult = await service.rpc("admin_sync_backfill_coverage", {
    backfill_revision: revision,
  });
  if (coverageResult.error) {
    safeError(`backfill_coverage_unavailable: ${redact(coverageResult.error)}`);
  } else {
    coverage = coverageResult.data;
  }

  const ok = completed && totals.failed === 0;
  const report = {
    ok,
    tool: "supabase_12c_backfill_staging",
    environment: "staging",
    // The masked ref is what lands in the artifact; the full project reference
    // is not something a report needs to carry to be useful.
    project_ref: target.maskedRef,
    host: target.host,
    branch: target.branch,
    commit: target.commit,
    run_id: runId,
    backfill_revision: revision,
    dry_run: dryRun,
    entity_types: entityTypes,
    batch_size: batchSize,
    started_at_utc: startedAt,
    finished_at_utc: new Date().toISOString(),
    calls,
    completed,
    totals,
    final_checkpoint: { entity_type: checkpointType, entity_id: checkpointId },
    coverage,
    batches,
  };

  const path = await writeArtifact(
    `12c-backfill-${dryRun ? "dryrun" : "execute"}-${utcStamp()}`,
    "json",
    JSON.stringify(report, null, 2),
  );
  safeLog(`report      = ${path}`);
  safeLog(
    `result      = ${ok ? "OK" : "INCOMPLETE"} scanned=${totals.scanned} ` +
      `${dryRun ? "would_insert" : "inserted"}=${totals.inserted} ` +
      `skipped=${totals.skipped} failed=${totals.failed}`,
  );
  if (!ok) safeLog(`resume with --resume ${runId}`);
  return ok ? 0 : 1;
}

try {
  Deno.exit(await main());
} catch (error) {
  safeError(`backfill_failed: ${redact(error)}`);
  Deno.exit(1);
}
