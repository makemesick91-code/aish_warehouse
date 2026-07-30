import '../../../../core/errors/failures.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/purchase_request_models.dart';
import '../repositories/purchase_request_repository.dart';
import 'purchase_request_opname_eligibility_policy.dart';
import 'suggested_purchase_request_calculator.dart';

/// Validated citations plus the lines they imply.
class PurchaseRequestSuggestion {
  const PurchaseRequestSuggestion({
    required this.references,
    required this.lines,
  });

  /// The cited counts, in the order the picker showed them.
  final List<PurchaseRequestOpnameReference> references;

  /// What the system proposes, positive suggestions only.
  final List<SuggestedPurchaseRequestLine> lines;
}

/// Turns a set of chosen opname ids into a validated, priced-up proposal.
///
/// Creating a draft and changing a draft's citations are the same piece of work
/// twice — validate every reference against G-P1, read the counted snapshots, run
/// the deficiency arithmetic — and they must produce identical numbers, or a
/// branch head who adds a room would see the whole document's suggestions shift
/// for reasons unrelated to the room they added. Hence one collaborator both use
/// rather than two implementations that agree today.
///
/// It performs **no writes** and holds no clock: the caller passes the instant, so
/// the eligibility window is deterministic in tests (T-7).
class PurchaseRequestSuggestionBuilder {
  PurchaseRequestSuggestionBuilder({
    required this._requests,
    required this._master,
    SuggestedPurchaseRequestCalculator? calculator,
  }) : _calculator = calculator ?? const SuggestedPurchaseRequestCalculator();

  final PurchaseRequestRepository _requests;
  final MasterDataRepository _master;
  final SuggestedPurchaseRequestCalculator _calculator;

  /// Validates [opnameIds] for [branchId] at [utcNow] and computes the proposal.
  ///
  /// [prId] is only used to attribute failures to a document; it is empty while a
  /// draft is being created and has no id yet.
  Future<PurchaseRequestSuggestion> build({
    required String branchId,
    required List<String> opnameIds,
    required DateTime utcNow,
    String prId = '',
  }) async {
    // G-P1, first half: an order with no evidence behind it is not an order.
    if (opnameIds.isEmpty) {
      throw PurchaseRequestOpnameRequiredFailure(
        'Pilih minimal satu stok opname sebagai acuan permintaan.',
        prId: prId,
      );
    }

    final unique = <String>{};
    for (final opnameId in opnameIds) {
      if (!unique.add(opnameId)) {
        throw ValidationFailure(
          'Stok opname yang sama dipilih lebih dari satu kali.',
        );
      }
    }

    final references = <PurchaseRequestOpnameReference>[];
    for (final opnameId in opnameIds) {
      references.add(
        await _requireEligible(
          opnameId: opnameId,
          branchId: branchId,
          utcNow: utcNow,
        ),
      );
    }

    final snapshots = <OpnameCountSnapshot>[];
    final itemIds = <String>{};
    for (final reference in references) {
      final positions = await _requests.countedPositionsOf(reference.opnameId);
      itemIds.addAll(positions.map((position) => position.itemId));
      snapshots.add((
        opnameId: reference.opnameId,
        roomId: reference.roomId,
        roomName: reference.roomName,
        periodYear: reference.periodYear,
        periodWeek: reference.periodWeek,
        lines: positions,
      ));
    }

    return PurchaseRequestSuggestion(
      references: List.unmodifiable(references),
      lines: _calculator(
        snapshots: snapshots,
        items: await _loadItems(itemIds),
      ),
    );
  }

  /// G-P1 for one citation, with the reason spelled out.
  Future<PurchaseRequestOpnameReference> _requireEligible({
    required String opnameId,
    required String branchId,
    required DateTime utcNow,
  }) async {
    final reference = await _requests.opnameReferenceById(opnameId);
    if (reference == null) {
      throw IneligibleStockOpnameFailure(
        PurchaseRequestOpnameEligibilityPolicy.messageFor(
          reason: StockOpnameEligibilityDenial.missing,
          docNumber: opnameId,
        ),
        opnameId: opnameId,
        reason: StockOpnameEligibilityDenial.missing,
      );
    }

    final denial = PurchaseRequestOpnameEligibilityPolicy.denialFor(
      facts: (
        opnameId: reference.opnameId,
        branchId: reference.branchId,
        status: reference.status,
        periodYear: reference.periodYear,
        periodWeek: reference.periodWeek,
      ),
      prBranchId: branchId,
      utcNow: utcNow,
    );
    if (denial == null) return reference;

    throw IneligibleStockOpnameFailure(
      PurchaseRequestOpnameEligibilityPolicy.messageFor(
        reason: denial,
        // A count from another branch is named by its id rather than its number:
        // the document number is the one piece of a foreign document worth
        // withholding, and the branch head has no legitimate reason to see it.
        docNumber: denial == StockOpnameEligibilityDenial.otherBranch
            ? opnameId
            : reference.docNumber,
      ),
      opnameId: opnameId,
      reason: denial,
    );
  }

  /// Master rows for every counted item.
  ///
  /// A missing row here is corruption, not a business case: `stock_opname_lines`
  /// has a foreign key to `items`, so the row can only be absent if something
  /// removed it behind the constraint. Refusing is the honest answer — a
  /// suggestion that silently omits a counted item would understate what the
  /// branch needs, and inventing a par level for an item nobody can find would be
  /// worse.
  Future<Map<String, MasterItem>> _loadItems(Set<String> itemIds) async {
    final items = <String, MasterItem>{};
    for (final itemId in itemIds) {
      final item = await _master.itemById(itemId);
      if (item == null) {
        throw EntityNotFoundFailure(
          'Barang pada stok opname acuan tidak ditemukan. Hubungi '
          'administrator.',
          entity: 'items',
          id: itemId,
        );
      }
      items[itemId] = item;
    }
    return items;
  }
}
