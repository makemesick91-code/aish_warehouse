import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/master/domain/models/master_models.dart';
import '../../features/master/presentation/providers/master_providers.dart';
import '../enums/app_enums.dart';

/// Who the app is acting as.
///
/// This is the shape the rest of the application programs against. It carries a
/// [MasterUser] loaded from the database — never a hard-coded id or email — so
/// swapping [DevelopmentSessionController] for real authentication later
/// changes only how the session is *obtained*, not how it is used.
///
/// The permissions below are for **UI affordances**: which screens to offer and
/// which buttons to enable. They are not the enforcement point. Every use case
/// re-reads the actor from the database and applies the same rules again, so a
/// tampered session cannot widen anyone's authority (G-R1/G-R2/G-R4).
@immutable
class CurrentUserSession {
  const CurrentUserSession(this.user);

  final MasterUser user;

  String get userId => user.id;

  String get displayName => user.fullName;

  UserRole get role => user.role;

  String? get branchId => user.branchId;

  bool get isPerawat => user.role == UserRole.perawat;

  bool get isKepalaCabang => user.role == UserRole.kepalaCabang;

  /// Perawat fill in stock counts (spec §3.1).
  bool get canFillOpname => isPerawat && branchId != null;

  /// Kepala Cabang review and lock them.
  bool get canReviewOpname => isKepalaCabang && branchId != null;

  /// Any branch-scoped role may read the documents of its own branch.
  bool get canViewOpname => canFillOpname || canReviewOpname;

  bool get isWarehouse => user.role == UserRole.warehouse;

  /// Kepala Cabang raise and send Purchase Requests (spec §3.1).
  bool get canManagePurchaseRequest => isKepalaCabang && branchId != null;

  /// The central warehouse processes and rejects them. It carries no branch by
  /// design, so — unlike the branch-scoped predicates above — this one must not
  /// ask for one.
  bool get canProcessPurchaseRequest => isWarehouse;

  /// Kepala Cabang distribute from the *Gudang Cabang* to their own rooms
  /// (spec §3.1, G-T1).
  ///
  /// Branch-scoped, and the branch is part of the predicate rather than an
  /// afterthought: *"ke ruangan dalam cabang yang sama"* is meaningless without one,
  /// and this affordance must not appear for an account that has none. Warehouse,
  /// Perawat and Super Admin answer `false` — an account being powerful is not a
  /// reason to offer it somebody else's job (G-R4).
  bool get canDistribute => isKepalaCabang && branchId != null;

  /// The Petugas Warehouse destroys expired stock at Warehouse Pusat (G-E7, §14).
  ///
  /// Unscoped by branch, exactly like [canProcessPurchaseRequest]: the central
  /// warehouse carries `users.branch_id = NULL` by design, so asking for one here
  /// would refuse the only account that has this job.
  bool get canDisposeWarehouseStock => isWarehouse;

  /// The Kepala Cabang destroys expired stock in their own *Gudang Cabang* and
  /// rooms (G-E7, §14).
  ///
  /// Branch-scoped, and the branch is part of the predicate rather than an
  /// afterthought: *"stok cabangnya sendiri"* is meaningless without one. Perawat and
  /// Super Admin answer `false` to both — a nurse sees the expiry badges through the
  /// stock module (G-E6) but has no document that removes inventory, and an account
  /// being powerful is not a reason to hand it somebody else's job (G-R4).
  bool get canDisposeBranchStock => isKepalaCabang && branchId != null;

  /// The Perawat records what was used in a room (schema v10, §14).
  ///
  /// Branch-scoped, and the branch is part of the predicate rather than an
  /// afterthought: *"ruangan di cabangnya sendiri"* is meaningless without one, and
  /// this affordance must not appear for an account that has none.
  ///
  /// Kepala Cabang, Warehouse and Super Admin all answer `false`, and the branch head's
  /// `false` is the one worth stating. Spec §3.1 gives them branch-level acts — review,
  /// request, receive, distribute — and recording what physically came out of a packet
  /// in a treatment room is not one of them: the person who opened it is the only one
  /// who knows how much. What they get instead is [canReadConsumptionHistory].
  bool get canRecordConsumption => isPerawat && branchId != null;

  /// The Kepala Cabang reads their branch's **posted** consumption history (§14/§31).
  ///
  /// Read-only, and deliberately a separate predicate from
  /// [canRecordConsumption] rather than a widening of it: the two describe different
  /// acts on different documents, and one predicate covering both would be the quiet
  /// grant G-R4 is about. A nurse's unposted draft is outside this too — it is their
  /// account of a shift until they post it.
  bool get canReadConsumptionHistory => isKepalaCabang && branchId != null;

  /// Whether this session may raise, edit and ship Retur documents (Milestone 9, §15).
  ///
  /// The same branch-scoped shape [canDistribute] has, and for the same reason: the
  /// goods being sent back are physically at *their* branch, and the rejection that
  /// produced them was their own decision (G-G4/G-G5).
  bool get canManageGoodsReturn => isKepalaCabang && branchId != null;

  /// Whether this session may work the Retur queue and confirm arrivals (§15).
  ///
  /// Deliberately **not** branch-scoped: a Petugas Warehouse operates Warehouse Pusat,
  /// which belongs to no branch, and the returns from every branch arrive at that one
  /// building. What keeps them out of a branch's unfinished work is the status scope on
  /// the query, not a branch predicate.
  ///
  /// Says nothing about *which* document they may confirm — G-R4 forbids the creator or
  /// the shipper from being the receiver, and that is a question about a person and a
  /// document rather than about a session.
  bool get canReceiveGoodsReturn => isWarehouse;

  String get roleLabel => user.role.label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CurrentUserSession && other.user.id == user.id);

  @override
  int get hashCode => user.id.hashCode;
}

/// Chooses the acting user while there is no authentication backend.
///
/// **Development only.** Supabase Auth is not part of this milestone, and
/// pretending otherwise would mean inventing a login flow that has to be thrown
/// away. Instead this controller picks a seeded user and lets the developer
/// switch roles, which is exactly what is needed to exercise the Perawat →
/// Kepala Cabang handover end to end.
///
/// What it deliberately does **not** do is grant anything. It hands a user id to
/// the use cases, and they decide. When real auth arrives, this class is
/// replaced by one that resolves the session from a token — no call site
/// changes.
class DevelopmentSessionController extends AsyncNotifier<CurrentUserSession?> {
  @override
  Future<CurrentUserSession?> build() async {
    final users = await ref.watch(masterDataRepositoryProvider).activeUsers();
    if (users.isEmpty) return null;

    // Default to a nurse: the Stok Opname workflow starts there.
    final nurse = users.where((user) => user.role == UserRole.perawat);
    return CurrentUserSession(nurse.isNotEmpty ? nurse.first : users.first);
  }

  /// Switches the acting user, e.g. from the nurse who counted to the branch
  /// head who reviews.
  Future<void> switchTo(String userId) async {
    final repository = ref.read(masterDataRepositoryProvider);
    state = const AsyncValue<CurrentUserSession?>.loading();
    state = await AsyncValue.guard(() async {
      final user = await repository.userById(userId);
      return user == null ? null : CurrentUserSession(user);
    });
  }

  /// Picks the first active user holding [role], if the seed created one.
  Future<void> switchToRole(UserRole role) async {
    final repository = ref.read(masterDataRepositoryProvider);
    final users = await repository.activeUsers();
    final match = users.where((user) => user.role == role);
    if (match.isEmpty) return;
    await switchTo(match.first.id);
  }
}

final currentSessionProvider =
    AsyncNotifierProvider<DevelopmentSessionController, CurrentUserSession?>(
      DevelopmentSessionController.new,
    );

/// The acting session, or `null` while it is loading or master data is empty.
/// Widgets that must not render without one use this and show an empty state.
final currentSessionValueProvider = Provider<CurrentUserSession?>(
  (ref) => ref.watch(currentSessionProvider).value,
);

/// Every user that can be switched to on the development role picker.
final selectableSessionUsersProvider = FutureProvider<List<MasterUser>>(
  (ref) => ref.watch(masterDataRepositoryProvider).activeUsers(),
);
