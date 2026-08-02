import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/time/document_timestamp_policy.dart';
import '../../../../core/sync/sync_contracts.dart';
import '../../../../core/sync/sync_outbox_writer.dart';
import '../../../inventory/domain/models/inventory_models.dart';
import '../../../inventory/domain/services/stock_posting_service.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/opname_models.dart';
import '../repositories/opname_repository.dart';
import 'opname_guards.dart';

/// The outcome of a review: the locked document and what it did to the ledger.
class StockOpnameReviewResult {
  const StockOpnameReviewResult({
    required this.opname,
    required this.adjustments,
  });

  final StockOpname opname;
  final List<OpnameAdjustmentResult> adjustments;

  /// Lines that actually moved stock. Lines whose balance already matched the
  /// count produce no ledger row at all.
  int get postedMovementCount =>
      adjustments.where((result) => result.didAdjust).length;
}

/// `submitted → reviewed` — the Kepala Cabang locks the count and the ledger
/// follows it (G-O5).
///
/// The entire review is **one database transaction**: read each line's live
/// balance, append the `opname_adjustment` movements, write the new balances,
/// then flip the document to `reviewed`. Either all of that commits or none of
/// it does. A failure on the last line leaves no movement, no changed balance
/// and a document still sitting in `submitted`, ready to be reviewed again once
/// the cause is fixed.
///
/// The adjustment is computed against the **current** balance, not against the
/// `difference` column snapshotted at creation time. Stock may legitimately
/// have moved between counting and reviewing; the rule is that the room ends up
/// holding exactly what was physically counted, and only the live balance can
/// tell us how far away that is.
///
/// Master data may also legitimately have moved on. A branch, room, stock
/// location, item, batch or nurse can be deactivated or archived in the days
/// between submit and review, and none of that is a reason to strand the
/// document: `submitted` has no transition back to `draft`, so a count that
/// could not be reviewed could never be resolved at all. Every reference is
/// therefore resolved **historically** — by id, deactivated and soft-deleted
/// rows included (§7.2). The reviewer is the one exception, because they are
/// acting now rather than being referenced by history: they must still be
/// active, hold the role, belong to the document's branch, and not be the
/// person who counted it.
class ReviewStockOpnameUseCase {
  ReviewStockOpnameUseCase({
    required this._opnames,
    required MasterDataRepository master,
    required this._posting,
    this._outbox = const NoopSyncOutboxWriter(),
    DateTime Function()? clock,
  }) : _guards = OpnameGuards(master),
       _clock = clock ?? _defaultClock;

  final OpnameRepository _opnames;
  final StockPostingService _posting;
  final OpnameGuards _guards;
  final SyncOutboxWriter _outbox;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  Future<StockOpnameReviewResult> call({
    required String actorUserId,
    required String opnameId,
  }) async {
    final actor = await _guards.requireActor(
      actorUserId,
      UserRole.kepalaCabang,
    );

    return _opnames.runInTransaction(() async {
      final detail = await _opnames.getDetail(opnameId);
      if (detail == null) {
        // `getDetail` joins the room, branch and counting nurse, so a document
        // whose header points at a row that is physically gone produces no
        // result — which is indistinguishable from "no such document" unless
        // the header itself is asked for separately. It is worth
        // distinguishing: one means the id was wrong, the other means a live
        // document is stuck and somebody has to repair master data.
        final header = await _opnames.getById(opnameId);
        if (header != null) {
          throw HistoricalReferenceMissingFailure(
            'Dokumen tidak dapat diselesaikan karena data historis '
            '(cabang, ruangan atau perawat) tidak ditemukan. '
            'Hubungi administrator.',
            entity: 'stock_opnames',
            id: opnameId,
            opnameId: opnameId,
          );
        }
        throw StockOpnameNotFoundFailure(
          'Dokumen opname tidak ditemukan.',
          opnameId: opnameId,
        );
      }

      final opname = detail.opname;
      _guards.requireSameBranch(actor: actor, opname: opname);
      _guards.requireStatus(
        opname: opname,
        expected: StockOpnameStatus.submitted,
        attempted: StockOpnameStatus.reviewed,
      );

      // G-R4 — separation of duties. The database enforces this too, with a
      // CHECK on (reviewed_by <> counted_by); this is the readable half.
      if (opname.countedBy == actor.id) {
        throw SelfReviewNotAllowedFailure(
          'Anda menghitung dokumen ${opname.docNumber} sendiri, sehingga tidak '
          'dapat mereviewnya. Review harus dilakukan oleh Kepala Cabang lain.',
          opnameId: opnameId,
          actorUserId: actor.id,
        );
      }

      // Every line the document actually has must be one of the lines about to
      // be posted. `detail.lines` comes from a query that inner-joins `items`,
      // so a line whose item row is physically gone is simply absent from it —
      // and posting the rest would lock the document as though the whole count
      // had been applied, with one position silently never adjusted.
      await _guards.requireEveryLineLoaded(
        opnameId: opnameId,
        storedItemIds: await _opnames.lineItemIds(opnameId),
        loadedItemIds: detail.lines.map((line) => line.itemId),
      );

      if (detail.isEmpty) {
        throw EmptyStockOpnameFailure(
          'Dokumen ${opname.docNumber} tidak memiliki baris untuk diposting.',
          opnameId: opnameId,
        );
      }

      // Historical lookups, not active ones (§7.2). The room, its location,
      // the items and the batches are resolved by id including deactivated and
      // soft-deleted rows: `submitted` has no transition back to `draft`, so a
      // document must not become unreviewable because master data was tidied
      // up after the count. What is still refused is a reference that resolves
      // to nothing — see `HistoricalReferenceMissingFailure`.
      final room = await _guards.requireHistoricalRoom(
        opnameId: opnameId,
        roomId: opname.roomId,
      );
      final location = await _guards.requireHistoricalRoomLocation(
        opnameId: opnameId,
        room: room,
      );

      // Re-validate every line before touching stock. A line that cannot be
      // posted must stop the review *before* the first movement is written,
      // not halfway through it.
      //
      // The item row is not re-read here: every line in `detail.lines` reached
      // this point through an inner join on `items`, so its existence is
      // already proven and its `sku`/`hasExpiry` are that row's own values.
      // Fetching it again would be one `items` SELECT per line, inside the
      // transaction holding the write lock, to learn what is already in hand.
      for (final line in detail.lines) {
        if (line.countedQty.isNegative) {
          throw ValidationFailure(
            'Hasil hitung ${line.displayName} tidak boleh negatif.',
          );
        }
        await _guards.requireHistoricalLineBatch(
          opnameId: opnameId,
          line: line,
        );
      }

      // Ordering is checked before anything is posted, so a device whose clock
      // is behind fails the whole review rather than half of it. The comparison
      // is between two UTC instants (T-1); the database no longer holds a
      // `reviewed_at >= submitted_at` CHECK, because on ISO-8601 TEXT that
      // operator compares characters instead of moments (§8.1).
      final reviewedAt = _clock().toUtc();
      DocumentTimestampPolicy.requireReviewNotBeforeSubmit(
        documentId: opnameId,
        submittedAtUtc: opname.submittedAt,
        reviewedAtUtc: reviewedAt,
      );

      final adjustments = await _posting.postOpnameAdjustmentsInTransaction(
        locationId: location.id,
        opnameId: opnameId,
        actorUserId: actor.id,
        lines: detail.lines
            .map(
              (line) => OpnameAdjustmentLine(
                lineId: line.id,
                itemId: line.itemId,
                batchId: line.batchId,
                countedQty: line.countedQty,
                // The nurse's explanation travels into the ledger, so the
                // stock card explains itself without a join back to the
                // opname.
                note: _movementNote(opname, line),
              ),
            )
            .toList(growable: false),
      );

      final moved = await _opnames.markReviewed(
        opnameId: opnameId,
        reviewedBy: actor.id,
        reviewedAtUtc: reviewedAt,
      );
      // Reached when another reviewer locked the document first. Throwing here
      // rolls back the movements posted moments ago, which is exactly right:
      // their document was reviewed, not ours.
      if (!moved) _guards.concurrentUpdate(opname);

      await _outbox.enqueueCurrentAggregate(
        operation: SyncOperationType.reviewOpname,
        aggregateType: SyncAggregateType.stockOpname,
        aggregateId: opnameId,
        actorUserId: actor.id,
        occurredAtUtc: reviewedAt,
      );

      final updated = await _opnames.getById(opnameId);
      if (updated == null) {
        throw StockOpnameNotFoundFailure(
          'Dokumen opname tidak ditemukan setelah direview.',
          opnameId: opnameId,
        );
      }

      return StockOpnameReviewResult(opname: updated, adjustments: adjustments);
    });
  }

  String _movementNote(StockOpname opname, StockOpnameLine line) {
    final reason = (line.note ?? '').trim();
    final prefix = 'Penyesuaian stok opname ${opname.docNumber}';
    return reason.isEmpty ? prefix : '$prefix — $reason';
  }
}
