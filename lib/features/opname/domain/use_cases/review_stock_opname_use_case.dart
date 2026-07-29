import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
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
class ReviewStockOpnameUseCase {
  ReviewStockOpnameUseCase({
    required this._opnames,
    required MasterDataRepository master,
    required this._posting,
    DateTime Function()? clock,
  }) : _master = master,
       _guards = OpnameGuards(master),
       _clock = clock ?? _defaultClock;

  final OpnameRepository _opnames;
  final MasterDataRepository _master;
  final StockPostingService _posting;
  final OpnameGuards _guards;
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

      if (detail.isEmpty) {
        throw EmptyStockOpnameFailure(
          'Dokumen ${opname.docNumber} tidak memiliki baris untuk diposting.',
          opnameId: opnameId,
        );
      }

      final room = await _master.roomById(opname.roomId);
      if (room == null) {
        throw EntityNotFoundFailure(
          'Ruangan dokumen ini tidak ditemukan.',
          entity: 'rooms',
          id: opname.roomId,
        );
      }
      final location = await _guards.requireRoomLocation(room);

      // Re-validate every line before touching stock. A line that cannot be
      // posted must stop the review *before* the first movement is written,
      // not halfway through it.
      for (final line in detail.lines) {
        if (line.countedQty.isNegative) {
          throw ValidationFailure(
            'Hasil hitung ${line.displayName} tidak boleh negatif.',
          );
        }
        final item = await _guards.requireItem(line.itemId);
        await _guards.requireValidItemBatch(item: item, batchId: line.batchId);
      }

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

      final reviewedAt = _clock().toUtc();
      final moved = await _opnames.markReviewed(
        opnameId: opnameId,
        reviewedBy: actor.id,
        reviewedAtUtc: reviewedAt,
      );
      // Reached when another reviewer locked the document first. Throwing here
      // rolls back the movements posted moments ago, which is exactly right:
      // their document was reviewed, not ours.
      if (!moved) _guards.concurrentUpdate(opname);

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
