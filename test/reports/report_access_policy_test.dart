import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:aish_warehouse/features/reports/domain/models/reporting_models.dart';
import 'package:aish_warehouse/features/reports/domain/services/report_access_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// G-L1 — *"Cakupan laporan mengikuti RBAC."*
///
/// > Perawat hanya ruangannya; Kepala Cabang hanya gudang cabang + ruangan
/// > cabangnya; Warehouse hanya warehouse pusat + rekap lintas cabang; Super Admin
/// > semua.
///
/// The policy is a pure function, so this file exercises the whole matrix without a
/// database — which is what makes it worth asserting exhaustively rather than
/// sampling. The repository and widget tests then check that the *rest* of the
/// module actually asks it.
void main() {
  const branchId = 'branch-1';
  const otherBranchId = 'branch-2';

  MasterUser userOf(UserRole role, {String? branch, bool isActive = true}) =>
      MasterUser(
        id: 'user-${role.dbValue}',
        fullName: 'Uji ${role.label}',
        email: '${role.dbValue}@test.local',
        role: role,
        branchId: branch,
        isActive: isActive,
      );

  final nurse = userOf(UserRole.perawat, branch: branchId);
  final branchHead = userOf(UserRole.kepalaCabang, branch: branchId);
  final warehouse = userOf(UserRole.warehouse);
  final superAdmin = userOf(UserRole.superAdmin);

  group('Perawat', () {
    test('menjangkau tepat lima jenis laporan', () {
      expect(ReportAccessPolicy.allowedReportTypes(UserRole.perawat), {
        ReportType.stokLokasi,
        ReportType.kartuStok,
        ReportType.rekapOpname,
        ReportType.rekapPemakaian,
        ReportType.kadaluarsa,
      });
    });

    test('tidak menjangkau rekap PR/DO/GR/Distribusi/Retur/Pemusnahan', () {
      final allowed = ReportAccessPolicy.allowedReportTypes(UserRole.perawat);
      for (final type in const [
        ReportType.rekapPr,
        ReportType.rekapDo,
        ReportType.rekapGr,
        ReportType.rekapDistribusi,
        ReportType.rekapRetur,
        ReportType.rekapPemusnahan,
      ]) {
        expect(allowed.contains(type), isFalse, reason: type.dbValue);
      }
    });

    test('hanya cakupan ruangan, untuk setiap laporan yang boleh', () {
      for (final type in ReportAccessPolicy.perawatReports) {
        expect(
          ReportAccessPolicy.allowedScopesFor(
            role: UserRole.perawat,
            reportType: type,
          ),
          {ReportScopeType.room},
          reason: type.dbValue,
        );
      }
    });

    test('ruangan di cabang sendiri diizinkan', () {
      expect(
        ReportAccessPolicy.forRequest(
          user: nurse,
          reportType: ReportType.stokLokasi,
          scopeType: ReportScopeType.room,
          locationType: StockLocationType.room,
          locationBranchId: branchId,
        ).isGranted,
        isTrue,
      );
    });

    test('ruangan di cabang lain ditolak', () {
      final decision = ReportAccessPolicy.forRequest(
        user: nurse,
        reportType: ReportType.stokLokasi,
        scopeType: ReportScopeType.room,
        locationType: StockLocationType.room,
        locationBranchId: otherBranchId,
      );

      expect(decision.isDenied, isTrue);
      expect(decision.reason, ReportAccessDenialReason.location);
    });

    test('Gudang Cabang ditolak', () {
      expect(
        ReportAccessPolicy.forRequest(
          user: nurse,
          reportType: ReportType.stokLokasi,
          scopeType: ReportScopeType.branchStore,
          locationType: StockLocationType.branchStore,
          locationBranchId: branchId,
        ).reason,
        ReportAccessDenialReason.scope,
      );
    });

    test('Warehouse Pusat ditolak', () {
      expect(
        ReportAccessPolicy.forRequest(
          user: nurse,
          reportType: ReportType.stokLokasi,
          scopeType: ReportScopeType.warehouse,
          locationType: StockLocationType.warehouse,
        ).isDenied,
        isTrue,
      );
    });

    test('branch_all, cross_branch dan all_locations ditolak', () {
      for (final scope in const [
        ReportScopeType.branchAll,
        ReportScopeType.crossBranch,
        ReportScopeType.allLocations,
      ]) {
        expect(
          ReportAccessPolicy.forRequest(
            user: nurse,
            reportType: ReportType.stokLokasi,
            scopeType: scope,
            requestedBranchId: branchId,
          ).isDenied,
          isTrue,
          reason: scope.dbValue,
        );
      }
    });

    test('rekap opname dan pemakaian dibatasi dokumen sendiri', () {
      for (final type in const [
        ReportType.rekapOpname,
        ReportType.rekapPemakaian,
      ]) {
        expect(
          ReportAccessPolicy.requiresOwnDocuments(
            role: UserRole.perawat,
            reportType: type,
          ),
          isTrue,
          reason: type.dbValue,
        );
      }
    });

    test('peran lain tidak dibatasi dokumen sendiri', () {
      for (final role in const [
        UserRole.kepalaCabang,
        UserRole.warehouse,
        UserRole.superAdmin,
      ]) {
        expect(
          ReportAccessPolicy.requiresOwnDocuments(
            role: role,
            reportType: ReportType.rekapPemakaian,
          ),
          isFalse,
          reason: role.dbValue,
        );
      }
    });
  });

  group('Kepala Cabang', () {
    test('menjangkau seluruh sebelas jenis laporan', () {
      expect(
        ReportAccessPolicy.allowedReportTypes(UserRole.kepalaCabang).length,
        ReportType.values.length,
      );
    });

    test('stok cabang boleh gudang cabang, ruangan dan seluruh cabang', () {
      expect(
        ReportAccessPolicy.allowedScopesFor(
          role: UserRole.kepalaCabang,
          reportType: ReportType.stokLokasi,
        ),
        {
          ReportScopeType.branchStore,
          ReportScopeType.room,
          ReportScopeType.branchAll,
        },
      );
    });

    test('kartu stok tidak boleh branch_all', () {
      // §17: a running balance is a statement about one shelf.
      expect(
        ReportAccessPolicy.allowedScopesFor(
          role: UserRole.kepalaCabang,
          reportType: ReportType.kartuStok,
        ).contains(ReportScopeType.branchAll),
        isFalse,
      );
    });

    test('rekap dijalankan pada cakupan cabang', () {
      expect(
        ReportAccessPolicy.allowedScopesFor(
          role: UserRole.kepalaCabang,
          reportType: ReportType.rekapGr,
        ),
        {ReportScopeType.branchAll},
      );
    });

    test('Warehouse Pusat ditolak', () {
      expect(
        ReportAccessPolicy.forRequest(
          user: branchHead,
          reportType: ReportType.stokLokasi,
          scopeType: ReportScopeType.warehouse,
          locationType: StockLocationType.warehouse,
        ).isDenied,
        isTrue,
      );
    });

    test('lokasi cabang lain ditolak', () {
      expect(
        ReportAccessPolicy.forRequest(
          user: branchHead,
          reportType: ReportType.stokLokasi,
          scopeType: ReportScopeType.branchStore,
          locationType: StockLocationType.branchStore,
          locationBranchId: otherBranchId,
        ).reason,
        ReportAccessDenialReason.location,
      );
    });

    test('branch_all cabang lain ditolak', () {
      expect(
        ReportAccessPolicy.forRequest(
          user: branchHead,
          reportType: ReportType.rekapGr,
          scopeType: ReportScopeType.branchAll,
          requestedBranchId: otherBranchId,
        ).reason,
        ReportAccessDenialReason.location,
      );
    });

    test('lintas cabang ditolak', () {
      expect(
        ReportAccessPolicy.forRequest(
          user: branchHead,
          reportType: ReportType.rekapGr,
          scopeType: ReportScopeType.crossBranch,
        ).isDenied,
        isTrue,
      );
    });

    test('cabang selalu dipaksa ke cabang sendiri', () {
      expect(
        ReportAccessPolicy.enforcedBranchIdFor(
          user: branchHead,
          scopeType: ReportScopeType.branchAll,
        ),
        branchId,
      );
    });
  });

  group('Warehouse', () {
    test('laporan stok hanya pada Warehouse Pusat', () {
      for (final type in const [
        ReportType.stokLokasi,
        ReportType.kartuStok,
        ReportType.kadaluarsa,
      ]) {
        expect(
          ReportAccessPolicy.allowedScopesFor(
            role: UserRole.warehouse,
            reportType: type,
          ),
          {ReportScopeType.warehouse},
          reason: type.dbValue,
        );
      }
    });

    test('saldo ruangan dan gudang cabang tidak terjangkau', () {
      // The other half of G-L1's Warehouse sentence: documents cross branches,
      // current stock does not.
      for (final scope in const [
        ReportScopeType.branchStore,
        ReportScopeType.room,
        ReportScopeType.branchAll,
      ]) {
        expect(
          ReportAccessPolicy.forRequest(
            user: warehouse,
            reportType: ReportType.stokLokasi,
            scopeType: scope,
            locationType: scope.requiredLocationType,
            locationBranchId: branchId,
            requestedBranchId: branchId,
          ).isDenied,
          isTrue,
          reason: scope.dbValue,
        );
      }
    });

    test('rekap dijalankan lintas cabang atau per cabang', () {
      // §4.2 asks the Warehouse screen for both: *"rekap PR/DO per cabang & per
      // periode"* and the cross-branch view. Narrowing to one branch is a scope
      // rather than a filter so the audit row can record which branch it was.
      for (final type in const [
        ReportType.rekapPr,
        ReportType.rekapDo,
        ReportType.rekapGr,
        ReportType.rekapDistribusi,
        ReportType.rekapPemakaian,
        ReportType.rekapPemusnahan,
        ReportType.rekapRetur,
        ReportType.rekapOpname,
      ]) {
        expect(
          ReportAccessPolicy.allowedScopesFor(
            role: UserRole.warehouse,
            reportType: type,
          ),
          {ReportScopeType.crossBranch, ReportScopeType.branchAll},
          reason: type.dbValue,
        );
      }
    });

    test('cakupan per cabang tetap menolak laporan stok', () {
      // The other half of G-L1's Warehouse sentence survives the addition: reading
      // a branch's *current stock* is still refused.
      expect(
        ReportAccessPolicy.allowedScopesFor(
          role: UserRole.warehouse,
          reportType: ReportType.stokLokasi,
        ).contains(ReportScopeType.branchAll),
        isFalse,
      );
    });

    test('all_locations ditolak', () {
      expect(
        ReportAccessPolicy.forRequest(
          user: warehouse,
          reportType: ReportType.rekapGr,
          scopeType: ReportScopeType.allLocations,
        ).reason,
        ReportAccessDenialReason.scope,
      );
    });

    test('riwayat ekspor ditolak', () {
      expect(
        ReportAccessPolicy.canReadExportHistory(UserRole.warehouse),
        isFalse,
      );
    });
  });

  group('Super Admin', () {
    test('menjangkau seluruh jenis laporan', () {
      expect(
        ReportAccessPolicy.allowedReportTypes(UserRole.superAdmin).length,
        ReportType.values.length,
      );
    });

    test('all_locations dan cross_branch diizinkan untuk rekap', () {
      final scopes = ReportAccessPolicy.allowedScopesFor(
        role: UserRole.superAdmin,
        reportType: ReportType.rekapGr,
      );
      expect(scopes, contains(ReportScopeType.crossBranch));
      expect(scopes, contains(ReportScopeType.allLocations));
    });

    test('lokasi cabang mana pun diizinkan', () {
      expect(
        ReportAccessPolicy.forRequest(
          user: superAdmin,
          reportType: ReportType.stokLokasi,
          scopeType: ReportScopeType.room,
          locationType: StockLocationType.room,
          locationBranchId: otherBranchId,
        ).isGranted,
        isTrue,
      );
    });

    test('satu-satunya peran yang membaca riwayat ekspor', () {
      expect(
        ReportAccessPolicy.canReadExportHistory(UserRole.superAdmin),
        isTrue,
      );
      for (final role in const [
        UserRole.perawat,
        UserRole.kepalaCabang,
        UserRole.warehouse,
      ]) {
        expect(
          ReportAccessPolicy.canReadExportHistory(role),
          isFalse,
          reason: role.dbValue,
        );
      }
    });

    test('cabang tidak dipaksa; boleh menjadi filter', () {
      expect(
        ReportAccessPolicy.enforcedBranchIdFor(
          user: superAdmin,
          scopeType: ReportScopeType.crossBranch,
        ),
        isNull,
      );
    });
  });

  group('semua peran', () {
    test('tanpa sesi seluruh akses ditolak', () {
      expect(
        ReportAccessPolicy.forSection(
          user: null,
          kind: ReportRouteKind.reports,
        ).reason,
        ReportAccessDenialReason.noSession,
      );
    });

    test('akun nonaktif ditolak walau perannya cukup', () {
      // O-8: `is_active` changes under an open session, and the decision rests on
      // the stored row.
      final inactive = userOf(UserRole.superAdmin, isActive: false);

      expect(
        ReportAccessPolicy.forSection(
          user: inactive,
          kind: ReportRouteKind.reports,
        ).reason,
        ReportAccessDenialReason.role,
      );
      expect(
        ReportAccessPolicy.forSection(
          user: inactive,
          kind: ReportRouteKind.exportHistory,
        ).isDenied,
        isTrue,
      );
    });

    test('peran bercakupan cabang tanpa cabang ditolak', () {
      expect(
        ReportAccessPolicy.forSection(
          user: userOf(UserRole.kepalaCabang),
          kind: ReportRouteKind.reports,
        ).reason,
        ReportAccessDenialReason.noBranch,
      );
    });

    test('lokasi dengan tipe salah ditolak seperti lokasi asing', () {
      // §52: "wrong type" and "another branch" must be indistinguishable, or the
      // form becomes a way to enumerate what exists.
      final wrongType = ReportAccessPolicy.forRequest(
        user: branchHead,
        reportType: ReportType.stokLokasi,
        scopeType: ReportScopeType.room,
        locationType: StockLocationType.branchStore,
        locationBranchId: branchId,
      );
      final foreign = ReportAccessPolicy.forRequest(
        user: branchHead,
        reportType: ReportType.stokLokasi,
        scopeType: ReportScopeType.room,
        locationType: StockLocationType.room,
        locationBranchId: otherBranchId,
      );

      expect(wrongType.reason, foreign.reason);
    });

    test('lokasi hilang pada cakupan lokasi tunggal ditolak', () {
      expect(
        ReportAccessPolicy.forRequest(
          user: branchHead,
          reportType: ReportType.stokLokasi,
          scopeType: ReportScopeType.room,
        ).reason,
        ReportAccessDenialReason.location,
      );
    });

    test(
      'setiap peran punya minimal satu cakupan untuk laporan yang boleh',
      () {
        for (final role in UserRole.values) {
          for (final type in ReportAccessPolicy.allowedReportTypes(role)) {
            expect(
              ReportAccessPolicy.allowedScopesFor(role: role, reportType: type),
              isNotEmpty,
              reason: '${role.dbValue}/${type.dbValue}',
            );
          }
        }
      },
    );

    test('cakupan untuk laporan yang tidak boleh selalu kosong', () {
      for (final role in UserRole.values) {
        final allowed = ReportAccessPolicy.allowedReportTypes(role);
        for (final type in ReportType.values) {
          if (allowed.contains(type)) continue;
          expect(
            ReportAccessPolicy.allowedScopesFor(role: role, reportType: type),
            isEmpty,
            reason: '${role.dbValue}/${type.dbValue}',
          );
        }
      }
    });
  });
}
