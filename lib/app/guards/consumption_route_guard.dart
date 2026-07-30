import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/acting_user_providers.dart';
import '../../core/session/current_user_session.dart';
import '../../features/consumption/domain/models/consumption_models.dart';
import '../../features/consumption/domain/services/consumption_access_policy.dart';
import '../../features/consumption/presentation/providers/consumption_providers.dart';
import '../../features/master/domain/models/master_models.dart';
import 'access_denied_page.dart';

/// Which document, on which screen. A record rather than a class: Dart gives structural
/// equality and `hashCode` for free, which is the whole of what a Riverpod family key
/// needs.
typedef ConsumptionRouteRequest = ({
  ConsumptionRouteKind kind,
  String consumptionId,
});

/// Resolves [ConsumptionAccessPolicy] against the database for one Pemakaian route.
///
/// Four things make this a real guard rather than a hint:
///
/// * The acting user is **re-read from the database** through [actingUserProvider], so
///   the decision rests on the stored role, branch, id and `is_active` rather than on
///   whatever the session object claims about itself (O-8). It is the same provider the
///   Stok Opname, Purchase Request, Delivery Order, Good Receipt, Distribusi and
///   Pemusnahan guards use — one source, so the seven cannot disagree about who is
///   acting.
/// * The document lookup is `findAccessScope`, which selects five columns and pins them
///   to the scope the *route kind* requires. Deciding whether a consumption may be shown
///   never loads the consumption — so a refusal cannot leak the CNS number, the room, the
///   items, the batches, the quantities or the note.
/// * Whether the lookup is owner- or branch-scoped, and which statuses it accepts, are
///   [ConsumptionAccessPolicy]'s answers rather than this file's. The editor accepts
///   `draft` only and the branch history accepts `posted` only; deciding either here
///   would be a second copy of the rule.
/// * The scope row's `created_by` and `branch_id` are compared again in
///   `forDocument`. The SQL predicate is the first line — a nurse's lookup already
///   carries `created_by = ?` — and this is the second, so a caller that ever passed an
///   unscoped lookup by mistake still cannot open somebody else's document.
///
/// ### The ownership dimension no earlier guard had
///
/// Every earlier route guard in this application asks *"is this document in your
/// place?"*. This one also asks *"is this document yours?"*, because §14 makes a
/// Pemakaian draft one nurse's record rather than the branch's. Two nurses in the same
/// branch are a case no earlier guard's tests could have caught, which is why the
/// security tests exercise exactly that pair.
///
/// It watches the session, so switching user re-runs the whole decision instead of
/// serving the previous user's verdict from cache.
final consumptionRouteAccessProvider = FutureProvider.autoDispose
    .family<ConsumptionAccess, ConsumptionRouteRequest>((ref, request) async {
      final session = ref.watch(currentSessionValueProvider);
      if (session == null) {
        return const ConsumptionAccess.denied(
          ConsumptionAccessDenialReason.noSession,
        );
      }

      final MasterUser? actor = await ref.watch(actingUserProvider.future);

      final section = ConsumptionAccessPolicy.forSection(
        user: actor,
        kind: request.kind,
      );
      // Short-circuits on purpose: a role that may not reach this screen at all must not
      // cause a document lookup, not even a scoped one.
      if (section.isDenied) return section;

      final repository = ref.watch(consumptionRepositoryProvider);
      final ConsumptionAccessScope? scope = await repository.findAccessScope(
        consumptionId: request.consumptionId,
        scope: ConsumptionAccessPolicy.requiredScope(request.kind),
        // `actor` is non-null and has a branch — `forSection` granted, and it refuses a
        // branch-scoped role without one.
        actorUserId: ConsumptionAccessPolicy.requiresOwnership(request.kind)
            ? actor!.id
            : null,
        branchId: actor!.branchId,
        statuses: ConsumptionAccessPolicy.visibleStatusesFor(request.kind),
      );

      return ConsumptionAccessPolicy.forDocument(
        user: actor,
        kind: request.kind,
        scope: scope,
      );
    });

/// Renders the page only once the route has been cleared.
///
/// The page is passed as a builder rather than a widget, so it and the providers it
/// watches do not exist while the decision is pending or after it is refused. A refused
/// route therefore has no subscription to any document stream — the difference between
/// hiding data and not fetching it.
class ConsumptionRouteGuard extends ConsumerWidget {
  const ConsumptionRouteGuard({
    super.key,
    required this.kind,
    required this.consumptionId,
    required this.builder,
  });

  final ConsumptionRouteKind kind;
  final String consumptionId;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(
      consumptionRouteAccessProvider((
        kind: kind,
        consumptionId: consumptionId,
      )),
    );

    return access.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      // A guard that fails open is not a guard. Anything unexpected while deciding is
      // treated as a refusal.
      error: (_, _) => const AccessDeniedPage(),
      data: (decision) =>
          decision.isGranted ? builder(context) : const AccessDeniedPage(),
    );
  }
}

/// Guards a Pemakaian screen that does **not** name a document.
///
/// The list and create routes are decided by role and branch alone, which the router's
/// synchronous redirect already does from the session. This wrapper re-asks the same
/// question against the *stored* user, so a section reached by any other means — a deep
/// link that arrives before the redirect, a session whose role was changed underneath it
/// — still renders nothing.
class ConsumptionSectionGuard extends ConsumerWidget {
  const ConsumptionSectionGuard({
    super.key,
    required this.kind,
    required this.builder,
  });

  final ConsumptionRouteKind kind;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(actingUserProvider);

    return actor.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const AccessDeniedPage(),
      data: (user) =>
          ConsumptionAccessPolicy.forSection(user: user, kind: kind).isGranted
          ? builder(context)
          : const AccessDeniedPage(),
    );
  }
}
