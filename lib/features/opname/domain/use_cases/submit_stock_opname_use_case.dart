import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/sync/sync_contracts.dart';
import '../../../../core/sync/sync_outbox_writer.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/opname_models.dart';
import '../repositories/opname_repository.dart';
import 'opname_guards.dart';

/// `draft → submitted` — the nurse hands the count to the Kepala Cabang.
///
/// This is the moment the whole document is validated rather than line by line:
/// a nurse fills the sheet over a shift and should not be blocked mid-count,
/// but nothing incomplete may leave. After a successful submit the document and
/// its lines are read-only for the nurse (G-S2), and the local copy is queued
/// for sync (G-Y2).
class SubmitStockOpnameUseCase {
  SubmitStockOpnameUseCase({
    required this._opnames,
    required MasterDataRepository master,
    this._outbox = const NoopSyncOutboxWriter(),
    DateTime Function()? clock,
  }) : _guards = OpnameGuards(master),
       _clock = clock ?? _defaultClock;

  final OpnameRepository _opnames;
  final OpnameGuards _guards;
  final SyncOutboxWriter _outbox;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  Future<StockOpname> call({
    required String actorUserId,
    required String opnameId,
  }) async {
    final actor = await _guards.requireActor(actorUserId, UserRole.perawat);

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
        expected: StockOpnameStatus.draft,
        attempted: StockOpnameStatus.submitted,
      );

      // The document must be validated in full, and `detail.lines` is only as
      // complete as the join that produced it: it inner-joins `items`, so a
      // line whose item row is physically gone is absent from it entirely.
      // Submitting on that basis would freeze a document whose G-O3 check
      // never saw one of its positions — an unexplained difference locked in
      // permanently. Catching it here, while the document is still a draft,
      // leaves a way forward that `submitted` would not have.
      await _guards.requireEveryLineLoaded(
        opnameId: opnameId,
        storedItemIds: await _opnames.lineItemIds(opnameId),
        loadedItemIds: detail.lines.map((line) => line.itemId),
      );

      if (detail.isEmpty) {
        throw EmptyStockOpnameFailure(
          'Dokumen ${opname.docNumber} belum memiliki satu baris pun, '
          'sehingga belum dapat dikirim.',
          opnameId: opnameId,
        );
      }

      await _validateLines(detail);

      final submittedAt = _clock().toUtc();
      final moved = await _opnames.submit(
        opnameId: opnameId,
        submittedAtUtc: submittedAt,
      );
      if (!moved) _guards.concurrentUpdate(opname);

      await _outbox.enqueueCurrentAggregate(
        operation: SyncOperationType.submitOpname,
        aggregateType: SyncAggregateType.stockOpname,
        aggregateId: opnameId,
        actorUserId: actor.id,
        occurredAtUtc: submittedAt,
      );

      final updated = await _opnames.getById(opnameId);
      if (updated == null) {
        throw StockOpnameNotFoundFailure(
          'Dokumen opname tidak ditemukan setelah dikirim.',
          opnameId: opnameId,
        );
      }
      return updated;
    });
  }

  /// Whole-document validation (G-O3, G-E2).
  Future<void> _validateLines(StockOpnameDetail detail) async {
    final seen = <String>{};
    for (final line in detail.lines) {
      if (line.countedQty.isNegative) {
        throw ValidationFailure(
          'Hasil hitung ${line.displayName} tidak boleh negatif.',
        );
      }

      // The two partial unique indexes already make this impossible in the
      // database; checking here turns a constraint error into a sentence the
      // nurse can act on.
      final key = '${line.itemId}|${line.batchId ?? ''}';
      if (!seen.add(key)) {
        throw DuplicateStockOpnameLineFailure(
          '${line.displayName} muncul lebih dari satu kali pada dokumen ini.',
          opnameId: detail.id,
          itemId: line.itemId,
          batchId: line.batchId,
        );
      }

      // Same reasoning as the review path: the line came through an inner join
      // on `items`, so re-reading the row would be one SELECT per line to
      // recover fields the line already carries.
      await _guards.requireHistoricalLineBatch(opnameId: detail.id, line: line);
    }

    // G-O3: every difference needs a reason. All offending lines are reported
    // at once so the form can mark them together instead of surfacing them one
    // failed submit at a time. A note of only whitespace does not count.
    final missing = detail.linesMissingNote;
    if (missing.isNotEmpty) {
      final names = missing.take(3).map((line) => line.displayName).join(', ');
      final suffix = missing.length > 3
          ? ' dan ${missing.length - 3} baris lainnya'
          : '';
      throw DifferenceNoteRequiredFailure(
        'Catatan wajib diisi untuk baris yang berselisih: $names$suffix.',
        lineIds: missing.map((line) => line.id).toList(growable: false),
      );
    }
  }
}
