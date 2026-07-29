import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/database_providers.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/session/current_user_session.dart';
import '../../../../core/time/app_time_zone.dart';
import '../../../inventory/presentation/providers/inventory_providers.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/presentation/providers/master_providers.dart';
import '../../data/repositories/drift_opname_repository.dart';
import '../../domain/models/opname_models.dart';
import '../../domain/repositories/opname_repository.dart';
import '../../domain/use_cases/add_stock_opname_line_use_case.dart';
import '../../domain/use_cases/create_stock_opname_use_case.dart';
import '../../domain/use_cases/remove_stock_opname_line_use_case.dart';
import '../../domain/use_cases/review_stock_opname_use_case.dart';
import '../../domain/use_cases/submit_stock_opname_use_case.dart';
import '../../domain/use_cases/update_stock_opname_line_use_case.dart';

// --- wiring -----------------------------------------------------------------

final opnameRepositoryProvider = Provider<OpnameRepository>(
  (ref) => DriftOpnameRepository(ref.watch(opnameDaoProvider)),
);

final createStockOpnameUseCaseProvider = Provider<CreateStockOpnameUseCase>(
  (ref) => CreateStockOpnameUseCase(
    opnames: ref.watch(opnameRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    inventory: ref.watch(inventoryRepositoryProvider),
  ),
);

final updateStockOpnameLineUseCaseProvider =
    Provider<UpdateStockOpnameLineUseCase>(
      (ref) => UpdateStockOpnameLineUseCase(
        opnames: ref.watch(opnameRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
      ),
    );

final addStockOpnameLineUseCaseProvider = Provider<AddStockOpnameLineUseCase>(
  (ref) => AddStockOpnameLineUseCase(
    opnames: ref.watch(opnameRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    inventory: ref.watch(inventoryRepositoryProvider),
  ),
);

final removeStockOpnameLineUseCaseProvider =
    Provider<RemoveStockOpnameLineUseCase>(
      (ref) => RemoveStockOpnameLineUseCase(
        opnames: ref.watch(opnameRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
      ),
    );

final submitStockOpnameUseCaseProvider = Provider<SubmitStockOpnameUseCase>(
  (ref) => SubmitStockOpnameUseCase(
    opnames: ref.watch(opnameRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
  ),
);

final reviewStockOpnameUseCaseProvider = Provider<ReviewStockOpnameUseCase>(
  (ref) => ReviewStockOpnameUseCase(
    opnames: ref.watch(opnameRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    posting: ref.watch(stockPostingServiceProvider),
  ),
);

// --- period -----------------------------------------------------------------

/// The ISO week a count created right now would belong to, in operational time.
///
/// Riverpod caches this like any other provider, so a tablet left open across
/// midnight would keep showing the previous week. The list screen therefore
/// invalidates it on refresh and whenever the app returns to the foreground.
///
/// This value drives *display and affordances only*. The authoritative period
/// is recomputed inside `CreateStockOpnameUseCase` at the moment a document is
/// created, so a stale cache here can never file a count under the wrong week
/// — at worst it offers a button that the use case then refuses.
class OperationalPeriod {
  const OperationalPeriod({
    required this.year,
    required this.week,
    required this.date,
  });

  final int year;
  final int week;

  /// The GMT+8 calendar date this period was derived from.
  final DateTime date;

  String get label => '$year-W${week.toString().padLeft(2, '0')}';
}

final currentOperationalPeriodProvider = Provider<OperationalPeriod>((ref) {
  final date = AppTimeZone.operationalDate(DateTime.now().toUtc());
  return OperationalPeriod(
    year: AppTimeZone.isoWeekYear(date),
    week: AppTimeZone.isoWeekNumber(date),
    date: date,
  );
});

// --- lists and details ------------------------------------------------------

/// Rooms of the acting user's branch — the rooms a nurse may count.
final sessionRoomsProvider = FutureProvider<List<MasterRoom>>((ref) async {
  final session = ref.watch(currentSessionValueProvider);
  final branchId = session?.branchId;
  if (branchId == null) return const <MasterRoom>[];
  return ref
      .watch(masterDataRepositoryProvider)
      .activeRooms(branchId: branchId);
});

/// Which room the nurse's list is filtered to; `null` means every room of the
/// branch.
class SelectedRoomController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? roomId) => state = roomId;
}

final selectedRoomIdProvider =
    NotifierProvider<SelectedRoomController, String?>(
      SelectedRoomController.new,
    );

/// The nurse's own opname history, newest period first.
final nurseOpnameListProvider = StreamProvider<List<StockOpnameSummary>>((ref) {
  final session = ref.watch(currentSessionValueProvider);
  final branchId = session?.branchId;
  if (session == null || branchId == null) {
    return Stream.value(const <StockOpnameSummary>[]);
  }

  return ref
      .watch(opnameRepositoryProvider)
      .watchList(
        StockOpnameFilter(
          branchId: branchId,
          roomId: ref.watch(selectedRoomIdProvider),
        ),
      );
});

/// The Kepala Cabang review inbox: submitted documents of their branch only
/// (G-R2).
final submittedOpnameListProvider = StreamProvider<List<StockOpnameSummary>>((
  ref,
) {
  final session = ref.watch(currentSessionValueProvider);
  final branchId = session?.branchId;
  if (session == null || branchId == null || !session.canReviewOpname) {
    return Stream.value(const <StockOpnameSummary>[]);
  }
  return ref
      .watch(opnameRepositoryProvider)
      .watchList(submittedForBranch(branchId));
});

final opnameDetailProvider = StreamProvider.family<StockOpnameDetail?, String>(
  (ref, opnameId) => ref.watch(opnameRepositoryProvider).watchDetail(opnameId),
);

/// Whether the given room already has a count this week — the reason
/// "+ Opname Minggu Ini" is enabled or not (G-O1).
final roomOpnameForCurrentWeekProvider =
    FutureProvider.family<StockOpname?, String>((ref, roomId) {
      final period = ref.watch(currentOperationalPeriodProvider);
      return ref
          .watch(opnameRepositoryProvider)
          .findForRoomAndPeriod(
            roomId: roomId,
            periodYear: period.year,
            periodWeek: period.week,
          );
    });

// --- filtering --------------------------------------------------------------

/// Selected category chip; `null` is "Semua".
class OpnameCategoryFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  /// Tapping the active chip clears the filter, which is what "Semua" means.
  void select(String? categoryId) =>
      state = state == categoryId ? null : categoryId;

  void clear() => state = null;
}

final opnameCategoryFilterProvider =
    NotifierProvider<OpnameCategoryFilterController, String?>(
      OpnameCategoryFilterController.new,
    );

/// Text typed into the search field above the item list.
class OpnameSearchQueryController extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;

  void clear() => state = '';
}

final opnameSearchQueryProvider =
    NotifierProvider<OpnameSearchQueryController, String>(
      OpnameSearchQueryController.new,
    );

final opnameLineFilterProvider = Provider<StockOpnameFilter>(
  (ref) => StockOpnameFilter(
    categoryId: ref.watch(opnameCategoryFilterProvider),
    searchQuery: ref.watch(opnameSearchQueryProvider),
  ),
);

final itemCategoriesProvider = FutureProvider<List<MasterCategory>>(
  (ref) => ref.watch(masterDataRepositoryProvider).categories(),
);

/// Offline typeahead results for the SearchableDropdown. Keyed by the query so
/// each keystroke reuses the cached result of a repeated query.
final addableItemSearchProvider =
    FutureProvider.family<List<MasterItem>, String>((ref, query) {
      if (query.trim().isEmpty) return Future.value(const <MasterItem>[]);
      return ref
          .watch(opnameRepositoryProvider)
          .searchAddableItems(
            query: query,
            categoryId: ref.watch(opnameCategoryFilterProvider),
          );
    });

/// Batches selectable for an expiry-tracked item, nearest expiry first.
final itemBatchOptionsProvider =
    FutureProvider.family<List<MasterBatch>, String>(
      (ref, itemId) =>
          ref.watch(masterDataRepositoryProvider).batchesOfItem(itemId),
    );

// --- controllers ------------------------------------------------------------

/// Creates this week's document for a room.
///
/// The `AsyncValue<String?>` state is the double-tap guard: while it is
/// loading, the button is disabled, so two taps cannot produce two documents
/// (and if they somehow did, G-O1 would reject the second).
class CreateOpnameController extends AsyncNotifier<String?> {
  @override
  String? build() => null;

  Future<String?> create(String roomId) async {
    if (state.isLoading) return null;

    final session = ref.read(currentSessionValueProvider);
    if (session == null) return null;

    state = const AsyncValue<String?>.loading();
    final result = await AsyncValue.guard(() async {
      final opname = await ref
          .read(createStockOpnameUseCaseProvider)
          .call(actorUserId: session.userId, roomId: roomId);
      return opname.id;
    });
    state = result;

    ref.invalidate(roomOpnameForCurrentWeekProvider(roomId));
    return result.value;
  }
}

final createOpnameControllerProvider =
    AsyncNotifierProvider<CreateOpnameController, String?>(
      CreateOpnameController.new,
    );

/// Edits and submits a draft.
///
/// The state is `AsyncValue<void>`: the screen needs to know only whether an
/// action is in flight and whether the last one failed. The document itself
/// arrives through [opnameDetailProvider], which is a live stream — so a
/// successful write is reflected without this controller having to carry it.
///
/// One instance serves whichever document is open, because only one form is
/// on screen at a time and the in-flight guard is naturally global: while a
/// save is running no other edit should start.
class OpnameFormController extends AsyncNotifier<void> {
  @override
  void build() {}

  Future<bool> saveLine({
    required String lineId,
    required Quantity countedQty,
    String? note,
  }) {
    return _run(
      () => ref
          .read(updateStockOpnameLineUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            lineId: lineId,
            countedQty: countedQty,
            note: note,
          ),
    );
  }

  Future<bool> addLine({
    required String opnameId,
    required String itemId,
    String? batchId,
    required Quantity countedQty,
    String? note,
  }) {
    return _run(
      () => ref
          .read(addStockOpnameLineUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            opnameId: opnameId,
            itemId: itemId,
            batchId: batchId,
            countedQty: countedQty,
            note: note,
          ),
    );
  }

  Future<bool> removeLine(String lineId) {
    return _run(
      () => ref
          .read(removeStockOpnameLineUseCaseProvider)
          .call(actorUserId: _requireSession().userId, lineId: lineId),
    );
  }

  Future<bool> submit(String opnameId) {
    return _run(
      () => ref
          .read(submitStockOpnameUseCaseProvider)
          .call(actorUserId: _requireSession().userId, opnameId: opnameId),
    );
  }

  CurrentUserSession _requireSession() {
    final session = ref.read(currentSessionValueProvider);
    if (session == null) {
      throw StateError('Tidak ada sesi pengguna aktif.');
    }
    return session;
  }

  /// Runs one action behind the in-flight guard and records the outcome.
  /// Returns whether it succeeded, so the screen can navigate only on success.
  Future<bool> _run(Future<void> Function() action) async {
    if (state.isLoading) return false;

    state = const AsyncValue<void>.loading();
    final result = await AsyncValue.guard(action);
    state = result;
    return !result.hasError;
  }
}

final opnameFormControllerProvider =
    AsyncNotifierProvider<OpnameFormController, void>(OpnameFormController.new);

/// Performs the Kepala Cabang's "Review & Kunci".
///
/// Same guard as the form controller, for the same reason: the review posts
/// stock, and a double tap must not attempt it twice. The second attempt would
/// be rejected by the state machine anyway, but the user should never see that
/// error for a button they pressed twice.
class ReviewOpnameController extends AsyncNotifier<void> {
  @override
  void build() {}

  Future<bool> review(String opnameId) async {
    if (state.isLoading) return false;

    final session = ref.read(currentSessionValueProvider);
    if (session == null) return false;

    state = const AsyncValue<void>.loading();
    final result = await AsyncValue.guard(
      () => ref
          .read(reviewStockOpnameUseCaseProvider)
          .call(actorUserId: session.userId, opnameId: opnameId),
    );
    state = result;
    return !result.hasError;
  }
}

final reviewOpnameControllerProvider =
    AsyncNotifierProvider<ReviewOpnameController, void>(
      ReviewOpnameController.new,
    );
