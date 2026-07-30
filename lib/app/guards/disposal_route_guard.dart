import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/acting_user_providers.dart';
import '../../core/session/current_user_session.dart';
import '../../features/disposal/domain/models/disposal_models.dart';
import '../../features/disposal/domain/services/disposal_access_policy.dart';
import '../../features/disposal/presentation/providers/disposal_providers.dart';
import '../../features/master/domain/models/master_models.dart';
import 'access_denied_page.dart';

/// Which document, on which screen. A record rather than a class: Dart gives
/// structural equality and `hashCode` for free, which is the whole of what a
/// Riverpod family key needs.
typedef DisposalRouteRequest = ({DisposalRouteKind kind, String disposalId});

/// Resolves [DisposalAccessPolicy] against the database for one disposal route.
///
/// Four things make this a real guard rather than a hint:
///
/// * The acting user is **re-read from the database** through [actingUserProvider],
///   so the decision rests on the stored role, branch and `is_active` rather than on
///   whatever the session object claims about itself (O-8). It is the same provider
///   the Stok Opname, Purchase Request, Delivery Order, Good Receipt and Distribusi
///   guards use — one source, so the six cannot disagree about who is acting.
/// * The document lookup is `findAccessScope`, which selects four columns and pins
///   them to the scope the *route kind* requires. Deciding whether a disposal may be
///   shown never loads the disposal — so a refusal cannot leak the DSP number, the
///   source location, the items, the batches, the quantities or the reason.
/// * Whether the lookup is warehouse- or branch-scoped, and which statuses it
///   accepts, are [DisposalAccessPolicy]'s answers rather than this file's. The
///   editor accepts `draft` only, and deciding that here would be a second copy of
///   the rule.
/// * The document's *source branch* is resolved separately and compared. The SQL
///   predicate is the first line — a branch head's lookup already carries
///   `stock_locations.branch_id = ?` — and this is the second, so a caller that ever
///   passed an unscoped lookup by mistake still cannot open somebody else's
///   document.
///
/// It watches the session, so switching user re-runs the whole decision instead of
/// serving the previous user's verdict from cache.
final disposalRouteAccessProvider = FutureProvider.autoDispose
    .family<DisposalAccess, DisposalRouteRequest>((ref, request) async {
      final session = ref.watch(currentSessionValueProvider);
      if (session == null) {
        return const DisposalAccess.denied(
          DisposalAccessDenialReason.noSession,
        );
      }

      final MasterUser? actor = await ref.watch(actingUserProvider.future);

      final section = DisposalAccessPolicy.forSection(
        user: actor,
        kind: request.kind,
      );
      // Short-circuits on purpose: a role that may not reach this screen at all must
      // not cause a document lookup, not even a scoped one.
      if (section.isDenied) return section;

      final repository = ref.watch(disposalRepositoryProvider);
      final DisposalAccessScope? scope = await repository.findAccessScope(
        disposalId: request.disposalId,
        scope: DisposalAccessPolicy.requiredScope(request.kind),
        // `actor` is non-null and, on a branch screen, has a branch — `forSection`
        // granted, and it refuses a branch-scoped role without one.
        branchId: DisposalAccessPolicy.requiresBranchScope(request.kind)
            ? actor!.branchId
            : null,
        statuses: DisposalAccessPolicy.visibleStatusesFor(request.kind),
      );

      // The source's branch, for the belt-and-braces comparison. Resolved only once
      // the scoped lookup has already said yes, so a refused document still costs no
      // second query.
      String? sourceBranchId;
      if (scope != null) {
        sourceBranchId = (await repository.historicalLocationById(
          scope.sourceLocationId,
        ))?.branchId;
      }

      return DisposalAccessPolicy.forDocument(
        user: actor,
        kind: request.kind,
        scope: scope,
        sourceBranchId: sourceBranchId,
      );
    });

/// Renders the page only once the route has been cleared.
///
/// The page is passed as a builder rather than a widget, so it and the providers it
/// watches do not exist while the decision is pending or after it is refused. A
/// refused route therefore has no subscription to any document stream — the
/// difference between hiding data and not fetching it.
class DisposalRouteGuard extends ConsumerWidget {
  const DisposalRouteGuard({
    super.key,
    required this.kind,
    required this.disposalId,
    required this.builder,
  });

  final DisposalRouteKind kind;
  final String disposalId;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(
      disposalRouteAccessProvider((kind: kind, disposalId: disposalId)),
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

/// Guards a Pemusnahan screen that does **not** name a document.
///
/// The list and create routes are decided by role and branch alone, which the
/// router's synchronous redirect already does from the session. This wrapper
/// re-asks the same question against the *stored* user, so a section reached by any
/// other means — a deep link that arrives before the redirect, a session whose role
/// was changed underneath it — still renders nothing.
class DisposalSectionGuard extends ConsumerWidget {
  const DisposalSectionGuard({
    super.key,
    required this.kind,
    required this.builder,
  });

  final DisposalRouteKind kind;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(actingUserProvider);

    return actor.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const AccessDeniedPage(),
      data: (user) =>
          DisposalAccessPolicy.forSection(user: user, kind: kind).isGranted
          ? builder(context)
          : const AccessDeniedPage(),
    );
  }
}
