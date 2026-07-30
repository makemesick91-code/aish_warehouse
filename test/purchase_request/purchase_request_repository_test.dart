import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/features/purchase_request/domain/models/purchase_request_models.dart';
import 'package:aish_warehouse/features/purchase_request/domain/repositories/purchase_request_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';

/// The repository contract: streams, guarded writes, and transaction atomicity.
///
/// The guarded writes are the interesting half. Every one of them carries its
/// predicate into the same SQL statement as the change, so a stale screen or a racing
/// device cannot slip an edit through the gap between reading a status and writing to
/// it. Each returns whether it affected a row, and the tests below check both answers:
/// that a legitimate write reports `true`, and that the same write against a document
/// that has moved on reports `false` **and changes nothing**.
void main() {
  late TestContext context;

  setUp(() => context = TestContext.create());
  tearDown(() => context.dispose());

  Future<
    ({
      PurchaseRequestFixture fixture,
      String prId,
      String opnameOne,
      String opnameTwo,
    })
  >
  draft() async {
    final fixture = await buildPurchaseRequestFixture(
      context,
      now: prWednesdayUtc(),
    );
    final one = await fileOpnameForRoom(
      context,
      roomId: fixture.roomOne.id,
      nurseId: fixture.nurse.id,
      utcNow: prWednesdayUtc(),
    );
    final two = await fileOpnameForRoom(
      context,
      roomId: fixture.roomTwo.id,
      nurseId: fixture.nurse.id,
      utcNow: prWednesdayUtc(),
    );
    final request = await context
        .createPurchaseRequest(clock: prWednesdayUtc)
        .call(actorUserId: fixture.branchHead.id, selectedOpnameIds: [one]);
    return (fixture: fixture, prId: request.id, opnameOne: one, opnameTwo: two);
  }

  group('stream', () {
    test('watch daftar cabang memancarkan draft baru', () async {
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWednesdayUtc(),
      );
      final opnameId = await fileOpnameForRoom(
        context,
        roomId: fixture.roomOne.id,
        nurseId: fixture.nurse.id,
        utcNow: prWednesdayUtc(),
      );

      final emissions = <List<PurchaseRequestSummary>>[];
      final subscription = context.requests
          .watchForBranch(branchId: fixture.branch.id)
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      expect(emissions.last, isEmpty);

      await context
          .createPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: fixture.branchHead.id,
            selectedOpnameIds: [opnameId],
          );
      await pumpEventQueue();

      expect(emissions.last, hasLength(1));
      expect(emissions.last.single.status, PurchaseRequestStatus.draft);
    });

    test('watch detail memancarkan perubahan baris', () async {
      final setup = await draft();
      final line = (await context.requests.getDetail(setup.prId))!.lines
          .firstWhere((line) => line.itemId == setup.fixture.simpleItem.id);

      final emissions = <PurchaseRequestDetail?>[];
      final subscription = context.requests
          .watchDetailForBranch(
            prId: setup.prId,
            branchId: setup.fixture.branch.id,
          )
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      expect(emissions.last!.lines, isNotEmpty);

      await context.updatePurchaseRequest.line(
        actorUserId: setup.fixture.branchHead.id,
        lineId: line.id,
        requestedQty: Quantity.parse('3'),
      );
      await pumpEventQueue();

      expect(
        emissions.last!.lines
            .firstWhere((line) => line.itemId == setup.fixture.simpleItem.id)
            .requestedQty,
        Quantity.parse('3'),
      );
    });

    test('watch detail memancarkan perubahan status', () async {
      final setup = await draft();

      final emissions = <PurchaseRequestDetail?>[];
      final subscription = context.requests
          .watchDetailForBranch(
            prId: setup.prId,
            branchId: setup.fixture.branch.id,
          )
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      expect(emissions.last!.status, PurchaseRequestStatus.draft);

      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);
      await pumpEventQueue();

      expect(emissions.last!.status, PurchaseRequestStatus.submitted);
      expect(emissions.last!.isEditable, isFalse);
    });

    test('PR submitted muncul di antrean Warehouse, draft tidak', () async {
      final setup = await draft();

      final emissions = <List<PurchaseRequestSummary>>[];
      final subscription = context.requests.watchWarehouseQueue().listen(
        emissions.add,
      );
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      expect(
        emissions.last,
        isEmpty,
        reason: 'Draft bersifat device-authoritative sampai dikirim (G-Y2).',
      );

      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);
      await pumpEventQueue();

      expect(emissions.last.map((summary) => summary.id), [setup.prId]);
    });

    test('processing terlihat real-time di antrean', () async {
      final setup = await draft();
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);

      final emissions = <List<PurchaseRequestSummary>>[];
      final subscription = context.requests.watchWarehouseQueue().listen(
        emissions.add,
      );
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      expect(emissions.last.single.status, PurchaseRequestStatus.submitted);

      await context
          .markPurchaseRequestProcessing(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.warehouseUser.id, prId: setup.prId);
      await pumpEventQueue();

      expect(emissions.last.single.status, PurchaseRequestStatus.processing);
    });

    test('cancelled dan rejected keluar dari antrean aktif', () async {
      final setup = await draft();
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);

      final emissions = <List<PurchaseRequestSummary>>[];
      final subscription = context.requests.watchWarehouseQueue().listen(
        emissions.add,
      );
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      expect(emissions.last, hasLength(1));

      await context
          .cancelPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: setup.fixture.branchHead.id,
            prId: setup.prId,
            reason: 'Dibatalkan cabang',
          );
      await pumpEventQueue();

      expect(
        emissions.last,
        isEmpty,
        reason: 'Antrean warehouse hanya submitted dan processing.',
      );
      // But the document is still readable by its branch, which is the difference
      // between leaving a queue and being deleted.
      expect(
        (await context.requests.getDetailForBranch(
          prId: setup.prId,
          branchId: setup.fixture.branch.id,
        ))!.status,
        PurchaseRequestStatus.cancelled,
      );
    });

    test('antrean Warehouse mencakup semua cabang', () async {
      final setup = await draft();
      final otherCount = await fileOpnameForRoom(
        context,
        roomId: setup.fixture.otherBranchRoom.id,
        nurseId: setup.fixture.otherBranchNurse.id,
        utcNow: prWednesdayUtc(),
      );
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);
      final theirs = await context
          .createPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: setup.fixture.otherBranchHead.id,
            selectedOpnameIds: [otherCount],
          );
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.otherBranchHead.id, prId: theirs.id);

      final queue = await context.requests.list(
        const PurchaseRequestFilter(statuses: warehouseQueueStatuses),
      );
      expect(queue.map((summary) => summary.id).toSet(), {
        setup.prId,
        theirs.id,
      });

      // …and the branch filter narrows it back down.
      final filtered = await context.requests.list(
        PurchaseRequestFilter(
          branchId: setup.fixture.otherBranch.id,
          statuses: warehouseQueueStatuses,
        ),
      );
      expect(filtered.map((summary) => summary.id), [theirs.id]);
    });

    test(
      'pencarian antrean cocok pada nomor dokumen dan nama cabang',
      () async {
        final setup = await draft();
        final request = (await context.requests.getById(setup.prId))!;
        await context
            .submitPurchaseRequest(clock: prWednesdayUtc)
            .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);

        Future<List<String>> search(String query) async {
          final rows = await context.requests.list(
            PurchaseRequestFilter(
              statuses: warehouseQueueStatuses,
              searchQuery: query,
            ),
          );
          return rows.map((summary) => summary.id).toList(growable: false);
        }

        expect(await search(request.docNumber), [setup.prId]);
        // Case-insensitive, and matches the branch name too.
        expect(await search('cabang uji'), [setup.prId]);
        expect(await search('CABANG UJI'), [setup.prId]);
        expect(await search('tidak ada'), isEmpty);
      },
    );

    test('filter status daftar cabang', () async {
      final setup = await draft();
      final secondDraft = await context
          .createPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: setup.fixture.branchHead.id,
            selectedOpnameIds: [setup.opnameTwo],
          );
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);

      final drafts = await context.requests.list(
        PurchaseRequestFilter(
          branchId: setup.fixture.branch.id,
          statuses: const {PurchaseRequestStatus.draft},
        ),
      );
      expect(drafts.map((summary) => summary.id), [secondDraft.id]);

      final submitted = await context.requests.list(
        PurchaseRequestFilter(
          branchId: setup.fixture.branch.id,
          statuses: const {PurchaseRequestStatus.submitted},
        ),
      );
      expect(submitted.map((summary) => summary.id), [setup.prId]);
    });

    test(
      'ringkasan menghitung baris dan tautan tanpa saling menggandakan',
      () async {
        final setup = await draft();
        // Two citations and, from both rooms, three items.
        await context
            .replacePurchaseRequestOpnames(clock: prWednesdayUtc)
            .call(
              actorUserId: setup.fixture.branchHead.id,
              prId: setup.prId,
              selectedOpnameIds: [setup.opnameOne, setup.opnameTwo],
            );

        final summary = (await context.requests.getDetail(setup.prId))!.summary;
        expect(
          summary.lineCount,
          await context.purchaseRequestLineCount(setup.prId),
          reason:
              'Join baris × tautan menghasilkan cross product; COUNT harus '
              'DISTINCT.',
        );
        expect(
          summary.linkedOpnameCount,
          await context.purchaseRequestOpnameLinkCount(setup.prId),
        );
        expect(summary.linkedOpnameCount, 2);
      },
    );
  });

  group('penulisan terjaga', () {
    test('update stale pada dokumen yang sudah dikirim ditolak', () async {
      final setup = await draft();
      final line = (await context.requests.getDetail(setup.prId))!.lines.first;
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);

      // Straight at the repository, as a stale screen would: the guard is the
      // `status = 'draft'` predicate inside the statement, not a Dart check above it.
      expect(
        await context.requests.updateDraftLine(
          lineId: line.id,
          requestedQty: Quantity.parse('99'),
        ),
        isFalse,
      );
      expect(
        await context.requests.updateDraftHeader(
          prId: setup.prId,
          note: 'Diubah setelah dikirim',
        ),
        isFalse,
      );
      expect(await context.requests.removeDraftLine(line.id), isFalse);
      expect(await context.requests.removeDraft(setup.prId), isFalse);
      expect(
        await context.requests.addDraftLine(
          prId: setup.prId,
          itemId: setup.fixture.unstockedItem.id,
          suggestedQty: Quantity.zero(),
          requestedQty: Quantity.parse('1'),
          note: 'Tambahan',
        ),
        isNull,
      );

      final after = await context.requests.getDetail(setup.prId);
      expect(after!.request.note, isNull);
      expect(after.lines.map((line) => line.id), contains(line.id));
      expect(
        after.lines
            .firstWhere((candidate) => candidate.id == line.id)
            .requestedQty,
        line.requestedQty,
      );
    });

    test('submit kedua aman', () async {
      final setup = await draft();
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);

      // The repository's own guard reports "nothing moved" rather than moving it
      // again; the use case turns the same situation into a state failure.
      expect(
        await context.requests.submit(
          prId: setup.prId,
          submittedAtUtc: prWednesdayUtc(),
        ),
        isFalse,
      );
      await expectLater(
        () => context
            .submitPurchaseRequest(clock: prWednesdayUtc)
            .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId),
        throwsA(isA<InvalidPurchaseRequestStateFailure>()),
      );
    });

    test('proses kedua aman', () async {
      final setup = await draft();
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);
      await context
          .markPurchaseRequestProcessing(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.warehouseUser.id, prId: setup.prId);
      final processedAt = await context.purchaseRequestColumn(
        setup.prId,
        'processing_at',
      );

      expect(
        await context.requests.markProcessing(
          prId: setup.prId,
          processedBy: setup.fixture.secondWarehouseUser.id,
          processingAtUtc: prWednesdayUtc().add(const Duration(hours: 5)),
        ),
        isFalse,
      );
      expect(
        await context.purchaseRequestColumn(setup.prId, 'processing_at'),
        processedAt,
        reason: 'Proses kedua tidak boleh menimpa jejak audit yang pertama.',
      );
      expect(
        await context.purchaseRequestColumn(setup.prId, 'processed_by'),
        setup.fixture.warehouseUser.id,
      );
    });

    test('tolak kedua aman', () async {
      final setup = await draft();
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);
      await context
          .markPurchaseRequestProcessing(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.warehouseUser.id, prId: setup.prId);
      await context
          .rejectPurchaseRequest(clock: prWednesdayUtc)
          .call(
            actorUserId: setup.fixture.warehouseUser.id,
            prId: setup.prId,
            reason: 'Stok habis',
          );

      expect(
        await context.requests.reject(
          prId: setup.prId,
          rejectedBy: setup.fixture.warehouseUser.id,
          rejectedAtUtc: prWednesdayUtc(),
          reason: 'Sekali lagi',
        ),
        isFalse,
      );
      expect(
        (await context.requests.getById(setup.prId))!.rejectReason,
        'Stok habis',
      );
    });

    test('cancel dengan status asal yang salah tidak berpengaruh', () async {
      final setup = await draft();
      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);

      // The caller states the status it believes it is leaving. Naming the wrong one
      // is what makes a lost update impossible rather than merely unlikely.
      expect(
        await context.requests.cancel(
          prId: setup.prId,
          from: PurchaseRequestStatus.draft,
          cancelledBy: setup.fixture.branchHead.id,
          cancelledAtUtc: prWednesdayUtc(),
          reason: 'Salah asumsi status',
        ),
        isFalse,
      );
      expect(await context.purchaseRequestStatusOf(setup.prId), 'submitted');
    });

    test('suggested_qty tidak dapat dijangkau lewat penulis baris', () async {
      final setup = await draft();
      final line = (await context.requests.getDetail(setup.prId))!.lines.first;
      final suggested = line.suggestedQty;

      await context.requests.updateDraftLine(
        lineId: line.id,
        requestedQty: Quantity.parse('3'),
        note: 'Disesuaikan',
      );

      final after = await context.requests.lineById(line.id);
      expect(
        after!.suggestedQty,
        suggested,
        reason:
            'Penulis baris tidak menerima suggested_qty, jadi editor tidak '
            'memiliki jalur ke snapshot itu.',
      );
    });
  });

  group('atomisitas transaksi', () {
    test('create menulis header, tautan dan baris bersama', () async {
      final setup = await draft();

      expect(await context.purchaseRequestOpnameLinkCount(setup.prId), 1);
      expect(
        await context.purchaseRequestLineCount(setup.prId),
        greaterThan(0),
      );
    });

    test('create yang gagal tidak menyisakan dokumen separuh', () async {
      final fixture = await buildPurchaseRequestFixture(
        context,
        now: prWednesdayUtc(),
      );
      final tooOld = await fileOpnameForRoom(
        context,
        roomId: fixture.roomOne.id,
        nurseId: fixture.nurse.id,
        utcNow: prWeeksBefore(3),
      );

      await expectLater(
        () => context
            .createPurchaseRequest(clock: prWednesdayUtc)
            .call(
              actorUserId: fixture.branchHead.id,
              selectedOpnameIds: [tooOld],
            ),
        throwsA(isA<IneligibleStockOpnameFailure>()),
      );

      final rows = await context.database
          .customSelect('SELECT COUNT(*) AS c FROM purchase_requests;')
          .getSingle();
      expect(
        rows.read<int>('c'),
        0,
        reason: 'Kegagalan validasi tidak boleh meninggalkan header.',
      );
    });

    test('recompute yang gagal tidak mengubah tautan atau baris', () async {
      final setup = await draft();
      final before = await context.requests.getDetail(setup.prId);
      final tooOld = await fileOpnameForRoom(
        context,
        roomId: setup.fixture.roomThree.id,
        nurseId: setup.fixture.nurse.id,
        utcNow: prWeeksBefore(3),
      );

      await expectLater(
        () => context
            .replacePurchaseRequestOpnames(clock: prWednesdayUtc)
            .call(
              actorUserId: setup.fixture.branchHead.id,
              prId: setup.prId,
              selectedOpnameIds: [setup.opnameOne, tooOld],
            ),
        throwsA(isA<IneligibleStockOpnameFailure>()),
      );

      final after = await context.requests.getDetail(setup.prId);
      expect(
        after!.opnames.map((reference) => reference.opnameId),
        before!.opnames.map((reference) => reference.opnameId),
      );
      expect(
        after.lines.map((line) => (line.itemId, line.suggestedQty)),
        before.lines.map((line) => (line.itemId, line.suggestedQty)),
      );
    });

    test('recompute mengganti tautan tanpa menduplikasi baris hidup', () async {
      final setup = await draft();

      await context
          .replacePurchaseRequestOpnames(clock: prWednesdayUtc)
          .call(
            actorUserId: setup.fixture.branchHead.id,
            prId: setup.prId,
            selectedOpnameIds: [setup.opnameTwo],
          );

      expect(await context.purchaseRequestOpnameLinkCount(setup.prId), 1);
      final detail = await context.requests.getDetail(setup.prId);
      expect(detail!.opnames.single.opnameId, setup.opnameTwo);

      final itemIds = detail.lines
          .map((line) => line.itemId)
          .toList(growable: false);
      expect(
        itemIds.toSet(),
        hasLength(itemIds.length),
        reason: 'Satu baris hidup per item (G-P2).',
      );

      // Re-selecting the original citation must not trip the partial unique index on
      // `(pr_id, opname_id)` — the old link was soft-deleted, so the position is free.
      await context
          .replacePurchaseRequestOpnames(clock: prWednesdayUtc)
          .call(
            actorUserId: setup.fixture.branchHead.id,
            prId: setup.prId,
            selectedOpnameIds: [setup.opnameOne],
          );
      expect(await context.purchaseRequestOpnameLinkCount(setup.prId), 1);
    });
  });

  group('pemetaan', () {
    test('milli-unit dipetakan ke Quantity di kedua arah', () async {
      final setup = await draft();
      final line = (await context.requests.getDetail(setup.prId))!.lines
          .firstWhere((line) => line.itemId == setup.fixture.simpleItem.id);

      // The fixture makes this exactly 2.5 box — 2500 milli-units.
      expect(line.suggestedQty, Quantity.parse('2.5'));

      await context.updatePurchaseRequest.line(
        actorUserId: setup.fixture.branchHead.id,
        lineId: line.id,
        requestedQty: Quantity.parse('3.375'),
      );

      final reread = await context.requests.lineById(line.id);
      expect(reread!.requestedQty, Quantity.parse('3.375'));
      expect(reread.requestedQty.milliUnits, 3375);
    });

    test('status text dipetakan ke enum', () async {
      final setup = await draft();
      expect(
        (await context.requests.getById(setup.prId))!.status,
        PurchaseRequestStatus.draft,
      );

      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);
      expect(
        (await context.requests.getById(setup.prId))!.status,
        PurchaseRequestStatus.submitted,
      );
    });

    test('draft baru berstatus sync pending (G-Y1)', () async {
      final setup = await draft();
      final request = (await context.requests.getById(setup.prId))!;
      expect(request.syncStatus, SyncStatus.pending);
      expect(request.isPendingSync, isTrue);
    });

    test('nomor dokumen sementara memakai pola TMP-PR', () async {
      final setup = await draft();
      final request = (await context.requests.getById(setup.prId))!;

      // G-Y4: the final `PR-{cabang}-{yyyyMMdd}-{seq}` is the server's to assign.
      expect(request.docNumber, startsWith('TMP-PR-'));

      await context
          .submitPurchaseRequest(clock: prWednesdayUtc)
          .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);
      expect(
        (await context.requests.getById(setup.prId))!.docNumber,
        request.docNumber,
        reason: 'Submit tidak boleh mengarang nomor berformat server.',
      );
    });

    test(
      'umur permintaan dihitung dari submit dan tidak pernah negatif',
      () async {
        final setup = await draft();
        await context
            .submitPurchaseRequest(clock: prWednesdayUtc)
            .call(actorUserId: setup.fixture.branchHead.id, prId: setup.prId);

        final summary = (await context.requests.getDetail(setup.prId))!.summary;
        expect(
          summary.ageSinceSubmission(
            prWednesdayUtc().add(const Duration(hours: 30)),
          ),
          const Duration(hours: 30),
        );
        // A device whose clock is behind must not render a negative age.
        expect(
          summary.ageSinceSubmission(
            prWednesdayUtc().subtract(const Duration(hours: 5)),
          ),
          Duration.zero,
        );
      },
    );

    test('total diminta dikelompokkan per satuan', () async {
      final setup = await draft();
      await context
          .replacePurchaseRequestOpnames(clock: prWednesdayUtc)
          .call(
            actorUserId: setup.fixture.branchHead.id,
            prId: setup.prId,
            selectedOpnameIds: [setup.opnameOne, setup.opnameTwo],
          );

      final detail = (await context.requests.getDetail(setup.prId))!;
      final totals = detail.requestedByUnit;

      // `box`, `ampul` and `pcs` are never added together: `2 box` and `3 pcs` are not
      // `5` of anything.
      expect(totals.keys, containsAll(<String>['box', 'ampul']));
      // The box line existed before the recompute, so its *requested* quantity is the
      // one already on the document — 2.5 — even though the suggestion behind it grew
      // to 6.5 when the second room was cited. Overwriting a typed quantity is exactly
      // what the reconciliation must not do.
      expect(totals['box'], Quantity.parse('2.5'));
      expect(
        detail.lines
            .firstWhere((line) => line.itemId == setup.fixture.simpleItem.id)
            .suggestedQty,
        Quantity.parse('6.5'),
      );
      // The ampul line is new, so it starts at its suggestion.
      expect(totals['ampul'], Quantity.parse('6'));
    });
  });
}
