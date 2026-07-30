import 'package:uuid/uuid.dart';

import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../../core/time/date_only.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/inventory_models.dart';
import '../repositories/inventory_repository.dart';

/// The single gate through which stock may change.
///
/// Every operation runs inside one database transaction and follows the same
/// order: validate input → load item → validate batch → read current balance →
/// check sufficiency → append ledger row → decrease source → increase target.
/// If any step throws, the transaction is rolled back and nothing is written —
/// partial postings are impossible.
///
/// Every quantity is a [Quantity], so all arithmetic here is exact integer
/// arithmetic on milli-units (Q-2): `0.1 + 0.2` is `0.3`, and splitting `1.5`
/// across several batches always adds back up to `1.5` with no residue.
///
/// The clock is injected and always UTC; dates are compared in operational time
/// through [AppTimeZone] so expiry never depends on the device timezone (T-7).
class StockPostingService {
  StockPostingService({
    required this._inventory,
    required this._master,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _clock = clock ?? _defaultClock,
       _newId = idGenerator ?? _defaultIdGenerator;

  final InventoryRepository _inventory;
  final MasterDataRepository _master;
  final DateTime Function() _clock;
  final String Function() _newId;

  static final _uuid = Uuid();

  static DateTime _defaultClock() => DateTime.now().toUtc();

  static String _defaultIdGenerator() => _uuid.v4();

  /// Goods arriving from a supplier into the central warehouse (G-E1).
  Future<InventoryMovement> postInboundWarehouse({
    required String itemId,
    String? batchId,
    required String toLocationId,
    required Quantity qty,
    required String actorUserId,
    String? refDocType,
    String? refDocId,
    String? note,
  }) {
    return _inventory.runInTransaction(() async {
      _requirePositiveQty(qty);
      final item = await _requireItem(itemId);
      final batch = await _validateBatch(item: item, batchId: batchId);
      final location = await _requireLocation(toLocationId);

      if (location.type != StockLocationType.warehouse) {
        throw InvalidLocationFailure(
          'Barang masuk dari pemasok hanya boleh diterima di warehouse pusat, '
          'bukan di "${location.name}".',
        );
      }
      _rejectExpiredBatch(batch);

      final movement = await _append(
        MovementDraft(
          id: _newId(),
          itemId: itemId,
          batchId: batchId,
          toLocationId: toLocationId,
          qty: qty,
          movementType: StockMovementType.inboundWarehouse,
          actorUserId: actorUserId,
          refDocType: refDocType,
          refDocId: refDocId,
          note: note,
        ),
      );

      await _increase(
        locationId: toLocationId,
        itemId: itemId,
        batchId: batchId,
        qty: qty,
      );
      return movement;
    });
  }

  /// Movement between two known locations: shipment, good receipt,
  /// distribution or return.
  Future<InventoryMovement> postTransfer({
    required String itemId,
    String? batchId,
    required String fromLocationId,
    required String toLocationId,
    required Quantity qty,
    required StockMovementType movementType,
    required String actorUserId,
    String? refDocType,
    String? refDocId,
    String? note,
  }) {
    return _inventory.runInTransaction(() async {
      if (!movementType.isLocationToLocation) {
        throw ValidationFailure(
          'Jenis pergerakan ${movementType.dbValue} bukan perpindahan '
          'antar lokasi.',
        );
      }
      _requirePositiveQty(qty);
      if (fromLocationId == toLocationId) {
        throw const InvalidLocationFailure(
          'Lokasi sumber dan lokasi tujuan tidak boleh sama.',
        );
      }

      final item = await _requireItem(itemId);
      final batch = await _validateBatch(item: item, batchId: batchId);
      await _requireLocation(fromLocationId);
      await _requireLocation(toLocationId);
      // Expired stock is blocked from every normal transfer (G-E4).
      _rejectExpiredBatch(batch);

      await _assertSufficientStock(
        locationId: fromLocationId,
        itemId: itemId,
        batchId: batchId,
        qty: qty,
      );

      final movement = await _append(
        MovementDraft(
          id: _newId(),
          itemId: itemId,
          batchId: batchId,
          fromLocationId: fromLocationId,
          toLocationId: toLocationId,
          qty: qty,
          movementType: movementType,
          actorUserId: actorUserId,
          refDocType: refDocType,
          refDocId: refDocId,
          note: note,
        ),
      );

      await _decrease(
        locationId: fromLocationId,
        itemId: itemId,
        batchId: batchId,
        qty: qty,
      );
      await _increase(
        locationId: toLocationId,
        itemId: itemId,
        batchId: batchId,
        qty: qty,
      );
      return movement;
    });
  }

  /// Aligns the balance at [locationId] with the physically counted quantity
  /// (G-O5). Returns `null` when there is no difference to post.
  ///
  /// Expired batches are *not* rejected here: a physical count must be able to
  /// report expired stock that is still sitting on the shelf. Removing it is
  /// then done through [postDisposal] (G-E7).
  Future<InventoryMovement?> postOpnameAdjustment({
    required String locationId,
    required String itemId,
    String? batchId,
    required Quantity countedQty,
    required String actorUserId,
    String? refDocType,
    String? refDocId,
    String? note,
  }) {
    return _inventory.runInTransaction(
      () => _postOpnameAdjustment(
        locationId: locationId,
        itemId: itemId,
        batchId: batchId,
        countedQty: countedQty,
        actorUserId: actorUserId,
        refDocType: refDocType,
        refDocId: refDocId,
        note: note,
      ),
    );
  }

  /// Posts every line of a Stok Opname review as **one** unit of work
  /// (G-O5, G-T4).
  ///
  /// This method opens no transaction of its own: the caller — the review use
  /// case — already owns one, and that is precisely the point. Locking the
  /// document and adjusting the stock have to commit or roll back together, so
  /// a failure on the last line cannot leave the first lines' movements behind.
  /// Calling a per-line method that opened its own transaction would make that
  /// impossible, which is why no such loop exists anywhere.
  ///
  /// Each line is posted against the balance **as it is right now**, not
  /// against the `difference` snapshotted when the document was created: stock
  /// may legitimately have moved between counting and reviewing, and the rule
  /// is that the balance ends up equal to what was physically counted. The
  /// closing assertion re-reads every balance and refuses to let the
  /// transaction commit if any of them disagrees with its counted quantity.
  Future<List<OpnameAdjustmentResult>> postOpnameAdjustmentsInTransaction({
    required String locationId,
    required List<OpnameAdjustmentLine> lines,
    required String actorUserId,
    required String opnameId,
  }) async {
    await _requireLocation(locationId);

    final results = <OpnameAdjustmentResult>[];
    for (final line in lines) {
      final movement = await _postOpnameAdjustment(
        locationId: locationId,
        itemId: line.itemId,
        batchId: line.batchId,
        countedQty: line.countedQty,
        actorUserId: actorUserId,
        refDocType: RefDocType.stockOpname,
        refDocId: opnameId,
        note: line.note,
      );
      results.add(
        OpnameAdjustmentResult(
          lineId: line.lineId,
          movement: movement,
          countedQty: line.countedQty,
        ),
      );
    }

    // Post-condition of G-O5, verified rather than assumed. `assert` would be
    // compiled out of a release build, and this is exactly the invariant that
    // must hold in production.
    for (final line in lines) {
      final finalQty = await _inventory.balanceQty(
        locationId: locationId,
        itemId: line.itemId,
        batchId: line.batchId,
      );
      if (finalQty != line.countedQty) {
        throw ValidationFailure(
          'Saldo setelah penyesuaian opname (${finalQty.format()}) tidak sama '
          'dengan hasil hitung fisik (${line.countedQty.format()}). '
          'Review dibatalkan.',
        );
      }
    }

    return results;
  }

  /// The transaction-free core of an opname adjustment. Every caller either
  /// wraps it in a transaction ([postOpnameAdjustment]) or already runs inside
  /// one ([postOpnameAdjustmentsInTransaction]).
  Future<InventoryMovement?> _postOpnameAdjustment({
    required String locationId,
    required String itemId,
    String? batchId,
    required Quantity countedQty,
    required String actorUserId,
    String? refDocType,
    String? refDocId,
    String? note,
  }) async {
    if (countedQty.isNegative) {
      throw const ValidationFailure('Hasil hitung fisik tidak boleh negatif.');
    }
    final item = await _requireItem(itemId);
    await _validateBatch(item: item, batchId: batchId);
    await _requireLocation(locationId);

    final currentQty = await _inventory.balanceQty(
      locationId: locationId,
      itemId: itemId,
      batchId: batchId,
    );
    // The difference may legitimately be negative (Q-7); the movement itself
    // still carries a positive qty and encodes the direction in its
    // from/to location.
    final difference = countedQty - currentQty;
    if (difference.isZero) return null;

    final movement = await _append(
      MovementDraft(
        id: _newId(),
        itemId: itemId,
        batchId: batchId,
        fromLocationId: difference.isNegative ? locationId : null,
        toLocationId: difference.isPositive ? locationId : null,
        qty: difference.absolute,
        movementType: StockMovementType.opnameAdjustment,
        actorUserId: actorUserId,
        refDocType: refDocType ?? RefDocType.stockOpname,
        refDocId: refDocId,
        note: note,
      ),
    );

    await _writeBalance(
      locationId: locationId,
      itemId: itemId,
      batchId: batchId,
      newQty: countedQty,
    );
    return movement;
  }

  /// Posts every allocation of a Delivery Order as **one** unit of work
  /// (G-D3, G-T4).
  ///
  /// This method opens no transaction of its own: the caller — the ship use case —
  /// already owns one, and that is precisely the point. Writing the movements,
  /// decreasing the warehouse, flipping the document to `shipped` and, when the
  /// order is complete, moving the Purchase Request to `shipped` all have to commit
  /// or roll back together, so a failure on the last allocation cannot leave the
  /// first one's movement behind. Calling [postTransfer] per line would make that
  /// impossible — it opens a transaction each time — which is why no such loop
  /// exists anywhere.
  ///
  /// ### Why `to_location_id` is NULL
  ///
  /// A shipment takes goods **out of** the warehouse and does not put them
  /// anywhere yet. The branch's own store must not gain the stock until Good
  /// Receipt has checked it in (spec §2.5: GR posts `good_receipt`, Gudang Cabang
  /// + `received_qty`, and only for the lines the branch accepted). Crediting the
  /// branch here would mean a shipment that was rejected on arrival had already
  /// been counted as branch stock, and the correction would have to be a movement
  /// nobody asked for. So the goods are in transit: one leg out now, one leg in
  /// later. `stock_movements` allows exactly this — its CHECK requires *one* of the
  /// two locations, not both.
  ///
  /// Every allocation is validated before **any** of them is written: item and
  /// batch consistency (G-E1/G-E2), expiry (G-E4) and sufficiency (G-D3). Only
  /// then does the posting loop start, and each balance is re-read as it goes, so
  /// two allocations drawing on the same batch cannot both see the opening
  /// quantity. The closing assertion re-reads every touched balance and refuses to
  /// let the transaction commit if any of them came out negative — the invariant
  /// G-A2 states, verified rather than assumed, because `assert` would be compiled
  /// out of a release build and this is exactly the check that must hold in
  /// production.
  Future<List<InventoryMovement>> postShipmentInTransaction({
    required String fromLocationId,
    required List<ShipmentPostingLine> lines,
    required String actorUserId,
    required String deliveryOrderId,
  }) async {
    if (lines.isEmpty) {
      throw const ValidationFailure(
        'Pengiriman tanpa baris tidak dapat diposting.',
      );
    }

    final source = await _requireLocation(fromLocationId);
    if (source.type != StockLocationType.warehouse) {
      throw InvalidLocationFailure(
        'Pengiriman hanya boleh dilakukan dari warehouse pusat, bukan dari '
        '"${source.name}".',
      );
    }

    // --- validate the whole document first -----------------------------------
    for (final line in lines) {
      _requirePositiveQty(line.qty);
      final item = await _requireItem(line.itemId);
      final batch = await _validateBatch(item: item, batchId: line.batchId);
      // Expired stock is blocked from a shipment outright (G-E4). No
      // confirmation and no note reach this point.
      _rejectExpiredBatch(batch);
    }

    // Sufficiency is checked against the **total** each position draws, not
    // per line: two allocations of 3 against a balance of 5 must fail, and
    // checking them one at a time would let both pass.
    final requestedByKey = <String, Quantity>{};
    for (final line in lines) {
      final key = _balanceKey(line.itemId, line.batchId);
      requestedByKey[key] = (requestedByKey[key] ?? Quantity.zero()) + line.qty;
    }
    for (final line in lines) {
      final key = _balanceKey(line.itemId, line.batchId);
      final wanted = requestedByKey[key];
      if (wanted == null) continue;
      await _assertSufficientStock(
        locationId: fromLocationId,
        itemId: line.itemId,
        batchId: line.batchId,
        qty: wanted,
      );
      // Checked once per distinct position.
      requestedByKey.remove(key);
    }

    // --- post ----------------------------------------------------------------
    final movements = <InventoryMovement>[];
    final touched = <String, ({String itemId, String? batchId})>{};
    for (final line in lines) {
      final movement = await _append(
        MovementDraft(
          id: _newId(),
          itemId: line.itemId,
          batchId: line.batchId,
          fromLocationId: fromLocationId,
          // In transit: the branch gains nothing until Good Receipt posts.
          toLocationId: null,
          qty: line.qty,
          movementType: StockMovementType.shipment,
          actorUserId: actorUserId,
          refDocType: RefDocType.deliveryOrder,
          refDocId: deliveryOrderId,
          note: line.note,
        ),
      );
      movements.add(movement);

      await _decrease(
        locationId: fromLocationId,
        itemId: line.itemId,
        batchId: line.batchId,
        qty: line.qty,
      );
      touched[_balanceKey(line.itemId, line.batchId)] = (
        itemId: line.itemId,
        batchId: line.batchId,
      );
    }

    // Post-condition of G-A2/G-D3, verified rather than assumed.
    for (final position in touched.values) {
      final remaining = await _inventory.balanceQty(
        locationId: fromLocationId,
        itemId: position.itemId,
        batchId: position.batchId,
      );
      if (remaining.isNegative) {
        throw InsufficientStockFailure(
          'Saldo warehouse menjadi negatif setelah pengiriman '
          '(${remaining.format()}). Pengiriman dibatalkan.',
          itemId: position.itemId,
          locationId: fromLocationId,
          batchId: position.batchId,
          available: Quantity.zero(),
          requested: -remaining,
        );
      }
    }

    return movements;
  }

  /// Posts every accepted position of a Good Receipt as **one** unit of work
  /// (G-G5, G-T4).
  ///
  /// This method opens no transaction of its own: the caller — the post use case —
  /// already owns one, and that is precisely the point. Writing the movements,
  /// increasing the branch store, flipping the receipt to `posted`, marking the
  /// shipment `received` and, when the order is complete, closing the Purchase
  /// Request all have to commit or roll back together, so a failure on the last
  /// position cannot leave the first one's movement behind. Calling [postTransfer]
  /// per line would make that impossible — it opens a transaction each time — which
  /// is why no such loop exists anywhere.
  ///
  /// ### Why `from_location_id` is NULL
  ///
  /// The other leg was already written. When the shipment was posted, the warehouse
  /// balance dropped and the movement recorded `to_location_id = NULL`: the goods
  /// were in transit (spec §2.5). This is the matching arrival — one leg out then,
  /// one leg in now — so it takes no stock from anywhere and must not reduce the
  /// warehouse a second time. `stock_movements` allows exactly this: its CHECK
  /// requires *one* of the two locations, not both.
  ///
  /// ### What is not here
  ///
  /// There is no branch for rejected positions, and there is no `return` movement.
  /// A refused line leaves the physical goods on the branch's counter and the
  /// warehouse's balance untouched; what it produces is a row on the selisih/retur
  /// queue. Crediting the warehouse here would invent stock that nobody has counted
  /// back in — the phantom the return workflow exists to prevent.
  ///
  /// Every position is validated before **any** of them is written: item and batch
  /// consistency (G-E1/G-E2) and expiry (G-E4 as a floor; the stricter G-E5 rule
  /// that refuses near-expiry batches outright is the Good Receipt's own and is
  /// applied by its use case before this is called). Only then does the posting loop
  /// start, and each balance is re-read as it goes, so two positions of the same
  /// batch cannot both see the opening quantity. The closing assertion re-reads
  /// every touched balance and refuses to let the transaction commit if any of them
  /// came out negative — the invariant G-A2 states, verified rather than assumed,
  /// because `assert` would be compiled out of a release build and this is exactly
  /// the check that must hold in production.
  Future<List<InventoryMovement>> postGoodReceiptInTransaction({
    required String toLocationId,
    required List<GoodReceiptPostingLine> lines,
    required String actorUserId,
    required String goodReceiptId,
  }) async {
    if (lines.isEmpty) {
      throw const ValidationFailure(
        'Tidak ada barang yang diterima, sehingga tidak ada stok untuk '
        'diposting.',
      );
    }

    final target = await _requireLocation(toLocationId);
    if (target.type != StockLocationType.branchStore) {
      throw InvalidLocationFailure(
        'Penerimaan barang hanya boleh masuk ke Gudang Cabang, bukan ke '
        '"${target.name}".',
      );
    }

    // --- validate the whole document first -----------------------------------
    for (final line in lines) {
      _requirePositiveQty(line.qty);
      final item = await _requireItem(line.itemId);
      final batch = await _validateBatch(item: item, batchId: line.batchId);
      // An expired batch never enters a balance (G-E4). The Good Receipt's own
      // policy already refused it with a message about rejecting the line; this is
      // the floor underneath that, so no other caller can post one either.
      _rejectExpiredBatch(batch);
    }

    // --- post ----------------------------------------------------------------
    final movements = <InventoryMovement>[];
    final touched = <String, ({String itemId, String? batchId})>{};
    for (final line in lines) {
      final movement = await _append(
        MovementDraft(
          id: _newId(),
          itemId: line.itemId,
          batchId: line.batchId,
          // The shipment already recorded the outbound leg; this is the arrival.
          fromLocationId: null,
          toLocationId: toLocationId,
          qty: line.qty,
          movementType: StockMovementType.goodReceipt,
          actorUserId: actorUserId,
          refDocType: RefDocType.goodReceipt,
          refDocId: goodReceiptId,
          note: line.note,
        ),
      );
      movements.add(movement);

      await _increase(
        locationId: toLocationId,
        itemId: line.itemId,
        batchId: line.batchId,
        qty: line.qty,
      );
      touched[_balanceKey(line.itemId, line.batchId)] = (
        itemId: line.itemId,
        batchId: line.batchId,
      );
    }

    // Post-condition of G-A2, verified rather than assumed. An arrival can only
    // raise a balance, so a negative one here means something else corrupted it —
    // and committing on top of that would bake the corruption in.
    for (final position in touched.values) {
      final onHand = await _inventory.balanceQty(
        locationId: toLocationId,
        itemId: position.itemId,
        batchId: position.batchId,
      );
      if (onHand.isNegative) {
        throw InsufficientStockFailure(
          'Saldo Gudang Cabang menjadi negatif setelah penerimaan '
          '(${onHand.format()}). Penerimaan dibatalkan.',
          itemId: position.itemId,
          locationId: toLocationId,
          batchId: position.batchId,
          available: Quantity.zero(),
          requested: -onHand,
        );
      }
    }

    return movements;
  }

  /// The identity of one balance row, as a map key. `item|batch`, with an empty
  /// batch segment for items without expiry.
  static String _balanceKey(String itemId, String? batchId) =>
      '$itemId|${batchId ?? ''}';

  /// Removes expired or damaged stock from the system (G-E7). A reason is
  /// mandatory because disposal is irreversible in the physical world.
  Future<InventoryMovement> postDisposal({
    required String locationId,
    required String itemId,
    String? batchId,
    required Quantity qty,
    required String actorUserId,
    required String note,
    String? refDocType,
    String? refDocId,
  }) {
    return _inventory.runInTransaction(() async {
      _requirePositiveQty(qty);
      if (note.trim().isEmpty) {
        throw const ValidationFailure(
          'Pemusnahan barang wajib disertai catatan alasan.',
        );
      }

      final item = await _requireItem(itemId);
      await _validateBatch(item: item, batchId: batchId);
      await _requireLocation(locationId);
      // Deliberately no expiry check: disposal is exactly how expired stock
      // leaves the system.

      await _assertSufficientStock(
        locationId: locationId,
        itemId: itemId,
        batchId: batchId,
        qty: qty,
      );

      final movement = await _append(
        MovementDraft(
          id: _newId(),
          itemId: itemId,
          batchId: batchId,
          fromLocationId: locationId,
          qty: qty,
          movementType: StockMovementType.disposal,
          actorUserId: actorUserId,
          refDocType: refDocType,
          refDocId: refDocId,
          note: note,
        ),
      );

      await _decrease(
        locationId: locationId,
        itemId: itemId,
        batchId: batchId,
        qty: qty,
      );
      return movement;
    });
  }

  /// Corrects a posted movement by appending its mirror image (G-A1). The
  /// original row is never touched.
  Future<InventoryMovement> postReversal({
    required String movementId,
    required String actorUserId,
    required String note,
  }) {
    return _inventory.runInTransaction(() async {
      if (note.trim().isEmpty) {
        throw const ValidationFailure(
          'Pembatalan pergerakan stok wajib disertai catatan alasan.',
        );
      }

      final original = await _inventory.movementById(movementId);
      if (original == null) {
        throw EntityNotFoundFailure(
          'Pergerakan stok tidak ditemukan.',
          entity: 'stock_movements',
          id: movementId,
        );
      }
      if (original.isReversal) {
        throw MovementImmutableFailure(
          'Pergerakan pembalik tidak dapat dibalik lagi.',
          movementId: movementId,
        );
      }
      final existingReversals = await _inventory.reversalsOf(movementId);
      if (existingReversals.isNotEmpty) {
        throw MovementImmutableFailure(
          'Pergerakan stok ini sudah pernah dibalik.',
          movementId: movementId,
        );
      }

      // The mirror image: what went in comes out and vice versa.
      final reversedFrom = original.toLocationId;
      final reversedTo = original.fromLocationId;

      if (reversedFrom != null) {
        await _assertSufficientStock(
          locationId: reversedFrom,
          itemId: original.itemId,
          batchId: original.batchId,
          qty: original.qty,
        );
      }

      final movement = await _append(
        MovementDraft(
          id: _newId(),
          itemId: original.itemId,
          batchId: original.batchId,
          fromLocationId: reversedFrom,
          toLocationId: reversedTo,
          qty: original.qty,
          movementType: StockMovementType.reversal,
          actorUserId: actorUserId,
          refDocType: original.refDocType,
          refDocId: original.refDocId,
          note: note,
          reversalOfMovementId: original.id,
        ),
      );

      if (reversedFrom != null) {
        await _decrease(
          locationId: reversedFrom,
          itemId: original.itemId,
          batchId: original.batchId,
          qty: original.qty,
        );
      }
      if (reversedTo != null) {
        await _increase(
          locationId: reversedTo,
          itemId: original.itemId,
          batchId: original.batchId,
          qty: original.qty,
        );
      }
      return movement;
    });
  }

  /// First-Expired-First-Out batch selection (G-E3).
  ///
  /// Only positive, non-expired balances take part; batches are consumed in
  /// ascending expiry order and the allocation may span several batches. The
  /// underlying query orders by `(expiry_date, batch_no, id)` so the result is
  /// deterministic. Throws [InsufficientStockFailure] when the usable stock is
  /// not enough — it never returns a partial allocation.
  Future<List<FefoAllocation>> allocateFefo({
    required String locationId,
    required String itemId,
    required Quantity qty,
    DateTime? asOf,
  }) async {
    _requirePositiveQty(qty);

    final item = await _requireItem(itemId);
    if (!item.hasExpiry) {
      throw BatchNotAllowedFailure(
        'Barang ${item.sku} tidak dilacak per batch, sehingga tidak '
        'memerlukan alokasi FEFO.',
        itemId: itemId,
      );
    }

    // "Today" is the operational date in GMT+8, not the device's (T-3).
    final today = AppTimeZone.operationalDate(asOf ?? _clock());

    final stocks = await _inventory.batchStocksForFefo(
      locationId: locationId,
      itemId: itemId,
    );
    final usable = stocks
        .where((stock) => !DateOnly.isBeforeDate(stock.expiryDate, today))
        .toList(growable: false);

    final available = Quantity.sum(usable.map((stock) => stock.qtyOnHand));
    if (available < qty) {
      throw InsufficientStockFailure(
        'Stok belum kedaluwarsa untuk ${item.name} tidak mencukupi '
        '(tersedia ${available.format()}, diminta ${qty.format()}).',
        itemId: itemId,
        locationId: locationId,
        available: available,
        requested: qty,
      );
    }

    // Integer milli-unit arithmetic: taking min(remaining, on hand) from each
    // batch in turn means the allocations always sum back to exactly [qty],
    // even when the request splits across batches (1.5 → 1 + 0.5).
    final allocations = <FefoAllocation>[];
    var remaining = qty;
    for (final stock in usable) {
      if (remaining.isZero) break;
      final take = Quantity.min(remaining, stock.qtyOnHand);
      allocations.add(
        FefoAllocation(
          batchId: stock.batchId,
          batchNo: stock.batchNo,
          expiryDate: stock.expiryDate,
          qty: take,
        ),
      );
      remaining -= take;
    }
    return allocations;
  }

  // --- internals ------------------------------------------------------------

  Future<InventoryMovement> _append(MovementDraft draft) =>
      _inventory.appendMovement(draft);

  void _requirePositiveQty(Quantity qty) {
    if (!qty.isPositive) {
      throw ValidationFailure(
        'Jumlah harus lebih besar dari 0 (diterima ${qty.format()}).',
      );
    }
  }

  Future<MasterItem> _requireItem(String itemId) async {
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

  Future<MasterLocation> _requireLocation(String locationId) async {
    final location = await _master.locationById(locationId);
    if (location == null) {
      throw EntityNotFoundFailure(
        'Lokasi stok tidak ditemukan.',
        entity: 'stock_locations',
        id: locationId,
      );
    }
    return location;
  }

  /// Enforces G-E1/G-E2: expiry items always move per batch, non-expiry items
  /// never carry one.
  Future<MasterBatch?> _validateBatch({
    required MasterItem item,
    required String? batchId,
  }) async {
    if (item.hasExpiry && batchId == null) {
      throw BatchRequiredFailure(
        'Barang ${item.sku} memiliki tanggal kedaluwarsa, batch wajib diisi.',
        itemId: item.id,
      );
    }
    if (!item.hasExpiry && batchId != null) {
      throw BatchNotAllowedFailure(
        'Barang ${item.sku} tidak memiliki tanggal kedaluwarsa, '
        'batch tidak boleh diisi.',
        itemId: item.id,
      );
    }
    if (batchId == null) return null;

    final batch = await _master.batchById(batchId);
    if (batch == null) {
      throw EntityNotFoundFailure(
        'Batch tidak ditemukan.',
        entity: 'item_batches',
        id: batchId,
      );
    }
    if (batch.itemId != item.id) {
      throw ValidationFailure(
        'Batch ${batch.batchNo} bukan milik barang ${item.sku}.',
      );
    }
    return batch;
  }

  void _rejectExpiredBatch(MasterBatch? batch) {
    if (batch == null) return;
    if (batch.isExpiredOn(_clock())) {
      throw ExpiredBatchFailure(
        'Batch ${batch.batchNo} sudah kedaluwarsa dan tidak dapat digunakan.',
        batchId: batch.id,
        expiryDate: batch.expiryDate,
      );
    }
  }

  Future<void> _assertSufficientStock({
    required String locationId,
    required String itemId,
    String? batchId,
    required Quantity qty,
  }) async {
    final available = await _inventory.balanceQty(
      locationId: locationId,
      itemId: itemId,
      batchId: batchId,
    );
    if (available < qty) {
      throw InsufficientStockFailure(
        'Stok tidak mencukupi (tersedia ${available.format()}, '
        'dibutuhkan ${qty.format()}).',
        itemId: itemId,
        locationId: locationId,
        batchId: batchId,
        available: available,
        requested: qty,
      );
    }
  }

  Future<void> _increase({
    required String locationId,
    required String itemId,
    String? batchId,
    required Quantity qty,
  }) async {
    final current = await _inventory.balanceQty(
      locationId: locationId,
      itemId: itemId,
      batchId: batchId,
    );
    await _writeBalance(
      locationId: locationId,
      itemId: itemId,
      batchId: batchId,
      newQty: current + qty,
    );
  }

  Future<void> _decrease({
    required String locationId,
    required String itemId,
    String? batchId,
    required Quantity qty,
  }) async {
    final current = await _inventory.balanceQty(
      locationId: locationId,
      itemId: itemId,
      batchId: batchId,
    );
    await _writeBalance(
      locationId: locationId,
      itemId: itemId,
      batchId: batchId,
      newQty: current - qty,
    );
  }

  Future<void> _writeBalance({
    required String locationId,
    required String itemId,
    String? batchId,
    required Quantity newQty,
  }) async {
    // Last line of defence before the database CHECK constraint (G-A2).
    if (newQty.isNegative) {
      throw InsufficientStockFailure(
        'Saldo stok tidak boleh negatif.',
        itemId: itemId,
        locationId: locationId,
        batchId: batchId,
        available: Quantity.zero(),
        requested: -newQty,
      );
    }
    await _inventory.setBalanceQty(
      locationId: locationId,
      itemId: itemId,
      batchId: batchId,
      qtyOnHand: newQty,
    );
  }
}
