import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/database_providers.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/session/acting_user_providers.dart';
import '../../../../core/session/current_user_session.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../inventory/domain/services/stock_posting_service.dart';
import '../../../inventory/presentation/models/stock_card_entry.dart';
import '../../../inventory/presentation/providers/inventory_providers.dart';
import '../../../inventory/presentation/stock_card_builder.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/presentation/providers/master_providers.dart';
import '../../data/repositories/drift_consumption_repository.dart';
import '../../domain/models/consumption_models.dart';
import '../../domain/repositories/consumption_repository.dart';
import '../../domain/services/consumption_access_policy.dart';
import '../../domain/services/consumption_room_policy.dart';
import '../../domain/services/consumption_state_policy.dart';
import '../../domain/services/consumption_stock_reader.dart';
import '../../domain/use_cases/add_consumption_line_use_case.dart';
import '../../domain/use_cases/create_consumption_use_case.dart';
import '../../domain/use_cases/post_consumption_use_case.dart';
import '../../domain/use_cases/remove_consumption_line_use_case.dart';
import '../../domain/use_cases/update_consumption_header_use_case.dart';
import '../../domain/use_cases/update_consumption_line_use_case.dart';

// --- clock ------------------------------------------------------------------

/// The UTC clock the whole feature reads "now" from.
///
/// A provider rather than a bare `DateTime.now()` because this milestone's eligibility
/// rule is a function of the current operational day: §17 asks which day it is, and a
/// batch that may be used today may not be tomorrow. Overriding this one provider moves
/// the candidate list, the badges, the dashboard counters and the `posted_at` stamp
/// together — which is what keeps them consistent (T-7).
final consumptionClockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

// --- wiring -----------------------------------------------------------------

final consumptionRepositoryProvider = Provider<ConsumptionRepository>(
  (ref) => DriftConsumptionRepository(ref.watch(consumptionDaoProvider)),
);

final consumptionStockReaderProvider = Provider<RoomConsumptionStockReader>(
  (ref) => RoomConsumptionStockReader(ref.watch(inventoryRepositoryProvider)),
);

/// The posting service the consumption uses, wired to [consumptionClockProvider].
///
/// Deliberately not `stockPostingServiceProvider`: that one reads the wall clock, and the
/// expiry decisions behind a posting have to be made against the same "now" the rest of
/// the screen used.
final consumptionStockPostingServiceProvider = Provider<StockPostingService>(
  (ref) => StockPostingService(
    inventory: ref.watch(inventoryRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    clock: ref.watch(consumptionClockProvider),
  ),
);

final createConsumptionUseCaseProvider = Provider<CreateConsumptionUseCase>(
  (ref) => CreateConsumptionUseCase(
    consumptions: ref.watch(consumptionRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    clock: ref.watch(consumptionClockProvider),
  ),
);

final updateConsumptionHeaderUseCaseProvider =
    Provider<UpdateConsumptionHeaderUseCase>(
      (ref) => UpdateConsumptionHeaderUseCase(
        consumptions: ref.watch(consumptionRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
      ),
    );

final addConsumptionLineUseCaseProvider = Provider<AddConsumptionLineUseCase>(
  (ref) => AddConsumptionLineUseCase(
    consumptions: ref.watch(consumptionRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    stock: ref.watch(consumptionStockReaderProvider),
    clock: ref.watch(consumptionClockProvider),
  ),
);

final updateConsumptionLineUseCaseProvider =
    Provider<UpdateConsumptionLineUseCase>(
      (ref) => UpdateConsumptionLineUseCase(
        consumptions: ref.watch(consumptionRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
        stock: ref.watch(consumptionStockReaderProvider),
        clock: ref.watch(consumptionClockProvider),
      ),
    );

final removeConsumptionLineUseCaseProvider =
    Provider<RemoveConsumptionLineUseCase>(
      (ref) => RemoveConsumptionLineUseCase(
        consumptions: ref.watch(consumptionRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
      ),
    );

final postConsumptionUseCaseProvider = Provider<PostConsumptionUseCase>(
  (ref) => PostConsumptionUseCase(
    consumptions: ref.watch(consumptionRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    posting: ref.watch(consumptionStockPostingServiceProvider),
    stock: ref.watch(consumptionStockReaderProvider),
    clock: ref.watch(consumptionClockProvider),
  ),
);

// --- filters ----------------------------------------------------------------

/// Text typed into a consumption list's search field.
class ConsumptionSearchController extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;

  void clear() => state = '';
}

final consumptionSearchProvider =
    NotifierProvider.autoDispose<ConsumptionSearchController, String>(
      ConsumptionSearchController.new,
    );

/// Status chip on the nurse's list; `null` means "Semua".
///
/// Not used by the branch history: that list is `posted`-only by scope (§14), so a status
/// chip there would offer a filter with one option.
class ConsumptionStatusFilterController extends Notifier<ConsumptionStatus?> {
  @override
  ConsumptionStatus? build() => null;

  void select(ConsumptionStatus? status) =>
      state = state == status ? null : status;

  void clear() => state = null;
}

final consumptionStatusFilterProvider =
    NotifierProvider.autoDispose<
      ConsumptionStatusFilterController,
      ConsumptionStatus?
    >(ConsumptionStatusFilterController.new);

/// Category chip on the candidate list; `null` means "Semua" (§28).
class ConsumptionCategoryFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? categoryId) =>
      state = state == categoryId ? null : categoryId;

  void clear() => state = null;
}

final consumptionCategoryFilterProvider =
    NotifierProvider.autoDispose<ConsumptionCategoryFilterController, String?>(
      ConsumptionCategoryFilterController.new,
    );

/// Text typed into the room-stock search field.
class ConsumptionCandidateSearchController extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;

  void clear() => state = '';
}

final consumptionCandidateSearchProvider =
    NotifierProvider.autoDispose<ConsumptionCandidateSearchController, String>(
      ConsumptionCandidateSearchController.new,
    );

/// The Perawat filter on the branch head's history; `null` means every nurse.
class ConsumptionNurseFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? userId) => state = state == userId ? null : userId;

  void clear() => state = null;
}

final consumptionNurseFilterProvider =
    NotifierProvider.autoDispose<ConsumptionNurseFilterController, String?>(
      ConsumptionNurseFilterController.new,
    );

/// The posted-date filter on the branch head's history, held as an **operational day**.
///
/// A civil date rather than a pair of instants, because that is what the branch head
/// picks. The two UTC instants the filter actually compares against are derived from it
/// through `AppTimeZone` in [consumptionPostedRangeProvider] — never by serialising the
/// date into SQL, which would compare ISO-8601 characters (§31).
class ConsumptionDateFilterController extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void select(DateTime? operationalDate) => state = operationalDate;

  void clear() => state = null;
}

final consumptionDateFilterProvider =
    NotifierProvider.autoDispose<ConsumptionDateFilterController, DateTime?>(
      ConsumptionDateFilterController.new,
    );

/// The selected operational day as the UTC instant range it covers.
///
/// `2026-07-30` GMT+8 runs from `2026-07-29T16:00:00Z` to `2026-07-30T15:59:59.999999Z`,
/// and those are the instants the filter compares `posted_at` against. Resolving it here
/// rather than in the widget is what keeps the list, its counters and the tests deciding
/// the same way.
final consumptionPostedRangeProvider =
    Provider.autoDispose<({DateTime? fromUtc, DateTime? toUtc})>((ref) {
      final day = ref.watch(consumptionDateFilterProvider);
      if (day == null) return (fromUtc: null, toUtc: null);
      return (
        fromUtc: AppTimeZone.startOfOperationalDayUtc(day),
        toUtc: AppTimeZone.endOfOperationalDayUtc(day),
      );
    });

/// The categories the chips are built from — dynamic master data, never hard-coded
/// (spec §4.3).
final consumptionCategoriesProvider =
    FutureProvider.autoDispose<List<MasterCategory>>(
      (ref) => ref.watch(masterDataRepositoryProvider).categories(),
    );

/// The nurses of the acting branch head's branch, for the Perawat filter.
///
/// Derived from the *stored* actor's branch, never from a family argument: a
/// `family<…, String branchId>` here would be a parameter a screen could fill in with
/// somebody else's branch.
final branchNursesProvider = FutureProvider.autoDispose<List<MasterUser>>((
  ref,
) async {
  final actor = await ref.watch(actingUserProvider.future);
  if (actor == null) return const <MasterUser>[];
  if (!ConsumptionAccessPolicy.canReadBranchHistory(actor.role)) {
    return const <MasterUser>[];
  }
  final branchId = actor.branchId;
  if (branchId == null) return const <MasterUser>[];

  final users = await ref.watch(masterDataRepositoryProvider).activeUsers();
  return users
      .where(
        (user) =>
            user.role == ConsumptionStatePolicy.writeRole &&
            user.branchId == branchId,
      )
      .toList(growable: false);
});

// --- rooms (§15/§27) --------------------------------------------------------

/// Every room the acting nurse may record a consumption against.
///
/// One provider, and that is what makes the invariant hold: the list is derived from the
/// *stored* role and branch through `ConsumptionRoomPolicy`, never from anything a widget
/// passes in. A nurse gets their own branch's active rooms; every other role gets an
/// empty list, which is what makes *"a Kepala Cabang has no room to choose"* a fact the UI
/// reads rather than a branch it writes.
///
/// It takes **no family argument**. A `family<…, String branchId>` here would be a
/// parameter a screen could fill in with somebody else's branch — the exact hole §26
/// closes by saying the branch must come from the acting actor.
final consumptionRoomsProvider = FutureProvider.autoDispose<List<ConsumptionRoom>>((
  ref,
) async {
  final actor = await ref.watch(actingUserProvider.future);
  if (actor == null) return const <ConsumptionRoom>[];
  if (!ConsumptionAccessPolicy.canWrite(actor.role)) {
    return const <ConsumptionRoom>[];
  }
  final branchId = actor.branchId;
  // `canWrite` passed and the guards refuse a Perawat without a branch, but the
  // null-check stays because a provider that assumed it would be the one place a data
  // fault became a crash instead of an empty list.
  if (branchId == null) return const <ConsumptionRoom>[];

  return ref.watch(consumptionRepositoryProvider).activeRoomsOfBranch(branchId);
});

/// Every room of the acting **branch head's** branch, for the history's room filter.
///
/// Separate from [consumptionRoomsProvider] because the two answer different questions: a
/// nurse needs the rooms they may *write* in, and a branch head needs the rooms they may
/// *read about*. Sharing one provider would mean one role's empty list was the other's
/// bug.
final branchConsumptionRoomsProvider =
    FutureProvider.autoDispose<List<ConsumptionRoom>>((ref) async {
      final actor = await ref.watch(actingUserProvider.future);
      if (actor == null) return const <ConsumptionRoom>[];
      if (!ConsumptionAccessPolicy.canReadBranchHistory(actor.role)) {
        return const <ConsumptionRoom>[];
      }
      final branchId = actor.branchId;
      if (branchId == null) return const <ConsumptionRoom>[];

      return ref
          .watch(consumptionRepositoryProvider)
          .activeRoomsOfBranch(branchId);
    });

/// Which room the nurse is currently looking at (§27).
///
/// A provider rather than widget state so the room chips, the candidate list and the
/// create button all read the same answer. `null` means "not chosen yet", which
/// [effectiveConsumptionRoomProvider] resolves to the first allowed room — never to
/// "all of them".
class SelectedConsumptionRoomController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? roomId) => state = roomId;

  void clear() => state = null;
}

final selectedConsumptionRoomProvider =
    NotifierProvider.autoDispose<SelectedConsumptionRoomController, String?>(
      SelectedConsumptionRoomController.new,
    );

/// The room the create surface actually works against.
///
/// Two rules, and both are load-bearing:
///
/// * a selection that is **not** in [consumptionRoomsProvider] is discarded rather than
///   honoured, so a stale selection surviving a session switch cannot point a nurse at
///   their previous branch's room;
/// * no selection at all falls back to the first allowed room rather than to nothing, so
///   a branch with one room works without the nurse choosing anything.
final effectiveConsumptionRoomProvider =
    FutureProvider.autoDispose<ConsumptionRoom?>((ref) async {
      final allowed = await ref.watch(consumptionRoomsProvider.future);
      if (allowed.isEmpty) return null;

      final selected = ref.watch(selectedConsumptionRoomProvider);
      for (final room in allowed) {
        if (room.roomId == selected) return room;
      }
      return allowed.first;
    });

/// The one `room` stock location of [roomId], or `null` when it does not resolve to
/// exactly one.
///
/// Returning `null` for both "none" and "two" is deliberate on a *read* path: a screen
/// with no location to read simply shows no candidates. The precise refusal — which of
/// the two it was — belongs to the write path, where `ConsumptionGuards` produces the
/// sentence an administrator can act on (§15).
final consumptionRoomLocationProvider = FutureProvider.autoDispose
    .family<MasterLocation?, String>((ref, roomId) async {
      final locations = await ref
          .watch(consumptionRepositoryProvider)
          .roomLocations(roomId);
      return locations.length == 1 ? locations.single : null;
    });

// --- room stock (§16/§28) ---------------------------------------------------

/// Consumable positions in the currently selected room, live.
///
/// Only positions that may actually be used appear: the repository applies
/// `ConsumptionExpiryPolicy` against [consumptionClockProvider], so an expired batch is
/// absent rather than offered and then refused (§17). A near-expiry batch *is* present,
/// with the flags a badge needs. Everything runs against the local database, so the list
/// keeps working with no network (G-Y1).
final consumptionRoomPositionsProvider =
    StreamProvider.autoDispose<List<RoomStockPosition>>((ref) async* {
      final room = await ref.watch(effectiveConsumptionRoomProvider.future);
      if (room == null) {
        yield const <RoomStockPosition>[];
        return;
      }
      final location = await ref.watch(
        consumptionRoomLocationProvider(room.roomId).future,
      );
      if (location == null) {
        yield const <RoomStockPosition>[];
        return;
      }
      yield* ref
          .watch(consumptionRepositoryProvider)
          .watchRoomPositions(
            roomId: room.roomId,
            roomLocationId: location.id,
            nowUtc: ref.watch(consumptionClockProvider)(),
            categoryId: ref.watch(consumptionCategoryFilterProvider),
          );
    });

/// The candidate picker's results for one **document** — the same rule, capped and
/// searchable.
///
/// Keyed on the consumption id rather than following the room *selector*, because a form
/// is open on one specific document whose room is fixed. Following the selector would
/// offer a nurse editing R1's document the positions of whichever chip happened to be
/// selected on the list screen behind it.
///
/// `activeItemsOnly: true`: adding a line is new work, so a withdrawn product is not
/// offered (G-A4). The document's *existing* lines still read back through the detail
/// stream, which filters neither flag (§33).
final consumptionCandidateSearchResultsProvider = FutureProvider.autoDispose
    .family<List<RoomStockPosition>, String>((ref, consumptionId) async {
      final detail = ref.watch(consumptionDetailProvider(consumptionId)).value;
      if (detail == null) return const <RoomStockPosition>[];

      final location = await ref.watch(
        consumptionRoomLocationProvider(detail.roomId).future,
      );
      if (location == null) return const <RoomStockPosition>[];

      return ref
          .watch(consumptionRepositoryProvider)
          .searchRoomCandidates(
            roomId: detail.roomId,
            roomLocationId: location.id,
            nowUtc: ref.watch(consumptionClockProvider)(),
            searchQuery: ref.watch(consumptionCandidateSearchProvider),
            categoryId: ref.watch(consumptionCategoryFilterProvider),
          );
    });

// --- lists ------------------------------------------------------------------

/// The acting nurse's own consumptions — drafts and posted history (§27).
///
/// Three properties keep this from becoming an IDOR:
///
/// * the scope is `created_by = <acting user>`, resolved in SQL, so another nurse's
///   document is not fetched and then withheld — it is not fetched;
/// * the role and the user id are re-read on every build, so switching user re-runs the
///   query rather than serving the previous nurse's rows from cache;
/// * `autoDispose` tears the subscription down with the screen.
final ownConsumptionListProvider =
    StreamProvider.autoDispose<List<ConsumptionSummary>>((ref) async* {
      final actor = await ref.watch(actingUserProvider.future);
      if (actor == null || !ConsumptionAccessPolicy.canWrite(actor.role)) {
        yield const <ConsumptionSummary>[];
        return;
      }
      final status = ref.watch(consumptionStatusFilterProvider);
      yield* ref
          .watch(consumptionRepositoryProvider)
          .watchOwnList(
            actorUserId: actor.id,
            roomId: ref.watch(selectedConsumptionRoomProvider),
            statuses: status == null ? const <ConsumptionStatus>{} : {status},
            searchQuery: ref.watch(consumptionSearchProvider),
          );
    });

/// The acting branch head's read-only history — **posted only**, branch-scoped (§31).
///
/// The branch comes from the stored actor on every build and travels into the SQL
/// predicate, and the `posted` restriction is in the DAO's scope predicate rather than in
/// a parameter here: a role that may not write consumptions must never see a nurse's
/// unfinished draft, and a rule that depended on this call site passing the right status
/// set would be one edit away from leaking one.
///
/// The date filter is applied **after** the query, on UTC instants, for the reason §31
/// gives: `posted_at` is ISO-8601 TEXT and a SQL range would compare characters.
final branchConsumptionListProvider =
    StreamProvider.autoDispose<List<ConsumptionSummary>>((ref) async* {
      final actor = await ref.watch(actingUserProvider.future);
      if (actor == null ||
          !ConsumptionAccessPolicy.canReadBranchHistory(actor.role)) {
        yield const <ConsumptionSummary>[];
        return;
      }
      final branchId = actor.branchId;
      if (branchId == null) {
        yield const <ConsumptionSummary>[];
        return;
      }

      final range = ref.watch(consumptionPostedRangeProvider);
      final filter = ConsumptionFilter(
        postedFromUtc: range.fromUtc,
        postedToUtc: range.toUtc,
      );

      yield* ref
          .watch(consumptionRepositoryProvider)
          .watchBranchPostedList(
            branchId: branchId,
            roomId: ref.watch(selectedConsumptionRoomProvider),
            createdBy: ref.watch(consumptionNurseFilterProvider),
            searchQuery: ref.watch(consumptionSearchProvider),
          )
          .map(
            (rows) => rows
                .where(
                  (row) => filter.includesPostedAt(row.consumption.postedAt),
                )
                .toList(growable: false),
          );
    });

// --- details ----------------------------------------------------------------

/// One document, scoped to the acting nurse's own.
///
/// Keying the family on the id alone is deliberate: adding the actor to the key would
/// make two entries for the same document look independent while still being resolvable,
/// and the leak this prevents is precisely the one where a stale key survives a session
/// change. `autoDispose` plus the actor read inside the body is what makes the scope
/// follow the session.
final ownConsumptionDetailProvider = StreamProvider.autoDispose
    .family<ConsumptionDetail?, String>((ref, consumptionId) async* {
      final actor = await ref.watch(actingUserProvider.future);
      if (actor == null || !ConsumptionAccessPolicy.canWrite(actor.role)) {
        yield null;
        return;
      }
      yield* ref
          .watch(consumptionRepositoryProvider)
          .watchOwn(consumptionId: consumptionId, actorUserId: actor.id);
    });

/// One **posted** document, scoped to the branch of whoever is acting.
final branchConsumptionDetailProvider = StreamProvider.autoDispose
    .family<ConsumptionDetail?, String>((ref, consumptionId) async* {
      final actor = await ref.watch(actingUserProvider.future);
      if (actor == null ||
          !ConsumptionAccessPolicy.canReadBranchHistory(actor.role)) {
        yield null;
        return;
      }
      final branchId = actor.branchId;
      if (branchId == null) {
        yield null;
        return;
      }
      yield* ref
          .watch(consumptionRepositoryProvider)
          .watchPostedForBranch(
            consumptionId: consumptionId,
            branchId: branchId,
          );
    });

/// One document through whichever scope the acting role has.
///
/// The posted detail screen is shared between the two audiences — a read-only document
/// looks the same whoever is reading it — so this is what lets one page be written once
/// without it having to know which route reached it. A role with neither scope gets
/// `null`, not an unscoped read.
final consumptionDetailProvider = Provider.autoDispose
    .family<AsyncValue<ConsumptionDetail?>, String>((ref, consumptionId) {
      return switch (ref.watch(actingRoleProvider)) {
        UserRole.perawat => ref.watch(
          ownConsumptionDetailProvider(consumptionId),
        ),
        UserRole.kepalaCabang => ref.watch(
          branchConsumptionDetailProvider(consumptionId),
        ),
        _ => const AsyncValue<ConsumptionDetail?>.data(null),
      };
    });

/// What the *document's own* room holds right now, keyed `item|batch`.
///
/// Distinct from [consumptionRoomPositionsProvider], which follows the room **selector**:
/// a form is open on one specific document, and its room is fixed — so a line's available
/// quantity must be read from that room rather than from whichever chip happens to be
/// selected on the list screen behind it.
///
/// This is what lets the form show *"tersedia 5.5 · sisa 3.125"* beside each line (§28).
/// It is a snapshot, exactly like everything else on the form: a draft reserves nothing,
/// and the posting re-reads these balances inside its own transaction (§18).
///
/// `activeItemsOnly: false`: a line the document already holds must keep showing its
/// availability even after the product is withdrawn (§33). What a *new* line may pick is
/// [consumptionCandidateSearchResultsProvider]'s stricter question.
final consumptionDocumentPositionsProvider = FutureProvider.autoDispose
    .family<Map<String, RoomStockPosition>, String>((ref, consumptionId) async {
      final detail = ref.watch(consumptionDetailProvider(consumptionId)).value;
      if (detail == null) return const <String, RoomStockPosition>{};

      final location = await ref.watch(
        consumptionRoomLocationProvider(detail.roomId).future,
      );
      if (location == null) return const <String, RoomStockPosition>{};

      final positions = await ref
          .watch(consumptionRepositoryProvider)
          .roomPositions(
            roomId: detail.roomId,
            roomLocationId: location.id,
            nowUtc: ref.watch(consumptionClockProvider)(),
          );
      return {for (final position in positions) position.positionKey: position};
    });

/// A **one-shot** scoped read of one document, straight from the database.
///
/// The live streams above are what the screens render, and they are the right tool for
/// that. This exists for the one moment a stream is the wrong tool: the instant after the
/// form flushes its pending edits and before it opens the posting confirmation. A stream
/// may not have re-emitted yet, so the dialog would describe the document as it was a
/// moment ago — and the nurse would confirm numbers they never saw.
/// `ref.refresh(…future)` forces the read.
///
/// It is scoped exactly as the streams are: a role with no consumption scope gets `null`,
/// never an unscoped read.
final consumptionDetailSnapshotProvider = FutureProvider.autoDispose
    .family<ConsumptionDetail?, String>((ref, consumptionId) async {
      final repository = ref.watch(consumptionRepositoryProvider);
      final actor = await ref.watch(actingUserProvider.future);
      if (actor == null) return null;
      return switch (actor.role) {
        UserRole.perawat => repository.getOwn(
          consumptionId: consumptionId,
          actorUserId: actor.id,
        ),
        UserRole.kepalaCabang => () {
          final branchId = actor.branchId;
          if (branchId == null) return Future<ConsumptionDetail?>.value();
          return repository.getPostedForBranch(
            consumptionId: consumptionId,
            branchId: branchId,
          );
        }(),
        _ => Future<ConsumptionDetail?>.value(),
      };
    });

/// The document's counters, judged against the feature clock so a badge and the number
/// beside it agree (T-7).
final consumptionProgressProvider = Provider.autoDispose
    .family<ConsumptionProgress?, String>((ref, consumptionId) {
      final detail = ref.watch(consumptionDetailProvider(consumptionId)).value;
      if (detail == null) return null;
      return detail.progressOn(ref.watch(consumptionClockProvider)());
    });

// --- kartu stok (§32) -------------------------------------------------------

/// The ledger rows **this document** wrote, ready for `StockCardList`.
///
/// Scope is *inherited* rather than re-derived: the first thing it does is read
/// [consumptionDetailProvider], which resolves through the acting role's own scoped query.
/// A document the reader may not open yields `null` there, and this yields an empty card —
/// so there is no path by which a stock card reaches movements of a document the reader was
/// refused. Re-implementing the scope here would be a second copy of the rule, and the copy
/// is what eventually differs.
///
/// The document number is supplied from the *scoped* detail, so a row always shows the number
/// of a document the reader is already looking at.
final consumptionLedgerProvider = FutureProvider.autoDispose
    .family<List<StockCardEntry>, String>((ref, consumptionId) async {
      final detail = ref.watch(consumptionDetailProvider(consumptionId)).value;
      if (detail == null) return const <StockCardEntry>[];

      final movements = await ref
          .watch(inventoryRepositoryProvider)
          .movementsByRef(
            refDocType: RefDocType.consumption,
            refDocId: detail.id,
          );

      return buildStockCardEntries(
        movements: movements,
        master: ref.watch(masterDataRepositoryProvider),
        documentNumbers: {detail.id: detail.consumption.docNumber},
      );
    });

/// Which position, on which document — the key of [consumptionPositionStockCardProvider].
///
/// A record rather than a class: Dart gives structural equality and `hashCode` for free,
/// which is the whole of what a Riverpod family key needs. `batchId` is nullable because an
/// item without expiry is a legitimate position (G-E2).
typedef ConsumptionStockCardRequest = ({
  String consumptionId,
  String itemId,
  String? batchId,
});

/// The **kartu stok** of one position at the document's room (§32).
///
/// This is the genuinely mixed card: it shows every movement that touched
/// `(item, batch)` at that room location — the Distribusi that brought the stock in, the
/// opname adjustment that corrected it, the Pemakaian that used it, the Pemusnahan that
/// destroyed it — so a nurse can see where a balance went rather than only what their own
/// document did.
///
/// ### How it stays scoped without inventing a scope
///
/// The room comes from the *document*, which came from [consumptionDetailProvider], which
/// came from the acting role's own scoped query (§14). A nurse therefore reads the card of a
/// room their own document names; a branch head reads the card of a room on a posted document
/// of their branch. Neither can name a room directly, and no role that cannot open the
/// document can reach the card at all — so this adds **no** access to what the guard already
/// granted.
///
/// Document numbers are resolved only for `CONS` rows the reader owns. Every other row —
/// including a Distribusi belonging to the branch head — renders
/// [StockMovementPresenter.unresolvedDocumentLabel] beside its type. The movement is still
/// shown: the stock moved, and a card that hid the row would not add up (§6).
final consumptionPositionStockCardProvider = FutureProvider.autoDispose
    .family<List<StockCardEntry>, ConsumptionStockCardRequest>((
      ref,
      request,
    ) async {
      final detail = ref
          .watch(consumptionDetailProvider(request.consumptionId))
          .value;
      if (detail == null) return const <StockCardEntry>[];

      final location = await ref.watch(
        consumptionRoomLocationProvider(detail.roomId).future,
      );
      if (location == null) return const <StockCardEntry>[];

      final movements = await ref
          .watch(inventoryRepositoryProvider)
          .stockCard(itemId: request.itemId, locationId: location.id);

      // The batch filter is applied here rather than in SQL, because `batch_id IS NULL`
      // cannot be expressed as an equality: a query pinned to the item alone returns the
      // unbatched row *and* every batch of it, and a nurse looking at one batch's history
      // must not be shown another's.
      final position = movements
          .where((movement) => movement.batchId == request.batchId)
          .toList(growable: false);

      // Only the numbers of documents this reader is scoped to. The one document we know
      // they may read is the one they are looking at.
      return buildStockCardEntries(
        movements: position,
        master: ref.watch(masterDataRepositoryProvider),
        documentNumbers: {detail.id: detail.consumption.docNumber},
      );
    });

// --- dashboard (§32) --------------------------------------------------------

/// The numbers the nurse's dashboard card shows.
class ConsumptionDashboardSummary {
  const ConsumptionDashboardSummary({
    required this.draftCount,
    required this.postedTodayCount,
    required this.lowStockPositions,
    required this.nearExpiryPositions,
    required this.expiredPositions,
  });

  const ConsumptionDashboardSummary.empty()
    : draftCount = 0,
      postedTodayCount = 0,
      lowStockPositions = 0,
      nearExpiryPositions = 0,
      expiredPositions = 0;

  /// Drafts not yet posted — the card that says "you have unfinished work".
  final int draftCount;

  /// Documents this nurse posted **today**, in operational time (GMT+8).
  final int postedTodayCount;

  /// Room positions at or below the item's room par level (`items.min_stock_room`).
  final int lowStockPositions;

  /// Positions inside their item's alert window — the orange badge (G-E6).
  final int nearExpiryPositions;

  /// Positions already past their expiry date — the red badge (G-E6). Counted here even
  /// though they can never be *consumed*, because a nurse seeing one needs to tell
  /// somebody: it leaves through a Pemusnahan, which is not their document.
  final int expiredPositions;

  bool get isEmpty =>
      draftCount == 0 &&
      postedTodayCount == 0 &&
      lowStockPositions == 0 &&
      nearExpiryPositions == 0 &&
      expiredPositions == 0;
}

/// The nurse's dashboard card (§32).
///
/// The near-expiry and expired counters come from the **unfiltered** room positions of
/// the selected room, plus one extra read the picker never makes: the expiry-policy
/// filter drops expired positions, so a count of them has to ask the repository for the
/// room's positions *without* it. That second read is what makes G-E6's red badge
/// possible on a screen whose whole job is to never offer those rows.
final nurseConsumptionDashboardProvider =
    FutureProvider.autoDispose<ConsumptionDashboardSummary>((ref) async {
      final actor = await ref.watch(actingUserProvider.future);
      if (actor == null || !ConsumptionAccessPolicy.canWrite(actor.role)) {
        return const ConsumptionDashboardSummary.empty();
      }

      final drafts =
          ref.watch(ownConsumptionListProvider).value ??
          const <ConsumptionSummary>[];
      final nowUtc = ref.watch(consumptionClockProvider)();
      final today = AppTimeZone.operationalDate(nowUtc);

      var draftCount = 0;
      var postedToday = 0;
      for (final summary in drafts) {
        if (summary.consumption.isDraft) {
          draftCount += 1;
          continue;
        }
        final postedAt = summary.consumption.postedAt;
        if (postedAt == null) continue;
        if (AppTimeZone.operationalDate(postedAt) == today) postedToday += 1;
      }

      final positions =
          ref.watch(consumptionRoomPositionsProvider).value ??
          const <RoomStockPosition>[];

      var low = 0;
      var nearExpiry = 0;
      for (final position in positions) {
        if (position.isNearExpiryOn(nowUtc)) nearExpiry += 1;
      }

      // Low stock is a per-**item** question — `min_stock_room` is an item column — so
      // the batches of one product are summed before the comparison. Counting per batch
      // would report a product split across three batches as three shortfalls.
      final byItem = <String, Quantity>{};
      for (final position in positions) {
        byItem[position.itemId] =
            (byItem[position.itemId] ?? Quantity.zero()) + position.qtyOnHand;
      }
      if (byItem.isNotEmpty) {
        final items = await ref
            .watch(masterDataRepositoryProvider)
            .activeItems();
        for (final item in items) {
          final onHand = byItem[item.id];
          if (onHand == null) continue;
          if (onHand <= Quantity.fromWhole(item.minStockRoom)) low += 1;
        }
      }

      // The expired count needs its own read: every provider above hides expired
      // positions by design, and G-E6 asks for them to be *reported*.
      var expired = 0;
      final room = await ref.watch(effectiveConsumptionRoomProvider.future);
      if (room != null) {
        final location = await ref.watch(
          consumptionRoomLocationProvider(room.roomId).future,
        );
        if (location != null) {
          expired = await _expiredPositionCount(
            ref,
            roomLocationId: location.id,
          );
        }
      }

      return ConsumptionDashboardSummary(
        draftCount: draftCount,
        postedTodayCount: postedToday,
        lowStockPositions: low,
        nearExpiryPositions: nearExpiry,
        expiredPositions: expired,
      );
    });

/// Positions in one room that are **past** their expiry date.
///
/// Read through the inventory repository rather than the consumption one, and that is the
/// point: `ConsumptionRepository` has no method that can return an expired position (§24),
/// so counting them has to go somewhere else. Using the balance view keeps the
/// consumption contract honest — there is still no way to *consume* one.
Future<int> _expiredPositionCount(
  Ref ref, {
  required String roomLocationId,
}) async {
  final nowUtc = ref.watch(consumptionClockProvider)();
  final balances = await ref
      .watch(inventoryRepositoryProvider)
      .balancesAtLocation(roomLocationId, positiveOnly: true);
  return balances.where((balance) => balance.isExpiredOn(nowUtc)).length;
}

/// The branch head's dashboard card (§32).
///
/// Deliberately minimal, as §32 asks: how much was used today, which room used the most,
/// and a link to the read-only history. Nothing here is a write affordance.
class BranchConsumptionDashboard {
  const BranchConsumptionDashboard({
    required this.postedTodayCount,
    required this.documentsByRoom,
    required this.totalsByUnit,
  });

  const BranchConsumptionDashboard.empty()
    : postedTodayCount = 0,
      documentsByRoom = const <String, int>{},
      totalsByUnit = const <String, Quantity>{};

  /// Consumptions posted today across the branch, in operational time (GMT+8).
  final int postedTodayCount;

  /// `roomId → document count` for today. **Document counts, not quantities**, and §32
  /// says why: quantities of different units are not addable, so "the room that used the
  /// most" has no single answer in units. Counting documents is a number that means
  /// something on its own.
  final Map<String, int> documentsByRoom;

  /// Today's totals grouped by unit, for the cards that can show them honestly.
  final Map<String, Quantity> totalsByUnit;

  bool get isEmpty => postedTodayCount == 0;

  /// The room with the most posted documents today, or `null` when there are none.
  ///
  /// Ties are broken by room id so the answer is deterministic — a dashboard that
  /// reported a different "busiest room" on each rebuild would be worse than one that
  /// reported none.
  String? get busiestRoomId {
    String? best;
    var bestCount = 0;
    final ids = documentsByRoom.keys.toList()..sort();
    for (final roomId in ids) {
      final count = documentsByRoom[roomId]!;
      if (count > bestCount) {
        best = roomId;
        bestCount = count;
      }
    }
    return best;
  }
}

final branchConsumptionDashboardProvider =
    Provider.autoDispose<BranchConsumptionDashboard>((ref) {
      if (ref.watch(actingRoleProvider) != UserRole.kepalaCabang) {
        return const BranchConsumptionDashboard.empty();
      }
      final rows =
          ref.watch(branchConsumptionListProvider).value ??
          const <ConsumptionSummary>[];
      final nowUtc = ref.watch(consumptionClockProvider)();
      final today = AppTimeZone.operationalDate(nowUtc);

      var postedToday = 0;
      final byRoom = <String, int>{};
      for (final summary in rows) {
        final postedAt = summary.consumption.postedAt;
        if (postedAt == null) continue;
        if (AppTimeZone.operationalDate(postedAt) != today) continue;
        postedToday += 1;
        byRoom[summary.roomId] = (byRoom[summary.roomId] ?? 0) + 1;
      }

      return BranchConsumptionDashboard(
        postedTodayCount: postedToday,
        documentsByRoom: byRoom,
        // Left empty here rather than summed from the summaries: a list row carries
        // counts, not per-unit quantities, and inventing a total from them would be a
        // number nobody could reconcile. A screen that needs it opens the document.
        totalsByUnit: const <String, Quantity>{},
      );
    });

// --- controllers ------------------------------------------------------------

/// Creates a draft and hands its id back so the caller can navigate to the form.
///
/// The `AsyncValue<String?>` state is the double-tap guard: while it is loading the button
/// is disabled, so two taps cannot produce two documents.
class CreateConsumptionController extends AsyncNotifier<String?> {
  @override
  String? build() => null;

  Future<String?> create({required String roomId, String? note}) async {
    if (state.isLoading) return null;

    final session = ref.read(currentSessionValueProvider);
    if (session == null) return null;

    state = const AsyncValue<String?>.loading();
    final result = await AsyncValue.guard(() async {
      final consumption = await ref
          .read(createConsumptionUseCaseProvider)
          .call(actorUserId: session.userId, roomId: roomId, note: note);
      return consumption.id;
    });
    state = result;
    return result.value;
  }
}

final createConsumptionControllerProvider =
    AsyncNotifierProvider<CreateConsumptionController, String?>(
      CreateConsumptionController.new,
    );

/// Edits one draft and posts it.
///
/// The state is `AsyncValue<void>`: the screen needs to know only whether an action is in
/// flight and whether the last one failed. The document itself arrives through
/// [consumptionDetailProvider], which is a live stream, so a successful write is
/// reflected without this controller having to carry it.
class ConsumptionEditorController extends AsyncNotifier<void> {
  @override
  void build() {}

  /// The last posted result, so the screen can say what it did. Reset on every new
  /// action.
  ConsumptionPostingResult? lastPosting;

  Future<bool> updateNote({
    required String consumptionId,
    required String? note,
  }) {
    return _run(
      () => ref
          .read(updateConsumptionHeaderUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            consumptionId: consumptionId,
            note: note,
          ),
    );
  }

  Future<bool> addPosition({
    required String consumptionId,
    required String itemId,
    String? batchId,
    required Quantity qty,
    String? note,
  }) {
    return _run(
      () => ref
          .read(addConsumptionLineUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            consumptionId: consumptionId,
            itemId: itemId,
            batchId: batchId,
            qty: qty,
            note: note,
          ),
    );
  }

  Future<bool> updateLine({
    required String consumptionId,
    required String lineId,
    required Quantity qty,
    String? note,
  }) {
    return _run(
      () => ref
          .read(updateConsumptionLineUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            consumptionId: consumptionId,
            lineId: lineId,
            qty: qty,
            note: note,
          ),
    );
  }

  Future<bool> removeLine({
    required String consumptionId,
    required String lineId,
  }) {
    return _run(
      () => ref
          .read(removeConsumptionLineUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            consumptionId: consumptionId,
            lineId: lineId,
          ),
    );
  }

  /// Posts the document. Irreversible: the room balance falls the moment this commits and
  /// nothing anywhere gains the stock (§19), which is why the screen confirms first.
  Future<bool> post(String consumptionId) async {
    if (state.isLoading) return false;

    lastPosting = null;
    state = const AsyncValue<void>.loading();
    final result = await AsyncValue.guard(() async {
      lastPosting = await ref
          .read(postConsumptionUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            consumptionId: consumptionId,
          );
    });
    state = result;
    return !result.hasError;
  }

  CurrentUserSession _requireSession() {
    final session = ref.read(currentSessionValueProvider);
    if (session == null) {
      throw StateError('Tidak ada sesi pengguna aktif.');
    }
    return session;
  }

  /// Runs one action behind the in-flight guard and records the outcome. Returns whether
  /// it succeeded, so the screen can close a sheet only on success.
  Future<bool> _run(Future<void> Function() action) async {
    if (state.isLoading) return false;

    state = const AsyncValue<void>.loading();
    final result = await AsyncValue.guard(action);
    state = result;
    return !result.hasError;
  }
}

final consumptionEditorControllerProvider =
    AsyncNotifierProvider<ConsumptionEditorController, void>(
      ConsumptionEditorController.new,
    );

/// Whether the acting user may build a room selector at all — the predicate a widget
/// asks instead of comparing roles itself.
final canRecordConsumptionProvider = Provider.autoDispose<bool>((ref) {
  final role = ref.watch(actingRoleProvider);
  return role != null && ConsumptionRoomPolicy.canConsume(role);
});
