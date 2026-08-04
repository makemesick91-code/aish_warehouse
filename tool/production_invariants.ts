// Business-data invariants for the production canary.
//
// The backfill's entire claim is "it writes the change journal and nothing
// else". This module is what turns that claim into something checked rather
// than asserted: a snapshot taken before a batch and again after it, compared
// field by field, with any difference stopping the run immediately.
//
// Every probe here is chosen to be cheap on a production database:
//
//   * counts use PostgREST `head` requests, so the server counts and no rows
//     cross the wire;
//   * "did anything change" uses `max(server_updated_at)` fetched as a single
//     ordered row, because every business write moves it;
//   * the balance checksum tries the server-side aggregate first and falls back
//     to a *deterministic bounded sample* — the same rows both times, so it is
//     still a real invariant, and the report says which method was used and how
//     much of the table it covered rather than implying full coverage.
//
// Nothing in this file writes, and nothing in it reads a business payload.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import { redact, retryTransient, safeLog } from "./production_guard.ts";

/// The tables the canary is allowed to observe. A table not on this list cannot
/// be probed by accident, and the list is deliberately the syncable business
/// surface rather than "every table".
export const OBSERVABLE_TABLES = [
  "branches",
  "rooms",
  "users",
  "item_categories",
  "items",
  "item_batches",
  "stock_locations",
  "stock_balances",
  "stock_movements",
  "stock_opnames",
  "purchase_requests",
  "delivery_orders",
  "good_receipts",
  "distributions",
  "consumptions",
  "goods_returns",
  "disposals",
] as const;

export type ObservableTable = (typeof OBSERVABLE_TABLES)[number];

export type TableFingerprint = {
  readonly rows: number;
  readonly max_updated_at: string | null;
  readonly max_server_updated_at: string | null;
  readonly max_server_version: number | null;
};

export type BalanceSignature = {
  readonly method: "server_aggregate" | "bounded_sample";
  readonly rows_covered: number;
  readonly total_rows: number;
  readonly negative_rows: number;
  readonly qty_sum: number | null;
  readonly checksum: string | null;
};

export type InvariantSnapshot = {
  readonly label: string;
  readonly taken_at_utc: string;
  readonly tables: Record<string, TableFingerprint>;
  readonly movements: TableFingerprint;
  readonly balances: BalanceSignature;
  readonly journal_rows: number;
  readonly journal_max_change_seq: number | null;
  readonly marks_for_revision: number;
  readonly duplicate_marks: number | null;
  readonly checkpoint: {
    readonly entity_type: string | null;
    readonly entity_id: string | null;
    readonly completed: boolean;
    readonly inserted: number;
    readonly failed: number;
  } | null;
};

export type Violation = {
  readonly invariant: string;
  readonly before: unknown;
  readonly after: unknown;
  readonly detail: string;
};

export type CompareExpectation = {
  /// How many journal entries the batch reported inserting. `marks_for_revision`
  /// and `journal_rows` may grow by at most this much and by nothing else.
  readonly journalInserted: number;
  /// The checkpoint the server reported for this batch. The run ledger must
  /// agree with it, or the driver and the server disagree about what committed.
  readonly expectedCheckpoint: {
    entity_type: string | null;
    entity_id: string | null;
  } | null;
  /// A dry run must not move even the journal.
  readonly dryRun: boolean;
};

export class ProductionInvariants {
  constructor(
    private readonly service: SupabaseClient,
    private readonly revision: string,
    private readonly tables: readonly string[],
    private readonly sampleCap: number,
  ) {}

  static forTables(
    service: SupabaseClient,
    revision: string,
    entityTables: readonly string[],
    sampleCap = 5000,
  ): ProductionInvariants {
    // `stock_movements` and `stock_balances` are always observed, whatever the
    // backfill was scoped to: they are the two tables where an accidental write
    // would be a business incident rather than a cosmetic one.
    const unique = new Set<string>([
      ...entityTables.filter((table) =>
        (OBSERVABLE_TABLES as readonly string[]).includes(table)
      ),
      "stock_movements",
      "stock_balances",
    ]);
    return new ProductionInvariants(service, revision, [...unique], sampleCap);
  }

  async snapshot(label: string, runId: string | null): Promise<InvariantSnapshot> {
    const tables: Record<string, TableFingerprint> = {};
    for (const table of this.tables) {
      tables[table] = await this.fingerprint(table);
    }
    const balances = await this.balanceSignature();
    const journal = await this.journalFingerprint();
    const marks = await this.markCount();
    const checkpoint = runId ? await this.checkpoint(runId) : null;

    return {
      label,
      taken_at_utc: new Date().toISOString(),
      tables,
      movements: tables["stock_movements"],
      balances,
      journal_rows: journal.rows,
      journal_max_change_seq: journal.maxSeq,
      marks_for_revision: marks,
      duplicate_marks: null,
      checkpoint,
    };
  }

  /// The expensive one: a full coverage report, which counts every syncable
  /// table server-side. Run at the start and the end of a canary, not between
  /// batches — on production that is a real query, not a free one.
  async coverage(): Promise<Record<string, unknown> | null> {
    const result = await this.service.rpc("admin_sync_backfill_coverage", {
      backfill_revision: this.revision,
    });
    if (result.error) {
      safeLog(`invariant_coverage_unavailable: ${redact(result.error)}`);
      return null;
    }
    return result.data as Record<string, unknown>;
  }

  private async fingerprint(table: string): Promise<TableFingerprint> {
    const rows = await this.count(table);
    const latest = await retryTransient(`invariant_${table}_latest`, async () => {
      const result = await this.service
        .from(table)
        .select("updated_at, server_updated_at, server_version")
        .order("server_updated_at", { ascending: false })
        .limit(1);
      if (result.error) throw result.error;
      return (result.data ?? [])[0] as Record<string, unknown> | undefined;
    });
    return {
      rows,
      max_updated_at: latest?.updated_at ? String(latest.updated_at) : null,
      max_server_updated_at: latest?.server_updated_at
        ? String(latest.server_updated_at)
        : null,
      max_server_version: latest?.server_version === undefined
        ? null
        : Number(latest.server_version),
    };
  }

  private async count(table: string, filter?: (query: any) => any): Promise<number> {
    return await retryTransient(`invariant_count_${table}`, async () => {
      let query = this.service.from(table).select("*", {
        count: "exact",
        head: true,
      });
      if (filter) query = filter(query);
      const result = await query;
      if (result.error) throw result.error;
      return Number(result.count ?? 0);
    });
  }

  private async balanceSignature(): Promise<BalanceSignature> {
    const total = await this.count("stock_balances");
    const negative = await this.count(
      "stock_balances",
      (query: any) => query.lt("qty_on_hand", 0),
    );

    // Preferred: the server adds it up and sends back one number.
    const aggregate = await this.service
      .from("stock_balances")
      .select("qty_on_hand.sum()")
      .single();
    if (!aggregate.error && aggregate.data) {
      const sum = Number((aggregate.data as Record<string, unknown>).sum ?? 0);
      if (Number.isFinite(sum)) {
        return {
          method: "server_aggregate",
          rows_covered: total,
          total_rows: total,
          negative_rows: negative,
          qty_sum: sum,
          checksum: null,
        };
      }
    }

    // Fallback for a project without PostgREST aggregates: hash a deterministic
    // prefix of the table ordered by primary key. It is the same set of rows on
    // every snapshot, so a change inside it is still caught — but it is a
    // sample, and the report says so instead of implying a full checksum.
    const limit = Math.min(this.sampleCap, Math.max(total, 1));
    const page = await retryTransient("invariant_balance_sample", async () => {
      const result = await this.service
        .from("stock_balances")
        .select("id, qty_on_hand")
        .order("id", { ascending: true })
        .limit(limit);
      if (result.error) throw result.error;
      return (result.data ?? []) as Array<{ id: string; qty_on_hand: number }>;
    });
    const text = page.map((row) => `${row.id}:${row.qty_on_hand}`).join("\n");
    const digest = new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)),
    );
    return {
      method: "bounded_sample",
      rows_covered: page.length,
      total_rows: total,
      negative_rows: negative,
      qty_sum: page.reduce((sum, row) => sum + Number(row.qty_on_hand), 0),
      checksum: Array.from(digest)
        .map((part) => part.toString(16).padStart(2, "0")).join(""),
    };
  }

  private async journalFingerprint(): Promise<{ rows: number; maxSeq: number | null }> {
    const rows = await this.count("sync_change_journal");
    const head = await retryTransient("invariant_journal_head", async () => {
      const result = await this.service
        .from("sync_change_journal")
        .select("change_seq")
        .order("change_seq", { ascending: false })
        .limit(1);
      if (result.error) throw result.error;
      return (result.data ?? [])[0] as { change_seq: number } | undefined;
    });
    return { rows, maxSeq: head ? Number(head.change_seq) : null };
  }

  private async markCount(): Promise<number> {
    return await this.count(
      "sync_change_journal_backfill_marks",
      (query: any) => query.eq("backfill_revision", this.revision),
    );
  }

  private async checkpoint(runId: string): Promise<InvariantSnapshot["checkpoint"]> {
    const result = await this.service
      .from("sync_change_journal_backfill_runs")
      .select("last_entity_type, last_entity_id, completed, inserted, failed")
      .eq("run_id", runId)
      .maybeSingle();
    if (result.error || !result.data) return null;
    const row = result.data as Record<string, unknown>;
    return {
      entity_type: row.last_entity_type === null ? null : String(row.last_entity_type),
      entity_id: row.last_entity_id === null ? null : String(row.last_entity_id),
      completed: row.completed === true,
      inserted: Number(row.inserted ?? 0),
      failed: Number(row.failed ?? 0),
    };
  }

  /// Marks written by one specific run, read back so the batch's own marks can
  /// be checked for duplication directly instead of inferred from a count.
  /// Bounded by the batch size, so this stays a small read.
  async marksForRun(runId: string, limit: number): Promise<
    Array<{ entity_type: string; entity_id: string }>
  > {
    const result = await this.service
      .from("sync_change_journal_backfill_marks")
      .select("entity_type, entity_id")
      .eq("run_id", runId)
      .order("entity_type", { ascending: true })
      .order("entity_id", { ascending: true })
      .limit(limit);
    if (result.error) throw result.error;
    return (result.data ?? []) as Array<{ entity_type: string; entity_id: string }>;
  }
}

/// Compares two snapshots. Business facts must be *identical*; journal facts may
/// grow by exactly what the batch reported and by nothing else.
export function compareSnapshots(
  before: InvariantSnapshot,
  after: InvariantSnapshot,
  expectation: CompareExpectation,
): Violation[] {
  const violations: Violation[] = [];
  const fail = (invariant: string, a: unknown, b: unknown, detail: string) =>
    violations.push({ invariant, before: a, after: b, detail });

  for (const table of Object.keys(before.tables)) {
    const left = before.tables[table];
    const right = after.tables[table];
    if (!right) {
      fail(`table_missing:${table}`, table, null, "table vanished between snapshots");
      continue;
    }
    if (left.rows !== right.rows) {
      fail(`row_count_changed:${table}`, left.rows, right.rows,
        "a business row was created or removed");
    }
    if (left.max_updated_at !== right.max_updated_at) {
      fail(`updated_at_changed:${table}`, left.max_updated_at, right.max_updated_at,
        "a business row's updated_at moved");
    }
    if (left.max_server_updated_at !== right.max_server_updated_at) {
      fail(`server_updated_at_changed:${table}`,
        left.max_server_updated_at, right.max_server_updated_at,
        "the server metadata trigger fired on a business row");
    }
    if (left.max_server_version !== right.max_server_version) {
      fail(`server_version_changed:${table}`,
        left.max_server_version, right.max_server_version,
        "a server_version moved, which would move every field_version with it");
    }
  }

  if (before.movements.rows !== after.movements.rows) {
    fail("movement_count_changed", before.movements.rows, after.movements.rows,
      "the ledger gained or lost a movement");
  }

  const b = before.balances;
  const a = after.balances;
  if (b.total_rows !== a.total_rows) {
    fail("balance_row_count_changed", b.total_rows, a.total_rows, "a balance row appeared or vanished");
  }
  if (a.negative_rows !== 0) {
    fail("negative_stock_present", b.negative_rows, a.negative_rows,
      "a stock balance went negative");
  }
  if (b.method === a.method) {
    if (b.qty_sum !== a.qty_sum) {
      fail("balance_quantity_changed", b.qty_sum, a.qty_sum, "total quantity on hand moved");
    }
    if (b.checksum !== a.checksum) {
      fail("balance_checksum_changed", b.checksum, a.checksum, "a balance row's quantity changed");
    }
  } else {
    // Comparing an aggregate against a sample would be comparing two different
    // things. Say so rather than emit a violation that means nothing.
    fail("balance_method_changed", b.method, a.method,
      "balance probe changed method between snapshots; comparison is not meaningful");
  }

  const journalGrowth = after.journal_rows - before.journal_rows;
  const markGrowth = after.marks_for_revision - before.marks_for_revision;
  if (expectation.dryRun) {
    if (journalGrowth !== 0) {
      fail("dry_run_wrote_the_journal", before.journal_rows, after.journal_rows,
        "a dry run must write nothing at all");
    }
    if (markGrowth !== 0) {
      fail("dry_run_wrote_a_mark", before.marks_for_revision, after.marks_for_revision,
        "a dry run must not record a backfill mark");
    }
  } else {
    if (journalGrowth < 0) {
      fail("journal_shrank", before.journal_rows, after.journal_rows,
        "journal rows were removed; the journal is append-only");
    }
    if (journalGrowth > expectation.journalInserted) {
      fail("journal_grew_beyond_the_batch",
        expectation.journalInserted, journalGrowth,
        "more journal rows appeared than this batch reported inserting");
    }
    if (markGrowth !== expectation.journalInserted) {
      fail("marks_do_not_match_the_batch",
        expectation.journalInserted, markGrowth,
        "the marks table disagrees with the batch report");
    }
  }

  if (after.duplicate_marks !== null && after.duplicate_marks !== 0) {
    fail("duplicate_marks_present", before.duplicate_marks, after.duplicate_marks,
      "the same entity was marked twice under one revision");
  }

  const expected = expectation.expectedCheckpoint;
  if (expected && !expectation.dryRun) {
    const actual = after.checkpoint;
    if (!actual) {
      fail("checkpoint_missing", expected, null, "no run ledger row for this run id");
    } else if (
      actual.entity_type !== expected.entity_type ||
      actual.entity_id !== expected.entity_id
    ) {
      fail("checkpoint_mismatch", expected, {
        entity_type: actual.entity_type,
        entity_id: actual.entity_id,
      }, "the server ledger and the batch report disagree about the checkpoint");
    } else if (actual.failed !== 0) {
      fail("checkpoint_reports_failures", 0, actual.failed,
        "the run ledger records a failed entity");
    }
  }

  return violations;
}
