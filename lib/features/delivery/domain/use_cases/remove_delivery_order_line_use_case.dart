import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../repositories/delivery_order_repository.dart';
import 'delivery_order_guards.dart';

/// Removes one allocation from a `preparing` Delivery Order (§20.4).
///
/// A soft delete (G-A5): the row stays, `deleted_at` is set, and the partial
/// unique indexes are written `WHERE deleted_at IS NULL` precisely so the position
/// it occupied can be allocated again afterwards.
///
/// Nothing is posted and nothing is reversed, because nothing was ever posted: a
/// `preparing` allocation has never touched the ledger, so removing it is not a
/// stock movement. Shipped and received documents are refused — their lines are
/// what the movements were written from, and deleting one would leave the ledger
/// describing a shipment the document no longer claims to have made.
class RemoveDeliveryOrderLineUseCase {
  RemoveDeliveryOrderLineUseCase({
    required this._deliveries,
    required MasterDataRepository master,
  }) : _guards = DeliveryOrderGuards(master);

  final DeliveryOrderRepository _deliveries;
  final DeliveryOrderGuards _guards;

  Future<void> call({
    required String actorUserId,
    required String lineId,
  }) async {
    final actor = await _guards.requireWarehouseActor(actorUserId);

    await _deliveries.runInTransaction(() async {
      final reference = await _deliveries.lineReferenceById(lineId);
      if (reference == null) {
        throw DeliveryOrderLineNotFoundFailure(
          'Baris Surat Jalan tidak ditemukan.',
          lineId: lineId,
        );
      }

      final order = await _deliveries.getById(reference.doId);
      if (order == null) {
        throw DeliveryOrderNotFoundFailure(
          'Surat Jalan tidak ditemukan.',
          doId: reference.doId,
        );
      }
      _guards.requireStatus(
        order: order,
        expected: DeliveryOrderStatus.preparing,
      );
      _guards.requireTransition(
        actor: actor,
        order: order,
        to: DeliveryOrderStatus.shipped,
      );

      final removed = await _deliveries.removePreparingLine(lineId);
      if (!removed) _guards.concurrentUpdate(order);
    });
  }
}
