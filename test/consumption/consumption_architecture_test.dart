import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_inspection.dart';

/// Invariants no runtime test can catch, because breaking them still compiles and still
/// passes (§46).
///
/// A widget reaching past the repository into a DAO, a quantity path that quietly grows a
/// `double`, a `:id` route that ships without a guard, an `updateStatus` that would let a
/// posted document be reopened — each of those is found in code review once and then slowly
/// reintroduced. Asserted here they fail the build instead.
///
/// Comment lines are stripped before matching (`readCodeOnly`), so a file can *explain* a
/// forbidden identifier — several of these deliberately discuss the very words they
/// forbid — without the test reading the explanation as a violation.
void main() {
  const domain = 'lib/features/consumption/domain';
  const presentation = 'lib/features/consumption/presentation';
  const data = 'lib/features/consumption/data';
  const dao = 'lib/core/db/daos/consumption_dao.dart';
  const tables = 'lib/core/db/tables/consumption_tables.dart';
  const guards = '$domain/use_cases/consumption_guards.dart';
  const repositoryContract = '$domain/repositories/consumption_repository.dart';
  const driftRepository =
      '$data/repositories/drift_consumption_repository.dart';
  const postUseCase = '$domain/use_cases/post_consumption_use_case.dart';
  const routeGuard = 'lib/app/guards/consumption_route_guard.dart';
  const router = 'lib/app/router.dart';

  group('lapisan', () {
    test('presentation tidak mengimpor DAO maupun drift', () {
      for (final path in dartFilesUnder(presentation)) {
        for (final import in importsOf(path)) {
          expect(
            import.contains('core/db/daos/'),
            isFalse,
            reason: '$path mengimpor DAO langsung.',
          );
          expect(
            import.startsWith('package:drift/'),
            isFalse,
            reason: '$path mengimpor drift.',
          );
          expect(
            import.contains('app_database'),
            isFalse,
            reason: '$path mengimpor generated database.',
          );
        }
      }
    });

    test('domain tidak mengimpor drift maupun Flutter', () {
      for (final path in dartFilesUnder(domain)) {
        for (final import in importsOf(path)) {
          expect(
            import.startsWith('package:drift/'),
            isFalse,
            reason: '$path mengimpor drift.',
          );
          expect(
            import.contains('core/db/'),
            isFalse,
            reason: '$path menjangkau lapisan database.',
          );
          expect(
            import.startsWith('package:flutter/'),
            isFalse,
            reason: '$path mengimpor Flutter.',
          );
          expect(
            import.startsWith('package:flutter_riverpod/'),
            isFalse,
            reason: '$path mengimpor Riverpod.',
          );
        }
      }
    });

    test(
      'hanya repository drift yang menyentuh milliUnits dan baris drift',
      () {
        for (final path
            in dartFilesUnder(domain) + dartFilesUnder(presentation)) {
          final code = readCodeOnly(path);
          expect(
            code.contains('.milliUnits'),
            isFalse,
            reason: '$path menyentuh skala milli-unit (Q-4).',
          );
          expect(
            code.contains('ConsumptionRow'),
            isFalse,
            reason: '$path menyentuh baris drift.',
          );
          expect(
            code.contains('ConsumptionLineRow'),
            isFalse,
            reason: '$path menyentuh baris drift.',
          );
        }
        // …and the one file that may.
        expect(readCodeOnly(driftRepository), contains('.milliUnits'));
      },
    );

    test('domain tidak memakai double pada jalur kuantitas', () {
      for (final path
          in dartFilesUnder(domain) +
              dartFilesUnder(presentation) +
              [driftRepository]) {
        final code = readCodeOnly(path);
        // `num ` is deliberately absent from this list: it matches `enum `, which several
        // of these files legitimately declare. `double` and the two lossy conversions are
        // what actually put a rounding error on the quantity path.
        for (final pattern in const [
          'double ',
          'toDouble',
          '.round()',
          'RealColumn',
        ]) {
          expect(
            code.contains(pattern),
            isFalse,
            reason: '$path memakai $pattern pada jalur kuantitas (Q-2).',
          );
        }
      }
    });

    test('qty adalah INTEGER, bukan REAL', () {
      final code = readCodeOnly(tables);
      expect(code, contains('IntColumn get qty'));
      expect(code.contains('RealColumn'), isFalse);
    });
  });

  group('ledger', () {
    test('hanya use case posting yang memanggil StockPostingService', () {
      for (final path
          in dartFilesUnder(domain) +
              dartFilesUnder(presentation) +
              dartFilesUnder(data)) {
        if (path.endsWith('post_consumption_use_case.dart')) continue;
        // The providers legitimately *construct* the service to inject it; what they must
        // not do is call a posting method on it.
        final code = readCodeOnly(path);
        expect(
          code.contains('postConsumptionLinesInTransaction'),
          isFalse,
          reason: '$path memanggil ledger langsung.',
        );
        expect(
          code.contains('appendMovement'),
          isFalse,
          reason: '$path menulis ledger langsung (G-A1).',
        );
      }
      expect(
        readCodeOnly(postUseCase),
        contains('postConsumptionLinesInTransaction'),
      );
    });

    test('tidak ada mutasi saldo langsung', () {
      for (final path
          in dartFilesUnder(domain) +
              dartFilesUnder(presentation) +
              dartFilesUnder(data) +
              [dao]) {
        final code = readCodeOnly(path);
        expect(
          code.contains('setBalanceQty'),
          isFalse,
          reason: '$path memutasi saldo langsung.',
        );
        expect(
          code.contains('UPDATE stock_balances'),
          isFalse,
          reason: '$path menulis stock_balances langsung.',
        );
      }
    });

    test('movement type dan ref doc type benar', () {
      final code = readCodeOnly(
        'lib/features/inventory/domain/services/stock_posting_service.dart',
      );
      expect(code, contains('StockMovementType.consumption'));
      expect(code, contains('RefDocType.consumption'));
      // The one-leg shape (§19): the room is the source and there is no destination.
      expect(code, contains('postConsumptionLinesInTransaction'));

      final enums = readCodeOnly('lib/core/enums/app_enums.dart');
      expect(enums, contains("static const consumption = 'CONS'"));
      expect(enums, contains("consumption('consumption')"));
    });

    test('tidak ada destinasi pada jalur pemakaian', () {
      for (final path
          in dartFilesUnder(domain) + dartFilesUnder(data) + [dao, tables]) {
        final code = readCodeOnly(path);
        for (final pattern in const [
          'toLocationId:',
          'to_location_id',
          'destinationLocationId',
          'destinationRoomId',
        ]) {
          expect(
            code.contains(pattern),
            isFalse,
            reason:
                '$path menyebut lokasi tujuan; pemakaian hanya satu kaki '
                '(§19).',
          );
        }
      }
    });

    test('use case posting memegang satu transaksi luar', () {
      final code = readCodeOnly(postUseCase);
      // One transaction, opened once, wrapping everything (§20).
      expect(code, contains('runInTransaction'));
      expect(
        RegExp(r'runInTransaction').allMatches(code).length,
        1,
        reason: 'Posting harus membuka tepat satu transaksi.',
      );
    });
  });

  group('kontrak repository', () {
    test('tidak ada writer status generik maupun un-post', () {
      final code = readCodeOnly(repositoryContract) + readCodeOnly(dao);
      for (final pattern in const [
        'setStatus',
        'updateStatus',
        'unpost',
        'unPost',
        'reopen',
        'cancel',
      ]) {
        expect(
          code.contains(pattern),
          isFalse,
          reason: 'Kontrak memuat $pattern; posted bersifat final (G-S2).',
        );
      }
      // The one transition there is, named after the status it moves to.
      expect(readCodeOnly(repositoryContract), contains('markPosted'));
    });

    test('tidak ada hard delete', () {
      final code = readCodeOnly(repositoryContract) + readCodeOnly(dao);
      for (final pattern in const [
        'DELETE FROM consumption',
        'deleteWhere',
        'hardDelete',
      ]) {
        expect(
          code.contains(pattern),
          isFalse,
          reason: 'Kontrak memuat $pattern; soft delete saja (G-A5).',
        );
      }
      expect(readCodeOnly(dao), contains('softDeleteOwnDraftLine'));
    });

    test('tidak ada writer ruangan, cabang, item atau batch', () {
      final code = readCodeOnly(dao);
      for (final pattern in const [
        'SET room_id',
        'SET branch_id',
        'SET item_id',
        'SET batch_id',
        'SET created_by',
      ]) {
        expect(
          code.contains(pattern),
          isFalse,
          reason: 'DAO memuat $pattern; kolom itu immutable setelah insert.',
        );
      }
    });

    test('tidak ada parameter lokasi bebas pada writer', () {
      final code = readCodeOnly(repositoryContract);
      for (final pattern in const [
        'locationId,',
        'required String locationId',
        'sourceLocationId',
      ]) {
        expect(
          code.contains(pattern),
          isFalse,
          reason:
              'Kontrak menerima lokasi bebas; sumber diresolusi dari room_id '
              '(§15).',
        );
      }
      // The read path does take a resolved room location — and it says so by name.
      expect(code, contains('roomLocationId'));
    });

    test('setiap writer membawa actorUserId', () {
      final code = readCodeOnly(repositoryContract);
      for (final writer in const [
        'markPosted',
        'updateOwnDraftNote',
        'addDraftLine',
        'updateDraftLine',
        'removeDraftLine',
      ]) {
        final index = code.indexOf(writer);
        expect(index, greaterThan(-1), reason: '$writer hilang dari kontrak.');
        // The signature runs to the closing brace of its parameter list.
        final signature = code.substring(index, code.indexOf('});', index));
        expect(
          signature,
          contains('actorUserId'),
          reason:
              '$writer tidak membawa actorUserId; kepemilikan §14 harus masuk '
              'ke SQL.',
        );
      }
    });

    test('SQL guarded write menyertakan created_by dan status', () {
      final code = readCodeOnly(dao);
      for (final statement in const [
        'updateOwnDraftNote',
        'updateOwnDraftLine',
        'softDeleteOwnDraftLine',
        'markPosted',
      ]) {
        final index = code.indexOf('Future<int> $statement');
        expect(index, greaterThan(-1), reason: '$statement hilang dari DAO.');
        // Sliced to the end of the `updates:` clause every guarded write closes with,
        // rather than to the first `  }` — a `customUpdate` body contains several of those
        // in its variable list, and cutting at the first one would read half a statement.
        final body = _methodBody(code, index);
        expect(
          body,
          contains('created_by'),
          reason: '$statement tidak menyaring created_by (§14/§43).',
        );
        expect(
          body,
          contains("status = 'draft'"),
          reason: '$statement tidak menyaring status draft (G-S1).',
        );
      }
    });

    test('markPosted menuntut minimal satu baris hidup', () {
      final code = readCodeOnly(dao);
      final index = code.indexOf('Future<int> markPosted');
      final body = _methodBody(code, index);
      expect(body, contains('EXISTS'));
      expect(body, contains('consumption_lines'));
      // …and deliberately does **not** demand a note: a consumption note is optional (§8).
      expect(
        body.contains('trim(note)'),
        isFalse,
        reason: 'Catatan pemakaian tidak wajib (§8).',
      );
    });

    test('read tidak ter-scope hanya satu, untuk use case', () {
      final code = readCodeOnly(repositoryContract);
      // `getDetail` is the only unscoped read, and the presentation layer must not use it.
      expect(code, contains('Future<ConsumptionDetail?> getDetail('));
      for (final path in dartFilesUnder(presentation)) {
        expect(
          readCodeOnly(path).contains('getDetail('),
          isFalse,
          reason: '$path memakai read tanpa scope (§24).',
        );
      }
    });

    test('scope cabang selalu posted-only di DAO', () {
      final code = readCodeOnly(dao);
      final index = code.indexOf('case ConsumptionQueryScope.branchPosted');
      expect(index, greaterThan(-1));
      final body = code.substring(index, index + 400);
      expect(
        body,
        contains('ConsumptionStatus.posted'),
        reason:
            'Predikat scope cabang harus membawa posted sendiri, bukan '
            'bergantung pada parameter (§14).',
      );
    });
  });

  group('aturan domain', () {
    test('hanya PostConsumptionUseCase menulis status posted', () {
      for (final path
          in dartFilesUnder(domain) +
              dartFilesUnder(presentation) +
              dartFilesUnder(data)) {
        // The posting use case *calls* it, the contract *declares* it and the drift
        // repository *implements* it. Anything else calling it would be a second way to
        // flip a document final.
        if (path.endsWith('post_consumption_use_case.dart')) continue;
        if (path.endsWith('drift_consumption_repository.dart')) continue;
        if (path.endsWith('consumption_repository.dart')) continue;
        expect(
          readCodeOnly(path).contains('markPosted('),
          isFalse,
          reason: '$path memposting dokumen di luar use case posting.',
        );
      }
      expect(readCodeOnly(postUseCase), contains('markPosted('));
    });

    test('tidak ada jalur pemakaian batch kedaluwarsa', () {
      final code = readCodeOnly(guards);
      expect(code, contains('requireNotExpired'));
      // No escape hatch of any shape.
      for (final pattern in const [
        'force',
        'confirmed',
        'override',
        'allowExpired',
        'skipExpiry',
      ]) {
        expect(
          code.contains(pattern),
          isFalse,
          reason: 'Guards memuat $pattern; kedaluwarsa diblokir mutlak (§17).',
        );
      }
    });

    test('tidak ada FEFO wajib pada pemakaian', () {
      for (final path
          in dartFilesUnder(domain) +
              dartFilesUnder(presentation) +
              dartFilesUnder(data) +
              [dao, tables]) {
        final code = readCodeOnly(path);
        for (final pattern in const [
          'fefo',
          'Fefo',
          'FEFO',
          'overrideReason',
        ]) {
          expect(
            code.contains(pattern),
            isFalse,
            reason: '$path menyebut FEFO; §17 tidak mewajibkannya.',
          );
        }
      }
    });

    test('tidak ada gudang cabang maupun warehouse sebagai sumber', () {
      for (final path
          in dartFilesUnder(domain) + dartFilesUnder(data) + [dao]) {
        final code = readCodeOnly(path);
        for (final pattern in const [
          'StockLocationType.branchStore',
          'StockLocationType.warehouse',
          'branchStoreLocations',
          'warehouseLocation',
        ]) {
          expect(
            code.contains(pattern),
            isFalse,
            reason: '$path menyebut sumber selain ruangan (§15).',
          );
        }
      }
      // The one place the room type *is* named, as the only allowed source.
      expect(
        readCodeOnly('$domain/services/consumption_room_policy.dart'),
        contains('StockLocationType.room'),
      );
    });

    test('tidak ada kosakata persetujuan di kode', () {
      for (final path
          in dartFilesUnder(domain) +
              dartFilesUnder(presentation) +
              dartFilesUnder(data) +
              [dao, tables, routeGuard]) {
        final code = readCodeOnly(path);
        // `rejected` is deliberately absent: `ConsumptionRoomRejection` and
        // `ConsumptionSourceVerdict.rejected` use it as a *verdict* word, which is a
        // different thing from a document status. What is banned is the vocabulary of an
        // approval *stage* — the states §7 says this document does not have.
        for (final pattern in const [
          "'submitted'",
          "'approved'",
          "'rejected'",
          'ConsumptionStatus.submitted',
          'ConsumptionStatus.approved',
          'Setujui',
          'Ajukan',
          'Menunggu Persetujuan',
          'Disetujui',
        ]) {
          expect(
            code.contains(pattern),
            isFalse,
            reason: '$path memakai kosakata persetujuan: $pattern (§7).',
          );
        }
      }
    });

    test('tidak ada kolom atau field data pasien', () {
      for (final path
          in dartFilesUnder(domain) +
              dartFilesUnder(presentation) +
              dartFilesUnder(data) +
              [dao, tables]) {
        final code = readCodeOnly(path);
        for (final pattern in const [
          'patientId',
          'patientName',
          'patient_id',
          'patient_name',
          'medicalRecord',
          'medical_record',
          'diagnosis',
          'procedureCode',
        ]) {
          expect(
            code.contains(pattern),
            isFalse,
            reason: '$path memuat field data pasien: $pattern (§9).',
          );
        }
      }
    });

    test('tidak ada perbandingan timestamp leksikal di SQL', () {
      for (final path in [dao, tables]) {
        final code = readCodeOnly(path);
        for (final pattern in const [
          'posted_at >=',
          'posted_at >',
          'posted_at <',
          'created_at <=',
          'created_at >=',
          "BETWEEN",
        ]) {
          expect(
            code.contains(pattern),
            isFalse,
            reason:
                '$path membandingkan timestamp TEXT secara leksikal; '
                'gunakan DocumentTimestampPolicy (§35).',
          );
        }
      }
    });

    test('urutan timestamp memakai DocumentTimestampPolicy', () {
      expect(readCodeOnly(postUseCase), contains('DocumentTimestampPolicy'));
      expect(readCodeOnly(postUseCase), contains('requireOrdered'));
    });

    test('expiry memakai zona operasional, bukan toLocal', () {
      for (final path
          in dartFilesUnder(domain) +
              dartFilesUnder(presentation) +
              dartFilesUnder(data)) {
        expect(
          readCodeOnly(path).contains('.toLocal()'),
          isFalse,
          reason: '$path memakai zona perangkat (T-4).',
        );
      }
      expect(
        readCodeOnly('$domain/services/consumption_expiry_policy.dart'),
        contains('AppTimeZone.operationalDate'),
      );
    });
  });

  group('route dan provider', () {
    test('setiap route :id dibungkus guard', () {
      final code = readCodeOnly(router);
      // Both document routes, and the editor with its own stricter kind.
      expect(code, contains('ConsumptionRouteKind.nurseDocument'));
      expect(code, contains('ConsumptionRouteKind.nurseDraft'));
      expect(code, contains('ConsumptionRouteKind.branchDocument'));
      expect(code, contains('ConsumptionRouteGuard('));
      // And the two sections, so a deep link cannot reach one unguarded.
      expect(code, contains('ConsumptionRouteKind.nurseList'));
      expect(code, contains('ConsumptionRouteKind.nurseCreate'));
      expect(code, contains('ConsumptionRouteKind.branchList'));
      expect(code, contains('ConsumptionSectionGuard('));
    });

    test('route guard memakai findAccessScope, bukan detail', () {
      final code = readCodeOnly(routeGuard);
      expect(code, contains('findAccessScope'));
      expect(
        code.contains('watchOwn('),
        isFalse,
        reason: 'Guard tidak boleh memuat dokumen untuk memutuskan akses.',
      );
      expect(code.contains('getDetail('), isFalse);
      // And it re-reads the *stored* actor (O-8).
      expect(code, contains('actingUserProvider'));
    });

    test('guard gagal tertutup', () {
      final code = readCodeOnly(routeGuard);
      expect(
        code,
        contains('AccessDeniedPage()'),
        reason: 'Kesalahan tak terduga harus ditolak, bukan diloloskan.',
      );
    });

    test('provider layar bersifat autoDispose', () {
      final code = readCodeOnly(
        '$presentation/providers/consumption_providers.dart',
      );
      for (final provider in const [
        'ownConsumptionListProvider',
        'branchConsumptionListProvider',
        'ownConsumptionDetailProvider',
        'branchConsumptionDetailProvider',
        'consumptionDetailProvider',
        'consumptionDetailSnapshotProvider',
        'consumptionRoomsProvider',
        'branchConsumptionRoomsProvider',
        'consumptionRoomPositionsProvider',
        'consumptionCandidateSearchResultsProvider',
        'consumptionDocumentPositionsProvider',
        'nurseConsumptionDashboardProvider',
        'branchConsumptionDashboardProvider',
      ]) {
        final index = code.indexOf('final $provider =');
        expect(index, greaterThan(-1), reason: '$provider hilang.');
        final declaration = code.substring(
          index,
          code.indexOf('((', index) + 2,
        );
        expect(
          declaration,
          contains('autoDispose'),
          reason: '$provider harus autoDispose (§26).',
        );
      }
    });

    test('provider tidak menerima aktor atau cabang dari UI', () {
      final code = readCodeOnly(
        '$presentation/providers/consumption_providers.dart',
      );
      // A `family<…, String>` keyed on a user or branch id would be a parameter a widget
      // could fill in with somebody else's. The families that do exist are keyed on a
      // *document* or a *room* id, both of which the guard has already scoped.
      for (final pattern in const [
        'family<List<ConsumptionSummary>, String>',
        'family<ConsumptionDashboardSummary, String>',
      ]) {
        expect(
          code.contains(pattern),
          isFalse,
          reason: 'Provider menerima kunci scope dari UI (§26).',
        );
      }
      // The scope comes from the stored actor instead.
      expect(code, contains('actingUserProvider'));
    });

    test('providers tidak menyentuh use case selain lewat provider', () {
      // Widgets read controllers; they never construct a use case, because a use case built
      // in a widget would take whatever repository and clock that widget happened to have.
      for (final path
          in dartFilesUnder('$presentation/pages') +
              dartFilesUnder('$presentation/widgets')) {
        final code = readCodeOnly(path);
        for (final useCase in const [
          'CreateConsumptionUseCase(',
          'AddConsumptionLineUseCase(',
          'UpdateConsumptionLineUseCase(',
          'RemoveConsumptionLineUseCase(',
          'PostConsumptionUseCase(',
        ]) {
          expect(
            code.contains(useCase),
            isFalse,
            reason: '$path membangun use case sendiri.',
          );
        }
      }
    });
  });

  group('milestone lain tidak berubah', () {
    test('pemusnahan tetap satu-satunya keluaran stok kedaluwarsa', () {
      // The complement of §17, asserted against the *other* feature's source: a disposal
      // requires the batch to be expired, and a consumption requires it not to be. If one
      // of them ever flipped there would be a day on which a batch could go nowhere, or one
      // on which it could go to both.
      final disposal = readCodeOnly(
        'lib/features/disposal/domain/services/disposal_expiry_policy.dart',
      );
      expect(disposal, contains('isDisposable'));
      expect(disposal, contains('isExpired'));

      final consumption = readCodeOnly(
        '$domain/services/consumption_expiry_policy.dart',
      );
      expect(consumption, contains('isConsumable'));
      expect(
        consumption,
        contains('!isExpired'),
        reason: 'Konsumsi adalah komplemen pemusnahan, bukan salinannya.',
      );
    });

    test('distribusi tetap gudang cabang → ruangan', () {
      final code = readCodeOnly(
        'lib/features/distribution/domain/services/distribution_room_policy.dart',
      );
      expect(code, contains('verifyBranchStore'));
      expect(code, contains('verifyRoomLocation'));
    });

    test('schema version dinaikkan ke 10 dan index dibekukan', () {
      final code = readCodeOnly('lib/core/db/app_database.dart');
      expect(code, contains('int get schemaVersion => 14;'));
      expect(code, contains('if (from < 10)'));
      expect(code, contains('_v10ConsumptionIndexes'));
      // Frozen as literal SQL rather than derived from `allSchemaEntities`, which always
      // describes the *current* schema.
      expect(
        code,
        contains(
          "'CREATE UNIQUE INDEX IF NOT EXISTS idx_consumptions_doc_number '",
        ),
      );
      expect(
        code.contains('allSchemaEntities'),
        isFalse,
        reason: 'SQL migrasi harus dibekukan, bukan diturunkan dari schema.',
      );
      // And the earlier steps are untouched.
      for (final step in const [
        'if (from < 2)',
        'if (from < 3)',
        'if (from < 4)',
        'if (from < 5)',
        'if (from < 6)',
        'if (from < 7)',
        'if (from < 8)',
        'if (from < 9)',
      ]) {
        expect(code, contains(step));
      }
    });

    test('migrasi v10 hanya membuat tabel pemakaian', () {
      final code = readCodeOnly('lib/core/db/app_database.dart');
      final index = code.indexOf('if (from < 10)');
      final body = code.substring(index);
      expect(body, contains('m.createTable(consumptions)'));
      expect(body, contains('m.createTable(consumptionLines)'));
      // Nothing else — no alterTable, no UPDATE, no INSERT.
      expect(body.contains('alterTable'), isFalse);
      expect(body.contains('UPDATE '), isFalse);
      expect(body.contains('INSERT '), isFalse);
    });
  });
}

/// One method body of a DAO, from its declaration to the `updateKind:` line every guarded
/// write closes with.
///
/// A `customUpdate` body contains several `  }` sequences in its variable list, so slicing
/// at the first one would read half a statement and pass a check the SQL never satisfied.
String _methodBody(String code, int start) {
  final end = code.indexOf('updateKind:', start);
  return code.substring(start, end == -1 ? code.length : end);
}
