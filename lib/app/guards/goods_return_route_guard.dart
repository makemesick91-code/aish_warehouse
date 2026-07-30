import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/acting_user_providers.dart';
import '../../core/session/current_user_session.dart';
import '../../features/goods_return/domain/models/goods_return_models.dart';
import '../../features/goods_return/domain/services/goods_return_access_policy.dart';
import '../../features/goods_return/presentation/providers/goods_return_providers.dart';
import '../../features/master/domain/models/master_models.dart';
import 'access_denied_page.dart';

/// Which document, on which screen. A record rather than a class: Dart gives structural
/// equality and `hashCode` for free, which is the whole of what a Riverpod family key
/// needs.
typedef GoodsReturnRouteRequest = ({
  GoodsReturnRouteKind kind,
  String goodsReturnId,
});

/// Resolves [GoodsReturnAccessPolicy] against the database for one Retur route (§27).
///
/// Four things make this a real guard rather than a hint:
///
/// * The acting user is **re-read from the database** through [actingUserProvider], so
///   the decision rests on the stored role, branch, id and `is_active` rather than on
///   whatever the session object claims about itself (O-8). It is the same provider
///   every earlier guard uses — one source, so the eight cannot disagree about who is
///   acting.
/// * The document lookup is `findAccessScope`, which selects seven columns and pins
///   them to the scope the *route kind* requires. Deciding whether a return may be
///   shown never loads the return — so a refusal cannot leak the RET number, the Good
///   Receipt, the branch, the items, the batches, the quantities, the reject reasons or
///   the notes.
/// * Whether the lookup is branch-scoped, and which statuses it accepts, are
///   [GoodsReturnAccessPolicy]'s answers rather than this file's. The note editor
///   accepts `draft` only and the Warehouse screens accept `shipped` and `received`
///   only; deciding either here would be a second copy of the rule.
/// * The scope row's `branch_id` is compared again in `forDocument`. The SQL predicate
///   is the first line and this is the second, so a caller that ever passed an unscoped
///   lookup by mistake still cannot open another branch's document.
///
/// ### The asymmetry no earlier guard had
///
/// Every earlier route guard scopes *both* audiences by place. This one scopes the
/// branch side by branch and the Warehouse side by **status**, because a Petugas
/// Warehouse legitimately works one queue across every branch (§15). What keeps them
/// out of a branch's private work is that a draft is not in their status set — so the
/// security tests exercise exactly that: a Warehouse user opening a draft's id by hand.
///
/// It watches the session, so switching user re-runs the whole decision instead of
/// serving the previous user's verdict from cache.
final goodsReturnRouteAccessProvider = FutureProvider.autoDispose
    .family<GoodsReturnAccess, GoodsReturnRouteRequest>((ref, request) async {
      final session = ref.watch(currentSessionValueProvider);
      if (session == null) {
        return const GoodsReturnAccess.denied(
          GoodsReturnAccessDenialReason.noSession,
        );
      }

      final MasterUser? actor = await ref.watch(actingUserProvider.future);

      final section = GoodsReturnAccessPolicy.forSection(
        user: actor,
        kind: request.kind,
      );
      // Short-circuits on purpose: a role that may not reach this screen at all must not
      // cause a document lookup, not even a scoped one.
      if (section.isDenied) return section;

      final repository = ref.watch(goodsReturnRepositoryProvider);
      final GoodsReturnAccessScope? scope = await repository.findAccessScope(
        goodsReturnId: request.goodsReturnId,
        scope: GoodsReturnAccessPolicy.requiredScope(request.kind),
        // Null for the Warehouse kinds, and deliberately so: pinning them to a branch
        // would break the cross-branch queue §15 requires. `forSection` has already
        // refused a branch-scoped role with no branch, so `actor!` is safe here.
        branchId: GoodsReturnAccessPolicy.requiresBranch(request.kind)
            ? actor!.branchId
            : null,
        statuses: GoodsReturnAccessPolicy.visibleStatusesFor(request.kind),
      );

      return GoodsReturnAccessPolicy.forDocument(
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
class GoodsReturnRouteGuard extends ConsumerWidget {
  const GoodsReturnRouteGuard({
    super.key,
    required this.kind,
    required this.goodsReturnId,
    required this.builder,
  });

  final GoodsReturnRouteKind kind;
  final String goodsReturnId;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(
      goodsReturnRouteAccessProvider((
        kind: kind,
        goodsReturnId: goodsReturnId,
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

/// Guards a Retur screen that does **not** name a document.
///
/// The two list routes and the create route are decided by role and branch alone, which
/// the router's synchronous redirect already does from the session. This wrapper
/// re-asks the same question against the *stored* user, so a section reached by any
/// other means — a deep link that arrives before the redirect, a session whose role was
/// changed underneath it — still renders nothing.
class GoodsReturnSectionGuard extends ConsumerWidget {
  const GoodsReturnSectionGuard({
    super.key,
    required this.kind,
    required this.builder,
  });

  final GoodsReturnRouteKind kind;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(actingUserProvider);

    return actor.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const AccessDeniedPage(),
      data: (user) =>
          GoodsReturnAccessPolicy.forSection(user: user, kind: kind).isGranted
          ? builder(context)
          : const AccessDeniedPage(),
    );
  }
}

/// Guards the create route, which names a **Good Receipt** rather than a return (§30).
///
/// The eligibility of that receipt is re-checked inside `CreateGoodsReturnUseCase`, so
/// this is not the only defence — but it is what stops the screen fetching a foreign
/// branch's receipt in order to render a summary of it. The lookup is the branch-scoped
/// eligible queue, so a receipt outside the actor's branch simply is not in it.
class GoodsReturnCreateGuard extends ConsumerWidget {
  const GoodsReturnCreateGuard({
    super.key,
    required this.goodReceiptId,
    required this.builder,
  });

  final String goodReceiptId;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eligibility = ref.watch(
      goodsReturnEligibilityByReceiptProvider(goodReceiptId),
    );

    return eligibility.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const AccessDeniedPage(),
      // `null` covers "no such receipt", "another branch's" and "nothing rejected" with
      // one answer, so the address bar cannot be used to tell them apart (§27).
      data: (row) => row == null ? const AccessDeniedPage() : builder(context),
    );
  }
}
