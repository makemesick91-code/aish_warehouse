import '../../../../core/quantity/quantity.dart';
import '../models/delivery_models.dart';

/// G-D2 — the cumulative shipment rule, in one place.
///
/// *"Total `shipped_qty` kumulatif untuk setiap PR line tidak boleh melebihi
/// `requested_qty`."*
///
/// Every comparison here is exact fixed-point integer arithmetic on milli-units
/// (Q-2/Q-3). Nothing converts to `double`, and that is load-bearing rather than
/// stylistic: a request of `2.375` shipped as `0.5 + 1.875` must land on exactly
/// zero remaining, and binary floating point would leave a residue that would
/// make the document either short by a hair or over-shipped by one.
///
/// A pure, synchronous policy so the form, the use case and the tests all ask the
/// same question. It is deliberately **not** the authority: the numbers it is
/// given while a form is open are a snapshot, and another device may ship in the
/// meantime. The authority is [PurchaseRequestShipmentProgressCalculator] applied
/// to quantities re-read **inside the posting transaction**.
abstract final class DeliveryQuantityPolicy {
  /// What is still outstanding on a requested position.
  ///
  /// May be negative if the data is already inconsistent, and the caller is
  /// expected to notice rather than to clamp: silently returning zero would hide
  /// an over-shipment instead of refusing it.
  static Quantity remaining({
    required Quantity requestedQty,
    required Quantity cumulativeShippedQty,
  }) => requestedQty - cumulativeShippedQty;

  /// Whether adding [additionalQty] would push the position past what was asked
  /// for.
  ///
  /// Strictly greater than, deliberately: shipping the last `0.5` of a `2.5`
  /// request is exactly complete and must be accepted (G-D5 depends on it).
  static bool exceedsRequested({
    required Quantity requestedQty,
    required Quantity cumulativeShippedQty,
    required Quantity additionalQty,
  }) => cumulativeShippedQty + additionalQty > requestedQty;

  /// Whether the position is exactly satisfied.
  static bool isFullyShipped({
    required Quantity requestedQty,
    required Quantity cumulativeShippedQty,
  }) => cumulativeShippedQty == requestedQty;

  /// Whether a quantity is a legal allocation at all: strictly positive.
  ///
  /// A zero allocation is not a shipment of nothing, it is an absent line, and
  /// the database CHECK says the same thing.
  static bool isValidAllocation(Quantity qty) => qty.isPositive;

  /// Whether [progress] would complete **every** requested position of a request
  /// — the condition that makes the Purchase Request `shipped` (G-D5).
  ///
  /// An empty list answers `false`: a request with no positions has nothing to
  /// complete, and treating "nothing outstanding" as "fully shipped" would move a
  /// corrupt document forward.
  static bool completesRequest(Iterable<ShipmentProgress> progress) {
    final entries = progress.toList(growable: false);
    if (entries.isEmpty) return false;
    return entries.every((entry) => entry.isFullyShipped);
  }

  /// Whether any position of [progress] is over-shipped.
  ///
  /// Asked separately from [completesRequest] because the two failures are
  /// different: an incomplete request stays `processing`, while an over-shipped
  /// one is refused outright and must never become `shipped`.
  static bool hasOverShipment(Iterable<ShipmentProgress> progress) =>
      progress.any((entry) => entry.isOverShipped);
}

/// Builds the per-position shipment picture of one Purchase Request.
///
/// Kept apart from [DeliveryQuantityPolicy] because it does a different job: the
/// policy answers yes/no questions about two quantities, while this assembles the
/// [ShipmentProgress] rows a screen renders and the ship path validates. Both are
/// pure and synchronous — the caller supplies the requested quantities and the two
/// cumulative maps, which is what lets the ship path feed it numbers it read
/// inside the transaction.
abstract final class PurchaseRequestShipmentProgressCalculator {
  /// One [ShipmentProgress] per requested position, in the order [lines] were
  /// given.
  ///
  /// [previouslyShippedByPrLine] must come from Delivery Orders in `shipped` or
  /// `received` **excluding** the document in hand; [currentByPrLine] is that
  /// document's own allocations. Keeping them as two maps rather than one total is
  /// what lets the same calculation serve a `preparing` document — whose
  /// quantities do not count as shipped yet — and the moment it is posted.
  ///
  /// A position absent from either map contributes zero, which is the honest
  /// reading of "nothing has shipped against it".
  static List<ShipmentProgress> build({
    required List<ShipmentProgressInput> lines,
    required Map<String, Quantity> previouslyShippedByPrLine,
    required Map<String, Quantity> currentByPrLine,
  }) {
    return lines
        .map(
          (line) => ShipmentProgress(
            prLineId: line.prLineId,
            itemId: line.itemId,
            sku: line.sku,
            itemName: line.itemName,
            unit: line.unit,
            requestedQty: line.requestedQty,
            previouslyShippedQty:
                previouslyShippedByPrLine[line.prLineId] ?? Quantity.zero(),
            currentDoQty: currentByPrLine[line.prLineId] ?? Quantity.zero(),
          ),
        )
        .toList(growable: false);
  }

  /// The first position that would exceed its request, or `null` when every one of
  /// them fits (G-D2).
  static ShipmentProgress? firstOverShipment(
    Iterable<ShipmentProgress> progress,
  ) {
    for (final entry in progress) {
      if (entry.isOverShipped) return entry;
    }
    return null;
  }
}

/// The identity and requested quantity of one Purchase Request line, as the
/// progress calculation needs it.
///
/// A record-like input class rather than the domain `PurchaseRequestLine`, so the
/// calculator does not drag the Purchase Request feature's model into every
/// caller — and so the ship path can feed it rows it read straight from the
/// database inside the transaction.
class ShipmentProgressInput {
  const ShipmentProgressInput({
    required this.prLineId,
    required this.itemId,
    required this.sku,
    required this.itemName,
    required this.unit,
    required this.requestedQty,
  });

  final String prLineId;
  final String itemId;
  final String sku;
  final String itemName;
  final String unit;
  final Quantity requestedQty;
}
