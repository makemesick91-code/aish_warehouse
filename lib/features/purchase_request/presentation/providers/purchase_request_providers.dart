import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/db/database_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../../core/enums/app_enums.dart';
import '../../../../core/quantity/quantity.dart';
import '../../../../core/session/acting_user_providers.dart';
import '../../../../core/session/current_user_session.dart';
import '../../../../core/time/operational_iso_week.dart';
import '../../../master/domain/models/master_models.dart';
import '../../../master/presentation/providers/master_providers.dart';
import '../../data/repositories/drift_purchase_request_repository.dart';
import '../../domain/models/purchase_request_models.dart';
import '../../domain/repositories/purchase_request_repository.dart';
import '../../domain/services/purchase_request_opname_eligibility_policy.dart';
import '../../domain/services/purchase_request_suggestion_builder.dart';
import '../../domain/services/suggested_purchase_request_calculator.dart';
import '../../domain/use_cases/add_purchase_request_line_use_case.dart';
import '../../domain/use_cases/cancel_purchase_request_use_case.dart';
import '../../domain/use_cases/create_purchase_request_use_case.dart';
import '../../domain/use_cases/mark_purchase_request_processing_use_case.dart';
import '../../domain/use_cases/reject_purchase_request_use_case.dart';
import '../../domain/use_cases/remove_purchase_request_line_use_case.dart';
import '../../domain/use_cases/replace_purchase_request_opnames_use_case.dart';
import '../../domain/use_cases/submit_purchase_request_use_case.dart';
import '../../domain/use_cases/update_purchase_request_use_case.dart';

// --- clock ------------------------------------------------------------------

/// The UTC clock the whole feature reads "now" from.
///
/// A provider rather than a bare `DateTime.now()` for two reasons. G-P1's window
/// is a function of the current operational week, so a test that has to sit on a
/// year boundary must be able to say so — overriding this one provider moves the
/// eligibility list, every use case's timestamps and the queue's "age" column
/// together, which is what keeps them consistent (T-7). And the use cases below
/// receive it explicitly, so nothing in the feature reads a wall clock of its own.
final purchaseRequestClockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

// --- wiring -----------------------------------------------------------------

final purchaseRequestRepositoryProvider = Provider<PurchaseRequestRepository>(
  (ref) =>
      DriftPurchaseRequestRepository(ref.watch(purchaseRequestDaoProvider)),
);

final suggestedPurchaseRequestCalculatorProvider =
    Provider<SuggestedPurchaseRequestCalculator>(
      (ref) => const SuggestedPurchaseRequestCalculator(),
    );

final purchaseRequestSuggestionBuilderProvider =
    Provider<PurchaseRequestSuggestionBuilder>(
      (ref) => PurchaseRequestSuggestionBuilder(
        requests: ref.watch(purchaseRequestRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
        calculator: ref.watch(suggestedPurchaseRequestCalculatorProvider),
      ),
    );

final createPurchaseRequestUseCaseProvider =
    Provider<CreatePurchaseRequestUseCase>(
      (ref) => CreatePurchaseRequestUseCase(
        requests: ref.watch(purchaseRequestRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
        suggestions: ref.watch(purchaseRequestSuggestionBuilderProvider),
        clock: ref.watch(purchaseRequestClockProvider),
      ),
    );

final updatePurchaseRequestUseCaseProvider =
    Provider<UpdatePurchaseRequestUseCase>(
      (ref) => UpdatePurchaseRequestUseCase(
        requests: ref.watch(purchaseRequestRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
      ),
    );

final replacePurchaseRequestOpnamesUseCaseProvider =
    Provider<ReplacePurchaseRequestOpnamesUseCase>(
      (ref) => ReplacePurchaseRequestOpnamesUseCase(
        requests: ref.watch(purchaseRequestRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
        suggestions: ref.watch(purchaseRequestSuggestionBuilderProvider),
        clock: ref.watch(purchaseRequestClockProvider),
      ),
    );

final addPurchaseRequestLineUseCaseProvider =
    Provider<AddPurchaseRequestLineUseCase>(
      (ref) => AddPurchaseRequestLineUseCase(
        requests: ref.watch(purchaseRequestRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
      ),
    );

final removePurchaseRequestLineUseCaseProvider =
    Provider<RemovePurchaseRequestLineUseCase>(
      (ref) => RemovePurchaseRequestLineUseCase(
        requests: ref.watch(purchaseRequestRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
      ),
    );

final submitPurchaseRequestUseCaseProvider =
    Provider<SubmitPurchaseRequestUseCase>(
      (ref) => SubmitPurchaseRequestUseCase(
        requests: ref.watch(purchaseRequestRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
        outbox: ref.watch(syncOutboxWriterProvider),
        clock: ref.watch(purchaseRequestClockProvider),
      ),
    );

final cancelPurchaseRequestUseCaseProvider =
    Provider<CancelPurchaseRequestUseCase>(
      (ref) => CancelPurchaseRequestUseCase(
        requests: ref.watch(purchaseRequestRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
        outbox: ref.watch(syncOutboxWriterProvider),
        clock: ref.watch(purchaseRequestClockProvider),
      ),
    );

final markPurchaseRequestProcessingUseCaseProvider =
    Provider<MarkPurchaseRequestProcessingUseCase>(
      (ref) => MarkPurchaseRequestProcessingUseCase(
        requests: ref.watch(purchaseRequestRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
        outbox: ref.watch(syncOutboxWriterProvider),
        clock: ref.watch(purchaseRequestClockProvider),
      ),
    );

final rejectPurchaseRequestUseCaseProvider =
    Provider<RejectPurchaseRequestUseCase>(
      (ref) => RejectPurchaseRequestUseCase(
        requests: ref.watch(purchaseRequestRepositoryProvider),
        master: ref.watch(masterDataRepositoryProvider),
        outbox: ref.watch(syncOutboxWriterProvider),
        clock: ref.watch(purchaseRequestClockProvider),
      ),
    );

// --- period -----------------------------------------------------------------

/// The operational ISO weeks a request may cite right now (G-P1).
///
/// Riverpod caches this like any other provider, so a tablet left open across
/// midnight would keep offering last week's window. The list and form screens
/// therefore invalidate it on refresh and whenever the app returns to the
/// foreground.
///
/// This value drives *display and affordances only*. Every use case recomputes the
/// window from its own clock at the moment it writes, so a stale cache here can
/// never file a request against an expired count — at worst it offers a citation
/// the use case then refuses.
final purchaseRequestEligiblePeriodsProvider =
    Provider<List<OperationalIsoWeek>>(
      (ref) => PurchaseRequestOpnameEligibilityPolicy.eligiblePeriods(
        ref.watch(purchaseRequestClockProvider)(),
      ),
    );

/// `2026-W31` — the week a request created now belongs to.
final currentPurchaseRequestPeriodProvider = Provider<OperationalIsoWeek>(
  (ref) => ref.watch(purchaseRequestEligiblePeriodsProvider).first,
);

// --- lists ------------------------------------------------------------------

/// Selected status chip on a list; `null` means "Semua".
class PurchaseRequestStatusFilterController
    extends Notifier<PurchaseRequestStatus?> {
  @override
  PurchaseRequestStatus? build() => null;

  /// Tapping the active chip clears the filter, which is what "Semua" means.
  void select(PurchaseRequestStatus? status) =>
      state = state == status ? null : status;

  void clear() => state = null;
}

final branchPurchaseRequestStatusFilterProvider =
    NotifierProvider<
      PurchaseRequestStatusFilterController,
      PurchaseRequestStatus?
    >(PurchaseRequestStatusFilterController.new);

final warehousePurchaseRequestStatusFilterProvider =
    NotifierProvider<
      PurchaseRequestStatusFilterController,
      PurchaseRequestStatus?
    >(PurchaseRequestStatusFilterController.new);

/// The acting branch head's own requests, newest first (G-R2).
///
/// The branch comes from [actingBranchIdProvider] on every build, so switching
/// user re-runs the query rather than serving the previous branch from cache. A
/// role without a branch — warehouse, super admin — emits an empty list rather
/// than every branch's requests.
///
/// `autoDispose` because this is a **screen** stream, and the same reason
/// [purchaseRequestDetailProvider] is: a branch-scoped query left subscribed after
/// its screen closed is a cache entry that outlives the session it was scoped for.
/// Rebuilding on the next visit costs one query; keeping it warm risks serving one
/// branch's list to whoever logs in next.
final branchPurchaseRequestListProvider =
    StreamProvider.autoDispose<List<PurchaseRequestSummary>>((ref) {
      final branchId = ref.watch(actingBranchIdProvider);
      if (branchId == null) {
        return Stream.value(const <PurchaseRequestSummary>[]);
      }

      final status = ref.watch(branchPurchaseRequestStatusFilterProvider);
      return ref
          .watch(purchaseRequestRepositoryProvider)
          .watchForBranch(
            branchId: branchId,
            statuses: status == null
                ? const <PurchaseRequestStatus>{}
                : {status},
          );
    });

/// The branch's live `submitted`/`processing` request, if any — what the list
/// header uses to say "you already have an order in flight" (G-P4).
final activeBranchPurchaseRequestProvider = FutureProvider<PurchaseRequest?>((
  ref,
) {
  final branchId = ref.watch(actingBranchIdProvider);
  if (branchId == null) return Future.value(null);
  return ref
      .watch(purchaseRequestRepositoryProvider)
      .activeRequestForBranch(branchId);
});

/// Text typed into the warehouse queue's search field.
class PurchaseRequestSearchController extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;

  void clear() => state = '';
}

final warehousePurchaseRequestSearchProvider =
    NotifierProvider<PurchaseRequestSearchController, String>(
      PurchaseRequestSearchController.new,
    );

/// Branch filter on the warehouse queue; `null` means every branch.
class WarehouseBranchFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? branchId) => state = state == branchId ? null : branchId;
}

final warehouseBranchFilterProvider =
    NotifierProvider<WarehouseBranchFilterController, String?>(
      WarehouseBranchFilterController.new,
    );

final branchesProvider = FutureProvider<List<MasterBranch>>(
  (ref) => ref.watch(masterDataRepositoryProvider).activeBranches(),
);

/// The central warehouse inbox — every branch, by design (spec §4.2).
///
/// Deliberately *not* branch-scoped: the whole job spans branches. What replaces
/// the branch predicate is the status set — a `draft` is device-authoritative
/// until submitted (G-Y2) and never appears here, whatever the filter says.
///
/// `autoDispose` for the reason above, and more sharply so: this is the *unscoped*
/// read. A cross-branch query that stays subscribed after the warehouse screen
/// closes is exactly the cache entry a later branch session must not be able to
/// resolve.
final warehousePurchaseRequestQueueProvider =
    StreamProvider.autoDispose<List<PurchaseRequestSummary>>((ref) {
      // Through `actingRoleProvider`, so this provider and the detail one below rest
      // on the same single source rather than each reaching into the session its own
      // way.
      if (ref.watch(actingRoleProvider) != UserRole.warehouse) {
        return Stream.value(const <PurchaseRequestSummary>[]);
      }

      final status = ref.watch(warehousePurchaseRequestStatusFilterProvider);
      return ref
          .watch(purchaseRequestRepositoryProvider)
          .watchWarehouseQueue(
            statuses: status == null ? warehouseQueueStatuses : {status},
            branchId: ref.watch(warehouseBranchFilterProvider),
            searchQuery: ref.watch(warehousePurchaseRequestSearchProvider),
          );
    });

// --- details ----------------------------------------------------------------

/// One request, scoped to the branch of whoever is acting.
///
/// Three properties keep this from becoming an IDOR:
///
/// * It watches [actingBranchIdProvider], so the branch is never a stale capture.
///   Switching user rebuilds the provider and re-runs the query; the previous
///   user's document cannot be served from cache to the next one.
/// * The branch travels into the SQL predicate
///   (`watchDetailForBranch`), so a document from elsewhere is not fetched and
///   then withheld — it is not fetched.
/// * `autoDispose` tears the subscription down with the screen, so a document
///   opened once is not still cached behind a different session later.
///
/// Keying the family on the id alone is deliberate: adding the branch to the key
/// would make two entries for the same document look independent while still being
/// resolvable, and the leak this prevents is precisely the one where a stale key
/// survives a session change.
final purchaseRequestDetailProvider = StreamProvider.autoDispose
    .family<PurchaseRequestDetail?, String>((ref, prId) {
      final branchId = ref.watch(actingBranchIdProvider);
      // No session or an unscoped role: nothing to show, and nothing queried.
      if (branchId == null) return Stream.value(null);

      return ref
          .watch(purchaseRequestRepositoryProvider)
          .watchDetailForBranch(prId: prId, branchId: branchId);
    });

/// One request for a warehouse reader — unscoped by branch, but only for an actor
/// that actually holds the warehouse role.
///
/// The role check is here as well as in the route guard because this provider is
/// the unscoped read: a screen that reached it with a branch-scoped session would
/// otherwise see every branch's documents.
final warehousePurchaseRequestDetailProvider = StreamProvider.autoDispose
    .family<PurchaseRequestDetail?, String>((ref, prId) {
      final role = ref.watch(actingRoleProvider);
      if (role != UserRole.warehouse) return Stream.value(null);

      return ref
          .watch(purchaseRequestRepositoryProvider)
          .watchDetailForWarehouse(prId);
    });

// --- draft form: opname selection -------------------------------------------

/// The counts the acting branch head may cite right now (G-P1).
///
/// `autoDispose` because this is form state: leaving the wizard should not keep a
/// week-sensitive list warm.
/// Deliberately **not** a family keyed on a branch id.
///
/// An earlier shape took the branch as a family parameter, defaulting to the acting
/// one. Every call site passed something correct, and the affordance was still wrong:
/// a provider that accepts a branch id is one careless call away from reading another
/// branch's counts, and nothing about `eligibleOpnamesProvider('branch-2')` looks
/// suspicious at the call site. The branch is read from [actingBranchIdProvider] here
/// and nowhere else, so there is no argument to get wrong.
final eligibleOpnamesProvider =
    FutureProvider.autoDispose<List<PurchaseRequestOpnameReference>>((ref) {
      final branchId = ref.watch(actingBranchIdProvider);
      if (branchId == null) {
        return Future.value(const <PurchaseRequestOpnameReference>[]);
      }

      return ref
          .watch(purchaseRequestRepositoryProvider)
          .eligibleOpnames(
            branchId: branchId,
            periods: ref
                .watch(purchaseRequestEligiblePeriodsProvider)
                .map((week) => (year: week.year, week: week.week))
                .toList(growable: false),
          );
    });

/// Which counts the branch head has ticked in the wizard.
class SelectedOpnameIdsController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void toggle(String opnameId) {
    final next = state.toSet();
    if (!next.remove(opnameId)) next.add(opnameId);
    state = next;
  }

  void replaceAll(Iterable<String> opnameIds) => state = opnameIds.toSet();

  void clear() => state = const <String>{};

  bool contains(String opnameId) => state.contains(opnameId);
}

final selectedOpnameIdsProvider =
    NotifierProvider.autoDispose<SelectedOpnameIdsController, Set<String>>(
      SelectedOpnameIdsController.new,
    );

/// The working behind a **draft's** suggestions, keyed by item id: par level, the
/// counted total, and which rooms contributed a shortfall (§24.2).
///
/// Only for drafts, and that restriction is the point. Recomputing the arithmetic
/// of a sent request would show today's answer next to a `suggested_qty` that was
/// snapshotted when it was raised, and the two would differ for entirely
/// legitimate reasons — a later count, a changed par level. A reader would have no
/// way to tell which number the order was actually based on. On a draft they cannot
/// differ, because the draft's citations are exactly what the breakdown is computed
/// from.
///
/// A failure here is swallowed into an empty map on purpose: this is explanatory
/// decoration beside a number that is already stored, and a citation that has aged
/// out of the G-P1 window must surface as a refused *submit*, not as a broken edit
/// screen that cannot render at all.
final draftSuggestionBreakdownProvider = FutureProvider.autoDispose
    .family<Map<String, SuggestedPurchaseRequestLine>, String>((
      ref,
      prId,
    ) async {
      final detail = await ref.watch(
        purchaseRequestDetailProvider(prId).future,
      );
      if (detail == null || !detail.isEditable) {
        return const <String, SuggestedPurchaseRequestLine>{};
      }

      try {
        final suggestion = await ref
            .watch(purchaseRequestSuggestionBuilderProvider)
            .build(
              branchId: detail.request.branchId,
              opnameIds: detail.opnames
                  .map((reference) => reference.opnameId)
                  .toList(growable: false),
              utcNow: ref.watch(purchaseRequestClockProvider)(),
              prId: prId,
            );
        return {for (final line in suggestion.lines) line.itemId: line};
      } on Object {
        return const <String, SuggestedPurchaseRequestLine>{};
      }
    });

// --- draft form: item filtering ---------------------------------------------

/// Selected category chip on the review step; `null` is "Semua".
class PurchaseRequestCategoryFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? categoryId) =>
      state = state == categoryId ? null : categoryId;

  void clear() => state = null;
}

final purchaseRequestCategoryFilterProvider =
    NotifierProvider<PurchaseRequestCategoryFilterController, String?>(
      PurchaseRequestCategoryFilterController.new,
    );

/// Text typed into the search field above the line list.
final purchaseRequestSearchQueryProvider =
    NotifierProvider<PurchaseRequestSearchController, String>(
      PurchaseRequestSearchController.new,
    );

final purchaseRequestLineFilterProvider = Provider<PurchaseRequestFilter>(
  (ref) => PurchaseRequestFilter(
    categoryId: ref.watch(purchaseRequestCategoryFilterProvider),
    searchQuery: ref.watch(purchaseRequestSearchQueryProvider),
  ),
);

final purchaseRequestCategoriesProvider = FutureProvider<List<MasterCategory>>(
  (ref) => ref.watch(masterDataRepositoryProvider).categories(),
);

/// Offline typeahead results for the "add an item by hand" dropdown. Keyed by the
/// query so a repeated keystroke reuses the cached result.
final purchaseRequestAddableItemSearchProvider = FutureProvider.autoDispose
    .family<List<MasterItem>, String>((ref, query) {
      if (query.trim().isEmpty) return Future.value(const <MasterItem>[]);
      return ref
          .watch(purchaseRequestRepositoryProvider)
          .searchAddableItems(
            query: query,
            categoryId: ref.watch(purchaseRequestCategoryFilterProvider),
          );
    });

// --- controllers ------------------------------------------------------------

/// Creates a draft from the wizard's first step.
///
/// The `AsyncValue<String?>` state is the double-tap guard: while it is loading
/// the button is disabled, so two taps cannot produce two drafts.
class CreatePurchaseRequestController extends AsyncNotifier<String?> {
  @override
  String? build() => null;

  Future<String?> create({
    required Set<String> opnameIds,
    DateTime? neededDate,
    String? note,
  }) async {
    if (state.isLoading) return null;

    final session = ref.read(currentSessionValueProvider);
    if (session == null) return null;

    state = const AsyncValue<String?>.loading();
    final result = await AsyncValue.guard(() async {
      final request = await ref
          .read(createPurchaseRequestUseCaseProvider)
          .call(
            actorUserId: session.userId,
            selectedOpnameIds: opnameIds.toList(growable: false),
            neededDate: neededDate,
            note: note,
          );
      return request.id;
    });
    state = result;

    // A new draft changes what the list shows and may change whether the branch
    // still has room for another order.
    ref.invalidate(activeBranchPurchaseRequestProvider);
    return result.value;
  }
}

final createPurchaseRequestControllerProvider =
    AsyncNotifierProvider<CreatePurchaseRequestController, String?>(
      CreatePurchaseRequestController.new,
    );

/// Edits and submits a draft.
///
/// The state is `AsyncValue<void>`: the screen needs to know only whether an
/// action is in flight and whether the last one failed. The document itself
/// arrives through [purchaseRequestDetailProvider], which is a live stream, so a
/// successful write is reflected without this controller having to carry it.
class PurchaseRequestFormController extends AsyncNotifier<void> {
  @override
  void build() {}

  Future<bool> saveHeader({
    required String prId,
    DateTime? neededDate,
    String? note,
  }) {
    return _run(
      () => ref
          .read(updatePurchaseRequestUseCaseProvider)
          .header(
            actorUserId: _requireSession().userId,
            prId: prId,
            neededDate: neededDate,
            note: note,
          ),
    );
  }

  Future<bool> saveLine({
    required String lineId,
    required Quantity requestedQty,
    String? note,
  }) {
    return _run(
      () => ref
          .read(updatePurchaseRequestUseCaseProvider)
          .line(
            actorUserId: _requireSession().userId,
            lineId: lineId,
            requestedQty: requestedQty,
            note: note,
          ),
    );
  }

  Future<bool> addLine({
    required String prId,
    required String itemId,
    required Quantity requestedQty,
    String? note,
  }) {
    return _run(
      () => ref
          .read(addPurchaseRequestLineUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            prId: prId,
            itemId: itemId,
            requestedQty: requestedQty,
            note: note,
          ),
    );
  }

  Future<bool> removeLine(String lineId) {
    return _run(
      () => ref
          .read(removePurchaseRequestLineUseCaseProvider)
          .call(actorUserId: _requireSession().userId, lineId: lineId),
    );
  }

  Future<bool> replaceOpnames({
    required String prId,
    required Set<String> opnameIds,
  }) {
    return _run(
      () => ref
          .read(replacePurchaseRequestOpnamesUseCaseProvider)
          .call(
            actorUserId: _requireSession().userId,
            prId: prId,
            selectedOpnameIds: opnameIds.toList(growable: false),
          ),
    );
  }

  Future<bool> submit(String prId) async {
    final submitted = await _run(
      () => ref
          .read(submitPurchaseRequestUseCaseProvider)
          .call(actorUserId: _requireSession().userId, prId: prId),
    );
    if (submitted) ref.invalidate(activeBranchPurchaseRequestProvider);
    return submitted;
  }

  CurrentUserSession _requireSession() {
    final session = ref.read(currentSessionValueProvider);
    if (session == null) {
      throw StateError('Tidak ada sesi pengguna aktif.');
    }
    return session;
  }

  /// Runs one action behind the in-flight guard and records the outcome. Returns
  /// whether it succeeded, so the screen can navigate only on success.
  Future<bool> _run(Future<void> Function() action) async {
    if (state.isLoading) return false;

    state = const AsyncValue<void>.loading();
    final result = await AsyncValue.guard(action);
    state = result;
    return !result.hasError;
  }
}

final purchaseRequestFormControllerProvider =
    AsyncNotifierProvider<PurchaseRequestFormController, void>(
      PurchaseRequestFormController.new,
    );

/// Withdraws a request (G-S3).
class CancelPurchaseRequestController extends AsyncNotifier<void> {
  @override
  void build() {}

  Future<bool> cancel({required String prId, required String reason}) async {
    if (state.isLoading) return false;

    final session = ref.read(currentSessionValueProvider);
    if (session == null) return false;

    state = const AsyncValue<void>.loading();
    final result = await AsyncValue.guard(
      () => ref
          .read(cancelPurchaseRequestUseCaseProvider)
          .call(actorUserId: session.userId, prId: prId, reason: reason),
    );
    state = result;
    // Cancelling releases the branch's active-order slot.
    if (!result.hasError) ref.invalidate(activeBranchPurchaseRequestProvider);
    return !result.hasError;
  }
}

final cancelPurchaseRequestControllerProvider =
    AsyncNotifierProvider<CancelPurchaseRequestController, void>(
      CancelPurchaseRequestController.new,
    );

/// The warehouse's two actions. One controller because only one document is on
/// screen at a time and the in-flight guard is naturally shared: while a
/// transition is running, no other should start.
class WarehousePurchaseRequestController extends AsyncNotifier<void> {
  @override
  void build() {}

  Future<bool> markProcessing(String prId) {
    return _run(
      (session) => ref
          .read(markPurchaseRequestProcessingUseCaseProvider)
          .call(actorUserId: session.userId, prId: prId),
    );
  }

  Future<bool> reject({required String prId, required String reason}) {
    return _run(
      (session) => ref
          .read(rejectPurchaseRequestUseCaseProvider)
          .call(actorUserId: session.userId, prId: prId, reason: reason),
    );
  }

  Future<bool> _run(
    Future<void> Function(CurrentUserSession session) action,
  ) async {
    if (state.isLoading) return false;

    final session = ref.read(currentSessionValueProvider);
    if (session == null) return false;

    state = const AsyncValue<void>.loading();
    final result = await AsyncValue.guard(() => action(session));
    state = result;
    return !result.hasError;
  }
}

final warehousePurchaseRequestControllerProvider =
    AsyncNotifierProvider<WarehousePurchaseRequestController, void>(
      WarehousePurchaseRequestController.new,
    );
