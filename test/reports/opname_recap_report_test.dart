import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/time/app_date_time_formatter.dart';
import 'package:aish_warehouse/core/time/app_time_zone.dart';
import 'package:aish_warehouse/core/time/date_only.dart';
import 'package:aish_warehouse/core/time/operational_iso_week.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:aish_warehouse/features/reports/domain/models/reporting_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// *Rekap Stok Opname* (§24) against a document driven through the **real**
/// workflow: `draft → submitted → reviewed`, with G-O5 posting the adjustments.
///
/// ### Why the document is counted three different ways
///
/// The report prints two quantities that must never be confused — the document's
/// `difference` and the ledger's `opname_adjustment` — and one position each way is
/// the only way to show they are separately sourced:
///
/// * `simpleItem` is counted **short**, so the ledger debits the room;
/// * `validBatch` is counted **over**, so the ledger credits it;
/// * `expiredBatch` is counted **exactly**, so G-O5 posts nothing at all and the
///   ledger column must be *empty* rather than a zero copied from the difference.
///
/// ### Clocks
///
/// `stock_opnames.created_at` comes from the table's own `clientDefault` (the wall
/// clock), so the report window has to cover today. The two *transitions* are
/// stamped from injected clocks a minute and two minutes ahead, which keeps
/// `created_at < submitted_at < reviewed_at` without depending on how fast the
/// suite runs (T-7).
void main() {
  late TestContext context;
  late OpnameFixture fixture;
  late DateTime submittedAtUtc;
  late DateTime reviewedAtUtc;
  late DateTime today;
  late String opnameId;

  /// Column indexes of [OpnameRecapReportBuilder.columns], named once.
  const docNumberColumn = 0;
  const branchColumn = 1;
  const roomColumn = 2;
  const periodColumn = 3;
  const statusColumn = 4;
  const countedByColumn = 5;
  const reviewedByColumn = 6;
  const createdAtColumn = 7;
  const submittedAtColumn = 8;
  const reviewedAtColumn = 9;
  const categoryColumn = 10;
  const skuColumn = 11;
  const itemColumn = 12;
  const batchColumn = 13;
  const systemQtyColumn = 14;
  const countedQtyColumn = 15;
  const differenceColumn = 16;
  const ledgerColumn = 17;
  const noteColumn = 18;

  setUp(() async {
    final wallClock = DateTime.now().toUtc();
    submittedAtUtc = wallClock.add(const Duration(minutes: 1));
    reviewedAtUtc = wallClock.add(const Duration(minutes: 2));
    today = AppTimeZone.operationalDate(wallClock);

    context = TestContext.create(clock: () => wallClock);
    fixture = await buildOpnameFixture(context, now: wallClock);

    final opname = await context
        .createOpname(clock: () => wallClock)
        .call(actorUserId: fixture.nurse.id, roomId: fixture.room.id);
    opnameId = opname.id;

    // Counted through the real line editor, one position each way — see the file
    // note on why three.
    final detail = await context.opnames.getDetail(opnameId);
    for (final line in detail!.lines) {
      final isSimple = line.itemId == fixture.simpleItem.id;
      final isValidBatch = line.batchId == fixture.validBatch.id;
      final isExpiredBatch = line.batchId == fixture.expiredBatch.id;

      if (isSimple) {
        await context.updateOpnameLine(
          actorUserId: fixture.nurse.id,
          lineId: line.id,
          countedQty: Quantity.parse('8'),
          note: 'Dua setengah box terpakai',
        );
      } else if (isValidBatch) {
        await context.updateOpnameLine(
          actorUserId: fixture.nurse.id,
          lineId: line.id,
          countedQty: Quantity.parse('3.375'),
          note: 'Satu ampul temuan',
        );
      } else if (isExpiredBatch) {
        await context.updateOpnameLine(
          actorUserId: fixture.nurse.id,
          lineId: line.id,
          countedQty: Quantity.parse('0.5'),
        );
      }
    }

    await context
        .submitOpname(clock: () => submittedAtUtc)
        .call(actorUserId: fixture.nurse.id, opnameId: opnameId);
    await context
        .reviewOpname(clock: () => reviewedAtUtc)
        .call(actorUserId: fixture.branchHead.id, opnameId: opnameId);
  });

  tearDown(() => context.dispose());

  Future<ReportPreview> recap({
    MasterUser? actor,
    ReportScopeType? scopeType,
    String? categoryId,
    String? roomLocationId,
    DateTime? periodStart,
    DateTime? periodEnd,
  }) {
    final who = actor ?? fixture.branchHead;
    return context
        .buildReportPreview(clock: () => reviewedAtUtc)
        .call(
          actorUserId: who.id,
          draft: ReportRequestDraft(
            reportType: ReportType.rekapOpname,
            scopeType:
                scopeType ??
                (who.role == UserRole.perawat
                    ? ReportScopeType.room
                    : ReportScopeType.branchAll),
            periodStart: periodStart ?? DateOnly.addDays(today, -1),
            periodEnd: periodEnd ?? DateOnly.addDays(today, 1),
            locationId: who.role == UserRole.perawat
                ? (roomLocationId ?? fixture.roomLocation.id)
                : null,
            filter: ReportFilter(categoryId: categoryId),
          ),
        );
  }

  /// The row for one position, addressed the way the database identifies it.
  ReportDataRow rowFor(
    ReportDocument document, {
    required String sku,
    String? batch,
  }) => document.rows.firstWhere(
    (row) =>
        row.cells[skuColumn].text == sku &&
        row.cells[batchColumn].text == (batch ?? ReportLabels.notApplicable),
  );

  group('metadata dokumen', () {
    test('nomor, branch, ruangan dan status', () async {
      final document = (await recap()).document;
      final docNumber = await context.database
          .customSelect(
            "SELECT doc_number FROM stock_opnames WHERE id = '$opnameId';",
          )
          .getSingle()
          .then((row) => row.read<String>('doc_number'));

      expect(document.rows, hasLength(3));
      for (final row in document.rows) {
        expect(row.cells[docNumberColumn].text, docNumber);
        expect(row.cells[branchColumn].text, fixture.branch.code);
        expect(row.cells[roomColumn].text, fixture.room.name);
        expect(row.cells[statusColumn].text, StockOpnameStatus.reviewed.label);
      }
    });

    test('periode ISO week diambil dari dokumen', () async {
      final document = (await recap()).document;
      final expected = OperationalIsoWeek.ofUtcInstant(
        DateTime.now().toUtc(),
      ).label;

      expect(document.rows.first.cells[periodColumn].text, expected);
    });

    test('dibuat oleh perawat, direview oleh kepala cabang', () async {
      // G-R4 in the report: the two actors are different people, and the recap has
      // to be able to show that.
      final document = (await recap()).document;

      expect(
        document.rows.first.cells[countedByColumn].text,
        fixture.nurse.fullName,
      );
      expect(
        document.rows.first.cells[reviewedByColumn].text,
        fixture.branchHead.fullName,
      );
    });

    test('tiga timestamp berbeda dan berurutan', () async {
      final document = (await recap()).document;
      final row = document.rows.first;

      expect(row.cells[createdAtColumn].text, isNotEmpty);
      expect(
        row.cells[submittedAtColumn].text,
        AppDateTimeFormatter.dateTime(submittedAtUtc),
      );
      expect(
        row.cells[reviewedAtColumn].text,
        AppDateTimeFormatter.dateTime(reviewedAtUtc),
      );
      expect(
        row.cells[createdAtColumn].text,
        isNot(row.cells[reviewedAtColumn].text),
      );
    });

    test('catatan selisih tampil', () async {
      // G-O3 made the note mandatory on a difference; the recap is where a branch
      // head reads it.
      final document = (await recap()).document;

      expect(
        rowFor(document, sku: fixture.simpleItem.sku).cells[noteColumn].text,
        'Dua setengah box terpakai',
      );
    });
  });

  group('kolom barang', () {
    test('SKU, nama, kategori, batch dan satuan', () async {
      final document = (await recap()).document;
      final simple = rowFor(document, sku: fixture.simpleItem.sku);
      final batched = rowFor(
        document,
        sku: fixture.expiryItem.sku,
        batch: fixture.validBatch.batchNo,
      );

      expect(simple.cells[itemColumn].text, fixture.simpleItem.name);
      expect(simple.cells[categoryColumn].text, fixture.category.name);
      expect(simple.cells[batchColumn].text, ReportLabels.notApplicable);
      expect(simple.unit, fixture.simpleItem.unit);

      expect(batched.cells[itemColumn].text, fixture.expiryItem.name);
      expect(batched.cells[batchColumn].text, fixture.validBatch.batchNo);
      expect(batched.unit, fixture.expiryItem.unit);
    });
  });

  group('kuantitas dokumen dan efek ledger', () {
    test('system dan counted quantity fixed-point', () async {
      final document = (await recap()).document;
      final batched = rowFor(
        document,
        sku: fixture.expiryItem.sku,
        batch: fixture.validBatch.batchNo,
      );

      expect(batched.cells[systemQtyColumn].text, '2.375');
      expect(batched.cells[countedQtyColumn].text, '3.375');
    });

    test('difference dihitung persis, termasuk negatif', () async {
      final document = (await recap()).document;

      expect(
        rowFor(
          document,
          sku: fixture.simpleItem.sku,
        ).cells[differenceColumn].text,
        '-2.5',
      );
      expect(
        rowFor(
          document,
          sku: fixture.expiryItem.sku,
          batch: fixture.validBatch.batchNo,
        ).cells[differenceColumn].text,
        '1',
      );
    });

    test('ledger adjustment berasal dari stock_movements', () async {
      // Read straight from the ledger and compared against the printed column: the
      // report may not be the only witness to its own number (G-L4).
      final rows = await context.database
          .customSelect(
            'SELECT item_id, batch_id, qty, from_location_id, to_location_id '
            "FROM stock_movements WHERE ref_doc_type = 'SO' "
            "AND ref_doc_id = '$opnameId';",
          )
          .get();
      expect(rows, hasLength(2), reason: 'hanya dua posisi berselisih');

      final byPosition = {
        for (final row in rows)
          '${row.read<String>('item_id')}|${row.read<String?>('batch_id') ?? ''}':
              row.read<String?>('to_location_id') != null
              ? Quantity.fromMilliUnits(row.read<int>('qty'))
              : -Quantity.fromMilliUnits(row.read<int>('qty')),
      };

      final document = (await recap()).document;
      expect(
        rowFor(document, sku: fixture.simpleItem.sku).cells[ledgerColumn].text,
        byPosition['${fixture.simpleItem.id}|']!.format(),
      );
      expect(
        rowFor(
          document,
          sku: fixture.expiryItem.sku,
          batch: fixture.validBatch.batchNo,
        ).cells[ledgerColumn].text,
        byPosition['${fixture.expiryItem.id}|${fixture.validBatch.id}']!
            .format(),
      );
    });

    test('difference dan ledger adjustment direkonsiliasi persis', () async {
      // The reconciliation a reviewed opname must satisfy, and the whole reason the
      // report prints both columns side by side.
      final document = (await recap()).document;

      for (final row in document.rows) {
        final ledger = row.cells[ledgerColumn].text;
        if (ledger.isEmpty) continue;
        expect(
          Quantity.parse(ledger.replaceFirst('-', '')),
          Quantity.parse(
            row.cells[differenceColumn].text.replaceFirst('-', ''),
          ),
          reason: row.cells[skuColumn].text,
        );
        expect(
          ledger.startsWith('-'),
          row.cells[differenceColumn].text.startsWith('-'),
          reason: 'tanda harus sama pada ${row.cells[skuColumn].text}',
        );
      }
    });

    test('selisih nol tidak memposting dan kolom ledger kosong', () async {
      // Not a zero copied from the difference: no movement exists, and the report
      // must say so by leaving the cell empty (§24).
      final document = (await recap()).document;
      final unchanged = rowFor(
        document,
        sku: fixture.expiryItem.sku,
        batch: fixture.expiredBatch.batchNo,
      );

      expect(unchanged.cells[differenceColumn].text, '0');
      expect(unchanged.cells[ledgerColumn].text, isEmpty);
      expect(unchanged.quantity, isNull);
    });
  });

  group('total per satuan (§32)', () {
    test('box dan ampul dijumlahkan terpisah, tanda dipertahankan', () async {
      final document = (await recap()).document;

      expect(document.overallTotals.units, ['ampul', 'box']);
      // `Quantity.parse` refuses a leading minus by design (Q-5), so a negative
      // expectation is built by negating rather than by parsing.
      expect(document.overallTotals['box'], -Quantity.parse('2.5'));
      expect(document.overallTotals['ampul'], Quantity.parse('1'));
    });

    test('subtotal kategori sama dengan total, satu kategori', () async {
      final document = (await recap()).document;

      expect(document.groups, hasLength(1));
      expect(document.groups.single.subtotals, document.overallTotals);
    });
  });

  group('filter', () {
    test('periode di luar dokumen menghasilkan laporan kosong', () async {
      final document = (await recap(
        periodStart: DateOnly.addDays(today, -20),
        periodEnd: DateOnly.addDays(today, -10),
      )).document;

      expect(document.isEmpty, isTrue);
    });

    test('kategori dokumen menampilkan seluruh baris', () async {
      final document = (await recap(categoryId: fixture.category.id)).document;

      expect(document.rowCount, 3);
    });

    test('kategori lain menghasilkan laporan kosong', () async {
      final other = await context.master.ensureCategory('Obat Keras');

      final document = (await recap(categoryId: other.id)).document;

      expect(document.isEmpty, isTrue);
    });
  });

  group('cakupan (G-L1)', () {
    test('perawat melihat opname miliknya sendiri', () async {
      final document = (await recap(actor: fixture.nurse)).document;

      expect(document.rowCount, 3);
    });

    test('opname perawat lain tidak terlihat, meski ruangannya diminta', () async {
      // The ownership rule §14 established, isolated from the room rule. G-O1 allows
      // one opname per room per ISO week, so the colleague's document has to live in
      // the second room — and the assertion is that pointing the *scope* straight at
      // that room still shows the wrong nurse nothing. Ownership, not the room
      // predicate, is what hides it.
      await context
          .createOpname(clock: () => submittedAtUtc)
          .call(
            actorUserId: fixture.secondNurse.id,
            roomId: fixture.secondRoom.id,
          );
      // `ensureLocation` is idempotent, so this returns the room location the
      // fixture already created rather than a second one.
      final secondRoomLocation = await context.master.ensureLocation(
        type: StockLocationType.room,
        name: fixture.secondRoom.name,
        branchId: fixture.branch.id,
        roomId: fixture.secondRoom.id,
      );

      final wrongNurse = (await recap(
        actor: fixture.nurse,
        roomLocationId: secondRoomLocation.id,
      )).document;
      final rightNurse = (await recap(
        actor: fixture.secondNurse,
        roomLocationId: secondRoomLocation.id,
      )).document;

      expect(wrongNurse.isEmpty, isTrue);
      expect(rightNurse.rows, isNotEmpty);
    });

    test('cakupan ruangan menyaring ke ruangan itu saja', () async {
      // Heading and rows have to describe the same place: a nurse who asks about R2
      // must not be handed their own R1 count.
      final secondRoomLocation = await context.master.ensureLocation(
        type: StockLocationType.room,
        name: fixture.secondRoom.name,
        branchId: fixture.branch.id,
        roomId: fixture.secondRoom.id,
      );

      final ownRoom = (await recap(actor: fixture.nurse)).document;
      final otherRoom = (await recap(
        actor: fixture.nurse,
        roomLocationId: secondRoomLocation.id,
      )).document;

      expect(ownRoom.rowCount, 3);
      expect(otherRoom.isEmpty, isTrue);
    });

    test('kepala cabang melihat cabangnya sendiri', () async {
      final document = (await recap()).document;

      expect(document.header.branchLabel, fixture.branch.name);
      expect(document.rowCount, 3);
    });

    test('kepala cabang lain tidak melihat dokumen ini', () async {
      final document = (await recap(actor: fixture.otherBranchHead)).document;

      expect(document.isEmpty, isTrue);
    });
  });

  group('determinisme dan pemulihan historis', () {
    test(
      'dua kali menjalankan laporan menghasilkan urutan yang sama',
      () async {
        final first = (await recap()).document;
        final second = (await recap()).document;

        expect(
          first.rows.map((row) => row.sortKey),
          second.rows.map((row) => row.sortKey),
        );
      },
    );

    test(
      'menonaktifkan barang, ruangan dan pengguna tidak menghapus baris',
      () async {
        // §51: a reviewed opname is permanent, and tidying master data afterwards may
        // not make it unreadable.
        await context.deactivate('items', fixture.simpleItem.id);
        await context.deactivate('rooms', fixture.room.id);
        await context.deactivate('users', fixture.nurse.id);

        final document = (await recap()).document;

        expect(document.rowCount, 3);
        expect(
          rowFor(document, sku: fixture.simpleItem.sku).cells[itemColumn].text,
          fixture.simpleItem.name,
        );
        expect(document.rows.first.cells[roomColumn].text, fixture.room.name);
        expect(
          document.rows.first.cells[countedByColumn].text,
          fixture.nurse.fullName,
        );
      },
    );

    test(
      'mengarsipkan barang tetap mempertahankan baris dan kuantitas',
      () async {
        await context.archive('items', fixture.expiryItem.id);

        final document = (await recap()).document;

        expect(document.rowCount, 3);
        expect(document.overallTotals['ampul'], Quantity.parse('1'));
      },
    );
  });
}
