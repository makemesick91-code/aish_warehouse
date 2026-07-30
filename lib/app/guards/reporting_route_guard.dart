import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/acting_user_providers.dart';
import '../../features/reports/domain/services/report_access_policy.dart';
import 'access_denied_page.dart';

/// Refuses a reporting route before its page is built (§43).
///
/// ### What a refusal must not reveal
///
/// `/reports/export-history` typed by a Kepala Cabang renders [AccessDeniedPage] and
/// nothing else — no branch name, no location, no file name, no exporter, no row
/// count, and no hint that any export exists. The guard runs **before** the page, so
/// no provider is read and no query is issued: there is nothing to leak because
/// nothing was fetched.
///
/// ### Why the actor is re-read here
///
/// [actingUserProvider] loads the user from the database by id, so the decision
/// rests on the stored role and `is_active` rather than on whatever the session
/// claims (O-8). It is the same provider the seven earlier route guards use — one
/// source, so the eight cannot disagree about who is acting.
///
/// ### And why this is not the only defence
///
/// A guard protects a *route*. The audit stream is a provider, and a provider can be
/// read from anywhere; [WatchExportHistoryUseCase] therefore applies the same role
/// check against the same re-read actor before it opens a stream, and the preview
/// and export use cases re-check scope on every call (§16). This is the first line,
/// not the line.
class ReportingSectionGuard extends ConsumerWidget {
  const ReportingSectionGuard({
    super.key,
    required this.kind,
    required this.builder,
  });

  final ReportRouteKind kind;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(actingUserProvider);

    return actor.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      // An error resolving the actor is treated as a refusal, not as a page with an
      // error on it: whether the user *may* be here is precisely the question that
      // failed, and rendering the report anyway would answer it optimistically.
      error: (_, _) => const AccessDeniedPage(),
      data: (user) =>
          ReportAccessPolicy.forSection(user: user, kind: kind).isGranted
          ? builder(context)
          : const AccessDeniedPage(),
    );
  }
}
