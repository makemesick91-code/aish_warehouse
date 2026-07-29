import 'package:uuid/uuid.dart';

import '../../../../core/enums/app_enums.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../inventory/domain/repositories/inventory_repository.dart';
import '../../../master/domain/repositories/master_data_repository.dart';
import '../models/opname_models.dart';
import '../repositories/opname_repository.dart';
import 'opname_guards.dart';

/// Opens this week's Stok Opname for one room (G-O1, G-O2).
///
/// The document is created already filled in: every position that currently
/// holds stock in the room becomes a line whose `system_qty` is the balance at
/// this instant. That snapshot is written once and never refreshed — if a
/// distribution arrives an hour later, the sheet still shows what the system
/// believed when counting started, which is the whole point of an opname
/// (G-O2).
///
/// `counted_qty` starts equal to `system_qty` so an untouched line means
/// "verified, no difference" rather than "counted as zero". A nurse who finds
/// nothing on the shelf enters 0 explicitly.
class CreateStockOpnameUseCase {
  CreateStockOpnameUseCase({
    required this._opnames,
    required MasterDataRepository master,
    required this._inventory,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _guards = OpnameGuards(master),
       _clock = clock ?? _defaultClock,
       _newId = idGenerator ?? _defaultIdGenerator;

  final OpnameRepository _opnames;
  final InventoryRepository _inventory;
  final OpnameGuards _guards;
  final DateTime Function() _clock;
  final String Function() _newId;

  static final _uuid = Uuid();

  static DateTime _defaultClock() => DateTime.now().toUtc();

  static String _defaultIdGenerator() => _uuid.v4();

  Future<StockOpname> call({
    required String actorUserId,
    required String roomId,
  }) async {
    final actor = await _guards.requireActor(actorUserId, UserRole.perawat);
    final room = await _guards.requireRoomInActorBranch(
      actor: actor,
      roomId: roomId,
    );
    final location = await _guards.requireRoomLocation(room);

    // The weekly key comes from the GMT+8 operational calendar, never the
    // device's (T-3). A count started at 23:00 in Jakarta and one started at
    // 08:00 the next morning in Manila land in the same ISO week only because
    // both are resolved through AppTimeZone.
    final operationalDate = AppTimeZone.operationalDate(_clock());
    final periodYear = AppTimeZone.isoWeekYear(operationalDate);
    final periodWeek = AppTimeZone.isoWeekNumber(operationalDate);

    // Everything from here runs in one transaction: the duplicate check, the
    // balance snapshot and the insert. Two nurses tapping at the same moment
    // therefore cannot both pass the check — and if they somehow did, the
    // UNIQUE(room_id, period_year, period_week) index is the final guard.
    return _opnames.runInTransaction(() async {
      final existing = await _opnames.findForRoomAndPeriod(
        roomId: roomId,
        periodYear: periodYear,
        periodWeek: periodWeek,
      );
      if (existing != null) {
        throw StockOpnameAlreadyExistsFailure(
          'Stok opname ${room.name} untuk minggu '
          '${_periodLabel(periodYear, periodWeek)} sudah ada '
          '(${existing.docNumber}).',
          roomId: roomId,
          periodYear: periodYear,
          periodWeek: periodWeek,
          existingOpnameId: existing.id,
        );
      }

      final lines = await _snapshotRoom(location.id);

      return _opnames.createDraft(
        // Local temporary number: the sync backend assigns the final
        // `SO-{cabang}-{yyyyMMdd}-{seq}` when the document reaches it (G-Y4).
        // Minting a server-shaped number offline would collide across devices.
        docNumber: 'TMP-SO-${_newId()}',
        branchId: actor.branchId!,
        roomId: roomId,
        periodYear: periodYear,
        periodWeek: periodWeek,
        countedBy: actor.id,
        lines: lines,
      );
    });
  }

  /// Turns the room's current balances into snapshot lines.
  ///
  /// Expiry-tracked items produce one line per batch and non-expiry items a
  /// single line with `batch_id = null` (G-E2) — which is exactly how the
  /// balance table is already keyed, so the mapping is one to one.
  Future<List<StockOpnameLineDraft>> _snapshotRoom(String locationId) async {
    final balances = await _inventory.balancesAtLocation(
      locationId,
      // Positions counted down to zero must stay on the sheet: they are the
      // ones most likely to be found again during a physical count.
      positiveOnly: false,
    );

    return balances
        .map(
          (balance) => StockOpnameLineDraft(
            itemId: balance.itemId,
            batchId: balance.batchId,
            systemQty: balance.qtyOnHand,
            countedQty: balance.qtyOnHand,
          ),
        )
        .toList(growable: false);
  }

  /// The ISO period a new document would land in, so the UI can label the
  /// button and decide whether this week is already covered.
  ({int year, int week}) currentPeriod() {
    final date = AppTimeZone.operationalDate(_clock());
    return (
      year: AppTimeZone.isoWeekYear(date),
      week: AppTimeZone.isoWeekNumber(date),
    );
  }

  /// Whether the room still needs a count this week (drives the enabled state
  /// of "+ Opname Minggu Ini").
  Future<StockOpname?> existingForCurrentWeek(String roomId) async {
    final period = currentPeriod();
    return _opnames.findForRoomAndPeriod(
      roomId: roomId,
      periodYear: period.year,
      periodWeek: period.week,
    );
  }

  static String _periodLabel(int year, int week) =>
      '$year-W${week.toString().padLeft(2, '0')}';
}
