import '../../../core/time/date_only.dart';
import '../../master/domain/models/master_models.dart';
import '../../master/domain/repositories/master_data_repository.dart';
import '../domain/models/inventory_models.dart';
import 'models/stock_card_entry.dart';

/// Resolves the display data a [StockCardEntry] needs, for a list of movements.
///
/// One function rather than a provider family, and the reason is the document numbers:
/// *which* documents a reader may see is a question the inventory feature cannot answer
/// (§14), so the feature that owns the document resolves its numbers through its own scoped
/// repository and passes them in. A provider family keyed on a closure would have no usable
/// equality; a function called from each feature's own scoped provider has exactly the right
/// shape.
///
/// ### Every lookup is historical
///
/// `itemById`, `batchById`, `locationById` and `userById` all return deactivated and
/// soft-deleted rows rather than hiding them (G-A4/G-A5), which is what keeps a movement
/// readable after an administrator withdraws the product it names. A row that cannot be
/// resolved at all leaves its field `null`, and the widget renders a safe label — the
/// movement is never dropped (§6).
///
/// Lookups are memoised per id, so a card with twelve movements of one product costs one item
/// query rather than twelve.
Future<List<StockCardEntry>> buildStockCardEntries({
  required List<InventoryMovement> movements,
  required MasterDataRepository master,
  Map<String, String> documentNumbers = const <String, String>{},
}) async {
  if (movements.isEmpty) return const <StockCardEntry>[];

  final items = <String, MasterItem?>{};
  final batches = <String, MasterBatch?>{};
  final locations = <String, MasterLocation?>{};
  final users = <String, MasterUser?>{};

  Future<MasterItem?> item(String id) async =>
      items.containsKey(id) ? items[id] : items[id] = await master.itemById(id);

  Future<MasterBatch?> batch(String id) async => batches.containsKey(id)
      ? batches[id]
      : batches[id] = await master.batchById(id);

  Future<MasterLocation?> location(String id) async => locations.containsKey(id)
      ? locations[id]
      : locations[id] = await master.locationById(id);

  Future<MasterUser?> user(String id) async =>
      users.containsKey(id) ? users[id] : users[id] = await master.userById(id);

  final entries = <StockCardEntry>[];
  for (final movement in movements) {
    final resolvedItem = await item(movement.itemId);
    final batchId = movement.batchId;
    final resolvedBatch = batchId == null ? null : await batch(batchId);
    final fromId = movement.fromLocationId;
    final toId = movement.toLocationId;
    final actor = await user(movement.actorUserId);
    final refDocId = movement.refDocId;

    entries.add(
      StockCardEntry(
        movement: movement,
        itemName: resolvedItem?.name,
        sku: resolvedItem?.sku,
        unit: resolvedItem?.unit,
        batchNo: resolvedBatch?.batchNo,
        // A civil date is read back verbatim, never timezone converted (T-9).
        expiryDate: resolvedBatch == null
            ? null
            : DateOnly.from(resolvedBatch.expiryDate),
        fromLocationName: fromId == null
            ? null
            : (await location(fromId))?.name,
        toLocationName: toId == null ? null : (await location(toId))?.name,
        actorName: actor?.fullName,
        documentNumber: refDocId == null ? null : documentNumbers[refDocId],
        itemIsHistorical: resolvedItem != null && !resolvedItem.isActive,
        // `MasterBatch` carries no `is_active` and no `deleted_at` — batches are only ever
        // archived, and `batchById` returns an archived row identically to a live one. So
        // there is nothing here to derive a badge from, and inventing one would be a badge
        // that never lights up. What the widget *does* handle is a batch that cannot be
        // resolved at all, which renders `unresolvedMasterLabel` rather than a missing row.
        batchIsHistorical: false,
        actorIsHistorical: actor != null && !actor.isActive,
      ),
    );
  }

  entries.sort(compareStockCardEntries);
  return List<StockCardEntry>.unmodifiable(entries);
}
