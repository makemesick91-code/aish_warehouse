import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/acting_user_providers.dart';
import '../../core/session/current_user_session.dart';
import '../../features/distribution/domain/models/distribution_models.dart';
import '../../features/distribution/domain/services/distribution_access_policy.dart';
import '../../features/distribution/presentation/providers/distribution_providers.dart';
import '../../features/master/domain/models/master_models.dart';
import 'access_denied_page.dart';

/// Which document, on which screen. A record rather than a class: Dart gives
/// structural equality and `hashCode` for free, which is the whole of what a Riverpod
/// family key needs.
typedef DistributionRouteRequest = ({
  DistributionRouteKind kind,
  String distributionId,
});

/// Resolves [DistributionAccessPolicy] against the database for one distribution
/// route.
///
/// Three things make this a real guard rather than a hint:
///
/// * The acting user is **re-read from the database** through [actingUserProvider], so
///   the decision rests on the stored role, branch and `is_active` rather than on
///   whatever the session object claims about itself (O-8). It is the same provider the
///   Stok Opname, Purchase Request, Delivery Order and Good Receipt guards use — one
///   source, so the five cannot disagree about who is acting.
/// * The document lookup is `findAccessScope`, which selects four columns and pins them
///   to the actor's own branch. Deciding whether a distribution may be shown never
///   loads the distribution — so a refusal cannot leak the DIST number, the rooms, the
///   items, the batches or the quantities.
/// * Whether the lookup is branch-scoped, and which statuses it accepts, are
///   [DistributionAccessPolicy]'s answers rather than this file's. The editor accepts
///   `draft` only, and deciding that here would be a second copy of the rule.
///
/// It watches the session, so switching user re-runs the whole decision instead of
/// serving the previous user's verdict from cache.
final distributionRouteAccessProvider = FutureProvider.autoDispose
    .family<DistributionAccess, DistributionRouteRequest>((ref, request) async {
      final session = ref.watch(currentSessionValueProvider);
      if (session == null) {
        return const DistributionAccess.denied(
          DistributionAccessDenialReason.noSession,
        );
      }

      final MasterUser? actor = await ref.watch(actingUserProvider.future);

      final section = DistributionAccessPolicy.forSection(
        user: actor,
        kind: request.kind,
      );
      // Short-circuits on purpose: a role that may not reach this screen at all must
      // not cause a document lookup, not even a scoped one.
      if (section.isDenied) return section;

      final DistributionAccessScope? scope = await ref
          .watch(distributionRepositoryProvider)
          .findAccessScope(
            distributionId: request.distributionId,
            // Always the actor's own branch: `requiresBranchScope` answers `true` for
            // every kind, because this document has no warehouse side at all. `actor`
            // is non-null and has a branch — `forSection` granted, and it refuses a
            // branch-scoped role without one.
            branchId: DistributionAccessPolicy.requiresBranchScope(request.kind)
                ? actor!.branchId!
                : null,
            statuses: DistributionAccessPolicy.visibleStatuses(request.kind),
          );

      return DistributionAccessPolicy.forDocument(
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
class DistributionRouteGuard extends ConsumerWidget {
  const DistributionRouteGuard({
    super.key,
    required this.kind,
    required this.distributionId,
    required this.builder,
  });

  final DistributionRouteKind kind;
  final String distributionId;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(
      distributionRouteAccessProvider((
        kind: kind,
        distributionId: distributionId,
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

/// Guards a Distribusi screen that does **not** name a document.
///
/// `/distributions` and `/distributions/new` are decided by role and branch alone,
/// which the router's synchronous redirect already does from the session. This wrapper
/// re-asks the same question against the *stored* user, so a section reached by any
/// other means — a deep link that arrives before the redirect, a session whose role was
/// changed underneath it — still renders nothing.
class DistributionSectionGuard extends ConsumerWidget {
  const DistributionSectionGuard({
    super.key,
    required this.kind,
    required this.builder,
  });

  final DistributionRouteKind kind;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(actingUserProvider);

    return actor.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const AccessDeniedPage(),
      data: (user) =>
          DistributionAccessPolicy.forSection(user: user, kind: kind).isGranted
          ? builder(context)
          : const AccessDeniedPage(),
    );
  }
}
