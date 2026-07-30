import 'package:aish_warehouse/app/guards/access_denied_page.dart';
import 'package:aish_warehouse/app/routes.dart';
import 'package:aish_warehouse/app/theme.dart';
import 'package:aish_warehouse/core/db/database_providers.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/session/current_user_session.dart';
import 'package:aish_warehouse/core/time/app_date_time_formatter.dart';
import 'package:aish_warehouse/features/consumption/presentation/pages/consumption_detail_page.dart';
import 'package:aish_warehouse/features/consumption/presentation/providers/consumption_providers.dart';
import 'package:aish_warehouse/features/inventory/domain/models/inventory_models.dart';
import 'package:aish_warehouse/features/inventory/presentation/models/stock_card_entry.dart';
import 'package:aish_warehouse/features/inventory/presentation/stock_card_builder.dart';
import 'package:aish_warehouse/features/inventory/presentation/stock_movement_presenter.dart';
import 'package:aish_warehouse/features/inventory/presentation/widgets/stock_card_list.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` lives here rather than in the main barrel file in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_inspection.dart';
import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// The **kartu stok** surface, for Consumption (Milestone 8 hardening §1–§7).
///
/// ### Which surface these tests drive
///
/// There is no standalone stock-card *page* in this application and this hardening did not
/// add one. The audit found exactly one movement-history query —
/// `InventoryDao.stockCard` — reached through `InventoryRepository`, and no widget that
/// rendered it: every earlier milestone printed its own document's effect from inside its own
/// screens. So the surface is the **movement-history section of `ConsumptionDetailPage`**,
/// which already existed and already named `movement_type` and `ref_doc_type` — as raw
/// database codes. These tests drive it through the real router, plus the per-position card it
/// opens, plus the renderer directly for the cases a real posting cannot produce (a corrupt
/// `ref_doc_type`, a movement type this feature never writes).
///
/// ### Why so much of this renders the widget rather than the mapping
///
/// Asserting `StockMovementPresenter.labelOf(consumption) == 'Pemakaian'` proves the mapping
/// exists, not that anything shows it — and the finding this hardening answers was precisely
/// that the data was right and the screen was silent. So every numbered requirement below is
/// asserted against a pumped widget tree, and the presenter is checked separately, by an
/// architecture test, for *living in one place*.
void main() {
  late TestContext context;
  late ConsumptionFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 8);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildConsumptionFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  final overrides = <Override>[
    consumptionClockProvider.overrideWithValue(() => nowUtc),
  ];

  /// A posted Pemakaian with one batched position and one unbatched one.
  ///
  /// Both shapes in one document on purpose: requirements 7 and 8 are each other's
  /// complement, and asserting them against the same rendered card removes any chance that
  /// one of them passed because the *other* item was the one on screen.
  Future<String> postedDocument({MasterUser? actor, String? note}) async {
    final nurse = actor ?? fixture.nurse;
    final id = await createConsumptionDraft(
      context,
      fixture,
      roomId: fixture.roomOne.id,
      nowUtc: nowUtc,
      actorUserId: nurse.id,
    );
    await addConsumptionPosition(
      context,
      fixture,
      consumptionId: id,
      itemId: fixture.expiryItem.id,
      batchId: fixture.validBatch.id,
      qty: '1.5',
      note: note ?? 'Dipakai untuk tindakan pagi',
      nowUtc: nowUtc,
      actorUserId: nurse.id,
    );
    await addConsumptionPosition(
      context,
      fixture,
      consumptionId: id,
      itemId: fixture.plainItem.id,
      qty: '2.25',
      nowUtc: nowUtc,
      actorUserId: nurse.id,
    );
    await context.postConsumption().call(
      actorUserId: nurse.id,
      consumptionId: id,
    );
    return id;
  }

  /// Opens the nurse's own detail screen through the router, guards included.
  Future<void> openDetail(
    WidgetTester tester,
    String id, {
    MasterUser? actingAs,
  }) async {
    useTabletSurface(tester);
    await pumpAppAt(
      tester,
      context: context,
      actingAs: actingAs ?? fixture.nurse,
      location: '${AppRoutes.consumptions}/$id',
      overrides: overrides,
    );
  }

  /// The rendered text of one row's field, addressed by the row's movement id.
  String textOf(WidgetTester tester, Key key) =>
      tester.widget<Text>(find.byKey(key)).data!;

  /// Every rendered stock-card row of the tree, as `movementId → row`.
  ///
  /// Rows are addressed by movement id rather than by index because the card sorts on
  /// instants, and two movements posted inside one transaction share a timestamp.
  Future<Map<String, StockCardEntry>> renderedRows(WidgetTester tester) async {
    final rows = tester
        .widgetList<StockCardRow>(find.byType(StockCardRow))
        .toList(growable: false);
    return {for (final row in rows) row.entry.id: row.entry};
  }

  /// The renderer on its own, for the states a healthy posting cannot reach.
  Future<void> pumpCard(
    WidgetTester tester,
    List<StockCardEntry> entries, {
    Size surface = const Size(1024, 1366),
    String? locationId,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = surface;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: StockCardList(entries: entries, locationId: locationId),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The real movements of one document, resolved exactly as the screen resolves them but
  /// with the document numbers a caller chooses to supply.
  ///
  /// `documentNumbers` empty is the §6 case: the reference cannot be resolved, either
  /// because the document is gone or because it is not this reader's to see.
  Future<List<StockCardEntry>> entriesFor(
    String consumptionId, {
    Map<String, String> documentNumbers = const <String, String>{},
  }) async {
    final movements = await context.inventory.movementsByRef(
      refDocType: RefDocType.consumption,
      refDocId: consumptionId,
    );
    return buildStockCardEntries(
      movements: movements,
      master: context.master,
      documentNumbers: documentNumbers,
    );
  }

  group('1-2. label movement dan referensi dokumen', () {
    testWidgets('movement consumption dirender sebagai Pemakaian', (
      tester,
    ) async {
      final id = await postedDocument();
      await openDetail(tester, id);

      final ids = await context.consumptionMovementIds(id);
      expect(ids, hasLength(2));
      expect(find.byKey(StockCardList.listKey), findsOneWidget);

      for (final movementId in ids) {
        expect(
          textOf(tester, StockCardList.typeKeyFor(movementId)),
          'Pemakaian',
          reason: 'Kata Indonesia, bukan nilai kolom `movement_type`.',
        );
      }
      // The database code must not survive into the UI.
      expect(
        find.text(StockMovementType.consumption.dbValue),
        findsNothing,
        reason: 'Sebelum hardening ini layar mencetak `consumption` mentah.',
      );
      await disposeWidget(tester);
    });

    testWidgets('ref doc CONS tampil sebagai nomor Consumption', (
      tester,
    ) async {
      final id = await postedDocument();
      await openDetail(tester, id);

      final docNumber = await context.consumptionDocNumber(id);
      expect(
        docNumber,
        startsWith('TMP-CNS-'),
        reason: 'Draft bernomor sementara sampai penomoran final (§11).',
      );

      for (final movementId in await context.consumptionMovementIds(id)) {
        expect(
          textOf(tester, StockCardList.documentKeyFor(movementId)),
          'dokumen Pemakaian · $docNumber',
        );
      }
      // The raw ref_doc_type code, and the raw row id it used to print beside it, are both
      // gone.
      expect(find.textContaining(RefDocType.consumption), findsNothing);
      expect(find.textContaining('ref_doc_type'), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('ruangan sumber tampil dan tujuan dinyatakan kosong', (
      tester,
    ) async {
      final id = await postedDocument();
      await openDetail(tester, id);

      // A consumption has one leg: out of the room, and nowhere (§19). Both halves are
      // stated, so the absent destination reads as absent rather than as forgotten.
      expect(
        find.textContaining('Keluar · Dari ${fixture.locationOne.name} · Ke —'),
        findsNWidgets(2),
      );
      await disposeWidget(tester);
    });
  });

  group('3-4. kuantitas', () {
    testWidgets('desimal diformat benar dan milli-unit tidak tampil', (
      tester,
    ) async {
      final id = await postedDocument();
      await openDetail(tester, id);

      final rows = await renderedRows(tester);
      final quantities = <String>{};
      for (final entry in rows.values) {
        quantities.add(textOf(tester, StockCardList.qtyKeyFor(entry.id)));
      }
      expect(quantities, {'1.5 ampul', '2.25 box'});

      // The stored representation of both, which must never reach a screen (Q-4).
      expect(
        rows.values.map((entry) => entry.qty.milliUnits),
        containsAll([1500, 2250]),
      );
      expect(find.textContaining('1500'), findsNothing);
      expect(find.textContaining('2250'), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('tanda − muncul saat kartu dibaca dari lokasi ruangan', (
      tester,
    ) async {
      final id = await postedDocument();
      final entries = await entriesFor(id);
      await pumpCard(tester, entries, locationId: fixture.locationOne.id);

      for (final entry in entries) {
        expect(
          textOf(tester, StockCardList.qtyKeyFor(entry.id)),
          startsWith('−'),
          reason: 'Dari sudut pandang ruangan, pemakaian mengurangi saldo.',
        );
      }
      // Read from a location the movement never touched, no sign is invented.
      await pumpCard(tester, entries, locationId: fixture.locationTwo.id);
      for (final entry in entries) {
        expect(
          textOf(tester, StockCardList.qtyKeyFor(entry.id)),
          isNot(anyOf(startsWith('−'), startsWith('+'))),
        );
      }
      await disposeWidget(tester);
    });
  });

  group('5-6. actor dan timestamp', () {
    testWidgets('actor Perawat tampil', (tester) async {
      final id = await postedDocument();
      await openDetail(tester, id);

      for (final movementId in await context.consumptionMovementIds(id)) {
        expect(
          textOf(tester, StockCardList.actorKeyFor(movementId)),
          'Oleh ${fixture.nurse.fullName}',
        );
      }
      await disposeWidget(tester);
    });

    testWidgets('timestamp memakai formatter GMT+8', (tester) async {
      final id = await postedDocument();
      await openDetail(tester, id);

      final rows = await renderedRows(tester);
      expect(rows, isNotEmpty);
      for (final entry in rows.values) {
        final rendered = textOf(
          tester,
          StockCardList.timestampKeyFor(entry.id),
        );
        expect(
          rendered,
          AppDateTimeFormatter.dateTimeWithZone(entry.createdAt),
          reason: 'Lewat formatter operasional, bukan interpolasi sendiri.',
        );
        expect(rendered, endsWith('GMT+8'));
        // The instant is stored in UTC and displayed shifted by the operational offset, so
        // the UTC clock reading must **not** appear (T-4). Derived from the row's own
        // timestamp rather than from a literal, because the posting clock is the real one.
        expect(entry.createdAt.isUtc, isTrue);
        String hhmm(DateTime value) =>
            '${value.hour.toString().padLeft(2, '0')}:'
            '${value.minute.toString().padLeft(2, '0')}';
        final operational = entry.createdAt.add(const Duration(hours: 8));
        expect(rendered, contains(hhmm(operational)));
        expect(
          rendered,
          isNot(contains(hhmm(entry.createdAt))),
          reason: 'Jam UTC tidak boleh tampil apa adanya.',
        );
      }
      await disposeWidget(tester);
    });
  });

  group('7-9. batch, expiry dan catatan', () {
    testWidgets('batch dan expiry tampil untuk item ber-expiry', (
      tester,
    ) async {
      final id = await postedDocument();
      await openDetail(tester, id);

      final batched = (await renderedRows(tester)).values.singleWhere(
        (entry) => entry.movement.itemId == fixture.expiryItem.id,
      );
      expect(
        textOf(tester, StockCardList.batchKeyFor(batched.id)),
        'Batch ${fixture.validBatch.batchNo} · '
        'ED ${AppDateTimeFormatter.civilDate(fixture.validBatch.expiryDate)}',
      );
      await disposeWidget(tester);
    });

    testWidgets('batch tidak tampil untuk item tanpa expiry', (tester) async {
      final id = await postedDocument();
      await openDetail(tester, id);

      final plain = (await renderedRows(tester)).values.singleWhere(
        (entry) => entry.movement.itemId == fixture.plainItem.id,
      );
      expect(plain.isBatched, isFalse);
      expect(
        find.byKey(StockCardList.batchKeyFor(plain.id)),
        findsNothing,
        reason:
            'Bukan baris "Batch —" yang terbaca sebagai data hilang (G-E2).',
      );
      await disposeWidget(tester);
    });

    testWidgets('catatan tampil bila ada dan tidak dirender bila kosong', (
      tester,
    ) async {
      final id = await postedDocument(note: 'Dipakai untuk tindakan pagi');
      await openDetail(tester, id);

      final rows = await renderedRows(tester);
      final withNote = rows.values.where((entry) => entry.hasNote).toList();
      final without = rows.values.where((entry) => !entry.hasNote).toList();
      expect(withNote, hasLength(1));
      expect(without, hasLength(1));
      expect(
        textOf(tester, StockCardList.noteKeyFor(withNote.single.id)),
        'Dipakai untuk tindakan pagi',
      );
      expect(
        find.byKey(StockCardList.noteKeyFor(without.single.id)),
        findsNothing,
      );
      await disposeWidget(tester);
    });
  });

  group('10-11. historical', () {
    testWidgets('movement tetap tampil setelah master dinonaktifkan', (
      tester,
    ) async {
      final id = await postedDocument();
      final expected = await context.consumptionMovementIds(id);

      // Everything the row points at is withdrawn: the product, the room it left, and the
      // nurse who recorded it. None of it may remove a ledger row (§6/G-A4).
      await context.deactivate('items', fixture.expiryItem.id);
      await context.deactivate('items', fixture.plainItem.id);
      await context.deactivate('rooms', fixture.roomOne.id);
      await context.deactivate('users', fixture.nurse.id);

      final entries = await entriesFor(
        id,
        documentNumbers: {id: await context.consumptionDocNumber(id)},
      );
      expect(
        entries.map((entry) => entry.id).toSet(),
        expected.toSet(),
        reason: 'Tidak ada inner join active-only yang menghapus movement.',
      );

      await pumpCard(tester, entries);
      expect(find.byType(StockCardRow), findsNWidgets(2));
      for (final entry in entries) {
        // The names still resolve — deactivation is not deletion (G-A4) — and the row is
        // labelled as history.
        expect(entry.itemName, isNotNull);
        expect(entry.actorName, fixture.nurse.fullName);
        expect(entry.usesHistoricalMaster, isTrue);
        expect(textOf(tester, StockCardList.typeKeyFor(entry.id)), 'Pemakaian');
      }
      expect(tester.takeException(), isNull);
      await disposeWidget(tester);
    });

    testWidgets('referensi dokumen hilang tidak menghilangkan movement', (
      tester,
    ) async {
      final id = await postedDocument();
      final expected = await context.consumptionMovementIds(id);

      // Physically removing the header is not something the app can do — there is no
      // hard-delete path — so it is done in raw SQL, which is exactly the shape a partial
      // restore or a back-office repair leaves behind.
      await context.database.customStatement(
        'DELETE FROM consumption_lines WHERE consumption_id = ?;',
        [id],
      );
      await context.database.customStatement(
        'DELETE FROM consumptions WHERE id = ?;',
        [id],
      );

      final entries = await entriesFor(id);
      expect(entries.map((entry) => entry.id).toSet(), expected.toSet());

      await pumpCard(tester, entries);
      expect(find.byType(StockCardRow), findsNWidgets(2));
      for (final entry in entries) {
        expect(entry.hasDocumentNumber, isFalse);
        expect(
          textOf(tester, StockCardList.documentKeyFor(entry.id)),
          'dokumen Pemakaian · ${StockMovementPresenter.unresolvedDocumentLabel}',
          reason: 'Label aman, bukan baris hilang dan bukan UUID mentah.',
        );
        expect(textOf(tester, StockCardList.qtyKeyFor(entry.id)), isNotEmpty);
      }
      expect(tester.takeException(), isNull);
      await disposeWidget(tester);
    });

    testWidgets('master yang benar-benar tidak dapat diresolusi tidak crash', (
      tester,
    ) async {
      // Ids that resolve to nothing at all — the difference between "archived" and "gone".
      final orphan = StockCardEntry(
        movement: InventoryMovement(
          id: 'orphan-movement',
          itemId: 'item-yang-hilang',
          batchId: 'batch-yang-hilang',
          fromLocationId: 'lokasi-yang-hilang',
          qty: Quantity.parse('3'),
          movementType: StockMovementType.consumption,
          actorUserId: 'user-yang-hilang',
          refDocType: RefDocType.consumption,
          refDocId: 'dokumen-yang-hilang',
          createdAt: nowUtc,
        ),
      );

      await pumpCard(tester, [orphan]);
      expect(find.byType(StockCardRow), findsOneWidget);
      expect(textOf(tester, StockCardList.typeKeyFor(orphan.id)), 'Pemakaian');
      expect(
        find.text(StockMovementPresenter.unresolvedMasterLabel),
        findsWidgets,
      );
      expect(
        textOf(tester, StockCardList.batchKeyFor(orphan.id)),
        'Batch ${StockMovementPresenter.unresolvedMasterLabel}',
        reason: 'Batch tanpa expiry yang dapat dibaca tidak mencetak "ED ".',
      );
      expect(tester.takeException(), isNull);
      await disposeWidget(tester);
    });

    testWidgets('ref_doc_type tak dikenal punya fallback aman', (tester) async {
      // What a newer build, or the future sync backend, could write into a TEXT column.
      final unknown = StockCardEntry(
        movement: InventoryMovement(
          id: 'unknown-ref-movement',
          itemId: fixture.plainItem.id,
          fromLocationId: fixture.locationOne.id,
          qty: Quantity.parse('1'),
          movementType: StockMovementType.consumption,
          actorUserId: fixture.nurse.id,
          refDocType: 'XYZ',
          refDocId: 'xyz-1',
          createdAt: nowUtc,
        ),
        itemName: fixture.plainItem.name,
        sku: fixture.plainItem.sku,
        unit: fixture.plainItem.unit,
      );

      await pumpCard(tester, [unknown]);
      expect(
        textOf(tester, StockCardList.documentKeyFor(unknown.id)),
        'Dokumen (XYZ) · ${StockMovementPresenter.unresolvedDocumentLabel}',
      );
      expect(tester.takeException(), isNull);
      await disposeWidget(tester);
    });
  });

  group('12-14. scope kartu stok', () {
    testWidgets(
      'perawat lain tidak membaca kartu stok dokumen bukan miliknya',
      (tester) async {
        final id = await postedDocument();
        await openDetail(tester, id, actingAs: fixture.otherNurse);

        // Same role, same branch, same room — different person (§14).
        expect(find.byKey(AccessDeniedPage.pageKey), findsOneWidget);
        expect(find.byType(StockCardRow), findsNothing);
        expect(find.text('Pemakaian'), findsNothing);
        await disposeWidget(tester);
      },
    );

    testWidgets('perawat cabang lain tidak membaca kartu stok lintas cabang', (
      tester,
    ) async {
      final id = await postedDocument();
      await openDetail(tester, id, actingAs: fixture.otherBranchNurse);

      expect(find.byKey(AccessDeniedPage.pageKey), findsOneWidget);
      expect(find.byType(StockCardRow), findsNothing);
      await disposeWidget(tester);
    });

    // A plain `test`, not `testWidgets`: there is no widget here, and drift schedules a
    // timer when a query stream is cancelled which the widget binding would report as a
    // leak of this test's own container teardown.
    test('provider kartu stok posisi kosong untuk dokumen orang lain', () async {
      // The route guard is not the only line: the provider derives its room from
      // `consumptionDetailProvider`, whose query is owner-scoped, so a caller that reached
      // the provider directly still gets nothing.
      final id = await postedDocument();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(context.database),
          currentSessionProvider.overrideWith(
            () => FixedSessionController(fixture.otherNurse),
          ),
          consumptionClockProvider.overrideWithValue(() => nowUtc),
        ],
      );
      addTearDown(container.dispose);
      await container.read(currentSessionProvider.future);

      expect(
        await container.read(consumptionLedgerProvider(id).future),
        isEmpty,
      );
      expect(
        await container.read(
          consumptionPositionStockCardProvider((
            consumptionId: id,
            itemId: fixture.expiryItem.id,
            batchId: fixture.validBatch.id,
          )).future,
        ),
        isEmpty,
      );
    });

    testWidgets('kepala cabang membaca kartu stok posted cabangnya', (
      tester,
    ) async {
      final id = await postedDocument();
      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '${AppRoutes.branchConsumptions}/$id',
        overrides: overrides,
      );

      expect(find.byType(StockCardRow), findsNWidgets(2));
      final docNumber = await context.consumptionDocNumber(id);
      for (final movementId in await context.consumptionMovementIds(id)) {
        // Actor and document reference, read-only.
        expect(
          textOf(tester, StockCardList.actorKeyFor(movementId)),
          'Oleh ${fixture.nurse.fullName}',
        );
        expect(
          textOf(tester, StockCardList.documentKeyFor(movementId)),
          'dokumen Pemakaian · $docNumber',
        );
      }
      // Read-only: the card offers no control that changes anything.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Posting Pemakaian'), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('kepala cabang lain ditolak', (tester) async {
      final id = await postedDocument();
      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.otherBranchHead,
        location: '${AppRoutes.branchConsumptions}/$id',
        overrides: overrides,
      );

      expect(find.byKey(AccessDeniedPage.pageKey), findsOneWidget);
      expect(find.byType(StockCardRow), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('warehouse dan super admin tidak memperoleh akses baru', (
      tester,
    ) async {
      final id = await postedDocument();

      for (final actor in [fixture.warehouseUser, fixture.superAdmin]) {
        for (final location in [
          '${AppRoutes.consumptions}/$id',
          '${AppRoutes.branchConsumptions}/$id',
        ]) {
          useTabletSurface(tester);
          await pumpAppAt(
            tester,
            context: context,
            actingAs: actor,
            location: location,
            overrides: overrides,
          );
          expect(
            find.byType(StockCardRow),
            findsNothing,
            reason:
                '${actor.role.dbValue} tidak boleh mendapat kartu stok '
                'Pemakaian hanya untuk menutup hardening ini.',
          );
          expect(find.text('Pemakaian'), findsNothing);
          await disposeWidget(tester);
        }
      }
    });

    test('hardening tidak menambah route baru', () {
      // §1 forbids a new reports module and §4 forbids new access. The stock card is
      // mounted on screens that already existed, so the route table must be untouched.
      final routes = readCodeOnly('lib/app/routes.dart');
      expect(routes.contains('stockCard'), isFalse);
      expect(routes.contains('stock-card'), isFalse);
      expect(routes.contains('kartuStok'), isFalse);

      final router = readCodeOnly('lib/app/router.dart');
      expect(router.contains('StockCardList'), isFalse);
      expect(
        router.contains('ConsumptionDetailPage'),
        isTrue,
        reason: 'Surface-nya tetap halaman detail yang sudah ada.',
      );
    });
  });

  group('15. movement type lama tanpa regresi', () {
    testWidgets('sembilan jenis movement dirender dengan labelnya', (
      tester,
    ) async {
      // Every type the ledger can hold, in one card — which is the case no earlier screen
      // could produce, because each rendered only its own document's movements.
      final entries = <StockCardEntry>[];
      var index = 0;
      for (final type in StockMovementType.values) {
        entries.add(
          StockCardEntry(
            movement: InventoryMovement(
              id: 'mixed-${type.dbValue}',
              itemId: fixture.plainItem.id,
              fromLocationId: type == StockMovementType.inboundWarehouse
                  ? null
                  : fixture.locationOne.id,
              toLocationId:
                  type == StockMovementType.consumption ||
                      type == StockMovementType.disposal
                  ? null
                  : fixture.locationTwo.id,
              qty: Quantity.parse('1.25'),
              movementType: type,
              actorUserId: fixture.nurse.id,
              createdAt: nowUtc.subtract(Duration(minutes: index++)),
            ),
            itemName: fixture.plainItem.name,
            sku: fixture.plainItem.sku,
            unit: fixture.plainItem.unit,
            actorName: fixture.nurse.fullName,
          ),
        );
      }

      await pumpCard(tester, entries);
      expect(find.byType(StockCardRow), findsNWidgets(entries.length));

      // The wording each earlier milestone's own screens already used, unchanged, plus the
      // one line this hardening added.
      const expected = <StockMovementType, String>{
        StockMovementType.inboundWarehouse: 'Barang Masuk',
        StockMovementType.shipment: 'Pengiriman',
        StockMovementType.goodReceipt: 'Penerimaan',
        StockMovementType.distribution: 'Distribusi',
        StockMovementType.opnameAdjustment: 'Penyesuaian Opname',
        StockMovementType.consumption: 'Pemakaian',
        StockMovementType.itemReturn: 'Retur',
        StockMovementType.disposal: 'Pemusnahan',
        StockMovementType.reversal: 'Pembalikan',
      };
      expect(
        expected.keys.toSet(),
        StockMovementType.values.toSet(),
        reason: 'Setiap jenis movement harus punya kata Indonesia-nya.',
      );
      expected.forEach((type, label) {
        expect(
          textOf(tester, StockCardList.typeKeyFor('mixed-${type.dbValue}')),
          label,
        );
      });
      // A movement without a document reference reads as such rather than as broken.
      expect(
        find.textContaining(StockMovementPresenter.noDocumentLabel),
        findsNWidgets(entries.length),
      );
      expect(tester.takeException(), isNull);
      await disposeWidget(tester);
    });

    testWidgets('urutan baris mengikuti instant, bukan ejaan ISO-8601', (
      tester,
    ) async {
      // `created_at` is TEXT, so SQL orders it by characters. Two spellings of the same
      // ordering, one of which sorts wrong lexically.
      StockCardEntry at(String id, DateTime createdAt) => StockCardEntry(
        movement: InventoryMovement(
          id: id,
          itemId: fixture.plainItem.id,
          fromLocationId: fixture.locationOne.id,
          qty: Quantity.parse('1'),
          movementType: StockMovementType.consumption,
          actorUserId: fixture.nurse.id,
          createdAt: createdAt,
        ),
        itemName: fixture.plainItem.name,
        unit: fixture.plainItem.unit,
      );

      final older = at('older', DateTime.utc(2026, 7, 30, 1));
      final newer = at('newer', DateTime.utc(2026, 7, 30, 2));
      await pumpCard(tester, [older, newer]);

      final rendered = tester
          .widgetList<StockCardRow>(find.byType(StockCardRow))
          .map((row) => row.entry.id)
          .toList(growable: false);
      expect(rendered, ['newer', 'older']);
      await disposeWidget(tester);
    });
  });

  group('16-17. jalur kartu stok', () {
    /// Every file the rendered stock card actually goes through.
    const path = <String>[
      'lib/core/db/daos/inventory_dao.dart',
      'lib/features/inventory/data/repositories/drift_inventory_repository.dart',
      'lib/features/inventory/presentation/stock_movement_presenter.dart',
      'lib/features/inventory/presentation/stock_card_builder.dart',
      'lib/features/inventory/presentation/models/stock_card_entry.dart',
      'lib/features/inventory/presentation/widgets/stock_card_list.dart',
      'lib/features/consumption/presentation/pages/consumption_detail_page.dart',
      'lib/features/consumption/presentation/providers/consumption_providers.dart',
    ];

    test('tidak ada SQL lexical timestamp comparison', () {
      // A stock card is read as a sequence, and comparing ISO-8601 TEXT with `<`/`>` in SQL
      // compares spellings rather than instants (T-3). Ordering is fine; *filtering* on a
      // string boundary is not.
      const forbidden = <String>[
        "created_at >",
        "created_at <",
        "created_at BETWEEN",
        'createdAt.isBiggerThanValue',
        'createdAt.isBiggerOrEqualValue',
        'createdAt.isSmallerThanValue',
        'createdAt.isSmallerOrEqualValue',
        'createdAt.isBetweenValues',
      ];
      for (final file in path) {
        final source = readCodeOnly(file);
        for (final needle in forbidden) {
          expect(
            source.contains(needle),
            isFalse,
            reason: '$file membandingkan timestamp secara leksikal: $needle',
          );
        }
      }
      // And the sequence the screen shows is re-established on instants in Dart.
      expect(
        readCodeOnly(
          'lib/features/inventory/presentation/models/stock_card_entry.dart',
        ),
        contains('b.createdAt.toUtc().compareTo(a.createdAt.toUtc())'),
      );
      expect(
        readCodeOnly(
          'lib/features/inventory/presentation/widgets/stock_card_list.dart',
        ),
        contains('sort(compareStockCardEntries)'),
      );
    });

    test('tidak ada .toLocal() pada jalur kartu stok', () {
      for (final file in path) {
        expect(
          readCodeOnly(file).contains('.toLocal()'),
          isFalse,
          reason:
              '$file mengikuti timezone perangkat, bukan operasional (T-4).',
        );
      }
      // The timestamp goes through the operational formatter instead.
      expect(
        readCodeOnly(
          'lib/features/inventory/presentation/widgets/stock_card_list.dart',
        ),
        contains('AppDateTimeFormatter.dateTimeWithZone'),
      );
    });

    test('widget kartu stok tidak memformat kuantitas sendiri', () {
      final widget = readCodeOnly(
        'lib/features/inventory/presentation/widgets/stock_card_list.dart',
      );
      expect(widget.contains('milliUnits'), isFalse);
      expect(widget.contains('double'), isFalse);
      expect(
        widget,
        contains('formatWithUnit'),
        reason: 'Formatter Quantity existing (Q-4).',
      );
    });
  });

  group('18. layar sempit', () {
    testWidgets('kartu stok tidak overflow pada 320 lebar', (tester) async {
      final id = await postedDocument(
        note:
            'Catatan panjang yang menjelaskan tindakan pagi di ruangan '
            'sehingga baris ini harus membungkus, bukan meluber ke samping.',
      );
      final entries = await entriesFor(
        id,
        documentNumbers: {id: await context.consumptionDocNumber(id)},
      );

      // The narrowest screen anybody could open this on, with the longest strings the card
      // can hold: a wrapped label is fine, a RenderFlex overflow is not.
      await pumpCard(
        tester,
        entries,
        surface: const Size(320, 640),
        locationId: fixture.locationOne.id,
      );

      expect(find.byType(StockCardRow), findsNWidgets(2));
      expect(
        tester.takeException(),
        isNull,
        reason: 'RenderFlex overflow terlaporkan sebagai exception saat paint.',
      );
      await disposeWidget(tester);
    });

    testWidgets('tetap terbaca pada text scale besar', (tester) async {
      final id = await postedDocument();
      final entries = await entriesFor(id);

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.8),
              size: Size(320, 640),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: StockCardList(entries: entries),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(StockCardRow), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await disposeWidget(tester);
    });
  });

  group('architecture: mapping terpusat', () {
    const presenterPath =
        'lib/features/inventory/presentation/stock_movement_presenter.dart';

    test('mapping consumption dan CONS ada di presenter', () {
      final source = readCodeOnly(presenterPath);
      expect(
        source,
        contains("StockMovementType.consumption => 'Pemakaian'"),
        reason: '§3: consumption → Pemakaian.',
      );
      expect(
        source,
        contains("RefDocType.consumption => 'dokumen Pemakaian'"),
        reason: '§3: CONS → dokumen Pemakaian.',
      );
      // Exhaustive over the enum, and `default`-free, so a tenth movement type fails to
      // compile rather than rendering as its database value.
      expect(source.contains('default:'), isFalse);
      expect(
        source.contains('_ =>'),
        isTrue,
        reason: 'Hanya untuk TEXT ref_doc_type.',
      );
      for (final type in StockMovementType.values) {
        expect(
          source,
          contains('StockMovementType.${type.name}'),
          reason: 'Setiap jenis movement harus disebut di presenter.',
        );
      }
    });

    test('tidak ada widget lain yang men-switch label movement sendiri', () {
      // §3 forbids scattering the switch. Any other file in `lib/` that words a
      // `StockMovementType` case has started a second copy of the mapping.
      final offenders = <String>[];
      for (final file in dartFilesUnder('lib')) {
        if (file.endsWith('stock_movement_presenter.dart')) continue;
        final source = readCodeOnly(file);
        if (RegExp(r"StockMovementType\.\w+\s*(=>|:)\s*'").hasMatch(source)) {
          offenders.add(file);
        }
      }
      expect(offenders, isEmpty);
    });

    test('tidak ada widget lain yang mengeja label Pemakaian movement', () {
      // The word itself may legitimately appear as a *screen* title in the Consumption
      // feature; what may not appear is a second file mapping a ref_doc_type to it.
      final offenders = <String>[];
      for (final file in dartFilesUnder('lib')) {
        if (file.endsWith('stock_movement_presenter.dart')) continue;
        if (readCodeOnly(file).contains('dokumen Pemakaian')) {
          offenders.add(file);
        }
      }
      expect(offenders, isEmpty);
    });

    test(
      'presenter tetap di lapisan presentation dan tidak menyentuh data',
      () {
        final imports = importsOf(presenterPath);
        expect(
          imports.any((target) => target.contains('drift')),
          isFalse,
          reason: 'Presenter tidak boleh melihat lapisan data.',
        );
        expect(
          imports.any((target) => target.contains('/db/')),
          isFalse,
          reason: 'Label tidak boleh bergantung pada tabel.',
        );
        expect(imports, contains('../../../core/enums/app_enums.dart'));
      },
    );

    test('renderer kartu stok bersifat generik, bukan milik Consumption', () {
      final widget = readCodeOnly(
        'lib/features/inventory/presentation/widgets/stock_card_list.dart',
      );
      // The widget must not know which feature it is rendering, or the next movement type
      // needs a second widget.
      expect(widget.contains('Consumption'), isFalse);
      expect(widget.contains('consumption'), isFalse);
      expect(
        importsOf(
          'lib/features/inventory/presentation/widgets/stock_card_list.dart',
        ).any((target) => target.contains('consumption')),
        isFalse,
      );
    });

    test(
      'referensi dokumen bersifat read-only dan keputusannya terdokumentasi',
      () {
        // §5: nothing in this application ever made a movement reference tappable, so no
        // navigation was invented. The flag records the decision, and the prose beside it
        // records why.
        expect(StockCardList.documentReferenceIsReadOnly, isTrue);
        final widget = readLibrarySource(
          'lib/features/inventory/presentation/widgets/stock_card_list.dart',
        );
        expect(widget, contains('documentReferenceIsReadOnly'));
        expect(widget, contains('never tappable'));
        // No navigation from a row.
        final code = readCodeOnly(
          'lib/features/inventory/presentation/widgets/stock_card_list.dart',
        );
        for (final needle in [
          'GoRouter',
          'context.go',
          'context.push',
          'Navigator',
        ]) {
          expect(
            code.contains(needle),
            isFalse,
            reason: 'Baris kartu stok tidak menavigasi.',
          );
        }
      },
    );

    test('kartu stok tidak menembus repository ke DAO', () {
      for (final file in [
        'lib/features/inventory/presentation/stock_card_builder.dart',
        'lib/features/inventory/presentation/widgets/stock_card_list.dart',
        'lib/features/inventory/presentation/models/stock_card_entry.dart',
      ]) {
        for (final target in importsOf(file)) {
          expect(
            target.contains('/daos/'),
            isFalse,
            reason: '$file harus lewat repository.',
          );
          expect(target.contains('drift'), isFalse);
        }
      }
    });
  });

  group('surface: halaman detail yang sudah ada', () {
    testWidgets('draft belum menampilkan kartu stok', (tester) async {
      final id = await createConsumptionDraft(
        context,
        fixture,
        roomId: fixture.roomOne.id,
        nowUtc: nowUtc,
        actorUserId: fixture.nurse.id,
      );
      await openDetail(tester, id);

      // Nothing is posted, so there is nothing to show — and saying so is not the same as
      // showing an empty card (G-A1).
      expect(find.byKey(ConsumptionDetailPage.ledgerKey), findsOneWidget);
      expect(find.byType(StockCardRow), findsNothing);
      expect(find.text('Belum tercatat di ledger'), findsWidgets);
      await disposeWidget(tester);
    });

    testWidgets('kartu stok posisi menampilkan riwayat campuran ruangan', (
      tester,
    ) async {
      final id = await postedDocument();
      await openDetail(tester, id);

      final lines = await consumptionLineIdsByPosition(context, id);
      final lineId =
          lines['${fixture.expiryItem.id}|${fixture.validBatch.id}']!;

      await tester.tap(
        find.byKey(ConsumptionDetailPage.stockCardButtonKeyFor(lineId)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ConsumptionDetailPage.positionCardKey), findsOneWidget);
      // The fixture stocked this room through the warehouse and the branch store, so the
      // card holds a Distribusi as well as the Pemakaian — the mixed history the acceptance
      // criterion is about.
      expect(find.text('Pemakaian'), findsWidgets);
      expect(find.text('Distribusi'), findsWidgets);
      expect(tester.takeException(), isNull);
      await disposeWidget(tester);
    });
  });
}
