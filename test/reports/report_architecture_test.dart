import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_inspection.dart';

/// Invariants no runtime test can catch, because breaking them still compiles and
/// still passes: a builder reaching past the repository, a quantity path that grows
/// a `double`, an exporter that decides a business rule (§18, §33, §50).
///
/// Comments are stripped before every check — several of these files *discuss* the
/// identifiers they forbid, and a guard that read the explanation as a violation
/// would forbid documenting the rule.
void main() {
  const domainRoot = 'lib/features/reports/domain';
  const dataRoot = 'lib/features/reports/data';
  const presentationRoot = 'lib/features/reports/presentation';
  const daoPath = 'lib/core/db/daos/reporting_dao.dart';

  List<String> reportingSources() => [
    ...dartFilesUnder(domainRoot),
    ...dartFilesUnder(dataRoot),
    ...dartFilesUnder(presentationRoot),
    daoPath,
  ];

  group('G-L4 — angka laporan berasal dari ledger', () {
    test('tidak ada sumber reporting yang menyebut stock_balances', () {
      for (final path in reportingSources()) {
        final code = readCodeOnly(path);
        expect(code, isNot(contains('stock_balances')), reason: path);
        expect(code, isNot(contains('StockBalances')), reason: path);
        expect(code, isNot(contains('qty_on_hand')), reason: path);
        expect(code, isNot(contains('qtyOnHand')), reason: path);
      }
    });

    test('reporting tidak mengimpor repository inventory', () {
      // `InventoryRepository` reads the balance cache; a report that reached for it
      // would be reading the number G-L4 forbids by a different name.
      for (final path in reportingSources()) {
        for (final import in importsOf(path)) {
          expect(
            import.contains('inventory/domain/repositories'),
            isFalse,
            reason: '$path imports $import',
          );
          expect(
            import.contains('inventory_dao'),
            isFalse,
            reason: '$path imports $import',
          );
        }
      }
    });

    test('reporting tidak menyentuh provider saldo lokasi', () {
      for (final path in reportingSources()) {
        final code = readCodeOnly(path);
        expect(code, isNot(contains('locationBalancesProvider')), reason: path);
        expect(code, isNot(contains('balancesAtLocation')), reason: path);
      }
    });
  });

  group('Q-3 — tidak ada floating point pada jalur kuantitas', () {
    test('domain reporting tidak memakai double atau REAL', () {
      for (final path in dartFilesUnder(domainRoot)) {
        final code = readCodeOnly(path);
        expect(
          code,
          isNot(matches(RegExp(r'\bdouble\b'))),
          reason: '$path must not use double for quantities',
        );
        expect(code, isNot(contains('AS REAL')), reason: path);
        expect(code, isNot(contains('toDouble()')), reason: path);
      }
    });

    test('DAO reporting tidak memakai double atau REAL', () {
      final code = readCodeOnly(daoPath);
      expect(code, isNot(matches(RegExp(r'\bdouble\b'))));
      expect(code, isNot(contains('AS REAL')));
      expect(code, isNot(contains('real()')));
    });
  });

  group('§33 — exporter hanya merender', () {
    test('exporter tidak mengimpor repository, DAO atau drift', () {
      for (final path in dartFilesUnder('$dataRoot/exporters')) {
        for (final import in importsOf(path)) {
          expect(import.contains('drift'), isFalse, reason: '$path: $import');
          expect(
            import.contains('repositories'),
            isFalse,
            reason: '$path: $import',
          );
          expect(import.contains('daos'), isFalse, reason: '$path: $import');
        }
      }
    });

    test('exporter tidak menghitung ulang subtotal', () {
      // Every figure arrives already rendered on the document; an exporter that
      // folded rows again would be a second formula for one number (§33).
      for (final path in dartFilesUnder('$dataRoot/exporters')) {
        final code = readCodeOnly(path);
        expect(
          code,
          isNot(contains('ReportTotalsEngine.totalsOf')),
          reason: path,
        );
        expect(code, isNot(contains('LedgerBalanceEngine')), reason: path);
      }
    });
  });

  group('§41 — domain tidak menyentuh Flutter atau platform', () {
    test('tidak ada BuildContext pada domain reporting', () {
      // Word-bounded on purpose: `ReportBuildContext` is this module's own value
      // object — the build inputs a report needs — and matching it would forbid the
      // very type that exists so no widget context ever has to travel down here.
      final flutterContext = RegExp(r'\bBuildContext\b');
      for (final path in dartFilesUnder(domainRoot)) {
        expect(
          readCodeOnly(path),
          isNot(matches(flutterContext)),
          reason: path,
        );
      }
    });

    test('domain reporting tidak mengimpor Flutter', () {
      // One exception, and it is a *presentation* helper the stock card reuses:
      // `StockMovementPresenter` lives under `inventory/presentation` and pulls in
      // Material for its colours and icons. The Kartu Stok builder imports it for
      // its Indonesian movement labels, which is the whole reason that class exists
      // in one place rather than three (§22).
      const allowedFlutterImporters = <String>{
        'stock_card_report_builder.dart',
      };

      for (final path in dartFilesUnder(domainRoot)) {
        if (allowedFlutterImporters.any(path.endsWith)) continue;
        for (final import in importsOf(path)) {
          expect(
            import.startsWith('package:flutter/'),
            isFalse,
            reason: '$path imports $import',
          );
        }
      }
    });

    test('domain reporting tidak mengimpor share_plus atau path_provider', () {
      for (final path in dartFilesUnder(domainRoot)) {
        for (final import in importsOf(path)) {
          expect(
            import.contains('share_plus'),
            isFalse,
            reason: '$path: $import',
          );
          expect(
            import.contains('path_provider'),
            isFalse,
            reason: '$path: $import',
          );
          expect(import == 'dart:io', isFalse, reason: '$path: $import');
        }
      }
    });
  });

  group('G-L3 / §50 — offline sepenuhnya', () {
    test('tidak ada klien HTTP di seluruh modul laporan', () {
      for (final path in reportingSources()) {
        final code = readCodeOnly(path);
        expect(code, isNot(contains('HttpClient')), reason: path);
        expect(code, isNot(contains('http.get')), reason: path);
        expect(code, isNot(contains('Supabase')), reason: path);
        for (final import in importsOf(path)) {
          expect(
            import == 'package:http/http.dart',
            isFalse,
            reason: '$path: $import',
          );
          expect(
            import.contains('supabase'),
            isFalse,
            reason: '$path: $import',
          );
          expect(
            import.contains('firebase'),
            isFalse,
            reason: '$path: $import',
          );
        }
      }
    });

    test('tidak ada font atau aset dari internet', () {
      for (final path in reportingSources()) {
        final code = readCodeOnly(path);
        expect(code, isNot(contains('https://')), reason: path);
        expect(code, isNot(contains('http://')), reason: path);
        expect(code, isNot(contains('google_fonts')), reason: path);
        expect(code, isNot(contains('NetworkImage')), reason: path);
      }
    });

    test('modul laporan tidak menyentuh SyncGateway', () {
      // G-L3 is about *data freshness*, not connectivity: the header's snapshot is
      // folded from the rows the report used, so a sync gateway has nothing to
      // contribute and a report cannot be blocked by one (§19).
      for (final path in reportingSources()) {
        final code = readCodeOnly(path);
        expect(code, isNot(contains('SyncGateway')), reason: path);
        expect(code, isNot(contains('pushPendingChanges')), reason: path);
        expect(code, isNot(contains('pullServerChanges')), reason: path);
      }
    });
  });

  group('§34 — DAO tidak membandingkan timestamp secara leksikal', () {
    test('tidak ada filter atau order SQL pada kolom waktu', () {
      final code = readCodeOnly(daoPath);
      for (final forbidden in const [
        'ORDER BY created_at',
        'ORDER BY updated_at',
        'ORDER BY posted_at',
        'ORDER BY shipped_at',
        'created_at >',
        'created_at <',
        'created_at BETWEEN',
        'posted_at >',
        'posted_at <',
      ]) {
        expect(code, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('repository mengurutkan log setelah parsing', () {
      final code = readCodeOnly(
        '$dataRoot/repositories/drift_reporting_repository.dart',
      );
      expect(code, contains('exportedAtUtc.compareTo'));
    });
  });

  group('§42 — audit hanya bertambah', () {
    test('tidak ada penulis selain insert di seluruh modul', () {
      for (final path in reportingSources()) {
        final code = readCodeOnly(path);
        expect(code, isNot(contains('update(exportLogs)')), reason: path);
        expect(code, isNot(contains('delete(exportLogs)')), reason: path);
        expect(code, isNot(contains('deleteExportLog')), reason: path);
        expect(code, isNot(contains('updateExportLog')), reason: path);
      }
    });
  });

  group('§14 — kuantitas selalu Quantity', () {
    test('model sumber tidak menyimpan milli-unit mentah', () {
      // Milli-units stop at the repository: above it every figure is a `Quantity`,
      // which is what keeps a scale factor from being dropped somewhere in eleven
      // builders.
      final code = readCodeOnly('$domainRoot/models/report_source_models.dart');
      expect(code, isNot(contains('MilliUnits')));
    });

    test('builder tidak menyentuh milliUnits', () {
      for (final path in dartFilesUnder('$domainRoot/builders')) {
        expect(
          readCodeOnly(path),
          isNot(contains('.milliUnits')),
          reason: path,
        );
      }
    });
  });

  group('presentation tidak melewati use case', () {
    test('widget dan halaman tidak mengimpor DAO atau drift', () {
      for (final path in dartFilesUnder(presentationRoot)) {
        for (final import in importsOf(path)) {
          expect(import.contains('daos/'), isFalse, reason: '$path: $import');
          expect(
            import.startsWith('package:drift/'),
            isFalse,
            reason: '$path: $import',
          );
        }
      }
    });

    test('halaman dan widget tidak memanggil repository langsung', () {
      for (final path in dartFilesUnder('$presentationRoot/pages')) {
        final code = readCodeOnly(path);
        expect(
          code,
          isNot(contains('reportingRepositoryProvider')),
          reason: path,
        );
      }
      for (final path in dartFilesUnder('$presentationRoot/widgets')) {
        final code = readCodeOnly(path);
        expect(
          code,
          isNot(contains('reportingRepositoryProvider')),
          reason: path,
        );
      }
    });
  });
}
