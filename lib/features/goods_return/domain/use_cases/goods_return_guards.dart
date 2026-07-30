import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/document_timestamp_policy.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/goods_return_models.dart';
import '../repositories/goods_return_repository.dart';
import '../services/goods_return_access_policy.dart';
import '../services/goods_return_eligibility_policy.dart';
import '../services/goods_return_snapshot_policy.dart';
import '../services/goods_return_state_policy.dart';

/// The RBAC, branch, segregation, eligibility, snapshot, integrity, destination and
/// timestamp checks every Retur use case shares (§15 … §26).
///
/// They live in one place because a rule that is re-implemented per use case is a rule
/// that eventually differs per use case. Each guard reads the actor from the database
/// rather than trusting whatever id the caller passed, so a development session (or,
/// later, a token) can never grant a permission the stored user does not have (O-8).
///
/// Every method here is a *refusal*: it either returns the value it verified or throws.
/// Nothing substitutes, guesses or repairs — a return that cannot be shipped or
/// received as written is refused, never shipped or received differently. That matters
/// more on this document than on any earlier one, because the two things a repair
/// would be tempted to do — drop a line whose item is missing, or adjust a quantity to
/// match — are exactly the two things that would make the Warehouse's balance wrong.
///
/// ### The guard no earlier document needed
///
/// [requireSegregationOfDuties] is new in this milestone. G-R4 has been quoted by every
/// document family so far as a reason *not* to invent an approval stage; this is the
/// first workflow where it has actual work to do, because this is the first document
/// whose two halves belong to different parts of the organisation. It is checked here,
/// in the SQL predicate of `markReceived`, and in the access policy the button reads —
/// three times, because a user whose role changed after the document was raised would
/// satisfy any one of them alone.
class GoodsReturnGuards {
  const GoodsReturnGuards(this._master);

  final MasterDataRepository _master;

  // --- actor (§15) ----------------------------------------------------------

  /// Loads the actor and refuses inactive accounts.
  ///
  /// Applies whatever the document's age: unlike the item or batch data a historic
  /// return points at, the person shipping or receiving goods *right now* has to be a
  /// currently valid account.
  Future<MasterUser> requireActiveUser(String userId) async {
    final user = await _master.userById(userId);
    if (user == null) {
      throw EntityNotFoundFailure(
        'Pengguna tidak ditemukan.',
        entity: 'users',
        id: userId,
      );
    }
    if (!user.isActive) {
      throw InactiveEntityFailure(
        'Akun ${user.fullName} sudah dinonaktifkan.',
        entity: 'users',
        id: userId,
      );
    }
    return user;
  }

  /// The actor for everything on the branch side: create, edit note, ship (§15).
  ///
  /// Requires a branch as well as the role, and the two are one check on purpose:
  /// *"their own branch's Good Receipt"* is meaningless without a branch to compare,
  /// and a branch-scoped account without one is a data fault rather than a permission
  /// that happens to be wide.
  ///
  /// Perawat, Warehouse and Super Admin are refused here, not merely unrouted, and each
  /// for the reason [GoodsReturnAccessPolicy] spells out. A Petugas Warehouse pressing
  /// *Kirim Retur* would be asserting that a box left a building they are not in.
  Future<MasterUser> requireBranchActor(String userId) async {
    final user = await requireActiveUser(userId);
    if (user.role != GoodsReturnStatePolicy.branchRole) {
      throw GoodsReturnAccessDeniedFailure(
        'Hanya Kepala Cabang yang dapat membuat dan mengirim Retur. '
        '${user.fullName} berperan sebagai ${user.role.label}.',
        actorUserId: userId,
        requiredRole: GoodsReturnStatePolicy.branchRole,
      );
    }
    if (user.branchId == null) {
      throw UnauthorizedBranchFailure(
        'Akun ${user.fullName} belum terhubung ke cabang mana pun, sehingga '
        'tidak dapat membuat atau mengirim Retur.',
        actorUserId: userId,
        branchId: '',
      );
    }
    return user;
  }

  /// The actor for the receiving half (§15/§21).
  ///
  /// Deliberately does **not** require a branch: a Petugas Warehouse operates Warehouse
  /// Pusat, which belongs to no branch, and demanding one would lock the queue to
  /// nobody.
  Future<MasterUser> requireWarehouseActor(String userId) async {
    final user = await requireActiveUser(userId);
    if (user.role != GoodsReturnStatePolicy.warehouseRole) {
      throw GoodsReturnAccessDeniedFailure(
        'Hanya Petugas Warehouse yang dapat mengonfirmasi penerimaan Retur. '
        '${user.fullName} berperan sebagai ${user.role.label}.',
        actorUserId: userId,
        requiredRole: GoodsReturnStatePolicy.warehouseRole,
      );
    }
    return user;
  }

  /// G-R2 — the actor's branch must be the document's.
  ///
  /// Asked in addition to the scoped queries rather than instead of them: a scoped read
  /// is what stops a foreign document being *fetched*, and this is what stops one being
  /// *written* if a caller ever passes an unscoped read by mistake. It also catches the
  /// case the scope alone would miss — a branch head whose branch was changed while a
  /// draft of theirs sat open in the old one.
  void requireBranchMatches({
    required MasterUser actor,
    required String documentBranchId,
  }) {
    if (actor.branchId == documentBranchId) return;
    throw GoodsReturnBranchMismatchFailure(
      'Retur ini milik cabang lain, sehingga tidak dapat diakses dari akun ini.',
      actorUserId: actor.id,
      actorBranchId: actor.branchId,
      documentBranchId: documentBranchId,
    );
  }

  /// The branch a new return is raised for must be live and active.
  ///
  /// Only asked when *creating*: an existing document whose branch was retired
  /// afterwards stays readable, and — critically — stays *receivable*. The goods are
  /// already in transit by then, and refusing to count them in because the branch that
  /// sent them has since closed would leave a box at the Warehouse door with no
  /// document (§37).
  Future<MasterBranch> requireActiveBranch(String branchId) async {
    final branches = await _master.activeBranches();
    for (final branch in branches) {
      if (branch.id == branchId) return branch;
    }
    throw InactiveEntityFailure(
      'Cabang tidak aktif atau tidak ditemukan, sehingga Retur tidak dapat '
      'dibuat.',
      entity: 'branches',
      id: branchId,
    );
  }

  /// G-R4 — the confirming actor may be neither the creator nor the shipper (§15).
  ///
  /// Takes **ids**, not roles, and that is the whole point: a Kepala Cabang who raised
  /// a return last month and has since moved to the Warehouse team passes every role
  /// check in the application, and is still the person who decided these goods should
  /// go back. Letting them also confirm their own delivery would make both halves of
  /// this workflow one person's word.
  void requireSegregationOfDuties({
    required MasterUser actor,
    required GoodsReturn goodsReturn,
  }) {
    final verdict = GoodsReturnAccessPolicy.checkSegregation(
      actorUserId: actor.id,
      createdBy: goodsReturn.createdBy,
      shippedBy: goodsReturn.shippedBy,
    );
    if (verdict.isGranted) return;
    throw GoodsReturnSegregationOfDutiesFailure(
      actor.id == goodsReturn.createdBy
          ? 'Retur ${goodsReturn.docNumber} dibuat oleh akun ini, sehingga '
                'penerimaannya harus dikonfirmasi petugas Warehouse lain.'
          : 'Retur ${goodsReturn.docNumber} dikirim oleh akun ini, sehingga '
                'penerimaannya harus dikonfirmasi petugas Warehouse lain.',
      goodsReturnId: goodsReturn.id,
      actorUserId: actor.id,
      createdBy: goodsReturn.createdBy,
      shippedBy: goodsReturn.shippedBy,
    );
  }

  // --- document state (§14) --------------------------------------------------

  /// The document, or an explicit not-found.
  GoodsReturn requireDocument({
    required GoodsReturn? goodsReturn,
    required String goodsReturnId,
  }) {
    if (goodsReturn != null) return goodsReturn;
    throw GoodsReturnNotFoundFailure(
      'Dokumen Retur tidak ditemukan.',
      goodsReturnId: goodsReturnId,
    );
  }

  /// G-S1/G-S2 — the document must currently be in [expected].
  ///
  /// The two "already" cases get their own failures rather than the generic one,
  /// because they are the two a user actually hits: two devices pressing the same
  /// button, and a stale screen. Each names the instant it already happened at, which
  /// is what turns *"that didn't work"* into *"somebody already did this"*.
  void requireStatus({
    required GoodsReturn goodsReturn,
    required GoodsReturnStatus expected,
    GoodsReturnStatus? attempted,
  }) {
    if (goodsReturn.status == expected) return;
    if (goodsReturn.isReceived) {
      throw GoodsReturnAlreadyReceivedFailure(
        'Retur ${goodsReturn.docNumber} sudah diterima Warehouse, sehingga '
        'tidak dapat diubah lagi.',
        goodsReturnId: goodsReturn.id,
        receivedAt: goodsReturn.receivedAt,
      );
    }
    if (goodsReturn.isShipped && expected == GoodsReturnStatus.draft) {
      throw GoodsReturnAlreadyShippedFailure(
        'Retur ${goodsReturn.docNumber} sudah dikirim ke Warehouse, sehingga '
        'tidak dapat diubah lagi dari cabang.',
        goodsReturnId: goodsReturn.id,
        shippedAt: goodsReturn.shippedAt,
      );
    }
    throw InvalidGoodsReturnStateFailure(
      'Retur ${goodsReturn.docNumber} berstatus ${goodsReturn.status.label}, '
      'sehingga tindakan ini tidak dapat dilakukan.',
      goodsReturnId: goodsReturn.id,
      currentStatus: goodsReturn.status,
      attemptedStatus: attempted,
    );
  }

  /// The state machine, asked with the actor's role in hand (§14).
  ///
  /// Asked in addition to [requireStatus] rather than instead of it: the status check
  /// produces the message about *this* document, and this one is what refuses a
  /// transition the table does not contain at all — including one a future caller might
  /// invent.
  void requireTransition({
    required MasterUser actor,
    required GoodsReturn goodsReturn,
    required GoodsReturnStatus to,
  }) {
    if (GoodsReturnStatePolicy.isAllowedFor(
      role: actor.role,
      from: goodsReturn.status,
      to: to,
    )) {
      return;
    }
    throw InvalidGoodsReturnStateFailure(
      'Perubahan status Retur dari ${goodsReturn.status.label} ke ${to.label} '
      'tidak diizinkan untuk ${actor.role.label}.',
      goodsReturnId: goodsReturn.id,
      currentStatus: goodsReturn.status,
      attemptedStatus: to,
    );
  }

  // --- eligibility (§16/§17) -------------------------------------------------

  /// Whether a return may be raised from [grId] at all.
  ///
  /// Every fact is re-read from the database by the caller and passed in, so this is
  /// the same question the queue answered — asked again, inside the create
  /// transaction, against the state the write will actually see.
  void requireEligibleGoodReceipt({
    required String grId,
    required GoodReceiptStatus? receiptStatus,
    required String? receiptBranchId,
    required String actorBranchId,
    required int rejectedLineCount,
    required GoodsReturn? existingReturn,
  }) {
    final verdict = GoodsReturnEligibilityPolicy.verify(
      receiptStatus: receiptStatus,
      receiptBranchId: receiptBranchId,
      actorBranchId: actorBranchId,
      rejectedLineCount: rejectedLineCount,
      hasExistingReturn: existingReturn != null,
    );
    if (verdict.isAccepted) return;

    switch (verdict.rejection!) {
      case GoodsReturnEligibilityRejection.missing:
        throw EntityNotFoundFailure(
          'Dokumen Penerimaan Barang tidak ditemukan.',
          entity: 'good_receipts',
          id: grId,
        );
      case GoodsReturnEligibilityRejection.branchMismatch:
        // Answered before any content check, so the message never confirms anything
        // about another branch's receipt — including whether it had rejections.
        throw GoodsReturnNotEligibleFailure(
          'Dokumen Penerimaan Barang ini milik cabang lain, sehingga Retur '
          'tidak dapat dibuat dari akun ini.',
          grId: grId,
        );
      case GoodsReturnEligibilityRejection.notPosted:
        throw GoodsReturnNotEligibleFailure(
          'Retur hanya dapat dibuat dari Penerimaan Barang yang sudah '
          'diposting. Selesaikan pemeriksaan dokumen tersebut terlebih dahulu.',
          grId: grId,
          receiptStatus: receiptStatus,
        );
      case GoodsReturnEligibilityRejection.alreadyReturned:
        throw GoodsReturnAlreadyExistsFailure(
          'Penerimaan Barang ini sudah memiliki dokumen Retur '
                  '${existingReturn?.docNumber ?? ''}'
              .trim(),
          grId: grId,
          existingGoodsReturnId: existingReturn?.id,
        );
      case GoodsReturnEligibilityRejection.noRejectedLines:
        throw GoodsReturnNoRejectedLinesFailure(
          'Tidak ada barang yang ditolak pada Penerimaan Barang ini, sehingga '
          'tidak ada yang perlu diretur.',
          grId: grId,
        );
    }
  }

  /// Whether one rejected position is in a shape a return line may be cut from (§16).
  ///
  /// Each refusal is its own failure because each is a different fault: a reason that
  /// went missing is a G-G4 violation upstream, a non-zero `received_qty` on a rejected
  /// line means the receipt's own CHECK failed, and an inconsistent batch is G-E2.
  void requireReturnablePosition(RejectedGoodReceiptPosition position) {
    if (position.rejectReason.trim().isEmpty) {
      throw GoodsReturnRejectReasonMissingFailure(
        'Baris penolakan tanpa alasan tidak dapat diretur. Hubungi '
        'administrator.',
        grLineId: position.grLineId,
      );
    }
    if (!position.receivedQty.isZero) {
      throw GoodsReturnQuantityMismatchFailure(
        'Baris ${position.sku} tercatat menerima sebagian barang, sehingga '
        'tidak dapat diretur seluruhnya.',
        goodsReturnId: '',
        grLineId: position.grLineId,
        expected: Quantity.zero(),
        actual: position.receivedQty,
      );
    }
    if (!position.shippedQty.isPositive) {
      throw GoodsReturnQuantityMismatchFailure(
        'Baris ${position.sku} tidak memiliki kuantitas kirim, sehingga tidak '
        'dapat diretur.',
        goodsReturnId: '',
        grLineId: position.grLineId,
        expected: position.shippedQty,
        actual: position.shippedQty,
      );
    }
    if (!position.isBatchConsistent) {
      throw GoodsReturnItemBatchMismatchFailure(
        position.hasExpiry
            ? 'Barang ${position.sku} dilacak per batch, tetapi baris '
                  'penolakan tidak menyimpan batch.'
            : 'Barang ${position.sku} tidak dilacak per batch, tetapi baris '
                  'penolakan menyimpan batch.',
        itemId: position.itemId,
        batchId: position.batchId,
        grLineId: position.grLineId,
      );
    }
  }

  // --- set integrity (§26) ---------------------------------------------------

  /// Compares two id collections read **without any join** and refuses on any
  /// difference.
  ///
  /// The one check a joined read cannot perform. An `INNER JOIN items` silently drops a
  /// line whose item row was physically deleted, so a corrupted document would arrive
  /// looking smaller but perfectly consistent. [expected] and [actual] therefore both
  /// come from single-column queries, and the difference between them is the answer.
  void requireLoadedSetMatches({
    required String goodsReturnId,
    required Iterable<String> expected,
    required Iterable<String> actual,
    required String entity,
  }) {
    final expectedSet = expected.toSet();
    final actualSet = actual.toSet();
    for (final id in expectedSet) {
      if (actualSet.contains(id)) continue;
      throw GoodsReturnLineIntegrityFailure(
        'Data $entity untuk Retur ini tidak lengkap, sehingga dokumen tidak '
        'dapat diproses. Hubungi administrator.',
        goodsReturnId: goodsReturnId,
        entity: entity,
        id: id,
      );
    }
    for (final id in actualSet) {
      if (expectedSet.contains(id)) continue;
      throw GoodsReturnLineIntegrityFailure(
        'Data $entity untuk Retur ini tidak konsisten, sehingga dokumen tidak '
        'dapat diproses. Hubungi administrator.',
        goodsReturnId: goodsReturnId,
        entity: entity,
        id: id,
      );
    }
  }

  /// The document must have at least one line.
  void requireLines({
    required String goodsReturnId,
    required List<GoodsReturnLineReference> lines,
  }) {
    if (lines.isNotEmpty) return;
    throw GoodsReturnLineIntegrityFailure(
      'Retur ini tidak memiliki baris barang, sehingga tidak dapat diproses.',
      goodsReturnId: goodsReturnId,
    );
  }

  // --- snapshot (§18) ---------------------------------------------------------

  /// The stored snapshot must still reproduce the receipt's rejections exactly.
  ///
  /// Asked before shipping and again before receiving, because the snapshot is not the
  /// only copy of these facts and something could have happened to the other one. A
  /// mismatch is always a refusal — never a line skipped, never a quantity adjusted to
  /// fit — because either of those would make the Warehouse's balance describe goods
  /// nobody sent.
  void requireSnapshotMatches({
    required GoodsReturn goodsReturn,
    required List<GoodsReturnLineReference> lines,
    required List<RejectedGoodReceiptPosition> positions,
  }) {
    final verdict = GoodsReturnSnapshotPolicy.verify(
      lines: lines,
      positions: positions,
    );
    if (verdict.matches) return;

    switch (verdict.mismatch!) {
      case GoodsReturnSnapshotMismatch.quantity:
        final line = _lineFor(lines, verdict.grLineId);
        final position = _positionFor(positions, verdict.grLineId);
        throw GoodsReturnQuantityMismatchFailure(
          'Kuantitas retur tidak lagi sama dengan kuantitas kirim pada '
          'Penerimaan Barang, sehingga dokumen tidak dapat diproses.',
          goodsReturnId: goodsReturn.id,
          grLineId: verdict.grLineId ?? '',
          expected: position?.returnQty ?? Quantity.zero(),
          actual: line?.qty ?? Quantity.zero(),
        );
      case GoodsReturnSnapshotMismatch.item:
      case GoodsReturnSnapshotMismatch.batch:
        final line = _lineFor(lines, verdict.grLineId);
        throw GoodsReturnItemBatchMismatchFailure(
          'Barang atau batch pada Retur ini tidak lagi sama dengan baris '
          'penolakan aslinya, sehingga dokumen tidak dapat diproses.',
          itemId: line?.itemId ?? '',
          batchId: line?.batchId,
          grLineId: verdict.grLineId,
        );
      case GoodsReturnSnapshotMismatch.rejectReason:
        throw GoodsReturnRejectReasonMissingFailure(
          'Alasan penolakan pada Retur ini tidak lagi sama dengan alasan pada '
          'Penerimaan Barang, sehingga dokumen tidak dapat diproses.',
          grLineId: verdict.grLineId ?? '',
          goodsReturnId: goodsReturn.id,
        );
      case GoodsReturnSnapshotMismatch.empty:
      case GoodsReturnSnapshotMismatch.missingLine:
      case GoodsReturnSnapshotMismatch.extraLine:
      case GoodsReturnSnapshotMismatch.duplicateLine:
        throw GoodsReturnSnapshotMismatchFailure(
          _snapshotMessage(verdict.mismatch!),
          goodsReturnId: goodsReturn.id,
          grId: goodsReturn.grId,
          grLineId: verdict.grLineId,
        );
    }
  }

  static String _snapshotMessage(
    GoodsReturnSnapshotMismatch mismatch,
  ) => switch (mismatch) {
    GoodsReturnSnapshotMismatch.empty =>
      'Retur ini tidak memiliki baris barang, sehingga tidak dapat '
          'diproses.',
    GoodsReturnSnapshotMismatch.missingLine =>
      'Retur ini tidak lagi mencakup seluruh barang yang ditolak pada '
          'Penerimaan Barang, sehingga dokumen tidak dapat diproses. '
          'Hubungi administrator.',
    GoodsReturnSnapshotMismatch.extraLine =>
      'Retur ini memuat barang yang tidak ditolak pada Penerimaan Barang, '
          'sehingga dokumen tidak dapat diproses. Hubungi administrator.',
    GoodsReturnSnapshotMismatch.duplicateLine =>
      'Retur ini memuat baris ganda untuk satu barang yang ditolak, '
          'sehingga dokumen tidak dapat diproses. Hubungi administrator.',
    // The three per-line shapes are handled by their own failures above; listed
    // so a new mismatch value cannot be added without this switch failing to
    // compile.
    GoodsReturnSnapshotMismatch.quantity ||
    GoodsReturnSnapshotMismatch.item ||
    GoodsReturnSnapshotMismatch.batch ||
    GoodsReturnSnapshotMismatch.rejectReason =>
      'Retur ini tidak lagi sesuai dengan Penerimaan Barang asalnya, '
          'sehingga dokumen tidak dapat diproses.',
  };

  static GoodsReturnLineReference? _lineFor(
    List<GoodsReturnLineReference> lines,
    String? grLineId,
  ) {
    for (final line in lines) {
      if (line.grLineId == grLineId) return line;
    }
    return null;
  }

  static RejectedGoodReceiptPosition? _positionFor(
    List<RejectedGoodReceiptPosition> positions,
    String? grLineId,
  ) {
    for (final position in positions) {
      if (position.grLineId == grLineId) return position;
    }
    return null;
  }

  // --- historical references (§37) --------------------------------------------

  /// The Good Receipt the document points at must still exist, and still be posted.
  ///
  /// *Inactive* master data is fine on this path — a received return whose item was
  /// withdrawn afterwards must stay readable — but the exact receipt row is different:
  /// it is what the snapshot is verified against, and without it there is nothing to
  /// verify against at all.
  void requireHistoricalGoodReceipt({
    required GoodsReturn goodsReturn,
    required GoodReceiptStatus? receiptStatus,
  }) {
    if (receiptStatus == null) {
      throw HistoricalGoodsReturnReferenceMissingFailure(
        'Retur tidak dapat diproses karena dokumen Penerimaan Barang asalnya '
        'tidak ditemukan. Hubungi administrator.',
        entity: 'good_receipts',
        id: goodsReturn.grId,
        goodsReturnId: goodsReturn.id,
      );
    }
    if (receiptStatus != GoodsReturnEligibilityPolicy.requiredReceiptStatus) {
      throw GoodsReturnNotEligibleFailure(
        'Dokumen Penerimaan Barang asal Retur ini tidak lagi berstatus '
        'diposting, sehingga Retur tidak dapat diproses.',
        grId: goodsReturn.grId,
        receiptStatus: receiptStatus,
      );
    }
  }

  // --- destination (§21) -------------------------------------------------------

  /// The single active Warehouse Pusat location a return is credited to.
  ///
  /// Both failure modes are explicit rather than resolved:
  ///
  /// * **none** — there is nowhere to put the goods, and inventing a location would
  ///   post the ledger against a row that does not exist;
  /// * **more than one** — which warehouse the goods arrived at is a business fact.
  ///   Picking the first would silently credit a balance nobody chose, and the real
  ///   shelf would still hold the stock.
  ///
  /// No seed id is hard-coded anywhere on this path: the location is looked up by type
  /// every time, which is what makes *"the destination is always the Warehouse Pusat"*
  /// a fact about the data rather than a constant a screen could pass.
  MasterLocation requireWarehouseLocation(List<MasterLocation> locations) {
    if (locations.isEmpty) {
      throw const GoodsReturnWarehouseLocationNotFoundFailure(
        'Lokasi Warehouse Pusat tidak ditemukan, sehingga Retur tidak dapat '
        'diterima. Hubungi administrator.',
      );
    }
    if (locations.length > 1) {
      throw GoodsReturnWarehouseLocationAmbiguousFailure(
        'Terdapat lebih dari satu lokasi Warehouse Pusat, sehingga sistem '
        'tidak dapat menentukan tujuan Retur. Hubungi administrator.',
        locationIds: locations
            .map((location) => location.id)
            .toList(growable: false),
      );
    }
    return locations.single;
  }

  // --- notes (§19/§21) ---------------------------------------------------------

  /// A note may be absent, but a *stored* one must say something.
  ///
  /// `null` clears it and is legitimate; whitespace is not, and returning it silently
  /// as `null` would be the repair this class does not do — a user who typed spaces
  /// gets told, rather than quietly having their input discarded.
  String? requireMeaningfulNote(String? note) {
    if (note == null) return null;
    final trimmed = note.trim();
    if (trimmed.isEmpty) {
      throw const ValidationFailure(
        'Catatan tidak boleh berisi spasi saja. Kosongkan atau isi dengan '
        'keterangan.',
      );
    }
    return trimmed;
  }

  // --- timestamps (§39) ---------------------------------------------------------

  /// `shipped_at >= created_at`, on UTC instants and never as text.
  void requireShipInstant({
    required GoodsReturn goodsReturn,
    required DateTime nowUtc,
  }) {
    _mapTimestampFailure(
      goodsReturn.id,
      () => DocumentTimestampPolicy.requireShipNotBeforeCreate(
        documentId: goodsReturn.id,
        createdAtUtc: goodsReturn.createdAt,
        shippedAtUtc: nowUtc,
      ),
    );
  }

  /// `received_at >= shipped_at`, on UTC instants and never as text.
  void requireReceiveInstant({
    required GoodsReturn goodsReturn,
    required DateTime nowUtc,
  }) {
    _mapTimestampFailure(
      goodsReturn.id,
      () => DocumentTimestampPolicy.requireReceiveNotBeforeShip(
        documentId: goodsReturn.id,
        shippedAtUtc: goodsReturn.shippedAt,
        receivedAtUtc: nowUtc,
      ),
    );
  }

  /// Re-labels the shared policy's failure as this document's.
  ///
  /// The ordering rule itself stays in [DocumentTimestampPolicy] — one implementation,
  /// on UTC instants, for every document type (§39) — and this only changes which type
  /// the caller catches, so the presenter and the tests can be specific about a Retur
  /// without a second copy of the comparison.
  void _mapTimestampFailure(String goodsReturnId, void Function() body) {
    try {
      body();
    } on InvalidDocumentTimestampFailure catch (failure) {
      throw InvalidGoodsReturnTimestampFailure(
        failure.message,
        goodsReturnId: goodsReturnId,
        earlierLabel: failure.earlierLabel,
        earlierUtc: failure.earlierUtc,
        laterLabel: failure.laterLabel,
        laterUtc: failure.laterUtc,
      );
    }
  }

  // --- concurrency ---------------------------------------------------------------

  /// A guarded write matched no rows.
  ///
  /// Always a refusal and never a retry: the row the caller read is not the row that is
  /// there now, so retrying would be writing a decision made against stale facts.
  Never concurrentUpdate(String goodsReturnId, String message) {
    throw ConcurrentGoodsReturnUpdateFailure(
      message,
      goodsReturnId: goodsReturnId,
    );
  }

  /// Whether [repository] and the caller agree that this return may still be shipped.
  ///
  /// A convenience for the two call sites that need the whole read-and-verify sequence,
  /// kept here so neither of them can perform four of the five steps.
  Future<List<GoodsReturnLineReference>> loadVerifiedLines({
    required GoodsReturnRepository repository,
    required GoodsReturn goodsReturn,
    required List<RejectedGoodReceiptPosition> positions,
  }) async {
    // The plain id list first — this is the authority, and the joined read below is
    // checked against it rather than the other way round (§26).
    final expectedIds = await repository.lineIds(goodsReturn.id);
    final lines = await repository.lineReferences(goodsReturn.id);
    requireLoadedSetMatches(
      goodsReturnId: goodsReturn.id,
      expected: expectedIds,
      actual: lines.map((line) => line.id),
      entity: 'goods_return_lines',
    );
    requireLines(goodsReturnId: goodsReturn.id, lines: lines);
    requireSnapshotMatches(
      goodsReturn: goodsReturn,
      lines: lines,
      positions: positions,
    );
    return lines;
  }
}
