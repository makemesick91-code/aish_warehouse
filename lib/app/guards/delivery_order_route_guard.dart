import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/acting_user_providers.dart';
import '../../core/session/current_user_session.dart';
import '../../features/delivery/domain/models/delivery_models.dart';
import '../../features/delivery/domain/services/delivery_order_access_policy.dart';
import '../../features/delivery/presentation/providers/delivery_providers.dart';
import '../../features/master/domain/models/master_models.dart';
import 'access_denied_page.dart';

/// Which document, on which screen. A record rather than a class: Dart gives
/// structural equality and `hashCode` for free, which is the whole of what a
/// Riverpod family key needs.
typedef DeliveryRouteRequest = ({DeliveryRouteKind kind, String doId});

/// Resolves [DeliveryOrderAccessPolicy] against the database for one document
/// route.
///
/// Three things make this a real guard rather than a hint:
///
/// * The acting user is **re-read from the database** through
///   [actingUserProvider], so the decision rests on the stored role, branch and
///   `is_active` rather than on whatever the session object claims about itself
///   (O-8). It is the same provider the Stok Opname and Purchase Request guards
///   use — one source, so the three cannot disagree about who is acting.
/// * The document lookup is `findAccessScope`, which selects four columns and, on
///   a branch screen, pins them to the actor's own branch **and** to the statuses
///   a branch may see. Deciding whether a document may be shown never loads the
///   document — so a refusal cannot leak the Surat Jalan number, the PR number,
///   the branch, the items, the batches or the quantities.
/// * Whether the lookup is branch-scoped, and which statuses it accepts, are
///   [DeliveryOrderAccessPolicy]'s answers rather than this file's. The
///   warehouse's list spans branches by design, and deciding that here would be a
///   second copy of the rule.
///
/// It watches the session, so switching user re-runs the whole decision instead of
/// serving the previous user's verdict from cache.
final deliveryRouteAccessProvider = FutureProvider.autoDispose
    .family<DeliveryAccess, DeliveryRouteRequest>((ref, request) async {
      final session = ref.watch(currentSessionValueProvider);
      if (session == null) {
        return const DeliveryAccess.denied(
          DeliveryAccessDenialReason.noSession,
        );
      }

      final MasterUser? actor = await ref.watch(actingUserProvider.future);

      final section = DeliveryOrderAccessPolicy.forSection(
        user: actor,
        kind: request.kind,
      );
      // Short-circuits on purpose: a role that may not reach this screen at all
      // must not cause a document lookup, not even a scoped one.
      if (section.isDenied) return section;

      final DeliveryOrderAccessScope? scope = await ref
          .watch(deliveryOrderRepositoryProvider)
          .findAccessScope(
            doId: request.doId,
            // `null` widens the lookup to every branch, and only the warehouse
            // kinds ask for that. `actor` is non-null and, on a branch screen, has
            // a branch — `forSection` granted, and it refuses a branch-scoped role
            // without one.
            branchId:
                DeliveryOrderAccessPolicy.requiresBranchScope(request.kind)
                ? actor!.branchId!
                : null,
            statuses: DeliveryOrderAccessPolicy.visibleStatuses(request.kind),
          );

      return DeliveryOrderAccessPolicy.forDocument(
        user: actor,
        kind: request.kind,
        scope: scope,
      );
    });

/// Renders the page only once the route has been cleared.
///
/// The page is passed as a builder rather than a widget, so it and the providers it
/// watches do not exist while the decision is pending or after it is refused. A
/// refused route therefore has no subscription to any document stream — the
/// difference between hiding data and not fetching it.
class DeliveryOrderRouteGuard extends ConsumerWidget {
  const DeliveryOrderRouteGuard({
    super.key,
    required this.kind,
    required this.doId,
    required this.builder,
  });

  final DeliveryRouteKind kind;
  final String doId;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(
      deliveryRouteAccessProvider((kind: kind, doId: doId)),
    );

    return access.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      // A guard that fails open is not a guard. Anything unexpected while deciding
      // is treated as a refusal.
      error: (_, _) => const AccessDeniedPage(),
      data: (decision) =>
          decision.isGranted ? builder(context) : const AccessDeniedPage(),
    );
  }
}

/// Guards a Delivery Order screen that does **not** name a document.
///
/// `/warehouse/delivery-orders`, `/deliveries` and the create route are decided by
/// role alone, which the router's synchronous redirect already does from the
/// session. This wrapper re-asks the same question against the *stored* user, so a
/// section reached by any other means — a deep link that arrives before the
/// redirect, a session whose role was changed underneath it — still renders
/// nothing.
class DeliverySectionGuard extends ConsumerWidget {
  const DeliverySectionGuard({
    super.key,
    required this.kind,
    required this.builder,
  });

  final DeliveryRouteKind kind;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(actingUserProvider);

    return actor.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const AccessDeniedPage(),
      data: (user) =>
          DeliveryOrderAccessPolicy.forSection(user: user, kind: kind).isGranted
          ? builder(context)
          : const AccessDeniedPage(),
    );
  }
}
