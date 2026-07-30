import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/purchase_request_models.dart';
import '../services/purchase_request_state_policy.dart';

/// The RBAC, state and reference checks every Purchase Request use case shares
/// (G-R2, G-R3, G-R4, G-P4, G-P5, G-S1).
///
/// They live in one place because a rule that is re-implemented per use case is a
/// rule that eventually differs per use case. Each guard reads the actor from the
/// database rather than trusting whatever id the caller passed, so a development
/// session (or, later, a token) can never grant a permission the stored user does
/// not have (O-8).
class PurchaseRequestGuards {
  const PurchaseRequestGuards(this._master);

  final MasterDataRepository _master;

  /// Loads the actor and refuses inactive accounts.
  ///
  /// Applies to **every** role, warehouse included: unlike the branch data a
  /// historic document points at, the person performing an action right now has
  /// to be a currently valid account (§7.2).
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

  /// The Kepala Cabang side of the workflow: the actor must hold the role *and*
  /// belong to a branch, because every request they touch is scoped to it.
  ///
  /// A warehouse actor is refused with its own failure rather than the generic
  /// wrong-role one, because G-R3 is a rule about the warehouse specifically —
  /// *"Warehouse tidak bisa mengubah isi PR — hanya memenuhi (fulfil) atau
  /// menolak dengan alasan"* — and a message that says so is the difference
  /// between an officer thinking they lack a permission and understanding that
  /// nobody has it. [prId] names the document when the caller knows it.
  Future<MasterUser> requireBranchActor(String userId, {String? prId}) async {
    final user = await requireActiveUser(userId);
    if (user.role == UserRole.warehouse) {
      throw WarehouseCannotEditPurchaseRequestFailure(
        'Petugas Warehouse tidak dapat mengubah isi Purchase Request. '
        'Warehouse hanya dapat memproses atau menolak permintaan.',
        actorUserId: userId,
        prId: prId ?? '',
      );
    }
    if (user.role != UserRole.kepalaCabang) {
      throw InvalidReviewerFailure(
        'Hanya Kepala Cabang yang dapat mengelola Purchase Request. '
        '${user.fullName} berperan sebagai ${user.role.label}.',
        actorUserId: userId,
        requiredRole: UserRole.kepalaCabang,
      );
    }
    if (user.branchId == null) {
      throw ValidationFailure(
        'Pengguna ${user.fullName} belum terhubung ke cabang mana pun.',
      );
    }
    return user;
  }

  /// The warehouse side. Deliberately does **not** require a branch: the central
  /// warehouse serves every branch, and `users.branch_id` is NULL for it by
  /// design (spec §2.1).
  Future<MasterUser> requireWarehouseActor(String userId) async {
    final user = await requireActiveUser(userId);
    if (user.role != UserRole.warehouse) {
      throw InvalidReviewerFailure(
        'Hanya Petugas Warehouse yang dapat memproses atau menolak Purchase '
        'Request. ${user.fullName} berperan sebagai ${user.role.label}.',
        actorUserId: userId,
        requiredRole: UserRole.warehouse,
      );
    }
    return user;
  }

  /// G-R2 — the document must belong to the actor's branch.
  void requireSameBranch({
    required MasterUser actor,
    required PurchaseRequest request,
  }) {
    if (request.branchId != actor.branchId) {
      throw UnauthorizedPurchaseRequestBranchFailure(
        'Purchase Request ${request.docNumber} milik cabang lain.',
        actorUserId: actor.id,
        branchId: request.branchId,
      );
    }
  }

  /// G-P5/G-S1 — the document must currently be in [expected].
  void requireStatus({
    required PurchaseRequest request,
    required PurchaseRequestStatus expected,
    PurchaseRequestStatus? attempted,
  }) {
    if (request.status == expected) return;
    throw InvalidPurchaseRequestStateFailure(
      _stateMessage(request, attempted),
      prId: request.id,
      currentStatus: request.status,
      attemptedStatus: attempted,
    );
  }

  /// G-S1 — the transition must exist in the state machine and belong to this
  /// role.
  ///
  /// Asked in addition to [requireStatus] rather than instead of it: the status
  /// check produces the message a user needs ("already being processed"), while
  /// this one is the structural check that no code path invents a transition the
  /// policy does not list — including the two `system` transitions that no use
  /// case in this milestone may perform.
  void requireTransition({
    required MasterUser actor,
    required PurchaseRequest request,
    required PurchaseRequestStatus to,
  }) {
    if (PurchaseRequestStatePolicy.isAllowedFor(
      role: actor.role,
      from: request.status,
      to: to,
    )) {
      return;
    }
    throw InvalidPurchaseRequestStateFailure(
      _stateMessage(request, to),
      prId: request.id,
      currentStatus: request.status,
      attemptedStatus: to,
    );
  }

  String _stateMessage(
    PurchaseRequest request,
    PurchaseRequestStatus? attempted,
  ) {
    final number = request.docNumber;
    return switch (request.status) {
      PurchaseRequestStatus.draft
          when attempted == PurchaseRequestStatus.processing ||
              attempted == PurchaseRequestStatus.rejected =>
        'Purchase Request $number masih draft dan belum dikirim ke Warehouse.',
      PurchaseRequestStatus.draft => 'Purchase Request $number masih draft.',
      PurchaseRequestStatus.submitted =>
        'Purchase Request $number sudah dikirim dan menunggu Warehouse, '
            'sehingga isinya tidak dapat diubah lagi.',
      PurchaseRequestStatus.processing =>
        'Purchase Request $number sedang diproses Warehouse, sehingga tidak '
            'dapat diubah atau dibatalkan.',
      PurchaseRequestStatus.shipped =>
        'Purchase Request $number sudah dikirim Warehouse dan menunggu '
            'penerimaan barang.',
      PurchaseRequestStatus.closed =>
        'Purchase Request $number sudah selesai dan bersifat final.',
      PurchaseRequestStatus.rejected =>
        'Purchase Request $number sudah ditolak Warehouse dan bersifat final.',
      PurchaseRequestStatus.cancelled =>
        'Purchase Request $number sudah dibatalkan. Buat permintaan baru bila '
            'barang masih dibutuhkan.',
    };
  }

  /// G-P4 — the branch must not already have a `submitted`/`processing` request.
  ///
  /// [exceptPrId] is the document being submitted, so a re-check on the document
  /// that already holds the slot does not report itself as the blocker.
  void requireNoActiveRequest({
    required String branchId,
    required PurchaseRequest? active,
    String? exceptPrId,
  }) {
    if (active == null || active.id == exceptPrId) return;
    throw PurchaseRequestAlreadyActiveFailure(
      'Cabang ini masih memiliki Purchase Request aktif '
      '(${active.docNumber}, ${active.status.label}). Selesaikan atau '
      'batalkan permintaan tersebut sebelum mengirim yang baru.',
      branchId: branchId,
      activePrId: active.id,
    );
  }

  /// Turns "the guarded write matched no rows" into the right failure. Reached
  /// when another device changed the document between the read and the write.
  Never concurrentUpdate(PurchaseRequest request) {
    throw ConcurrentPurchaseRequestUpdateFailure(
      'Purchase Request ${request.docNumber} baru saja diubah dari perangkat '
      'lain. Muat ulang halaman lalu coba lagi.',
      prId: request.id,
    );
  }

  /// A non-blank reason, or the failure the caller asked for.
  ///
  /// Whitespace is not a reason. The database enforces the same thing with
  /// `trim(...) <> ''`, so a hand-written UPDATE cannot slip one past either.
  String requireReason(
    String? reason, {
    required AppFailure Function() onMissing,
  }) {
    final trimmed = (reason ?? '').trim();
    if (trimmed.isEmpty) throw onMissing();
    return trimmed;
  }

  // --- master lookups: new work against active rows only ---------------------

  Future<MasterItem> requireItem(String itemId) async {
    final item = await _master.itemById(itemId);
    if (item == null) {
      throw EntityNotFoundFailure(
        'Barang tidak ditemukan.',
        entity: 'items',
        id: itemId,
      );
    }
    return item;
  }

  /// Only active items may be **added** to a draft, or proposed by the
  /// suggestion (G-A4). Items already requested by an existing document stay
  /// readable through the historical lookups below.
  Future<MasterItem> requireActiveItem(String itemId) async {
    final item = await requireItem(itemId);
    if (!item.isActive) {
      throw InactiveEntityFailure(
        'Barang ${item.name} sudah dinonaktifkan dan tidak dapat diminta.',
        entity: 'items',
        id: itemId,
      );
    }
    return item;
  }

  // --- historical recovery ---------------------------------------------------
  //
  // Everything below serves documents that are already `submitted`. They take the
  // request id so a broken reference can be reported against the document that is
  // stuck, and they never check `is_active`: a branch, item or count that was
  // deactivated after the request was raised is still exactly what was requested,
  // and the warehouse has to be able to act on it. What they do enforce is that
  // the row is physically *there* — a reference that resolves to nothing cannot be
  // guessed at, substituted or invented.

  /// The item a submitted line names. Deactivated items pass; missing ones do
  /// not.
  Future<MasterItem> requireHistoricalItem({
    required String prId,
    required String itemId,
  }) async {
    final item = await _master.itemById(itemId);
    if (item == null) {
      throw HistoricalPurchaseRequestReferenceMissingFailure(
        'Purchase Request tidak dapat diproses karena barang historis tidak '
        'ditemukan. Hubungi administrator.',
        entity: 'items',
        id: itemId,
        prId: prId,
      );
    }
    return item;
  }

  /// Refuses a document whose stored lines and loaded lines disagree.
  ///
  /// [PurchaseRequestDetail] is built from a query that inner-joins `items`, so a
  /// line whose item row is physically gone is absent from it rather than
  /// reported. Submitting or processing on that basis would treat the request as
  /// complete while one requested position was never seen — no justification
  /// demanded of it at submit, and a warehouse shipping against an order that is
  /// quietly short a line.
  ///
  /// [storedItemIds] comes from a plain select that no join can filter. The
  /// comparison is a set difference in memory, so the healthy case — every line
  /// loaded — costs no query at all; only a genuine gap is worth a lookup, and
  /// then only to name the row an administrator has to repair.
  Future<void> requireEveryLineLoaded({
    required String prId,
    required List<String> storedItemIds,
    required Iterable<String> loadedItemIds,
  }) async {
    final missing = storedItemIds.toSet().difference(loadedItemIds.toSet());
    if (missing.isEmpty) return;

    // The overwhelmingly likely cause, and the one worth a precise message.
    for (final itemId in missing) {
      await requireHistoricalItem(prId: prId, itemId: itemId);
    }

    // Every id still resolves, so the join dropped the line for a reason this
    // code cannot name. Refusing is still right: a document that does not agree
    // with itself must not be acted on from the half we can see.
    throw HistoricalPurchaseRequestReferenceMissingFailure(
      'Purchase Request tidak dapat diproses karena sebagian baris historis '
      'tidak dapat dimuat. Hubungi administrator.',
      entity: 'purchase_request_lines',
      id: missing.first,
      prId: prId,
    );
  }

  /// The same set-integrity check for the citation half of the document.
  ///
  /// A citation whose `stock_opnames` row is gone would silently reduce the
  /// evidence G-P1 is checked against — and on a document with exactly one
  /// citation it would turn "cites a valid count" into "cites nothing" without
  /// anybody being told.
  void requireEveryOpnameLoaded({
    required String prId,
    required List<String> storedOpnameIds,
    required Iterable<String> loadedOpnameIds,
  }) {
    final missing = storedOpnameIds.toSet().difference(loadedOpnameIds.toSet());
    if (missing.isEmpty) return;

    throw HistoricalPurchaseRequestReferenceMissingFailure(
      'Purchase Request tidak dapat diproses karena stok opname acuan tidak '
      'ditemukan. Hubungi administrator.',
      entity: 'stock_opnames',
      id: missing.first,
      prId: prId,
    );
  }
}
