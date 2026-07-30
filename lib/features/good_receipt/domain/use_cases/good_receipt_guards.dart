import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../delivery/domain/models/delivery_models.dart';
import '../../../delivery/domain/repositories/delivery_order_repository.dart';
import '../../../delivery/domain/services/delivery_order_state_policy.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../../../purchase_request/domain/models/purchase_request_models.dart';
import '../../../purchase_request/domain/services/purchase_request_state_policy.dart';
import '../models/good_receipt_models.dart';
import '../repositories/good_receipt_repository.dart';
import '../services/good_receipt_expiry_policy.dart';
import '../services/good_receipt_line_decision_policy.dart';
import '../services/good_receipt_state_policy.dart';

/// The RBAC, state, quantity, reference and expiry checks every Good Receipt use
/// case shares (G-G1 … G-G6, G-E5).
///
/// They live in one place because a rule that is re-implemented per use case is a
/// rule that eventually differs per use case. Each guard reads the actor from the
/// database rather than trusting whatever id the caller passed, so a development
/// session (or, later, a token) can never grant a permission the stored user does
/// not have (O-8).
class GoodReceiptGuards {
  const GoodReceiptGuards(this._master);

  final MasterDataRepository _master;

  // --- actor ----------------------------------------------------------------

  /// Loads the actor and refuses inactive accounts.
  ///
  /// Applies whatever the document's age: unlike the branch or item data a historic
  /// receipt points at, the person accepting goods *right now* has to be a currently
  /// valid account (§7.2).
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

  /// The only actor a Good Receipt has (G-G1, spec §3.1).
  ///
  /// Requires a branch as well as the role, and the two are one check on purpose:
  /// *"Kepala Cabang dari cabang tujuan"* is meaningless without a branch to compare,
  /// and a branch-scoped account without one is a data fault rather than a
  /// permission that happens to be wide.
  ///
  /// Warehouse and Super Admin are refused here, not merely unrouted. That is G-R4:
  /// the officer who prepared and shipped the goods must not also be the one who
  /// declares them received, and an account being powerful is not a reason to hand it
  /// the other side of a segregated duty.
  Future<MasterUser> requireBranchHeadActor(String userId) async {
    final user = await requireActiveUser(userId);
    if (user.role != UserRole.kepalaCabang) {
      throw InvalidReviewerFailure(
        'Hanya Kepala Cabang yang dapat memeriksa dan memposting Good Receipt. '
        '${user.fullName} berperan sebagai ${user.role.label}.',
        actorUserId: userId,
        requiredRole: UserRole.kepalaCabang,
      );
    }
    if (user.branchId == null) {
      throw UnauthorizedBranchFailure(
        'Akun ${user.fullName} belum terhubung ke cabang mana pun, sehingga '
        'tidak dapat menerima barang.',
        actorUserId: userId,
        branchId: '',
      );
    }
    return user;
  }

  /// G-G1 — the actor's branch must be the shipment's destination.
  ///
  /// Asked in addition to the scoped queries rather than instead of them: a scoped
  /// read is what stops a foreign document being *fetched*, and this is what stops
  /// one being *written* if a caller ever passes an unscoped read by mistake.
  void requireBranchMatches({
    required MasterUser actor,
    required String documentBranchId,
  }) {
    if (actor.branchId == documentBranchId) return;
    throw GoodReceiptBranchMismatchFailure(
      'Pengiriman ini ditujukan ke cabang lain, sehingga tidak dapat diterima '
      'dari akun ini.',
      actorUserId: actor.id,
      actorBranchId: actor.branchId,
      documentBranchId: documentBranchId,
    );
  }

  // --- branch store (G-G5) ---------------------------------------------------

  /// The single *Gudang Cabang* location a receipt credits.
  ///
  /// Both failure modes are explicit rather than resolved:
  ///
  /// * **none** — there is nothing to receive into, and inventing a location would
  ///   post the ledger against a row that does not exist.
  /// * **more than one** — which store the goods entered is a business fact. Picking
  ///   the first would silently attribute the movement to a location nobody chose,
  ///   and the balance it credited would be the wrong one.
  ///
  /// No seed id is hard-coded anywhere on this path: the location is looked up by
  /// type and branch every time.
  ///
  /// ### Historical recovery
  ///
  /// A Good Receipt completes work that already exists — the goods have shipped and
  /// are physically at the branch — so it must not become unpostable because an
  /// administrator archived the store row in the meantime. When no live location
  /// exists, the **exact** archived row is used, and only when there is exactly one
  /// of them. Nothing is substituted, and no other branch's store is ever
  /// considered: the fallback widens the query by `deleted_at`, never by `branch_id`.
  /// If the row is physically gone, the posting fails rather than guessing (§34).
  Future<MasterLocation> requireBranchStore(String branchId) async {
    final live = await _master.activeBranchStoreLocations(branchId);
    if (live.length == 1) return live.single;
    if (live.length > 1) {
      throw GoodReceiptBranchStoreAmbiguousFailure(
        'Terdapat lebih dari satu lokasi Gudang Cabang untuk cabang ini, '
        'sehingga sistem tidak dapat menentukan tujuan penerimaan. Hubungi '
        'administrator.',
        branchId: branchId,
        locationIds: live
            .map((location) => location.id)
            .toList(growable: false),
      );
    }

    final historical = await _master.historicalBranchStoreLocations(branchId);
    if (historical.isEmpty) {
      throw GoodReceiptBranchStoreNotFoundFailure(
        'Lokasi Gudang Cabang belum tersedia, sehingga penerimaan tidak dapat '
        'diposting. Hubungi administrator.',
        branchId: branchId,
      );
    }
    if (historical.length > 1) {
      throw GoodReceiptBranchStoreAmbiguousFailure(
        'Terdapat lebih dari satu lokasi Gudang Cabang historis untuk cabang '
        'ini, sehingga sistem tidak dapat menentukan tujuan penerimaan. '
        'Hubungi administrator.',
        branchId: branchId,
        locationIds: historical
            .map((location) => location.id)
            .toList(growable: false),
      );
    }
    return historical.single;
  }

  // --- documents -------------------------------------------------------------

  /// G-G1 — the shipment must be one a receipt may be raised against.
  void requireDeliveryOrderEligible(DeliveryOrder order) {
    if (GoodReceiptStatePolicy.canCreateFrom(order.status)) return;
    throw InvalidDeliveryOrderForReceiptFailure(
      _deliveryMessage(order),
      doId: order.id,
      currentStatus: order.status,
    );
  }

  /// The same check the posting applies: by the time stock moves, the shipment must
  /// still be `shipped`.
  ///
  /// Reached when a `checking` receipt sat open while another device posted a receipt
  /// for the same shipment — which the unique index makes impossible — or when the
  /// shipment was altered out from under it. Refused rather than posted, because
  /// crediting a branch for a shipment that is already `received` would double its
  /// stock.
  void requireDeliveryOrderPostable(DeliveryOrder order) {
    if (GoodReceiptStatePolicy.canPostAgainst(order.status)) return;
    throw InvalidDeliveryOrderForReceiptFailure(
      _deliveryMessage(order),
      doId: order.id,
      currentStatus: order.status,
    );
  }

  String _deliveryMessage(DeliveryOrder order) {
    final number = order.docNumber;
    return switch (order.status) {
      DeliveryOrderStatus.preparing =>
        'Surat Jalan $number masih disiapkan Warehouse dan belum dikirim, '
            'sehingga belum ada barang untuk diperiksa.',
      DeliveryOrderStatus.shipped =>
        'Surat Jalan $number sedang dalam pengiriman.',
      DeliveryOrderStatus.received =>
        'Surat Jalan $number sudah diterima dan bersifat final.',
    };
  }

  /// The Purchase Request behind the shipment must still stand (§23).
  ///
  /// Both `processing` and `shipped` are accepted, and the pair is deliberate: a
  /// partial shipment leaves its request `processing` (G-D5 only moves it to
  /// `shipped` once every position is fully sent), so demanding `shipped` here would
  /// make the first partial delivery impossible to receive.
  void requirePurchaseRequestReceivable(PurchaseRequest request) {
    if (GoodReceiptStatePolicy.canReceiveAgainst(request.status)) return;
    throw InvalidPurchaseRequestForDeliveryFailure(
      switch (request.status) {
        PurchaseRequestStatus.draft =>
          'Purchase Request ${request.docNumber} masih draft, sehingga '
              'pengiriman ini tidak dapat diterima.',
        PurchaseRequestStatus.submitted =>
          'Purchase Request ${request.docNumber} belum diproses Warehouse.',
        PurchaseRequestStatus.closed =>
          'Purchase Request ${request.docNumber} sudah selesai dan bersifat '
              'final.',
        PurchaseRequestStatus.rejected =>
          'Purchase Request ${request.docNumber} sudah ditolak Warehouse.',
        PurchaseRequestStatus.cancelled =>
          'Purchase Request ${request.docNumber} sudah dibatalkan cabang.',
        PurchaseRequestStatus.processing || PurchaseRequestStatus.shipped =>
          'Purchase Request tidak dapat diterima.',
      },
      prId: request.id,
      currentStatus: request.status,
    );
  }

  /// G-S1/G-S2 — the receipt must currently be in [expected].
  void requireStatus({
    required GoodReceipt receipt,
    required GoodReceiptStatus expected,
    GoodReceiptStatus? attempted,
  }) {
    if (receipt.status == expected) return;
    if (receipt.isPosted) {
      throw GoodReceiptAlreadyPostedFailure(
        'Good Receipt ${receipt.docNumber} sudah diposting, sehingga tidak '
        'dapat diubah lagi.',
        grId: receipt.id,
        postedAt: receipt.postedAt,
      );
    }
    throw InvalidGoodReceiptStateFailure(
      _stateMessage(receipt, attempted),
      grId: receipt.id,
      currentStatus: receipt.status,
      attemptedStatus: attempted,
    );
  }

  /// G-S1 — the transition must exist in the state machine and belong to this role.
  ///
  /// Asked in addition to [requireStatus] rather than instead of it: the status check
  /// produces the message a user needs ("already posted"), while this one is the
  /// structural check that no code path invents a transition the policy does not
  /// list.
  void requireTransition({
    required MasterUser actor,
    required GoodReceipt receipt,
    required GoodReceiptStatus to,
  }) {
    if (GoodReceiptStatePolicy.isAllowedFor(
      role: actor.role,
      from: receipt.status,
      to: to,
    )) {
      return;
    }
    throw InvalidGoodReceiptStateFailure(
      _stateMessage(receipt, to),
      grId: receipt.id,
      currentStatus: receipt.status,
      attemptedStatus: to,
    );
  }

  String _stateMessage(GoodReceipt receipt, GoodReceiptStatus? attempted) {
    final number = receipt.docNumber;
    return switch (receipt.status) {
      GoodReceiptStatus.checking =>
        'Good Receipt $number masih dalam pemeriksaan.',
      GoodReceiptStatus.posted =>
        'Good Receipt $number sudah diposting dan bersifat final.',
    };
  }

  /// Turns "the guarded write matched no rows" into the right failure. Reached when
  /// another device changed the receipt between the read and the write.
  Never concurrentUpdate(GoodReceipt receipt) {
    throw ConcurrentGoodReceiptUpdateFailure(
      'Good Receipt ${receipt.docNumber} baru saja diubah dari perangkat lain. '
      'Muat ulang halaman lalu coba lagi.',
      grId: receipt.id,
    );
  }

  /// A shipment with nothing allocated has nothing to check in.
  void requireShipmentNotEmpty({
    required String doId,
    required String docNumber,
    required List<DeliveryLineReference> lines,
  }) {
    if (lines.isNotEmpty) return;
    throw GoodReceiptLineRequiredFailure(
      'Surat Jalan $docNumber tidak memuat barang, sehingga tidak ada yang '
      'dapat diperiksa.',
      doId: doId,
    );
  }

  // --- line set integrity (§11/§34) ------------------------------------------

  /// Refuses a receipt whose lines and the shipment's allocations disagree.
  ///
  /// Both directions matter, and they fail in opposite ways:
  ///
  /// * a **missing** line means the receipt checks in less than was sent — the
  ///   branch would be credited short and nobody would be told, because every
  ///   per-line check still passes;
  /// * an **extra** line means the receipt claims a position the shipment never
  ///   carried, and posting it would credit stock that never left the warehouse.
  ///
  /// [expectedDoLineIds] comes from a plain select on `delivery_order_lines` that no
  /// join can filter; [loadedDoLineIds] is what the receipt's own lines point at,
  /// read the same way. The comparison is a set difference in memory, so the healthy
  /// case costs no query at all.
  void requireLineSetMatchesShipment({
    required String grId,
    required Iterable<String> expectedDoLineIds,
    required Iterable<String> loadedDoLineIds,
  }) {
    final expected = expectedDoLineIds.toSet();
    final loaded = loadedDoLineIds.toSet();
    final missing = expected.difference(loaded).toList(growable: false);
    final extra = loaded.difference(expected).toList(growable: false);
    if (missing.isEmpty && extra.isEmpty) return;

    throw GoodReceiptLineIntegrityFailure(
      'Daftar barang Good Receipt tidak sama dengan Surat Jalan-nya, sehingga '
      'penerimaan tidak dapat dilanjutkan. Hubungi administrator.',
      grId: grId,
      missingDoLineIds: missing,
      extraDoLineIds: extra,
    );
  }

  /// Refuses a receipt whose stored lines and loaded lines disagree.
  ///
  /// The joined read behind [GoodReceiptDetail] inner-joins `items` and
  /// `delivery_order_lines`, so a line whose item row is physically gone is absent
  /// from it rather than reported. Posting on that basis would credit a branch one
  /// position short while the receipt says otherwise.
  ///
  /// [storedLines] comes from a plain select that no join can filter. Only a genuine
  /// gap is worth a lookup, and then only to name the row an administrator has to
  /// repair.
  Future<void> requireEveryLineLoaded({
    required String grId,
    required List<GoodReceiptLineReference> storedLines,
    required Iterable<String> loadedLineIds,
  }) async {
    final stored = {for (final line in storedLines) line.id: line};
    final missing = stored.keys.toSet().difference(loadedLineIds.toSet());
    if (missing.isEmpty) return;

    // The overwhelmingly likely cause, and the one worth a precise message.
    for (final lineId in missing) {
      final line = stored[lineId]!;
      await requireHistoricalItem(grId: grId, itemId: line.itemId);
    }

    // Every id still resolves, so the join dropped the line for a reason this code
    // cannot name. Refusing is still right: a receipt that does not agree with
    // itself must not be posted from the half we can see.
    throw GoodReceiptHistoricalReferenceMissingFailure(
      'Good Receipt tidak dapat diproses karena sebagian baris historis tidak '
      'dapat dimuat. Hubungi administrator.',
      entity: 'good_receipt_lines',
      id: missing.first,
      grId: grId,
    );
  }

  // --- decisions (G-G2/G-G3/G-G4) --------------------------------------------

  /// The line, checked to belong to [grId].
  ///
  /// Both failures answer the same way — the line is not on this receipt — because
  /// telling "no such line" from "somebody else's line" apart would let the id be
  /// probed.
  GoodReceiptLineReference requireLineOf({
    required String grId,
    required String lineId,
    required GoodReceiptLineReference? line,
  }) {
    if (line != null && line.grId == grId) return line;
    throw GoodReceiptLineNotFoundFailure(
      'Baris pemeriksaan tidak ditemukan pada Good Receipt ini.',
      lineId: lineId,
    );
  }

  /// G-G3 — `0 ≤ received_qty ≤ shipped_qty`, with the two failures kept apart so
  /// the message can say *how much* was sent.
  void requireValidReceivedQty({
    required String lineId,
    required Quantity shippedQty,
    required Quantity receivedQty,
    required String unit,
  }) {
    if (GoodReceiptLineDecisionPolicy.isNegative(receivedQty)) {
      throw InvalidReceivedQuantityFailure(
        'Jumlah diterima tidak boleh negatif '
        '(diterima ${receivedQty.format()}).',
        lineId: lineId,
        received: receivedQty,
      );
    }
    if (GoodReceiptLineDecisionPolicy.exceedsShipped(
      shippedQty: shippedQty,
      receivedQty: receivedQty,
    )) {
      throw ReceivedQuantityExceedsShippedFailure(
        'Jumlah diterima ${receivedQty.formatWithUnit(unit)} melebihi jumlah '
        'yang dikirim ${shippedQty.formatWithUnit(unit)}.',
        lineId: lineId,
        shipped: shippedQty,
        received: receivedQty,
      );
    }
  }

  /// G-G4 — a refusal needs a reason that is not whitespace.
  String requireRejectReason({
    required String lineId,
    required String? reason,
  }) {
    final normalized = GoodReceiptLineDecisionPolicy.normalizeReason(reason);
    if (normalized != null) return normalized;
    throw GoodReceiptRejectReasonRequiredFailure(
      'Barang yang ditolak wajib disertai alasan penolakan.',
      lineId: lineId,
    );
  }

  /// G-G2 — no position may still be `pending` when the receipt is posted.
  void requireAllDecided({
    required String grId,
    required List<GoodReceiptLineReference> lines,
  }) {
    final pending = lines
        .where((line) => line.isPending)
        .map((line) => line.id)
        .toList(growable: false);
    if (pending.isEmpty && lines.isNotEmpty) return;
    if (lines.isEmpty) {
      throw GoodReceiptLinesPendingFailure(
        'Good Receipt tidak memuat barang, sehingga tidak dapat diposting.',
        grId: grId,
        pendingLineIds: const <String>[],
      );
    }
    throw GoodReceiptLinesPendingFailure(
      'Semua barang harus diperiksa sebelum Good Receipt diposting. '
      '${pending.length} barang belum diputuskan.',
      grId: grId,
      pendingLineIds: pending,
    );
  }

  /// The stored decisions must each be internally consistent — the same three shapes
  /// the table's CHECK states, re-asserted in the domain so a receipt written by an
  /// older client or a future sync payload cannot post an impossible line.
  void requireConsistentDecisions({
    required List<GoodReceiptLineReference> lines,
    required Map<String, MasterItem> itemsById,
  }) {
    for (final line in lines) {
      final unit = itemsById[line.itemId]?.unit ?? '';
      requireValidReceivedQty(
        lineId: line.id,
        shippedQty: line.shippedQty,
        receivedQty: line.receivedQty,
        unit: unit,
      );
      if (line.isRejected) {
        requireRejectReason(lineId: line.id, reason: line.rejectReason);
        if (!line.receivedQty.isZero) {
          throw InvalidReceivedQuantityFailure(
            'Barang yang ditolak tidak boleh memiliki jumlah diterima.',
            lineId: line.id,
            received: line.receivedQty,
          );
        }
      } else if (GoodReceiptLineDecisionPolicy.normalizeReason(
            line.rejectReason,
          ) !=
          null) {
        // A reason on an accepted line would be an audit trail for a decision that
        // was reversed.
        throw GoodReceiptRejectReasonRequiredFailure(
          'Barang yang diterima tidak boleh menyimpan alasan penolakan.',
          lineId: line.id,
        );
      }
    }
  }

  // --- expiry (G-E5) ---------------------------------------------------------

  /// G-E1/G-E2 — an expiry-tracked item always carries a batch, an item without
  /// expiry never does.
  ///
  /// Also checks that the batch belongs to the item, and that the row is physically
  /// there. A missing batch is a *historical* failure rather than a validation one:
  /// the shipment was legitimate when it was sent, and what has gone wrong is the
  /// reference, not the branch head's decision.
  Future<MasterBatch?> requireBatchConsistency({
    required String grId,
    required MasterItem item,
    required String? batchId,
  }) async {
    if (item.hasExpiry && batchId == null) {
      throw InvalidGoodReceiptBatchFailure(
        'Barang ${item.sku} memiliki tanggal kedaluwarsa, sehingga batch wajib '
        'tercatat pada penerimaan.',
        itemId: item.id,
      );
    }
    if (!item.hasExpiry && batchId != null) {
      throw InvalidGoodReceiptBatchFailure(
        'Barang ${item.sku} tidak dilacak per batch, sehingga tidak boleh '
        'memiliki batch.',
        itemId: item.id,
        batchId: batchId,
      );
    }
    if (batchId == null) return null;

    final batch = await _master.batchById(batchId);
    if (batch == null) {
      throw GoodReceiptHistoricalReferenceMissingFailure(
        'Good Receipt tidak dapat diproses karena batch historis tidak '
        'ditemukan. Hubungi administrator.',
        entity: 'item_batches',
        id: batchId,
        grId: grId,
      );
    }
    if (batch.itemId != item.id) {
      throw InvalidGoodReceiptBatchFailure(
        'Batch ${batch.batchNo} bukan milik barang ${item.sku}.',
        itemId: item.id,
        batchId: batchId,
      );
    }
    return batch;
  }

  /// G-E5 — an expired or nearly expired batch may not be **accepted**.
  ///
  /// Applied when a line is checked *and* again when the receipt is posted, and the
  /// second time is the one that matters: a batch with two days of shelf life left
  /// when the checklist opened may be inside its alert window — or past its date
  /// entirely — by the time the branch head presses *Posting*. Validating only at
  /// entry would let that receipt through, and the goods would be on the shelf with
  /// nothing to say they should not be.
  ///
  /// Unlike the shipment's near-expiry rule (G-E4) there is no confirmation that
  /// accepts either verdict: spec §3.11 says both are refused with `kedaluwarsa` and
  /// go on the return list.
  void requireAcceptableExpiry({
    required String lineId,
    required MasterItem item,
    required MasterBatch? batch,
    required DateTime nowUtc,
  }) {
    if (batch == null) return;

    final verdict = GoodReceiptExpiryPolicy.verdictFor(
      expiryDate: batch.expiryDate,
      expiryAlertDays: item.expiryAlertDays,
      nowUtc: nowUtc,
    );
    switch (verdict) {
      case GoodReceiptExpiryVerdict.valid:
        return;
      case GoodReceiptExpiryVerdict.expired:
        throw GoodReceiptExpiredBatchMustBeRejectedFailure(
          'Batch ${batch.batchNo} sudah kedaluwarsa, sehingga barang ini harus '
          'ditolak dengan alasan kedaluwarsa dan tidak boleh masuk stok '
          'cabang.',
          lineId: lineId,
          batchId: batch.id,
          batchNo: batch.batchNo,
          expiryDate: batch.expiryDate,
        );
      case GoodReceiptExpiryVerdict.nearExpiry:
        final remaining = GoodReceiptExpiryPolicy.remainingDays(
          expiryDate: batch.expiryDate,
          nowUtc: nowUtc,
        );
        throw GoodReceiptNearExpiryBatchMustBeRejectedFailure(
          'Batch ${batch.batchNo} tersisa $remaining hari '
          '(ambang ${item.expiryAlertDays} hari), sehingga barang ini harus '
          'ditolak dengan alasan terlalu dekat kedaluwarsa.',
          lineId: lineId,
          batchId: batch.id,
          batchNo: batch.batchNo,
          remainingDays: remaining,
          expiryAlertDays: item.expiryAlertDays,
        );
    }
  }

  // --- historical recovery (§34) ---------------------------------------------
  //
  // Everything below serves documents that already exist. They take the receipt id
  // so a broken reference can be reported against the document that is stuck, and
  // they never check `is_active`: an item, branch or batch that was deactivated after
  // the goods shipped is still exactly what shipped, and a receipt must not become
  // unpostable because somebody tidied up master data. What they do enforce is that
  // the row is physically *there* — a reference that resolves to nothing cannot be
  // guessed at, substituted or invented.

  /// The item a receipt line names. Deactivated items pass; missing ones do not.
  Future<MasterItem> requireHistoricalItem({
    required String grId,
    required String itemId,
  }) async {
    final item = await _master.itemById(itemId);
    if (item == null) {
      throw GoodReceiptHistoricalReferenceMissingFailure(
        'Good Receipt tidak dapat diproses karena barang historis tidak '
        'ditemukan. Hubungi administrator.',
        entity: 'items',
        id: itemId,
        grId: grId,
      );
    }
    return item;
  }

  /// The referenced row a receipt depends on is gone entirely.
  Never historicalReferenceMissing({
    required String grId,
    required String entity,
    required String id,
  }) {
    throw GoodReceiptHistoricalReferenceMissingFailure(
      'Good Receipt tidak dapat diproses karena referensi historis '
      'tidak ditemukan. Hubungi administrator.',
      entity: entity,
      id: id,
      grId: grId,
    );
  }

  // --- foreign transitions ---------------------------------------------------

  /// `shipped → received` must be a transition the **Delivery Order's own** state
  /// machine lists, and must be the one only a Good Receipt performs.
  ///
  /// Asserted rather than assumed, so this milestone cannot grow a second Delivery
  /// Order state machine by accident: if `DeliveryOrderStatePolicy` ever stops
  /// classifying it that way, the posting fails loudly here instead of writing a
  /// status nothing sanctions.
  void requireDeliveryOrderGoodReceiptTransition({
    required String doId,
    required DeliveryOrderStatus from,
    required DeliveryOrderStatus to,
  }) {
    if (DeliveryOrderStatePolicy.isGoodReceiptTransition(from, to)) return;
    throw InvalidDeliveryOrderStateFailure(
      'Transisi Surat Jalan dari ${from.label} ke ${to.label} bukan transisi '
      'Good Receipt yang diizinkan.',
      doId: doId,
      currentStatus: from,
      attemptedStatus: to,
    );
  }

  /// `shipped → closed` must be a transition the **Purchase Request's own** state
  /// machine lists, and must be a `system` one rather than something a role could
  /// trigger.
  void requirePurchaseRequestSystemTransition({
    required String prId,
    required PurchaseRequestStatus from,
    required PurchaseRequestStatus to,
  }) {
    if (PurchaseRequestStatePolicy.isSystemTransition(from, to)) return;
    throw InvalidPurchaseRequestStateFailure(
      'Transisi Purchase Request dari ${from.label} ke ${to.label} bukan '
      'transisi sistem yang diizinkan.',
      prId: prId,
      currentStatus: from,
      attemptedStatus: to,
    );
  }
}
