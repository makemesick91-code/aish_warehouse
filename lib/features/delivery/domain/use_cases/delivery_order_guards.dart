import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../../../purchase_request/domain/models/purchase_request_models.dart';
import '../../../purchase_request/domain/services/purchase_request_state_policy.dart';
import '../models/delivery_models.dart';
import '../repositories/delivery_order_repository.dart';
import '../services/delivery_expiry_policy.dart';
import '../services/delivery_fefo_policy.dart';
import '../services/delivery_order_state_policy.dart';
import '../services/delivery_quantity_policy.dart';

/// The RBAC, state, reference and expiry checks every Delivery Order use case
/// shares (G-D1 … G-D5, G-E3, G-E4).
///
/// They live in one place because a rule that is re-implemented per use case is a
/// rule that eventually differs per use case. Each guard reads the actor from the
/// database rather than trusting whatever id the caller passed, so a development
/// session (or, later, a token) can never grant a permission the stored user does
/// not have (O-8).
class DeliveryOrderGuards {
  const DeliveryOrderGuards(this._master);

  final MasterDataRepository _master;

  // --- actor ----------------------------------------------------------------

  /// Loads the actor and refuses inactive accounts.
  ///
  /// Applies to the warehouse too, and that asymmetry is deliberate: unlike the
  /// branch or item data a historic document points at, the person shipping goods
  /// *right now* has to be a currently valid account (§7.2).
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

  /// The only actor a Delivery Order has.
  ///
  /// Deliberately does **not** require a branch: the central warehouse serves
  /// every branch and `users.branch_id` is NULL for it by design (spec §2.1).
  Future<MasterUser> requireWarehouseActor(String userId) async {
    final user = await requireActiveUser(userId);
    if (user.role != UserRole.warehouse) {
      throw InvalidReviewerFailure(
        'Hanya Petugas Warehouse yang dapat menyiapkan atau mengirim Surat '
        'Jalan. ${user.fullName} berperan sebagai ${user.role.label}.',
        actorUserId: userId,
        requiredRole: UserRole.warehouse,
      );
    }
    return user;
  }

  // --- warehouse location (G-D3) --------------------------------------------

  /// The single central-warehouse location a shipment leaves from.
  ///
  /// Both failure modes are explicit rather than resolved:
  ///
  /// * **none** — there is nothing to ship out of, and inventing a location would
  ///   post the ledger against a row that does not exist.
  /// * **more than one** — which warehouse the goods left is a business fact.
  ///   Picking the first would silently attribute the movement to a location
  ///   nobody chose, and the balance it decremented would be the wrong one.
  ///
  /// No seed id is hard-coded anywhere on this path: the location is looked up by
  /// type every time.
  Future<MasterLocation> requireWarehouseLocation() async {
    final locations = await _master.activeWarehouseLocations();
    if (locations.isEmpty) {
      throw const WarehouseLocationNotFoundFailure(
        'Lokasi Warehouse Pusat belum tersedia, sehingga pengiriman tidak '
        'dapat diposting. Hubungi administrator.',
      );
    }
    if (locations.length > 1) {
      throw AmbiguousWarehouseLocationFailure(
        'Terdapat lebih dari satu lokasi Warehouse Pusat, sehingga sistem '
        'tidak dapat menentukan asal pengiriman. Hubungi administrator.',
        locationIds: locations
            .map((location) => location.id)
            .toList(growable: false),
      );
    }
    return locations.single;
  }

  // --- documents -------------------------------------------------------------

  /// G-D1 — the request must be one a shipment may be raised against.
  void requirePurchaseRequestEligible(PurchaseRequest request) {
    if (DeliveryOrderStatePolicy.canCreateFrom(request.status)) return;
    throw InvalidPurchaseRequestForDeliveryFailure(
      _requestMessage(request),
      prId: request.id,
      currentStatus: request.status,
    );
  }

  /// The narrower check the ship path applies: by the time anything is posted the
  /// request must already be `processing`.
  ///
  /// Reached when a request was cancelled, rejected or completed after a
  /// `preparing` document was prepared against it. The shipment is refused rather
  /// than posted, because stock must not leave the warehouse for an order that no
  /// longer stands.
  void requirePurchaseRequestShippable(PurchaseRequest request) {
    if (DeliveryOrderStatePolicy.canShipAgainst(request.status)) return;
    throw InvalidPurchaseRequestForDeliveryFailure(
      _requestMessage(request),
      prId: request.id,
      currentStatus: request.status,
    );
  }

  String _requestMessage(PurchaseRequest request) {
    final number = request.docNumber;
    return switch (request.status) {
      PurchaseRequestStatus.draft =>
        'Purchase Request $number masih draft dan belum dikirim ke Warehouse, '
            'sehingga belum dapat dibuatkan Surat Jalan.',
      PurchaseRequestStatus.submitted =>
        'Purchase Request $number belum diproses Warehouse.',
      PurchaseRequestStatus.processing =>
        'Purchase Request $number sedang diproses Warehouse.',
      PurchaseRequestStatus.shipped =>
        'Purchase Request $number sudah terkirim penuh, sehingga tidak ada '
            'lagi barang yang perlu dikirim.',
      PurchaseRequestStatus.closed =>
        'Purchase Request $number sudah selesai dan bersifat final.',
      PurchaseRequestStatus.rejected =>
        'Purchase Request $number sudah ditolak Warehouse.',
      PurchaseRequestStatus.cancelled =>
        'Purchase Request $number sudah dibatalkan cabang.',
    };
  }

  /// G-S1/G-S2 — the document must currently be in [expected].
  void requireStatus({
    required DeliveryOrder order,
    required DeliveryOrderStatus expected,
    DeliveryOrderStatus? attempted,
  }) {
    if (order.status == expected) return;
    if (order.status.isShipped && expected.isPreparing) {
      throw DeliveryOrderAlreadyShippedFailure(
        'Surat Jalan ${order.docNumber} sudah dikirim, sehingga tidak dapat '
        'diubah lagi.',
        doId: order.id,
        shippedAt: order.shippedAt,
      );
    }
    throw InvalidDeliveryOrderStateFailure(
      _stateMessage(order, attempted),
      doId: order.id,
      currentStatus: order.status,
      attemptedStatus: attempted,
    );
  }

  /// G-S1 — the transition must exist in the state machine and belong to this
  /// role.
  ///
  /// Asked in addition to [requireStatus] rather than instead of it: the status
  /// check produces the message a user needs ("already shipped"), while this one is
  /// the structural check that no code path invents a transition the policy does
  /// not list — including `shipped → received`, which no use case in this milestone
  /// may perform for any role.
  void requireTransition({
    required MasterUser actor,
    required DeliveryOrder order,
    required DeliveryOrderStatus to,
  }) {
    if (DeliveryOrderStatePolicy.isAllowedFor(
      role: actor.role,
      from: order.status,
      to: to,
    )) {
      return;
    }
    throw InvalidDeliveryOrderStateFailure(
      _stateMessage(order, to),
      doId: order.id,
      currentStatus: order.status,
      attemptedStatus: to,
    );
  }

  String _stateMessage(DeliveryOrder order, DeliveryOrderStatus? attempted) {
    final number = order.docNumber;
    return switch (order.status) {
      DeliveryOrderStatus.preparing
          when attempted == DeliveryOrderStatus.received =>
        'Surat Jalan $number belum dikirim, sehingga belum dapat diterima '
            'cabang.',
      DeliveryOrderStatus.preparing =>
        'Surat Jalan $number masih dalam penyiapan.',
      DeliveryOrderStatus.shipped =>
        'Surat Jalan $number sudah dikirim dan menunggu pemeriksaan Good '
            'Receipt cabang.',
      DeliveryOrderStatus.received =>
        'Surat Jalan $number sudah diterima cabang dan bersifat final.',
    };
  }

  /// Turns "the guarded write matched no rows" into the right failure. Reached
  /// when another device changed the document between the read and the write.
  Never concurrentUpdate(DeliveryOrder order) {
    throw ConcurrentDeliveryOrderUpdateFailure(
      'Surat Jalan ${order.docNumber} baru saja diubah dari perangkat lain. '
      'Muat ulang halaman lalu coba lagi.',
      doId: order.id,
    );
  }

  /// A document with nothing allocated has nothing to post.
  void requireNotEmpty({
    required String doId,
    required String docNumber,
    required List<DeliveryLineReference> lines,
  }) {
    if (lines.isNotEmpty) return;
    throw DeliveryOrderLineRequiredFailure(
      'Surat Jalan $docNumber belum memiliki barang untuk dikirim.',
      doId: doId,
    );
  }

  // --- allocation integrity (G-D4) -------------------------------------------

  /// G-D4 — every allocation must descend from a requested position of **this**
  /// document's request, and must name the item that position asks for.
  ///
  /// [positionsByPrLineId] is built from the request's own lines, read without a
  /// join. An allocation pointing at another request's line, or at the right line
  /// with the wrong item, is refused rather than corrected: quietly repointing it
  /// would ship something nobody ordered.
  void requireAllocationsBelongToRequest({
    required String doId,
    required Map<String, ShipmentProgressInput> positionsByPrLineId,
    required List<DeliveryLineReference> lines,
  }) {
    for (final line in lines) {
      final position = positionsByPrLineId[line.prLineId];
      if (position == null) {
        throw DeliveryPrLineMismatchFailure(
          'Surat Jalan memuat baris yang bukan milik Purchase Request ini. '
          'Hubungi administrator.',
          doId: doId,
          prLineId: line.prLineId,
          itemId: line.itemId,
        );
      }
      if (position.itemId != line.itemId) {
        throw DeliveryItemNotInPurchaseRequestFailure(
          'Barang pada baris Surat Jalan tidak sama dengan barang yang diminta '
          'cabang. Warehouse tidak dapat mengganti barang.',
          doId: doId,
          itemId: line.itemId,
        );
      }
    }
  }

  /// No `(PR line, batch)` position may appear twice on one document.
  ///
  /// The two partial unique indexes enforce the same thing, and this exists so the
  /// failure names the offending position instead of surfacing a driver error — and
  /// so a set of allocations can be checked *before* anything is inserted.
  void requireNoDuplicateAllocations({
    required String doId,
    required List<DeliveryLineReference> lines,
  }) {
    final seen = <String>{};
    for (final line in lines) {
      if (seen.add(line.allocationKey)) continue;
      throw DuplicateDeliveryAllocationFailure(
        'Batch yang sama dialokasikan dua kali untuk barang yang sama pada '
        'Surat Jalan ini.',
        doId: doId,
        prLineId: line.prLineId,
        batchId: line.batchId,
      );
    }
  }

  /// Every allocation must carry a strictly positive quantity.
  void requirePositiveQuantities(List<DeliveryLineReference> lines) {
    for (final line in lines) {
      if (DeliveryQuantityPolicy.isValidAllocation(line.shippedQty)) continue;
      throw ValidationFailure(
        'Jumlah kirim harus lebih dari 0 '
        '(diterima ${line.shippedQty.format()}).',
      );
    }
  }

  // --- cumulative quantity (G-D2) --------------------------------------------

  /// G-D2 — no requested position may end up shipped beyond what was asked for.
  ///
  /// [progress] must be built from quantities read **inside the posting
  /// transaction**. A form's idea of the remaining quantity is a snapshot and is
  /// explicitly not the authority here: two officers can each allocate the last
  /// `2` of a `3` request against balances that both looked sufficient, and this
  /// check — re-run under the transaction — is what lets exactly one of them
  /// commit.
  void requireWithinRequested(List<ShipmentProgress> progress) {
    final offending =
        PurchaseRequestShipmentProgressCalculator.firstOverShipment(progress);
    if (offending == null) return;

    throw DeliveryQuantityExceedsRequestedFailure(
      'Jumlah kirim ${offending.itemName} melebihi permintaan cabang. '
      'Diminta ${offending.requestedQty.formatWithUnit(offending.unit)}, '
      'sudah dikirim '
      '${offending.previouslyShippedQty.formatWithUnit(offending.unit)}, '
      'sisa ${offending.remainingBeforeCurrentDo.formatWithUnit(offending.unit)}.',
      prLineId: offending.prLineId,
      requested: offending.requestedQty,
      alreadyShipped: offending.previouslyShippedQty,
      attempted: offending.currentDoQty,
    );
  }

  // --- expiry and FEFO (G-E3/G-E4) -------------------------------------------

  /// G-E1/G-E2 — an expiry-tracked item always ships per batch, an item without
  /// expiry never carries one.
  ///
  /// Also checks that the batch actually belongs to the item, and that the row is
  /// physically there. A missing batch is a *historical* failure rather than a
  /// validation one: the allocation was legitimate when it was made, and what has
  /// gone wrong is the reference, not the officer's choice.
  Future<MasterBatch?> requireBatchConsistency({
    required String doId,
    required MasterItem item,
    required String? batchId,
  }) async {
    if (item.hasExpiry && batchId == null) {
      throw InvalidDeliveryBatchFailure(
        'Barang ${item.sku} memiliki tanggal kedaluwarsa, sehingga batch wajib '
        'dipilih sebelum dikirim.',
        itemId: item.id,
      );
    }
    if (!item.hasExpiry && batchId != null) {
      throw InvalidDeliveryBatchFailure(
        'Barang ${item.sku} tidak dilacak per batch, sehingga tidak boleh '
        'memiliki batch.',
        itemId: item.id,
        batchId: batchId,
      );
    }
    if (batchId == null) return null;

    final batch = await _master.batchById(batchId);
    if (batch == null) {
      throw HistoricalDeliveryReferenceMissingFailure(
        'Surat Jalan tidak dapat dikirim karena batch historis tidak '
        'ditemukan. Hubungi administrator.',
        entity: 'item_batches',
        id: batchId,
        doId: doId,
      );
    }
    if (batch.itemId != item.id) {
      throw InvalidDeliveryBatchFailure(
        'Batch ${batch.batchNo} bukan milik barang ${item.sku}.',
        itemId: item.id,
        batchId: batchId,
      );
    }
    return batch;
  }

  /// G-E4 — expired batches are blocked outright; near-expiry ones need an
  /// explicit confirmation.
  ///
  /// The order matters: expiry is checked *first* and refuses whatever the line
  /// says, so a stored `near_expiry_confirmed = true` can never carry an expired
  /// batch through. That is the difference between "the officer accepted a short
  /// shelf life" and "the officer accepted goods that may not be sold".
  void requireExpiryAcceptable({
    required MasterItem item,
    required MasterBatch batch,
    required bool nearExpiryConfirmed,
    required DateTime nowUtc,
  }) {
    if (DeliveryExpiryPolicy.isExpired(
      expiryDate: batch.expiryDate,
      nowUtc: nowUtc,
    )) {
      throw ExpiredBatchForDeliveryFailure(
        'Batch ${batch.batchNo} sudah kedaluwarsa dan tidak dapat dikirim.',
        batchId: batch.id,
        batchNo: batch.batchNo,
        expiryDate: batch.expiryDate,
      );
    }

    if (!DeliveryExpiryPolicy.requiresNearExpiryConfirmation(
      expiryDate: batch.expiryDate,
      expiryAlertDays: item.expiryAlertDays,
      nowUtc: nowUtc,
    )) {
      return;
    }
    if (nearExpiryConfirmed) return;

    final remaining = DeliveryExpiryPolicy.remainingDays(
      expiryDate: batch.expiryDate,
      nowUtc: nowUtc,
    );
    throw NearExpiryConfirmationRequiredFailure(
      'Batch ${batch.batchNo} tersisa $remaining hari '
      '(ambang ${item.expiryAlertDays} hari) dan memerlukan konfirmasi '
      'eksplisit sebelum dikirim.',
      batchId: batch.id,
      batchNo: batch.batchNo,
      remainingDays: remaining,
      expiryAlertDays: item.expiryAlertDays,
    );
  }

  /// G-E3 — a batch younger than the FEFO suggestion needs a written reason.
  ///
  /// [candidates] must be the batches and balances as they are **now**. The same
  /// selection can be compliant when the form opens and a violation when it is
  /// posted, because an older batch that was empty may have been restocked in
  /// between — which is why the ship path calls this again instead of trusting the
  /// reason (or the absence of one) the line already stores.
  ///
  /// The check is per requested position: FEFO is about how one line's quantity was
  /// sourced, and mixing two positions' choices would compare batches that never
  /// competed for the same demand.
  void requireFefoJustified({
    required List<DeliveryBatchCandidate> candidates,
    required List<DeliveryAllocation> selection,
    required DateTime nowUtc,
  }) {
    final violations = DeliveryFefoPolicy.violations(
      candidates: candidates,
      selection: selection,
      nowUtc: nowUtc,
    );
    if (violations.isEmpty) return;

    for (final violation in violations) {
      final reasons = selection
          .where(
            (allocation) => allocation.batchId == violation.selectedBatchId,
          )
          .map((allocation) => allocation.fefoOverrideReason);
      final justified = reasons.any(DeliveryFefoPolicy.hasValidReason);
      if (justified) continue;

      throw FefoOverrideReasonRequiredFailure(
        'Batch ${violation.selectedBatchNo} dipilih meskipun batch '
        '${violation.skippedBatchNo} lebih dekat kedaluwarsa dan masih '
        'bersaldo ${violation.skippedAvailableQty.format()}. Isi alasan '
        'penggantian batch (FEFO) terlebih dahulu.',
        batchId: violation.selectedBatchId,
        batchNo: violation.selectedBatchNo,
        skippedBatchNo: violation.skippedBatchNo,
      );
    }
  }

  // --- historical recovery ---------------------------------------------------
  //
  // Everything below serves documents that already exist. They take the document
  // id so a broken reference can be reported against the shipment that is stuck,
  // and they never check `is_active`: an item, branch or batch that was
  // deactivated after the allocation was made is still exactly what was
  // allocated, and a shipment must not become unpostable because somebody tidied
  // up master data. What they do enforce is that the row is physically *there* —
  // a reference that resolves to nothing cannot be guessed at, substituted or
  // invented.

  /// The item an existing allocation names. Deactivated items pass; missing ones
  /// do not.
  Future<MasterItem> requireHistoricalItem({
    required String doId,
    required String itemId,
  }) async {
    final item = await _master.itemById(itemId);
    if (item == null) {
      throw HistoricalDeliveryReferenceMissingFailure(
        'Surat Jalan tidak dapat diproses karena barang historis tidak '
        'ditemukan. Hubungi administrator.',
        entity: 'items',
        id: itemId,
        doId: doId,
      );
    }
    return item;
  }

  /// Refuses a document whose stored allocations and loaded allocations disagree.
  ///
  /// The joined read behind [DeliveryOrderDetail] inner-joins `items` and
  /// `purchase_request_lines`, so a line whose item row is physically gone is
  /// absent from it rather than reported. Posting on that basis would ship a
  /// document that is quietly one allocation short — the movements would be
  /// written, the balances decremented and the branch would receive less than the
  /// document says.
  ///
  /// [storedLineIds] comes from a plain select that no join can filter. The
  /// comparison is a set difference in memory, so the healthy case — every line
  /// loaded — costs no query at all; only a genuine gap is worth a lookup, and then
  /// only to name the row an administrator has to repair.
  Future<void> requireEveryLineLoaded({
    required String doId,
    required List<DeliveryLineReference> storedLines,
    required Iterable<String> loadedLineIds,
  }) async {
    final stored = {for (final line in storedLines) line.id: line};
    final missing = stored.keys.toSet().difference(loadedLineIds.toSet());
    if (missing.isEmpty) return;

    // The overwhelmingly likely cause, and the one worth a precise message.
    for (final lineId in missing) {
      final line = stored[lineId]!;
      await requireHistoricalItem(doId: doId, itemId: line.itemId);
    }

    // Every id still resolves, so the join dropped the line for a reason this
    // code cannot name. Refusing is still right: a document that does not agree
    // with itself must not be shipped from the half we can see.
    throw HistoricalDeliveryReferenceMissingFailure(
      'Surat Jalan tidak dapat diproses karena sebagian baris historis tidak '
      'dapat dimuat. Hubungi administrator.',
      entity: 'delivery_order_lines',
      id: missing.first,
      doId: doId,
    );
  }

  /// The same set-integrity check for the requested half of the workflow.
  ///
  /// A Purchase Request line whose row is gone would silently shrink the order the
  /// shipment is measured against — and on a request with one position it would
  /// turn "ships everything" into "ships nothing outstanding" without anybody
  /// being told, which G-D5 would then read as a completed request.
  void requireEveryPositionLoaded({
    required String doId,
    required List<String> storedPrLineIds,
    required Iterable<String> loadedPrLineIds,
  }) {
    final missing = storedPrLineIds.toSet().difference(loadedPrLineIds.toSet());
    if (missing.isEmpty) return;

    throw HistoricalDeliveryReferenceMissingFailure(
      'Surat Jalan tidak dapat diproses karena baris Purchase Request historis '
      'tidak ditemukan. Hubungi administrator.',
      entity: 'purchase_request_lines',
      id: missing.first,
      doId: doId,
    );
  }

  /// The `processing → shipped` transition must be one the Purchase Request state
  /// machine actually lists, and must be a *system* transition rather than
  /// something a role could trigger.
  ///
  /// Asserted rather than assumed, so this milestone cannot grow a second Purchase
  /// Request state machine by accident: if `PurchaseRequestStatePolicy` ever stops
  /// classifying it that way, the shipment fails loudly here instead of writing a
  /// status nothing sanctions.
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

  /// A non-blank reason, or `null` when there was nothing but whitespace.
  static String? normalizeReason(String? reason) {
    final trimmed = (reason ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Turns the balances the warehouse currently holds into FEFO candidates.
  ///
  /// A tiny mapping, but it lives here rather than in each use case because
  /// getting it wrong in one place — forgetting an item's non-batch balance, or
  /// including an expired batch — is a rule that then differs between the form and
  /// the posting.
  static List<DeliveryBatchCandidate> candidatesOf(
    Iterable<
      ({String batchId, String batchNo, DateTime expiryDate, Quantity qty})
    >
    stocks,
  ) => stocks
      .map(
        (stock) => DeliveryBatchCandidate(
          batchId: stock.batchId,
          batchNo: stock.batchNo,
          expiryDate: stock.expiryDate,
          availableQty: stock.qty,
        ),
      )
      .toList(growable: false);
}
