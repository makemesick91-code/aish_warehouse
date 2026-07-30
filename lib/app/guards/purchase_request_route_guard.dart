import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/acting_user_providers.dart';
import '../../core/session/current_user_session.dart';
import '../../features/master/domain/models/master_models.dart';
import '../../features/purchase_request/domain/models/purchase_request_models.dart';
import '../../features/purchase_request/domain/services/purchase_request_access_policy.dart';
import '../../features/purchase_request/presentation/providers/purchase_request_providers.dart';
import 'access_denied_page.dart';

/// Which document, on which screen. A record rather than a class: Dart gives
/// structural equality and `hashCode` for free, which is the whole of what a
/// Riverpod family key needs.
typedef PurchaseRequestRouteRequest = ({
  PurchaseRequestRouteKind kind,
  String prId,
});

/// Resolves [PurchaseRequestAccessPolicy] against the database for one document
/// route.
///
/// Three things make this a real guard rather than a hint:
///
/// * The acting user is **re-read from the database** through
///   [actingUserProvider], so the decision rests on the stored role, branch and
///   `is_active` rather than on whatever the session object claims about itself
///   (O-8). It is the same provider the Stok Opname guard uses — one source, so the
///   two cannot disagree about who is acting.
/// * The document lookup is `findAccessScope`, which selects four columns and, on a
///   branch screen, pins them to the actor's own branch. Deciding whether a
///   document may be shown never loads the document — so a refusal cannot leak the
///   document number, the cited counts, the items, the quantities or the notes.
/// * Whether the lookup is branch-scoped at all is
///   [PurchaseRequestAccessPolicy.requiresBranchScope]'s answer, not this file's.
///   The warehouse's queue spans branches by design, and deciding that here would
///   be a second copy of the rule.
///
/// It watches the session, so switching user re-runs the whole decision instead of
/// serving the previous user's verdict from cache.
final purchaseRequestRouteAccessProvider = FutureProvider.autoDispose
    .family<PurchaseRequestAccess, PurchaseRequestRouteRequest>((
      ref,
      request,
    ) async {
      final session = ref.watch(currentSessionValueProvider);
      if (session == null) {
        return const PurchaseRequestAccess.denied(
          PurchaseRequestAccessDenialReason.noSession,
        );
      }

      final MasterUser? actor = await ref.watch(actingUserProvider.future);

      final section = PurchaseRequestAccessPolicy.forSection(
        user: actor,
        kind: request.kind,
      );
      // Short-circuits on purpose: a role that may not reach this screen at all
      // must not cause a document lookup, not even a scoped one.
      if (section.isDenied) return section;

      final PurchaseRequestAccessScope? scope = await ref
          .watch(purchaseRequestRepositoryProvider)
          .findAccessScope(
            prId: request.prId,
            // `null` widens the lookup to every branch, and only the warehouse
            // kinds ask for that. `actor` is non-null and, on a branch screen, has
            // a branch — `forSection` granted, and it refuses a branch-scoped role
            // without one.
            branchId:
                PurchaseRequestAccessPolicy.requiresBranchScope(request.kind)
                ? actor!.branchId!
                : null,
          );

      return PurchaseRequestAccessPolicy.forDocument(
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
class PurchaseRequestRouteGuard extends ConsumerWidget {
  const PurchaseRequestRouteGuard({
    super.key,
    required this.kind,
    required this.prId,
    required this.builder,
  });

  final PurchaseRequestRouteKind kind;
  final String prId;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(
      purchaseRequestRouteAccessProvider((kind: kind, prId: prId)),
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

/// Guards a Purchase Request screen that does **not** name a document.
///
/// `/purchase-requests` and `/warehouse/purchase-requests` are decided by role
/// alone, which the router's synchronous redirect already does from the session.
/// This wrapper re-asks the same question against the *stored* user, so a section
/// reached by any other means — a deep link that arrives before the redirect, a
/// session whose role was changed underneath it — still renders nothing.
class PurchaseRequestSectionGuard extends ConsumerWidget {
  const PurchaseRequestSectionGuard({
    super.key,
    required this.kind,
    required this.builder,
  });

  final PurchaseRequestRouteKind kind;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(actingUserProvider);

    return actor.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const AccessDeniedPage(),
      data: (user) =>
          PurchaseRequestAccessPolicy.forSection(
            user: user,
            kind: kind,
          ).isGranted
          ? builder(context)
          : const AccessDeniedPage(),
    );
  }
}
