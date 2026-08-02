import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/database_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/session/acting_user_providers.dart';
import '../../../../core/session/current_user_session.dart';
import '../../../inventory/domain/services/stock_posting_service.dart';
import '../../../inventory/presentation/providers/inventory_providers.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/presentation/providers/master_providers.dart';
import '../../data/repositories/drift_disposal_repository.dart';
import '../../domain/models/disposal_models.dart';
import '../../domain/repositories/disposal_repository.dart';
import '../../domain/services/disposal_access_policy.dart';
import '../../domain/services/disposal_location_policy.dart';
import '../../domain/services/disposal_stock_reader.dart';
import '../../domain/use_cases/add_disposal_line_use_case.dart';
import '../../domain/use_cases/create_disposal_use_case.dart';
import '../../domain/use_cases/post_disposal_use_case.dart';
import '../../domain/use_cases/remove_disposal_line_use_case.dart';
import '../../domain/use_cases/update_disposal_header_use_case.dart';
import '../../domain/use_cases/update_disposal_line_use_case.dart';

// --- clock ------------------------------------------------------------------

/// The UTC clock the whole feature reads "now" from.
///
/// A provider rather than a bare `DateTime.now()` because this milestone's entire
/// eligibility rule is a function of the current operational day: G-E7 asks which
/// day it is, and a batch that may not be destroyed today may be destroyed
/// tomorrow. Overriding this one provider moves the candidate list, the badges, the
/// dashboard counters and the `posted_at` stamp together — which is what keeps them
/// consistent (T-7).
final disposalClockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

// --- wiring -----------------------------------------------------------------

final disposalRepositoryProvider = Provider<DisposalRepository>(
  (ref) => DriftDisposalRepository(ref.watch(disposalDaoProvider)),
);

final disposalStockReaderProvider = Provider<DisposalStockReader>(
  (ref) => DisposalStockReader(ref.watch(inventoryRepositoryProvider)),
);

/// The posting service the disposal uses, wired to [disposalClockProvider].
///
/// Deliberately not `stockPostingServiceProvider`: that one reads the wall clock,
/// and the expiry decisions behind a posting have to be made against the same "now"
/// the rest of the screen used.
final disposalStockPostingServiceProvider = Provider<StockPostingService>(
  (ref) => StockPostingService(
    inventory: ref.watch(inventoryRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    clock: ref.watch(disposalClockProvider),
  ),
);

final createDisposalUseCaseProvider = Provider<CreateDisposalUseCase>(
  (ref) => CreateDisposalUseCase(
    disposals: ref.watch(disposalRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    clock: ref.watch(disposalClockProvider),
  ),
);

final updateDisposalHeaderUseCaseProvider =
    Provider<UpdateDisposalHeaderUseCase>(
      (ref) => UpdateDisposalHeaderUseCase(
        disposals: ref.watch(disposalRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
      ),
    );

final addDisposalLineUseCaseProvider = Provider<AddDisposalLineUseCase>(
  (ref) => AddDisposalLineUseCase(
    disposals: ref.watch(disposalRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    stock: ref.watch(disposalStockReaderProvider),
    clock: ref.watch(disposalClockProvider),
  ),
);

final updateDisposalLineUseCaseProvider = Provider<UpdateDisposalLineUseCase>(
  (ref) => UpdateDisposalLineUseCase(
    disposals: ref.watch(disposalRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    stock: ref.watch(disposalStockReaderProvider),
    clock: ref.watch(disposalClockProvider),
  ),
);

final removeDisposalLineUseCaseProvider = Provider<RemoveDisposalLineUseCase>(
  (ref) => RemoveDisposalLineUseCase(
    disposals: ref.watch(disposalRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
  ),
);

final postDisposalUseCaseProvider = Provider<PostDisposalUseCase>(
  (ref) => PostDisposalUseCase(
    disposals: ref.watch(disposalRepositoryProvider),
    master: ref.watch(masterDataRepositoryProvider),
    posting: ref.watch(disposalStockPostingServiceProvider),
    stock: ref.watch(disposalStockReaderProvider),
    outbox: ref.watch(syncOutboxWriterProvider),
    clock: ref.watch(disposalClockProvider),
  ),
);

// --- filters ----------------------------------------------------------------

/// Text typed into a disposal list's search field.
class DisposalSearchController extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;

  void clear() => state = '';
}

final disposalSearchProvider =
    NotifierProvider.autoDispose<DisposalSearchController, String>(
      DisposalSearchController.new,
    );

/// Status chip on the list; `null` means "Semua".
class DisposalStatusFilterController extends Notifier<DisposalStatus?> {
  @override
  DisposalStatus? build() => null;

  void select(DisposalStatus? status) =>
      state = state == status ? null : status;

  void clear() => state = null;
}

final disposalStatusFilterProvider =
    NotifierProvider.autoDispose<
      DisposalStatusFilterController,
      DisposalStatus?
    >(DisposalStatusFilterController.new);

/// Category chip on the candidate list; `null` means "Semua" (§28/§29).
class DisposalCategoryFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? categoryId) =>
      state = state == categoryId ? null : categoryId;

  void clear() => state = null;
}

final disposalCategoryFilterProvider =
    NotifierProvider.autoDispose<DisposalCategoryFilterController, String?>(
      DisposalCategoryFilterController.new,
    );

/// Text typed into the expired-stock search field.
class DisposalCandidateSearchController extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;

  void clear() => state = '';
}

final disposalCandidateSearchProvider =
    NotifierProvider.autoDispose<DisposalCandidateSearchController, String>(
      DisposalCandidateSearchController.new,
    );

/// The categories the chips are built from — dynamic master data, never hard-coded
/// (spec §4.3).
final disposalCategoriesProvider =
    FutureProvider.autoDispose<List<MasterCategory>>(
      (ref) => ref.watch(masterDataRepositoryProvider).categories(),
    );

// --- source locations (§15/§29) ---------------------------------------------

/// Every location the acting user may raise a disposal against.
///
/// One provider for both screens, and that is what makes the invariant hold: the
/// list is derived from the *stored* role and branch through
/// `DisposalLocationPolicy`, never from anything a widget passes in. A warehouse
/// account gets the central-warehouse locations; a branch head gets their own store
/// and rooms; every other role gets an empty list, which is what makes *"Perawat has
/// no source to choose"* a fact the UI reads rather than a branch it writes.
///
/// It takes **no family argument**. A `family<…, String branchId>` here would be a
/// parameter a screen could fill in with somebody else's branch — the exact hole
/// §27 closes by saying the branch must come from the acting actor.
final disposalSourceLocationsProvider = FutureProvider.autoDispose<List<MasterLocation>>((
  ref,
) async {
  final actor = await ref.watch(actingUserProvider.future);
  if (actor == null) return const <MasterLocation>[];
  if (!DisposalAccessPolicy.canWrite(actor.role)) {
    return const <MasterLocation>[];
  }

  final repository = ref.watch(disposalRepositoryProvider);
  final locations = DisposalLocationPolicy.requiresBranchScope(actor.role)
      // `actor.branchId` is non-null: `canWrite` passed and the guards refuse a
      // branch-scoped account without one, but the null-check stays because a
      // provider that assumed it would be the one place a data fault became a
      // crash instead of an empty list.
      ? (actor.branchId == null
            ? const <MasterLocation>[]
            : await repository.branchSourceLocations(actor.branchId!))
      : await repository.warehouseSourceLocations();

  // Filtered through the policy rather than trusted from the query: the SQL and
  // the policy agree today, and this is what keeps them agreeing.
  return DisposalLocationPolicy.allowedSources(
    actor: actor,
    locations: locations,
  );
});

/// Which of those the branch head is currently looking at (§29).
///
/// A provider rather than widget state so the location chips, the candidate list and
/// the draft list all read the same answer. `null` means "not chosen yet", which
/// [effectiveDisposalSourceProvider] resolves to the first allowed location — never
/// to "all of them".
class SelectedDisposalSourceController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? locationId) => state = locationId;

  void clear() => state = null;
}

final selectedDisposalSourceProvider =
    NotifierProvider.autoDispose<SelectedDisposalSourceController, String?>(
      SelectedDisposalSourceController.new,
    );

/// The source the screens actually work against.
///
/// Two rules, and both are load-bearing:
///
/// * a selection that is **not** in [disposalSourceLocationsProvider] is discarded
///   rather than honoured, so a stale selection surviving a session switch cannot
///   point a branch head at their previous branch's store;
/// * no selection at all falls back to the first allowed location rather than to
///   nothing, so the warehouse screen — which has exactly one source and no selector
///   — works without the user choosing anything.
final effectiveDisposalSourceProvider =
    FutureProvider.autoDispose<MasterLocation?>((ref) async {
      final allowed = await ref.watch(disposalSourceLocationsProvider.future);
      if (allowed.isEmpty) return null;

      final selected = ref.watch(selectedDisposalSourceProvider);
      for (final location in allowed) {
        if (location.id == selected) return location;
      }
      return allowed.first;
    });

// --- expired stock (§17/§28/§29) --------------------------------------------

/// Expired positions at the currently selected source, live.
///
/// Only positions past their expiry date appear: the repository applies
/// `DisposalExpiryPolicy` against [disposalClockProvider], so an item that is merely
/// near expiry is absent rather than offered and then refused (§28). Everything runs
/// against the local database, so the list keeps working with no network (G-Y1).
final disposalExpiredPositionsProvider =
    StreamProvider.autoDispose<List<ExpiredStockPosition>>((ref) async* {
      final source = await ref.watch(effectiveDisposalSourceProvider.future);
      if (source == null) {
        yield const <ExpiredStockPosition>[];
        return;
      }
      yield* ref
          .watch(disposalRepositoryProvider)
          .watchExpiredPositions(
            sourceLocationId: source.id,
            nowUtc: ref.watch(disposalClockProvider)(),
            categoryId: ref.watch(disposalCategoryFilterProvider),
          );
    });

/// The candidate picker's results — the same rule, capped and searchable.
final disposalCandidateSearchResultsProvider =
    FutureProvider.autoDispose<List<ExpiredStockPosition>>((ref) async {
      final source = await ref.watch(effectiveDisposalSourceProvider.future);
      if (source == null) return const <ExpiredStockPosition>[];

      return ref
          .watch(disposalRepositoryProvider)
          .searchExpiredCandidates(
            sourceLocationId: source.id,
            nowUtc: ref.watch(disposalClockProvider)(),
            searchQuery: ref.watch(disposalCandidateSearchProvider),
            categoryId: ref.watch(disposalCategoryFilterProvider),
          );
    });

// --- lists ------------------------------------------------------------------

/// The warehouse's own disposals (§28).
///
/// Three properties keep this from becoming an IDOR:
///
/// * the scope is a **type** predicate resolved in SQL, so a branch document is not
///   fetched and then withheld — it is not fetched;
/// * the role is re-checked on every build, so switching user re-runs the query
///   rather than serving the previous role's rows from cache;
/// * `autoDispose` tears the subscription down with the screen.
final warehouseDisposalListProvider =
    StreamProvider.autoDispose<List<DisposalSummary>>((ref) {
      if (ref.watch(actingRoleProvider) != UserRole.warehouse) {
        return Stream.value(const <DisposalSummary>[]);
      }
      final status = ref.watch(disposalStatusFilterProvider);
      return ref
          .watch(disposalRepositoryProvider)
          .watchListForWarehouse(
            statuses: status == null ? const <DisposalStatus>{} : {status},
            searchQuery: ref.watch(disposalSearchProvider),
          );
    });

/// The acting branch head's own disposals, drafts and posted (§29, G-R2).
///
/// The branch comes from [actingBranchIdProvider] on **every build** and travels
/// into the SQL predicate. A role that may not write disposals emits an empty list
/// rather than a cross-branch read, so the route guard is never the only thing
/// standing between a warehouse session and a branch's documents.
final branchDisposalListProvider =
    StreamProvider.autoDispose<List<DisposalSummary>>((ref) {
      final branchId = ref.watch(actingBranchIdProvider);
      if (branchId == null) return Stream.value(const <DisposalSummary>[]);
      if (ref.watch(actingRoleProvider) != UserRole.kepalaCabang) {
        return Stream.value(const <DisposalSummary>[]);
      }
      final status = ref.watch(disposalStatusFilterProvider);
      return ref
          .watch(disposalRepositoryProvider)
          .watchListForBranch(
            branchId: branchId,
            statuses: status == null ? const <DisposalStatus>{} : {status},
            searchQuery: ref.watch(disposalSearchProvider),
          );
    });

// --- details ----------------------------------------------------------------

/// One document, scoped to Warehouse Pusat.
///
/// Keying the family on the id alone is deliberate: adding the scope to the key
/// would make two entries for the same document look independent while still being
/// resolvable, and the leak this prevents is precisely the one where a stale key
/// survives a session change.
final warehouseDisposalDetailProvider = StreamProvider.autoDispose
    .family<DisposalDetail?, String>((ref, disposalId) {
      if (ref.watch(actingRoleProvider) != UserRole.warehouse) {
        return Stream.value(null);
      }
      return ref
          .watch(disposalRepositoryProvider)
          .watchForWarehouse(disposalId);
    });

/// One document, scoped to the branch of whoever is acting.
final branchDisposalDetailProvider = StreamProvider.autoDispose
    .family<DisposalDetail?, String>((ref, disposalId) {
      final branchId = ref.watch(actingBranchIdProvider);
      if (branchId == null) return Stream.value(null);
      if (ref.watch(actingRoleProvider) != UserRole.kepalaCabang) {
        return Stream.value(null);
      }
      return ref
          .watch(disposalRepositoryProvider)
          .watchForBranch(disposalId: disposalId, branchId: branchId);
    });

/// One document through whichever scope the acting role has.
///
/// The screens are shared between the two sides — a posted detail looks the same
/// whoever is reading it — so this is what lets one page be written once without it
/// having to know which route reached it. A role with no disposal scope gets `null`,
/// not an unscoped read.
final disposalDetailProvider = Provider.autoDispose
    .family<AsyncValue<DisposalDetail?>, String>((ref, disposalId) {
      return switch (ref.watch(actingRoleProvider)) {
        UserRole.warehouse => ref.watch(
          warehouseDisposalDetailProvider(disposalId),
        ),
        UserRole.kepalaCabang => ref.watch(
          branchDisposalDetailProvider(disposalId),
        ),
        _ => const AsyncValue<DisposalDetail?>.data(null),
      };
    });

/// What the *document's own* source shelf holds right now, keyed `item|batch`.
///
/// Distinct from [disposalExpiredPositionsProvider], which follows the source
/// **selector**: a form is open on one specific document, and its source is fixed —
/// so a line's available quantity must be read from that shelf rather than from
/// whichever chip happens to be selected on the list screen behind it.
///
/// This is what lets the form show *"tersedia 5.5 · sisa 3.125"* beside each line
/// (§30). It is a snapshot, exactly like everything else on the form: a draft
/// reserves nothing, and the posting re-reads these balances inside its own
/// transaction (§18).
final disposalDocumentPositionsProvider = FutureProvider.autoDispose
    .family<Map<String, ExpiredStockPosition>, String>((ref, disposalId) async {
      final detail = ref.watch(disposalDetailProvider(disposalId)).value;
      if (detail == null) return const <String, ExpiredStockPosition>{};

      final positions = await ref
          .watch(disposalRepositoryProvider)
          .expiredPositions(
            sourceLocationId: detail.sourceLocationId,
            nowUtc: ref.watch(disposalClockProvider)(),
          );
      return {for (final position in positions) position.positionKey: position};
    });

/// A **one-shot** scoped read of one document, straight from the database.
///
/// The live streams above are what the screens render, and they are the right tool
/// for that. This exists for the one moment a stream is the wrong tool: the instant
/// after the form flushes its pending edits and before it opens the posting
/// confirmation. A stream may not have re-emitted yet, so the dialog would describe
/// the document as it was a moment ago — and the user would confirm numbers they
/// never saw. `ref.refresh(…future)` forces the read.
///
/// It is scoped exactly as the streams are: a role with no disposal scope gets
/// `null`, never an unscoped read.
final disposalDetailSnapshotProvider = FutureProvider.autoDispose
    .family<DisposalDetail?, String>((ref, disposalId) async {
      final repository = ref.watch(disposalRepositoryProvider);
      return switch (ref.watch(actingRoleProvider)) {
        UserRole.warehouse => repository.getForWarehouse(disposalId),
        UserRole.kepalaCabang => () {
          final branchId = ref.watch(actingBranchIdProvider);
          if (branchId == null) return Future<DisposalDetail?>.value();
          return repository.getForBranch(
            disposalId: disposalId,
            branchId: branchId,
          );
        }(),
        _ => Future<DisposalDetail?>.value(),
      };
    });

/// The document's counters, judged against the feature clock so a badge and the
/// number beside it agree (T-7).
final disposalProgressProvider = Provider.autoDispose
    .family<DisposalProgress?, String>((ref, disposalId) {
      final detail = ref.watch(disposalDetailProvider(disposalId)).value;
      if (detail == null) return null;
      return detail.progressOn(ref.watch(disposalClockProvider)());
    });

// --- dashboard (§33) --------------------------------------------------------

/// The numbers one dashboard card shows.
class DisposalDashboardSummary {
  const DisposalDashboardSummary({
    required this.expiredPositions,
    required this.draftCount,
  });

  const DisposalDashboardSummary.empty() : expiredPositions = 0, draftCount = 0;

  /// Batch positions already past their expiry date, within the role's scope
  /// (G-E6). Counted per **position** because that is what a reader acts on: one
  /// batch to destroy, rather than "this product has a problem".
  final int expiredPositions;

  /// Drafts not yet posted — the card that says "you have unfinished work".
  final int draftCount;

  bool get isEmpty => expiredPositions == 0 && draftCount == 0;
}

/// Expired positions across **every** location in the acting user's scope.
///
/// Distinct from [disposalExpiredPositionsProvider], which follows the source
/// selector: a branch head's dashboard has to count the store *and* every room, or
/// the number would change when they switched a chip. It iterates the same allowed
/// locations the selector is built from, so the two can never disagree about what
/// the scope is.
final disposalScopeExpiredCountProvider = FutureProvider.autoDispose
    .family<Map<String, int>, void>((ref, _) async {
      final locations = await ref.watch(disposalSourceLocationsProvider.future);
      if (locations.isEmpty) return const <String, int>{};

      final repository = ref.watch(disposalRepositoryProvider);
      final nowUtc = ref.watch(disposalClockProvider)();
      final counts = <String, int>{};
      for (final location in locations) {
        final positions = await repository.expiredPositions(
          sourceLocationId: location.id,
          nowUtc: nowUtc,
        );
        counts[location.id] = positions.length;
      }
      return counts;
    });

/// The warehouse dashboard card (§33).
final warehouseDisposalDashboardProvider =
    Provider.autoDispose<DisposalDashboardSummary>((ref) {
      if (ref.watch(actingRoleProvider) != UserRole.warehouse) {
        return const DisposalDashboardSummary.empty();
      }
      final counts =
          ref.watch(disposalScopeExpiredCountProvider(null)).value ??
          const <String, int>{};
      final drafts =
          ref.watch(warehouseDisposalListProvider).value ??
          const <DisposalSummary>[];
      return DisposalDashboardSummary(
        expiredPositions: counts.values.fold(0, (sum, count) => sum + count),
        draftCount: drafts.where((summary) => summary.disposal.isDraft).length,
      );
    });

/// The branch dashboard card (§33), split the way §33 asks: the store's expired
/// positions and the rooms' counted separately, because they are acted on by
/// different people on different days.
class BranchDisposalDashboard {
  const BranchDisposalDashboard({
    required this.storeExpiredPositions,
    required this.roomExpiredPositions,
    required this.draftCount,
  });

  const BranchDisposalDashboard.empty()
    : storeExpiredPositions = 0,
      roomExpiredPositions = 0,
      draftCount = 0;

  final int storeExpiredPositions;
  final int roomExpiredPositions;
  final int draftCount;

  int get totalExpiredPositions => storeExpiredPositions + roomExpiredPositions;

  bool get isEmpty => totalExpiredPositions == 0 && draftCount == 0;
}

final branchDisposalDashboardProvider =
    Provider.autoDispose<BranchDisposalDashboard>((ref) {
      if (ref.watch(actingRoleProvider) != UserRole.kepalaCabang) {
        return const BranchDisposalDashboard.empty();
      }
      final counts =
          ref.watch(disposalScopeExpiredCountProvider(null)).value ??
          const <String, int>{};
      final locations =
          ref.watch(disposalSourceLocationsProvider).value ??
          const <MasterLocation>[];
      final drafts =
          ref.watch(branchDisposalListProvider).value ??
          const <DisposalSummary>[];

      var store = 0;
      var rooms = 0;
      for (final location in locations) {
        final count = counts[location.id] ?? 0;
        if (location.type == StockLocationType.room) {
          rooms += count;
        } else {
          store += count;
        }
      }

      return BranchDisposalDashboard(
        storeExpiredPositions: store,
        roomExpiredPositions: rooms,
        draftCount: drafts.where((summary) => summary.disposal.isDraft).length,
      );
    });

// --- controllers ------------------------------------------------------------

/// Creates a draft and hands its id back so the caller can navigate to the form.
///
/// The `AsyncValue<String?>` state is the double-tap guard: while it is loading the
/// button is disabled, so two taps cannot produce two documents.
class CreateDisposalController extends AsyncNotifier<String?> {
  @override
  String? build() => null;

  Future<String?> create({
    required String sourceLocationId,
    String? reason,
  }) async {
    if (state.isLoading) return null;

    final session = ref.read(currentSessionValueProvider);
    if (session == null) return null;

    state = const AsyncValue<String?>.loading();
    final result = await AsyncValue.guard(() async {
      final disposal = await ref
          .read(createDisposalUseCaseProvider)
          .call(
            actorUserId: session.userId,
            sourceLocationId: sourceLocationId,
            reason: reason,
          );
      return disposal.id;
    });
    state = result;
    return result.value;
  }
}

final createDisposalControllerProvider =
    AsyncNotifierProvider<CreateDisposalController, String?>(
      CreateDisposalController.new,
    );

/// Edits one draft and posts it.
///
/// The state is `AsyncValue<void>`: the screen needs to know only whether an action
/// is in flight and whether the last one failed. The document itself arrives through
/// [disposalDetailProvider], which is a live stream, so a successful write is
/// reflected without this controller having to carry it.
class DisposalEditorController extends AsyncNotifier<void> {
  @override
  void build() {}

  /// The last posted result, so the screen can say what it did. Reset on every new
  /// action.
  DisposalPostingResult? lastPosting;

  Future<bool> updateReason({
    required String disposalId,
    required String? reason,
  }) {
    return _run(
      () => ref
          .read(updateDisposalHeaderUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            disposalId: disposalId,
            reason: reason,
          ),
    );
  }

  Future<bool> addPosition({
    required String disposalId,
    required String itemId,
    required String batchId,
    required Quantity qty,
    String? note,
  }) {
    return _run(
      () => ref
          .read(addDisposalLineUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            disposalId: disposalId,
            itemId: itemId,
            batchId: batchId,
            qty: qty,
            note: note,
          ),
    );
  }

  Future<bool> updateLine({
    required String disposalId,
    required String lineId,
    required Quantity qty,
    String? note,
  }) {
    return _run(
      () => ref
          .read(updateDisposalLineUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            disposalId: disposalId,
            lineId: lineId,
            qty: qty,
            note: note,
          ),
    );
  }

  Future<bool> removeLine({
    required String disposalId,
    required String lineId,
  }) {
    return _run(
      () => ref
          .read(removeDisposalLineUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            disposalId: disposalId,
            lineId: lineId,
          ),
    );
  }

  /// Posts the document. Irreversible: the source balance falls the moment this
  /// commits and nothing anywhere gains the stock (§20), which is why the screen
  /// confirms first.
  Future<bool> post(String disposalId) async {
    if (state.isLoading) return false;

    lastPosting = null;
    state = const AsyncValue<void>.loading();
    final result = await AsyncValue.guard(() async {
      lastPosting = await ref
          .read(postDisposalUseCaseProvider)
          .call(actorUserId: _requireSession().userId, disposalId: disposalId);
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

  /// Runs one action behind the in-flight guard and records the outcome. Returns
  /// whether it succeeded, so the screen can close a sheet only on success.
  Future<bool> _run(Future<void> Function() action) async {
    if (state.isLoading) return false;

    state = const AsyncValue<void>.loading();
    final result = await AsyncValue.guard(action);
    state = result;
    return !result.hasError;
  }
}

final disposalEditorControllerProvider =
    AsyncNotifierProvider<DisposalEditorController, void>(
      DisposalEditorController.new,
    );
