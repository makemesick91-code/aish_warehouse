import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../domain/models/inventory_models.dart';

/// One row of a stock card: a ledger movement plus the names needed to read it.
///
/// ### Why the display data is *attached* rather than joined
///
/// `InventoryDao.stockCard` is a plain select on `stock_movements` with no joins at all,
/// and that is load-bearing: a stock card must add up. If the query joined `items`,
/// `item_batches`, `stock_locations` or `users`, a row whose master reference has been
/// archived — or physically deleted — would silently vanish, and the card would show a
/// balance falling with no movement to explain it. §6 states the rule directly: the movement
/// stays visible whatever happened to the rows it points at.
///
/// So every descriptive field here is **nullable**, and the widget renders a safe label in
/// place of a missing one. Resolving them is the caller's job, through the historical master
/// lookups (`itemById`, `batchById`, `historicalRoomById`, `locationById`, `userById`) that
/// return deactivated and soft-deleted rows rather than hiding them (G-A4/G-A5).
///
/// ### Why the document number is supplied from outside
///
/// [documentNumber] is passed in rather than looked up here, because *which* documents a
/// reader may see is a question the inventory feature cannot answer: a Pemakaian number is
/// readable by the nurse who recorded it and by their branch head, and by nobody else (§14).
/// The feature that owns the document resolves the number through its own scoped repository
/// and hands it over; a `null` therefore means *"not yours to read, or gone"* and both render
/// the same way. That ambiguity is deliberate — distinguishing them would let a stock card be
/// used to probe which document ids exist.
class StockCardEntry {
  const StockCardEntry({
    required this.movement,
    this.itemName,
    this.sku,
    this.unit,
    this.batchNo,
    this.expiryDate,
    this.fromLocationName,
    this.toLocationName,
    this.actorName,
    this.documentNumber,
    this.itemIsHistorical = false,
    this.batchIsHistorical = false,
    this.actorIsHistorical = false,
  });

  final InventoryMovement movement;

  /// `null` when the item row can no longer be resolved.
  final String? itemName;
  final String? sku;

  /// The item's unit, for [Quantity.formatWithUnit]. `null` renders the bare number rather
  /// than inventing a unit.
  final String? unit;

  /// `null` for an item without expiry, **and** when the batch row is gone. The widget
  /// cannot tell those apart and does not need to: it renders no batch either way.
  final String? batchNo;

  /// Civil date — never timezone converted (T-8/T-9).
  final DateTime? expiryDate;

  /// Where the stock came from and went to. Either may legitimately be `null`: a movement
  /// that brings goods in from outside has no source, and one that takes them out of the
  /// system has no destination (§2.2).
  final String? fromLocationName;
  final String? toLocationName;

  /// Who performed the movement (G-A3). `null` only when the user row is gone.
  final String? actorName;

  /// The referenced document's number, or `null` when it is out of scope or missing.
  final String? documentNumber;

  /// The master row exists but has been deactivated or archived, so a screen can label it
  /// as history rather than presenting it as current (G-A4/G-A5).
  final bool itemIsHistorical;
  final bool batchIsHistorical;
  final bool actorIsHistorical;

  String get id => movement.id;

  StockMovementType get type => movement.movementType;

  Quantity get qty => movement.qty;

  /// UTC instant (T-1). Convert through `AppDateTimeFormatter` before displaying.
  DateTime get createdAt => movement.createdAt;

  String? get refDocType => movement.refDocType;

  String? get refDocId => movement.refDocId;

  String? get note => movement.note;

  bool get hasNote => (note ?? '').trim().isNotEmpty;

  bool get isBatched => movement.batchId != null;

  bool get isReversal => movement.isReversal;

  bool get usesHistoricalMaster =>
      itemIsHistorical || batchIsHistorical || actorIsHistorical;

  /// Whether the movement's document reference could be resolved to a number.
  bool get hasDocumentNumber => (documentNumber ?? '').trim().isNotEmpty;

  @override
  String toString() =>
      'StockCardEntry(${type.dbValue}, ${qty.format()}, '
      '${refDocType ?? '-'})';
}

/// Orders stock-card rows newest first, on **UTC instants**.
///
/// The DAO already orders by `created_at DESC`, and for the overwhelming majority of rows
/// that agrees with this. It is redone here anyway, and the reason is the one schema v4
/// removed a CHECK for: `created_at` is ISO-8601 **TEXT**, so SQL orders it by characters.
/// Two instants written in different but equally valid forms — `…02:00:00.000Z` against
/// `…02:00:00.000000Z`, or a `+08:00` suffix against a `Z` one — sort by their spelling
/// rather than by the moments they denote. A stock card is read as a sequence, so the one
/// place that guarantee has to hold is where the sequence is rendered.
///
/// `id` breaks ties, so two movements written in the same microsecond render in the same
/// order on two devices holding the same ledger.
int compareStockCardEntries(StockCardEntry a, StockCardEntry b) {
  final byInstant = b.createdAt.toUtc().compareTo(a.createdAt.toUtc());
  if (byInstant != 0) return byInstant;
  return b.id.compareTo(a.id);
}
