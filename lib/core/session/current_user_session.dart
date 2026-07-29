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

  String get roleLabel => switch (user.role) {
    UserRole.perawat => 'Perawat',
    UserRole.kepalaCabang => 'Kepala Cabang',
    UserRole.warehouse => 'Petugas Warehouse',
    UserRole.superAdmin => 'Super Admin',
  };

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
