import '../../../../core/enums/app_enums.dart';
import '../../../master/domain/models/master_models.dart';
import '../models/opname_models.dart';

/// Which Stok Opname screen is being asked for.
///
/// Named per screen rather than per URL so the rule reads as a permission
/// question ("may this person review this document?") instead of a routing one.
enum OpnameRouteKind {
  /// `/opname` — the nurse's own history.
  list,

  /// `/opname/{id}` — the counting sheet, editable only while it is a draft.
  document,

  /// `/opname/review` — the branch head's inbox.
  reviewList,

  /// `/opname/review/{id}` — the review sheet for one document.
  reviewDocument,
}

/// Why a screen was refused. The UI shows one sentence for all of them; the
/// distinction exists so tests and logs can be precise about which rule fired.
enum OpnameAccessDenialReason {
  /// No session yet — still loading, or master data has not been seeded.
  noSession,

  /// The acting user's role does not reach this screen at all.
  role,

  /// The acting user holds a branch-scoped role but no branch.
  noBranch,

  /// The document belongs to another branch, or does not exist. These are
  /// deliberately the same answer (§6.5).
  documentOutOfScope,

  /// The document exists in the right branch but is not in a status this
  /// screen may show — a draft has nothing to review.
  documentStatus,
}

/// The outcome of an access check.
class OpnameAccess {
  const OpnameAccess._(this.reason);

  const OpnameAccess.granted() : reason = null;

  const OpnameAccess.denied(OpnameAccessDenialReason reason) : this._(reason);

  /// `null` when access was granted.
  final OpnameAccessDenialReason? reason;

  bool get isGranted => reason == null;

  bool get isDenied => reason != null;

  /// The single sentence every refusal shows.
  ///
  /// One message for every reason on purpose. "This document belongs to
  /// another branch" and "this document does not exist" are different facts,
  /// and telling them apart would let anyone with the app enumerate which
  /// document ids are real across the whole clinic group.
  static const String deniedMessage =
      'Anda tidak memiliki akses ke halaman ini. Dokumen ini mungkin tidak ada '
      'atau berada di cabang lain.';
}

/// Who may read which Stok Opname screen (spec §3.1, G-R1/G-R2).
///
/// This is a **read** authorization rule, and it is separate from the write
/// guards in `OpnameGuards` for a reason. The write guards answer "may this
/// action be performed", and they are the last word — every use case re-reads
/// the actor from the database and applies them. But by the time a write is
/// refused, a document from another branch has already been fetched, rendered
/// and read. The rules here run first and decide whether it is fetched at all.
///
/// The policy is a pure function of facts the caller already holds, so it can
/// be exercised without a database, a widget tree or a router — and so the
/// route guard, the providers and the repository queries all agree by
/// construction rather than by three similar-looking `if` statements.
abstract final class OpnameAccessPolicy {
  /// Whether [user] may reach a screen that does not name a document.
  ///
  /// [user] is the *stored* user, not the session's claim about itself: the
  /// caller resolves it, so a tampered session cannot widen anything (O-8).
  static OpnameAccess forSection({
    required MasterUser? user,
    required OpnameRouteKind kind,
  }) {
    if (user == null) {
      return const OpnameAccess.denied(OpnameAccessDenialReason.noSession);
    }
    if (!user.isActive) {
      return const OpnameAccess.denied(OpnameAccessDenialReason.role);
    }

    final allowedRoles = switch (kind) {
      // Both branch-scoped roles may *read* the counts of their own branch:
      // the nurse fills them, and G-R2 gives the branch head the documents of
      // their branch. Filling one is still nurse-only, but that is a write
      // rule and the use cases own it — widening it here to keep routing
      // simple is exactly what this policy must not do.
      OpnameRouteKind.list || OpnameRouteKind.document => const {
        UserRole.perawat,
        UserRole.kepalaCabang,
      },
      // Review and lock is the branch head's, and nobody else's — under G-R4
      // even a second nurse must not reach the review screen.
      OpnameRouteKind.reviewList ||
      OpnameRouteKind.reviewDocument => const {UserRole.kepalaCabang},
    };

    if (!allowedRoles.contains(user.role)) {
      return const OpnameAccess.denied(OpnameAccessDenialReason.role);
    }
    // Both roles above are branch-scoped by definition; a row without one
    // cannot be scoped to anything and is refused rather than treated as
    // "every branch".
    if (user.branchId == null) {
      return const OpnameAccess.denied(OpnameAccessDenialReason.noBranch);
    }
    return const OpnameAccess.granted();
  }

  /// Whether [user] may open one specific document.
  ///
  /// [scope] is `null` when the id resolves to nothing *within the user's own
  /// branch* — which covers both "no such document" and "somebody else's
  /// branch", because the lookup that produced it was branch-scoped and can
  /// therefore not tell the two apart. That is the intended design, not a
  /// limitation.
  static OpnameAccess forDocument({
    required MasterUser? user,
    required OpnameRouteKind kind,
    required StockOpnameAccessScope? scope,
  }) {
    final section = forSection(user: user, kind: kind);
    if (section.isDenied) return section;

    if (scope == null || scope.branchId != user!.branchId) {
      return const OpnameAccess.denied(
        OpnameAccessDenialReason.documentOutOfScope,
      );
    }

    // A draft has not been handed over yet, so there is nothing for the branch
    // head to review and the review screen must not open on it (G-O4/G-S1).
    // The nurse's own sheet, by contrast, renders every status — read-only once
    // the document leaves draft (G-S2).
    if (kind == OpnameRouteKind.reviewDocument && scope.status.isDraft) {
      return const OpnameAccess.denied(OpnameAccessDenialReason.documentStatus);
    }

    return const OpnameAccess.granted();
  }
}
