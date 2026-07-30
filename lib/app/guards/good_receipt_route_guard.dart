import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/acting_user_providers.dart';
import '../../core/session/current_user_session.dart';
import '../../features/delivery/domain/models/delivery_models.dart';
import '../../features/delivery/presentation/providers/delivery_providers.dart';
import '../../features/good_receipt/domain/models/good_receipt_models.dart';
import '../../features/good_receipt/domain/services/good_receipt_access_policy.dart';
import '../../features/good_receipt/presentation/providers/good_receipt_providers.dart';
import '../../features/master/domain/models/master_models.dart';
import 'access_denied_page.dart';

/// Which receipt, on which screen. A record rather than a class: Dart gives
/// structural equality and `hashCode` for free, which is the whole of what a Riverpod
/// family key needs.
typedef GoodReceiptRouteRequest = ({GoodReceiptRouteKind kind, String grId});

/// The same, for the create route — which names a **Delivery Order**.
typedef GoodReceiptCreateRequest = ({GoodReceiptRouteKind kind, String doId});

/// Resolves [GoodReceiptAccessPolicy] against the database for one receipt route.
///
/// Three things make this a real guard rather than a hint:
///
/// * The acting user is **re-read from the database** through [actingUserProvider], so
///   the decision rests on the stored role, branch and `is_active` rather than on
///   whatever the session object claims about itself (O-8). It is the same provider the
///   Stok Opname, Purchase Request and Delivery Order guards use — one source, so the
///   four cannot disagree about who is acting.
/// * The document lookup is `findAccessScope`, which selects five columns and, on a
///   branch screen, pins them to the actor's own branch; on a warehouse screen it pins
///   them to `posted`. Deciding whether a receipt may be shown never loads the
///   receipt — so a refusal cannot leak the receipt number, the Surat Jalan number,
///   the PR number, the branch, the items, the batches, the quantities or the reject
///   reasons.
/// * Whether the lookup is branch-scoped, and which statuses it accepts, are
///   [GoodReceiptAccessPolicy]'s answers rather than this file's. The warehouse's queue
///   spans branches by design, and deciding that here would be a second copy of the
///   rule.
///
/// It watches the session, so switching user re-runs the whole decision instead of
/// serving the previous user's verdict from cache.
final goodReceiptRouteAccessProvider = FutureProvider.autoDispose
    .family<GoodReceiptAccess, GoodReceiptRouteRequest>((ref, request) async {
      final session = ref.watch(currentSessionValueProvider);
      if (session == null) {
        return const GoodReceiptAccess.denied(
          GoodReceiptAccessDenialReason.noSession,
        );
      }

      final MasterUser? actor = await ref.watch(actingUserProvider.future);

      final section = GoodReceiptAccessPolicy.forSection(
        user: actor,
        kind: request.kind,
      );
      // Short-circuits on purpose: a role that may not reach this screen at all must
      // not cause a document lookup, not even a scoped one.
      if (section.isDenied) return section;

      final GoodReceiptAccessScope? scope = await ref
          .watch(goodReceiptRepositoryProvider)
          .findAccessScope(
            grId: request.grId,
            // `null` widens the lookup to every branch, and only the warehouse kinds
            // ask for that. `actor` is non-null and, on a branch screen, has a branch —
            // `forSection` granted, and it refuses a branch-scoped role without one.
            branchId: GoodReceiptAccessPolicy.requiresBranchScope(request.kind)
                ? actor!.branchId!
                : null,
            statuses: GoodReceiptAccessPolicy.visibleStatuses(request.kind),
          );

      return GoodReceiptAccessPolicy.forDocument(
        user: actor,
        kind: request.kind,
        scope: scope,
      );
    });

/// The same decision for the create route, whose id names a shipment.
///
/// The lookup is the *Delivery Order's* access scope, carrying both the branch
/// predicate and G-G1's status predicate, so a `preparing` shipment or another
/// branch's is refused without ever being read. Whether a receipt already exists is
/// deliberately not part of it: that is a second row's existence rather than an
/// authorization fact, and the page resumes the checklist instead of refusing the
/// route.
final goodReceiptCreateAccessProvider = FutureProvider.autoDispose
    .family<GoodReceiptAccess, GoodReceiptCreateRequest>((ref, request) async {
      final session = ref.watch(currentSessionValueProvider);
      if (session == null) {
        return const GoodReceiptAccess.denied(
          GoodReceiptAccessDenialReason.noSession,
        );
      }

      final MasterUser? actor = await ref.watch(actingUserProvider.future);

      final section = GoodReceiptAccessPolicy.forSection(
        user: actor,
        kind: request.kind,
      );
      if (section.isDenied) return section;

      final DeliveryOrderAccessScope? scope = await ref
          .watch(deliveryOrderRepositoryProvider)
          .findAccessScope(
            doId: request.doId,
            branchId: actor!.branchId!,
            statuses: GoodReceiptAccessPolicy.visibleDeliveryOrderStatuses(
              request.kind,
            ),
          );

      return GoodReceiptAccessPolicy.forDeliveryOrder(
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
class GoodReceiptRouteGuard extends ConsumerWidget {
  const GoodReceiptRouteGuard({
    super.key,
    required this.kind,
    required this.grId,
    required this.builder,
  });

  final GoodReceiptRouteKind kind;
  final String grId;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(
      goodReceiptRouteAccessProvider((kind: kind, grId: grId)),
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

/// The same, for the route that names a shipment rather than a receipt.
class GoodReceiptCreateRouteGuard extends ConsumerWidget {
  const GoodReceiptCreateRouteGuard({
    super.key,
    required this.doId,
    required this.builder,
  });

  final String doId;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(
      goodReceiptCreateAccessProvider((
        kind: GoodReceiptRouteKind.branchCreate,
        doId: doId,
      )),
    );

    return access.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const AccessDeniedPage(),
      data: (decision) =>
          decision.isGranted ? builder(context) : const AccessDeniedPage(),
    );
  }
}

/// Guards a Good Receipt screen that does **not** name a document.
///
/// `/receipts`, `/warehouse/good-receipts` and the discrepancy queue are decided by
/// role alone, which the router's synchronous redirect already does from the session.
/// This wrapper re-asks the same question against the *stored* user, so a section
/// reached by any other means — a deep link that arrives before the redirect, a session
/// whose role was changed underneath it — still renders nothing.
class GoodReceiptSectionGuard extends ConsumerWidget {
  const GoodReceiptSectionGuard({
    super.key,
    required this.kind,
    required this.builder,
  });

  final GoodReceiptRouteKind kind;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(actingUserProvider);

    return actor.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const AccessDeniedPage(),
      data: (user) =>
          GoodReceiptAccessPolicy.forSection(user: user, kind: kind).isGranted
          ? builder(context)
          : const AccessDeniedPage(),
    );
  }
}
