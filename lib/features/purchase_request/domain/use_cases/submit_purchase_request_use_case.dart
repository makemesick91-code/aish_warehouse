import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/purchase_request_models.dart';
import '../repositories/purchase_request_repository.dart';
import '../services/purchase_request_opname_eligibility_policy.dart';
import '../services/purchase_request_quantity_policy.dart';
import 'purchase_request_guards.dart';

/// `draft → submitted` — the branch head hands the order to the warehouse.
///
/// This is the moment the whole document is validated rather than line by line: a
/// branch head fills the form over a shift and should not be blocked mid-edit, but
/// nothing incomplete may leave. After a successful submit the header, its
/// citations and its lines are read-only (G-P5), and the local copy is queued for
/// sync (G-Y2).
///
/// Two checks here exist specifically because time passed since the draft was
/// created, and both would be wrong to skip:
///
/// * **G-P1 is re-evaluated at the instant of submit.** A draft left open across a
///   week boundary must not be able to send citations that have since aged out of
///   the two-week window. The failure is deliberately its own type — nothing is
///   wrong with the branch head's choice, the draft simply sat too long.
/// * **G-P4 is re-evaluated too.** Another device may have submitted a different
///   request for the same branch in the meantime. The use case checks for a
///   friendly message; the partial unique index on
///   `(branch_id) WHERE status IN ('submitted','processing')` is the guarantee, and
///   it is what makes two simultaneous submits produce exactly one active order.
///
/// The document number stays `TMP-PR-…`. The final `PR-{cabang}-{yyyyMMdd}-{seq}`
/// is the server's to assign (G-Y4); minting a server-shaped number here would
/// collide across devices.
class SubmitPurchaseRequestUseCase {
  SubmitPurchaseRequestUseCase({
    required this._requests,
    required MasterDataRepository master,
    DateTime Function()? clock,
  }) : _guards = PurchaseRequestGuards(master),
       _clock = clock ?? _defaultClock;

  final PurchaseRequestRepository _requests;
  final PurchaseRequestGuards _guards;
  final DateTime Function() _clock;

  static DateTime _defaultClock() => DateTime.now().toUtc();

  Future<PurchaseRequest> call({
    required String actorUserId,
    required String prId,
  }) async {
    final actor = await _guards.requireBranchActor(actorUserId, prId: prId);

    return _requests.runInTransaction(() async {
      final detail = await _requests.getDetail(prId);
      if (detail == null) {
        throw PurchaseRequestNotFoundFailure(
          'Purchase Request tidak ditemukan.',
          prId: prId,
        );
      }

      final request = detail.request;
      _guards.requireSameBranch(actor: actor, request: request);
      _guards.requireStatus(
        request: request,
        expected: PurchaseRequestStatus.draft,
        attempted: PurchaseRequestStatus.submitted,
      );
      _guards.requireTransition(
        actor: actor,
        request: request,
        to: PurchaseRequestStatus.submitted,
      );

      // The document must be validated in full, and `detail` is only as complete
      // as the joins that produced it: lines inner-join `items` and citations
      // inner-join `stock_opnames`, so a row whose master reference is physically
      // gone is absent from it entirely rather than reported. Submitting on that
      // basis would freeze an order whose G-P3 check never saw one of its lines,
      // or whose G-P1 check never saw one of its citations. Catching it while the
      // document is still a draft leaves a way forward that `submitted` would not.
      await _guards.requireEveryLineLoaded(
        prId: prId,
        storedItemIds: await _requests.lineItemIds(prId),
        loadedItemIds: detail.lines.map((line) => line.itemId),
      );
      _guards.requireEveryOpnameLoaded(
        prId: prId,
        storedOpnameIds: await _requests.linkedOpnameIds(prId),
        loadedOpnameIds: detail.opnames.map((reference) => reference.opnameId),
      );

      _requireOpnameReferences(detail);
      _requireLines(detail);

      // G-P4, checked again now: `exceptPrId` keeps a document from reporting
      // itself as its own blocker if this runs twice.
      _guards.requireNoActiveRequest(
        branchId: request.branchId,
        active: await _requests.activeRequestForBranch(request.branchId),
        exceptPrId: prId,
      );

      // The submission is the document's *first* workflow event, so there is no
      // earlier event to order it against, and `DocumentTimestampPolicy` is not
      // consulted here.
      //
      // `created_at` deliberately does not serve as that earlier event. It is a
      // storage timestamp, written by the table's own `clientDefault(nowUtc)` and
      // therefore by the real wall clock — not by the clock this use case was given.
      // Comparing a workflow instant against it would mean comparing two different
      // notions of "now", which is exactly the class of confusion this policy exists
      // to remove, and it would make the rule untestable with an injected clock
      // (T-7). The chain that *is* enforced runs through the workflow events
      // themselves: submit → processing → rejected, and submit → cancelled.
      final submittedAt = _clock().toUtc();

      final moved = await _requests.submit(
        prId: prId,
        submittedAtUtc: submittedAt,
      );
      if (!moved) _guards.concurrentUpdate(request);

      final updated = await _requests.getById(prId);
      if (updated == null) {
        throw PurchaseRequestNotFoundFailure(
          'Purchase Request tidak ditemukan setelah dikirim.',
          prId: prId,
        );
      }
      return updated;
    });
  }

  /// G-P1 over the whole document, at the instant of submit.
  void _requireOpnameReferences(PurchaseRequestDetail detail) {
    if (detail.opnames.isEmpty) {
      throw PurchaseRequestOpnameRequiredFailure(
        'Purchase Request ${detail.request.docNumber} belum menautkan stok '
        'opname acuan, sehingga belum dapat dikirim.',
        prId: detail.id,
      );
    }

    final now = _clock().toUtc();
    final expired = <String>[];
    for (final reference in detail.opnames) {
      final denial = PurchaseRequestOpnameEligibilityPolicy.denialFor(
        facts: (
          opnameId: reference.opnameId,
          branchId: reference.branchId,
          status: reference.status,
          periodYear: reference.periodYear,
          periodWeek: reference.periodWeek,
        ),
        prBranchId: detail.request.branchId,
        utcNow: now,
      );
      if (denial == null) continue;

      // Ageing out is the one denial that can happen to a reference that was
      // valid when it was chosen, and it deserves its own answer: re-pick this
      // week's counts. Every other denial means the citation should never have
      // been accepted, which is a different conversation.
      if (denial == StockOpnameEligibilityDenial.periodTooOld) {
        expired.add(reference.opnameId);
        continue;
      }
      throw IneligibleStockOpnameFailure(
        PurchaseRequestOpnameEligibilityPolicy.messageFor(
          reason: denial,
          docNumber: reference.docNumber,
        ),
        opnameId: reference.opnameId,
        reason: denial,
      );
    }

    if (expired.isNotEmpty) {
      throw ExpiredStockOpnameReferenceFailure(
        'Stok opname acuan sudah melewati batas satu minggu sebelum minggu '
        'berjalan. Pilih ulang stok opname terbaru sebelum mengirim '
        'permintaan.',
        prId: detail.id,
        opnameIds: expired,
      );
    }
  }

  /// G-P2 and G-P3 over the whole document.
  void _requireLines(PurchaseRequestDetail detail) {
    if (detail.lines.isEmpty) {
      throw ValidationFailure(
        'Purchase Request ${detail.request.docNumber} belum memiliki satu '
        'baris pun, sehingga belum dapat dikirim.',
      );
    }

    final seen = <String>{};
    for (final line in detail.lines) {
      if (!line.requestedQty.isPositive) {
        throw InvalidRequestedQuantityFailure(
          'Jumlah permintaan ${line.itemName} harus lebih dari 0.',
          itemId: line.itemId,
          requested: line.requestedQty,
        );
      }
      // The partial unique index already makes this impossible in the database;
      // checking here turns a constraint error into a sentence a user can act on.
      if (!seen.add(line.itemId)) {
        throw DuplicatePurchaseRequestItemFailure(
          '${line.itemName} muncul lebih dari satu kali pada permintaan ini.',
          prId: detail.id,
          itemId: line.itemId,
        );
      }
    }

    // G-P3: every line above the threshold, and every manual line, needs a
    // reason. All offending lines are reported at once so the form can mark them
    // together instead of surfacing them one failed submit at a time.
    final missing = detail.linesMissingJustification;
    if (missing.isEmpty) return;

    final names = missing.take(3).map((line) => line.itemName).join(', ');
    final suffix = missing.length > 3
        ? ' dan ${missing.length - 3} baris lainnya'
        : '';
    throw PurchaseRequestJustificationRequiredFailure(
      'Catatan alasan wajib diisi untuk baris yang melebihi '
      '${PurchaseRequestQuantityPolicy.thresholdPercent}% saran sistem atau '
      'diminta manual: $names$suffix.',
      lineIds: missing.map((line) => line.id).toList(growable: false),
    );
  }
}
