import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/acting_user_providers.dart';
import '../../features/master/domain/services/master_admin_access_policy.dart';
import 'access_denied_page.dart';

/// Refuses a master or import route before its page is built (G-M1, §37).
///
/// ### What a refusal must not reveal
///
/// `/master/users` typed by a Kepala Cabang renders [AccessDeniedPage] and
/// nothing else — no email, no role, no branch, no entity count, no import
/// filename, no error detail, no hash. The guard runs **before** the page, so no
/// provider is read and no query is issued: there is nothing to leak because
/// nothing was fetched.
///
/// `/imports/{id}` behaves identically for an id that exists and one that does
/// not. Telling them apart would let anyone who reaches the route enumerate which
/// import ids are real.
///
/// ### Why the actor is re-read here
///
/// [actingUserProvider] loads the user from the database by id, so the decision
/// rests on the stored role and `is_active` rather than on whatever the session
/// claims (O-8). It is the same provider the eight earlier route guards use — one
/// source, so the nine cannot disagree about who is acting.
///
/// ### And why this is not the only defence
///
/// A guard protects a *route*. Every list is a provider, and a provider can be
/// read from anywhere; every provider in this feature therefore applies the same
/// policy against the same re-read actor, every write use case reloads the actor
/// again, and the commit re-checks inside its transaction (§53). This is the
/// first line, not the line.
class MasterAdminSectionGuard extends ConsumerWidget {
  const MasterAdminSectionGuard({
    super.key,
    required this.kind,
    required this.builder,
  });

  final MasterAdminRouteKind kind;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(actingUserProvider);

    return actor.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      // An error resolving the actor is treated as a refusal, not as a page with
      // an error on it: whether the user *may* be here is precisely the question
      // that failed, and rendering the master list anyway would answer it
      // optimistically.
      error: (_, _) => const AccessDeniedPage(),
      data: (user) =>
          MasterAdminAccessPolicy.forSection(user: user, kind: kind).isGranted
          ? builder(context)
          : const AccessDeniedPage(),
    );
  }
}
