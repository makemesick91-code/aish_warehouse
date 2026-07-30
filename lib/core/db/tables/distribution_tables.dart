import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';
import '../converters/enum_converters.dart';
import 'base_columns.dart';
import 'master_tables.dart';

/// Distribusi header — the branch head moving goods from the *Gudang Cabang* out
/// to the treatment rooms (schema v8, spec §2.3).
///
/// One document may target **several rooms at once** (G-T3), so there is
/// deliberately no `room_id` here: the room is a property of each line, and the
/// header carries only what the whole document shares — the branch, who
/// distributed, the status and the posting instant.
///
/// `branch_id` is the source side of G-T1. The *Gudang Cabang* the goods leave is
/// resolved from it by type and branch at posting time rather than stored, for the
/// reason §14 spells out: a stored location id would be a second copy of a fact the
/// location table already holds, and it would have to be kept in step with it by
/// hand. What the document does state is the branch, and every room on it must
/// belong to that branch — a cross-table rule SQLite cannot express as a foreign
/// key, so the use cases enforce it and revalidate it inside the posting
/// transaction.
///
/// `doc_number` keeps the partial `WHERE deleted_at IS NULL` shape the opname,
/// Purchase Request, Delivery Order and Good Receipt tables use, for the reason
/// those spell out: once the sync backend issues real numbers
/// (`DIST-{cabang}-{yyyyMMdd}-{seq}`), a soft-deleted row must not hold one
/// hostage. Until then the local number is `TMP-DIST-{uuid}` (G-Y4).
///
/// Two absences are deliberate:
///
/// * **No lexical timestamp CHECK.** Timestamps are ISO-8601 TEXT, so
///   `posted_at >= created_at` in SQL compares characters rather than instants.
///   Ordering is decided by `DocumentTimestampPolicy` on UTC `DateTime`s. What the
///   CHECKs below state is what SQLite can answer without ambiguity: which
///   timestamps each status must and must not carry.
/// * **No line or quantity totals.** Every one of them is derivable from
///   `distribution_lines`, and a stored copy would be a second version of the same
///   fact that a writer could contradict.
@DataClassName('DistributionRow')
@TableIndex(
  name: 'idx_distributions_branch_status',
  columns: {#branchId, #status},
)
@TableIndex(
  name: 'idx_distributions_distributed_by_status',
  columns: {#distributedBy, #status},
)
@TableIndex(name: 'idx_distributions_created_at', columns: {#createdAt})
@TableIndex(name: 'idx_distributions_posted_at', columns: {#postedAt})
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_distributions_doc_number
  ON distributions (doc_number)
  WHERE deleted_at IS NULL;
''')
class Distributions extends Table with BusinessColumns {
  /// Temporary local number `TMP-DIST-{uuid}` until a sync backend assigns the
  /// final `DIST-{cabang}-{yyyyMMdd}-{seq}` (G-Y4). Minting a server-shaped number
  /// offline would collide across devices — every branch distributes on its own.
  TextColumn get docNumber => text().withLength(min: 1, max: 64)();

  /// The branch whose *Gudang Cabang* the goods leave, and the only branch whose
  /// rooms may receive them (G-T1).
  TextColumn get branchId => text().references(Branches, #id)();

  /// The Kepala Cabang who distributed (spec §3.1). Their branch must be
  /// [branchId], which is a cross-table question and therefore the use case's to
  /// enforce.
  @ReferenceName('distributedDistributions')
  TextColumn get distributedBy => text().references(Users, #id)();

  TextColumn get status => text()
      .map(const DistributionStatusConverter())
      .clientDefault(() => DistributionStatus.draft.dbValue)();

  /// UTC instant the distribution was posted and the balances moved (T-1).
  DateTimeColumn get postedAt => dateTime().nullable()();

  /// Free-text remark about the distribution as a whole, e.g. why an unusual
  /// quantity left the store. Optional, and never a substitute for the per-line
  /// `fefo_override_reason`, which is an audit record for a specific decision.
  TextColumn get note => text().nullable()();

  @override
  List<String> get customConstraints => [
    // Defence in depth behind the type converter: a hand-written UPDATE cannot
    // introduce a status the Dart enum does not know.
    "CHECK (status IN ('draft', 'posted'))",
    // The posting instant exists exactly when the document has posted. Stated
    // exhaustively over both statuses so a new one cannot quietly land in
    // neither branch.
    "CHECK ((status = 'draft' AND posted_at IS NULL) "
        "OR (status = 'posted' AND posted_at IS NOT NULL))",
  ];
}

/// One distributed position — *one room, one item, one batch* (spec §2.3).
///
/// The grain is what makes G-T3 work: a document targeting three rooms carries
/// three groups of lines, and one item split across two batches for one room
/// carries two rows. The two partial unique indexes below are what stop the same
/// position appearing twice, which would double the quantity leaving the store
/// while every per-line check still passed. `deleted_at IS NULL` is what lets a
/// line removed from a draft be added back afterwards.
///
/// **No source or destination location column.** Both are derivable and neither is
/// stored: the source is the *Gudang Cabang* of `distributions.branch_id` and the
/// destination is the `room` location of `room_id`, each resolved by type at
/// posting time (§14). Storing them would mean a line could name a location that
/// contradicts its own room — the exact inconsistency the resolution rules exist to
/// prevent — and a UI that could submit an arbitrary location id is precisely the
/// hole G-T1 closes.
///
/// `qty` is INTEGER milli-units (Q-3); the repository converts it to `Quantity` and
/// nothing above it knows the scale.
@DataClassName('DistributionLineRow')
@TableIndex(
  name: 'idx_distribution_lines_distribution',
  columns: {#distributionId},
)
@TableIndex(name: 'idx_distribution_lines_room', columns: {#roomId})
@TableIndex(name: 'idx_distribution_lines_item', columns: {#itemId})
@TableIndex(name: 'idx_distribution_lines_batch', columns: {#batchId})
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_distribution_lines_batched
  ON distribution_lines (distribution_id, room_id, item_id, batch_id)
  WHERE batch_id IS NOT NULL AND deleted_at IS NULL;
''')
@TableIndex.sql('''
CREATE UNIQUE INDEX idx_distribution_lines_unbatched
  ON distribution_lines (distribution_id, room_id, item_id)
  WHERE batch_id IS NULL AND deleted_at IS NULL;
''')
class DistributionLines extends Table with BusinessColumns {
  TextColumn get distributionId => text().references(Distributions, #id)();

  /// The destination room. Must belong to the header's branch (G-T1) — a
  /// cross-table rule SQLite cannot express, enforced by the use cases and
  /// revalidated inside the posting transaction.
  TextColumn get roomId => text().references(Rooms, #id)();

  TextColumn get itemId => text().references(Items, #id)();

  /// The batch leaving the store. NULL, and only NULL, for an item without expiry
  /// (G-E2); the use case enforces both directions because the rule depends on
  /// `items.has_expiry`, which this table cannot read.
  TextColumn get batchId => text().nullable().references(ItemBatches, #id)();

  /// Distributed quantity in **milli-units** (Q-3). Strictly positive: a
  /// distribution of nothing is not a line, and the ledger records changes rather
  /// than confirmations (G-A1).
  IntColumn get qty => integer()();

  /// Why a batch younger than the FEFO suggestion was chosen (G-E3).
  ///
  /// NULL when the selection follows FEFO, which is the overwhelmingly common
  /// case. Whether a reason is *required* depends on the batches the store holds
  /// right now, which is not a fact this table can see — so the domain decides it
  /// (`DistributionFefoPolicy`) and re-decides it inside the posting transaction
  /// against fresh balances.
  TextColumn get fefoOverrideReason => text().nullable()();

  @override
  List<String> get customConstraints => [
    'CHECK (qty > 0)',
    // A stored reason must say something. Whitespace is not a reason, and this is
    // the database half of `DistributionFefoPolicy.hasValidReason`.
    //
    // The `IS NULL OR` branch is load-bearing in the *opposite* direction to the
    // Good Receipt's reject-reason CHECK, and for the same underlying quirk:
    // SQLite treats a CHECK whose result is **NULL as satisfied**, and
    // `trim(NULL) <> ''` is NULL. Where G-G4 needs `reject_reason IS NOT NULL AND
    // trim(...) <> ''` — because a `rejected` line must carry one — this column is
    // legitimately NULL on every compliant line, so the constraint has to accept
    // NULL *explicitly* rather than by accident and reject the empty string
    // *explicitly* rather than relying on a NULL comparison. Writing it as
    // `trim(fefo_override_reason) <> ''` alone would let `''` through on a NULL
    // row only by luck and would reject every compliant line outright; writing it
    // as `IS NOT NULL AND trim(...) <> ''` would make an override reason
    // mandatory on lines that never violated FEFO. The requirement the domain
    // enforces — *non-null and non-blank when, and only when, FEFO was
    // violated* — needs `items.has_expiry` and the current batch balances, and is
    // therefore stated in `DistributionFefoPolicy` and revalidated at posting.
    "CHECK (fefo_override_reason IS NULL "
        "OR trim(fefo_override_reason) <> '')",
  ];
}
