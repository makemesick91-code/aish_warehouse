import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/acting_user_providers.dart';
import '../../core/session/current_user_session.dart';
import '../../features/master/domain/models/master_models.dart';
import '../../features/opname/domain/models/opname_models.dart';
import '../../features/opname/domain/services/opname_access_policy.dart';
import '../../features/opname/presentation/providers/opname_providers.dart';
import 'access_denied_page.dart';

/// Which document, on which screen. A record rather than a class: Dart gives
/// structural equality and `hashCode` for free, which is the whole of what a
/// Riverpod family key needs.
typedef OpnameRouteRequest = ({OpnameRouteKind kind, String opnameId});

/// Resolves [OpnameAccessPolicy] against the database for one document route.
///
/// Two things make this a real guard rather than a hint:
///
/// * The acting user is **re-read from the database** by id, so the decision
///   rests on the stored role, branch and `is_active` rather than on whatever
///   the session object claims about itself (O-8).
/// * The document lookup is `findAccessScope`, which selects four columns
///   within the actor's own branch. Deciding whether a document may be shown
///   never loads the document — so a refusal cannot leak the room, the nurse,
///   the quantities or even the document number.
///
/// It `watch`es the session, so switching user re-runs the whole decision
/// instead of serving the previous user's verdict from cache.
final opnameRouteAccessProvider = FutureProvider.autoDispose
    .family<OpnameAccess, OpnameRouteRequest>((ref, request) async {
      final session = ref.watch(currentSessionValueProvider);
      if (session == null) {
        return const OpnameAccess.denied(OpnameAccessDenialReason.noSession);
      }

      // The stored user, not the session's claim about itself, and read through
      // the shared acting-user provider so this guard, the Purchase Request guard
      // and every branch-scoped provider rest on one source (O-8).
      final MasterUser? actor = await ref.watch(actingUserProvider.future);

      final section = OpnameAccessPolicy.forSection(
        user: actor,
        kind: request.kind,
      );
      // Short-circuits on purpose: a role that may not reach this screen at all
      // must not cause a document lookup, not even a scoped one.
      if (section.isDenied) return section;

      final StockOpnameAccessScope? scope = await ref
          .watch(opnameRepositoryProvider)
          .findAccessScope(
            opnameId: request.opnameId,
            // Non-null because `forSection` granted: both roles it admits are
            // branch-scoped, and it refuses a user without a branch.
            branchId: actor!.branchId!,
          );

      return OpnameAccessPolicy.forDocument(
        user: actor,
        kind: request.kind,
        scope: scope,
      );
    });

/// Renders the page only once the route has been cleared.
///
/// The page is passed as a builder rather than a widget, so it and the
/// providers it watches do not exist while the decision is pending or after it
/// is refused. A refused route therefore has no subscription to any document
/// stream — the difference between hiding data and not fetching it.
class OpnameRouteGuard extends ConsumerWidget {
  const OpnameRouteGuard({
    super.key,
    required this.kind,
    required this.opnameId,
    required this.builder,
  });

  final OpnameRouteKind kind;
  final String opnameId;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(
      opnameRouteAccessProvider((kind: kind, opnameId: opnameId)),
    );

    return access.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      // A guard that fails open is not a guard. Anything unexpected while
      // deciding is treated as a refusal.
      error: (_, _) => const AccessDeniedPage(),
      data: (decision) =>
          decision.isGranted ? builder(context) : const AccessDeniedPage(),
    );
  }
}
