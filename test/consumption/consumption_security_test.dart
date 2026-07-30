import 'package:aish_warehouse/app/routes.dart';
import 'package:aish_warehouse/core/db/database_providers.dart';
import 'package:aish_warehouse/core/enums/app_enums.dart';
import 'package:aish_warehouse/core/errors/failure_presenter.dart';
import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:aish_warehouse/core/session/acting_user_providers.dart';
import 'package:aish_warehouse/core/session/current_user_session.dart';
import 'package:aish_warehouse/features/consumption/domain/services/consumption_access_policy.dart';
import 'package:aish_warehouse/features/consumption/presentation/providers/consumption_providers.dart';
import 'package:aish_warehouse/features/master/domain/models/master_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `ProviderListenable` and `Refreshable` live here rather than in the main barrel file
// in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_context.dart';
import '../helpers/widget_harness.dart';

/// Who may read and write a Pemakaian, at every layer (§43).
///
/// The rule this milestone adds is **ownership**, and it is the one no earlier document
/// needed: every previous scope is a *place* — any Kepala Cabang of a branch may open any
/// of its Purchase Requests — whereas a Pemakaian draft belongs to the nurse who recorded
/// it (§14). So the pair these tests keep returning to is `nurse` and `otherNurse`: same
/// role, same branch, same room, different person. That pair passes every check an earlier
/// milestone's guards would have applied.
///
/// Each rule is asserted at four layers, because any one of them alone is a single point
/// of failure:
///
/// 1. **SQL** — the DAO's predicate, so a foreign document is never fetched;
/// 2. **providers** — the scope derived from the *stored* actor, never from an argument;
/// 3. **use cases** — the actor re-read from the database on every write (O-8);
/// 4. **routes** — the guard, exercised by typing the URL rather than by pumping a page.
void main() {
  late TestContext context;
  late ConsumptionFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 8);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildConsumptionFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  Future<String> draftOf(MasterUser nurse, {String? roomId}) =>
      createConsumptionDraft(
        context,
        fixture,
        roomId: roomId ?? fixture.roomOne.id,
        nowUtc: nowUtc,
        actorUserId: nurse.id,
      );

  Future<String> postedOf(MasterUser nurse, {String? roomId}) async {
    final id = await draftOf(nurse, roomId: roomId);
    await addConsumptionPosition(
      context,
      fixture,
      consumptionId: id,
      itemId: fixture.plainItem.id,
      qty: '1',
      nowUtc: nowUtc,
      actorUserId: nurse.id,
    );
    await context.postConsumption().call(
      actorUserId: nurse.id,
      consumptionId: id,
    );
    return id;
  }

  /// A provider graph hanging off the in-memory database, acting as [user].
  ///
  /// The whole graph hangs off `appDatabaseProvider`, exactly as in the app, so nothing
  /// here is a stub: the scoped queries really run, against real rows.
  Future<ProviderContainer> containerFor(MasterUser user) async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(context.database),
        currentSessionProvider.overrideWith(() => FixedSessionController(user)),
        consumptionClockProvider.overrideWithValue(() => nowUtc),
      ],
    );
    addTearDown(container.dispose);
    // Let the session resolve before anything reads it.
    await container.read(currentSessionProvider.future);
    return container;
  }

  /// Reads a stream provider while holding it open.
  ///
  /// `container.read(p.future)` alone opens and immediately closes its own subscription,
  /// so an `autoDispose` provider is torn down before its first emission ever arrives. A
  /// screen holds the provider for as long as it is on screen; this reproduces that rather
  /// than racing it.
  Future<T> readStream<T>(
    ProviderContainer container,
    ProviderListenable<AsyncValue<T>> provider,
    Refreshable<Future<T>> future,
  ) async {
    final subscription = container.listen(provider, (_, _) {});
    try {
      return await container.read(future);
    } finally {
      subscription.close();
    }
  }

  group('1. SQL scope', () {
    test('own-draft predicate memakai created_by', () async {
      final mine = await draftOf(fixture.nurse);
      final theirs = await draftOf(fixture.otherNurse);

      final myRows = await context.consumptions.listOwn(
        actorUserId: fixture.nurse.id,
      );
      expect(myRows.map((row) => row.id), [mine]);

      final theirRows = await context.consumptions.listOwn(
        actorUserId: fixture.otherNurse.id,
      );
      expect(theirRows.map((row) => row.id), [theirs]);
    });

    test('perawat A tidak dapat membaca draft perawat B', () async {
      final theirs = await draftOf(fixture.otherNurse);

      expect(
        await context.consumptions.getOwn(
          consumptionId: theirs,
          actorUserId: fixture.nurse.id,
        ),
        isNull,
      );
      expect(
        await context.consumptions.findAccessScope(
          consumptionId: theirs,
          scope: ConsumptionQueryScope.ownDocuments,
          actorUserId: fixture.nurse.id,
        ),
        isNull,
      );
    });

    test('perawat A tidak dapat membaca posted perawat B', () async {
      // Posted documents are no more shared between nurses than drafts are: what opens up
      // at `posted` is the *branch head's* view, not a colleague's (§14).
      final theirs = await postedOf(fixture.otherNurse);

      expect(
        await context.consumptions.getOwn(
          consumptionId: theirs,
          actorUserId: fixture.nurse.id,
        ),
        isNull,
      );
    });

    test('kepala cabang hanya melihat posted cabangnya', () async {
      final draft = await draftOf(fixture.nurse);
      final posted = await postedOf(fixture.otherNurse);

      final rows = await context.consumptions.listPostedForBranch(
        branchId: fixture.branch.id,
      );
      expect(rows.map((row) => row.id), [posted]);
      expect(rows.map((row) => row.id), isNot(contains(draft)));
    });

    test('scope branchPosted menolak draft meski status diminta', () async {
      // The `posted` half lives in the DAO's own scope predicate, not in a parameter — so
      // asking for `draft` explicitly still returns nothing (§14).
      final draft = await draftOf(fixture.nurse);

      final scope = await context.consumptions.findAccessScope(
        consumptionId: draft,
        scope: ConsumptionQueryScope.branchPosted,
        branchId: fixture.branch.id,
        statuses: const {ConsumptionStatus.draft},
      );
      expect(scope, isNull);
    });

    test('kepala cabang cabang lain tidak melihat apa pun', () async {
      await postedOf(fixture.nurse);

      final rows = await context.consumptions.listPostedForBranch(
        branchId: fixture.otherBranch.id,
      );
      expect(rows, isEmpty);
    });

    test('scope tanpa aktor atau cabang tidak cocok apa pun', () async {
      // A scope asked for without its key matches nothing rather than everything: a
      // provider that lost its session must see no documents, not all of them.
      final mine = await draftOf(fixture.nurse);

      expect(
        await context.consumptions.findAccessScope(
          consumptionId: mine,
          scope: ConsumptionQueryScope.ownDocuments,
        ),
        isNull,
      );
      expect(
        await context.consumptions.findAccessScope(
          consumptionId: mine,
          scope: ConsumptionQueryScope.branchPosted,
        ),
        isNull,
      );
    });

    test('kandidat hanya dari ruangan dokumen ini', () async {
      // Room 2 holds a smaller shelf, and none of the other branch's stock is reachable
      // from either.
      final roomTwo = await context.consumptions.roomPositions(
        roomId: fixture.roomTwo.id,
        roomLocationId: fixture.locationTwo.id,
        nowUtc: nowUtc,
      );
      expect(roomTwo, hasLength(2));
      expect(
        roomTwo.every(
          (position) => position.locationId == fixture.locationTwo.id,
        ),
        isTrue,
      );

      // The warehouse and the branch store hold plenty, and neither is a candidate: the
      // query takes a **room** location, so there is no parameter through which one could
      // arrive.
      final warehouseAsRoom = await context.consumptions.roomPositions(
        roomId: fixture.roomOne.id,
        roomLocationId: fixture.warehouse.id,
        nowUtc: nowUtc,
      );
      expect(warehouseAsRoom, isEmpty);
      final storeAsRoom = await context.consumptions.roomPositions(
        roomId: fixture.roomOne.id,
        roomLocationId: fixture.branchStore.id,
        nowUtc: nowUtc,
      );
      expect(storeAsRoom, isEmpty);
    });
  });

  group('2. providers', () {
    test('own list scoped ke aktor', () async {
      final mine = await draftOf(fixture.nurse);
      await draftOf(fixture.otherNurse);

      final container = await containerFor(fixture.nurse);
      final rows = await readStream(
        container,
        ownConsumptionListProvider,
        ownConsumptionListProvider.future,
      );
      expect(rows.map((row) => row.id), [mine]);
    });

    test('own list perawat lain tidak memuat dokumen kita', () async {
      final mine = await draftOf(fixture.nurse);

      final container = await containerFor(fixture.otherNurse);
      final rows = await readStream(
        container,
        ownConsumptionListProvider,
        ownConsumptionListProvider.future,
      );
      expect(rows.map((row) => row.id), isNot(contains(mine)));
    });

    test('kepala cabang own list kosong — tidak ada write scope', () async {
      await draftOf(fixture.nurse);

      final container = await containerFor(fixture.branchHead);
      expect(
        await readStream(
          container,
          ownConsumptionListProvider,
          ownConsumptionListProvider.future,
        ),
        isEmpty,
      );
    });

    test('branch list kosong untuk perawat', () async {
      await postedOf(fixture.nurse);

      final container = await containerFor(fixture.nurse);
      expect(
        await readStream(
          container,
          branchConsumptionListProvider,
          branchConsumptionListProvider.future,
        ),
        isEmpty,
      );
    });

    test('branch list kosong untuk warehouse dan super admin', () async {
      await postedOf(fixture.nurse);

      for (final actor in [fixture.warehouseUser, fixture.superAdmin]) {
        final container = await containerFor(actor);
        expect(
          await readStream(
            container,
            branchConsumptionListProvider,
            branchConsumptionListProvider.future,
          ),
          isEmpty,
          reason: '${actor.role.dbValue} tidak boleh membaca riwayat cabang.',
        );
        expect(
          await readStream(
            container,
            ownConsumptionListProvider,
            ownConsumptionListProvider.future,
          ),
          isEmpty,
        );
      }
    });

    test('detail provider menolak dokumen perawat lain', () async {
      final theirs = await draftOf(fixture.otherNurse);

      final container = await containerFor(fixture.nurse);
      expect(
        await readStream(
          container,
          ownConsumptionDetailProvider(theirs),
          ownConsumptionDetailProvider(theirs).future,
        ),
        isNull,
      );
      expect(
        await container.read(consumptionDetailSnapshotProvider(theirs).future),
        isNull,
      );
    });

    test('detail provider kepala cabang menolak draft', () async {
      final draft = await draftOf(fixture.nurse);

      final container = await containerFor(fixture.branchHead);
      expect(
        await readStream(
          container,
          branchConsumptionDetailProvider(draft),
          branchConsumptionDetailProvider(draft).future,
        ),
        isNull,
      );
    });

    test('detail provider kepala cabang cabang lain menolak posted', () async {
      final posted = await postedOf(fixture.nurse);

      final container = await containerFor(fixture.otherBranchHead);
      expect(
        await readStream(
          container,
          branchConsumptionDetailProvider(posted),
          branchConsumptionDetailProvider(posted).future,
        ),
        isNull,
      );
    });

    test('daftar ruangan berasal dari cabang aktor, bukan argumen', () async {
      final mine = await containerFor(fixture.nurse);
      final rooms = await mine.read(consumptionRoomsProvider.future);
      expect(rooms.map((room) => room.roomId).toSet(), {
        fixture.roomOne.id,
        fixture.roomTwo.id,
      });
      expect(
        rooms.map((room) => room.roomId),
        isNot(contains(fixture.otherBranchRoom.id)),
      );

      final other = await containerFor(fixture.otherBranchNurse);
      final otherRooms = await other.read(consumptionRoomsProvider.future);
      expect(otherRooms.map((room) => room.roomId), [
        fixture.otherBranchRoom.id,
      ]);
    });

    test('kepala cabang tidak mendapat daftar ruangan untuk menulis', () async {
      final container = await containerFor(fixture.branchHead);
      expect(await container.read(consumptionRoomsProvider.future), isEmpty);
      // …but does get the read-only room list for the history filter.
      expect(
        (await container.read(
          branchConsumptionRoomsProvider.future,
        )).map((room) => room.roomId).toSet(),
        {fixture.roomOne.id, fixture.roomTwo.id},
      );
    });

    test(
      'perawat tidak mendapat daftar perawat untuk filter riwayat',
      () async {
        final container = await containerFor(fixture.nurse);
        expect(await container.read(branchNursesProvider.future), isEmpty);
      },
    );

    test(
      'filter perawat kepala cabang hanya memuat perawat cabangnya',
      () async {
        final container = await containerFor(fixture.branchHead);
        final nurses = await container.read(branchNursesProvider.future);
        expect(nurses.map((user) => user.id).toSet(), {
          fixture.nurse.id,
          fixture.otherNurse.id,
        });
        expect(
          nurses.map((user) => user.id),
          isNot(contains(fixture.otherBranchNurse.id)),
        );
      },
    );

    test('canRecordConsumption hanya benar untuk perawat', () async {
      for (final entry in <MasterUser, bool>{
        fixture.nurse: true,
        fixture.branchHead: false,
        fixture.warehouseUser: false,
        fixture.superAdmin: false,
      }.entries) {
        final container = await containerFor(entry.key);
        // Read the acting user first, so the session — and therefore the role provider —
        // is resolved before the predicate is asked.
        await container.read(actingUserProvider.future);
        expect(
          container.read(canRecordConsumptionProvider),
          entry.value,
          reason: '${entry.key.role.dbValue} salah dinilai.',
        );
      }
    });

    test('ganti sesi membatalkan cache dokumen', () async {
      // The leak a stale cache entry would produce: a document opened under one session
      // must not still resolve under the next. `autoDispose` plus reading the actor inside
      // the provider body is what closes it.
      final mine = await draftOf(fixture.nurse);

      final asMine = await containerFor(fixture.nurse);
      expect(
        await readStream(
          asMine,
          ownConsumptionDetailProvider(mine),
          ownConsumptionDetailProvider(mine).future,
        ),
        isNotNull,
      );

      final asTheirs = await containerFor(fixture.otherNurse);
      expect(
        await readStream(
          asTheirs,
          ownConsumptionDetailProvider(mine),
          ownConsumptionDetailProvider(mine).future,
        ),
        isNull,
      );
    });
  });

  group('3. use cases', () {
    test('setiap tulis memuat ulang aktor dari database', () async {
      final id = await draftOf(fixture.nurse);
      // The account is demoted between the read and the write. The session object is
      // never consulted — every use case re-reads the actor (O-8).
      await context.database.customStatement(
        'UPDATE users SET role = ? WHERE id = ?;',
        [UserRole.warehouse.dbValue, fixture.nurse.id],
      );

      await expectLater(
        context
            .addConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              itemId: fixture.plainItem.id,
              qty: Quantity.parse('1'),
            ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
    });

    test('cabang aktor berubah menolak tulis pada draft lama', () async {
      // Ownership alone would let this through: the nurse still created the document. The
      // branch check is what catches it (§14).
      final id = await draftOf(fixture.nurse);
      await context.database.customStatement(
        'UPDATE users SET branch_id = ? WHERE id = ?;',
        [fixture.otherBranch.id, fixture.nurse.id],
      );

      await expectLater(
        context
            .addConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.nurse.id,
              consumptionId: id,
              itemId: fixture.plainItem.id,
              qty: Quantity.parse('1'),
            ),
        throwsA(isA<ConsumptionBranchMismatchFailure>()),
      );
    });

    test('setiap peran non-perawat ditolak pada setiap jalur tulis', () async {
      final id = await draftOf(fixture.nurse);
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );
      final lines = await consumptionLineIdsByPosition(context, id);
      final lineId = lines['${fixture.plainItem.id}|']!;

      for (final actor in [
        fixture.branchHead,
        fixture.otherBranchHead,
        fixture.warehouseUser,
        fixture.superAdmin,
      ]) {
        await expectLater(
          context.createConsumption().call(
            actorUserId: actor.id,
            roomId: fixture.roomOne.id,
          ),
          throwsA(isA<InvalidReviewerFailure>()),
          reason: '${actor.role.dbValue} create',
        );
        await expectLater(
          context
              .addConsumptionLine(clock: () => nowUtc)
              .call(
                actorUserId: actor.id,
                consumptionId: id,
                itemId: fixture.otherPlainItem.id,
                qty: Quantity.parse('1'),
              ),
          throwsA(isA<InvalidReviewerFailure>()),
          reason: '${actor.role.dbValue} add',
        );
        await expectLater(
          context
              .updateConsumptionLine(clock: () => nowUtc)
              .call(
                actorUserId: actor.id,
                consumptionId: id,
                lineId: lineId,
                qty: Quantity.parse('2'),
              ),
          throwsA(isA<InvalidReviewerFailure>()),
          reason: '${actor.role.dbValue} update',
        );
        await expectLater(
          context.removeConsumptionLine.call(
            actorUserId: actor.id,
            consumptionId: id,
            lineId: lineId,
          ),
          throwsA(isA<InvalidReviewerFailure>()),
          reason: '${actor.role.dbValue} remove',
        );
        await expectLater(
          context.updateConsumptionHeader.call(
            actorUserId: actor.id,
            consumptionId: id,
            note: 'x',
          ),
          throwsA(isA<InvalidReviewerFailure>()),
          reason: '${actor.role.dbValue} note',
        );
        await expectLater(
          context.postConsumption().call(
            actorUserId: actor.id,
            consumptionId: id,
          ),
          throwsA(isA<InvalidReviewerFailure>()),
          reason: '${actor.role.dbValue} post',
        );
      }

      // Nothing changed.
      expect(await context.consumptionStatusOf(id), 'draft');
      expect(await context.consumptionLineCount(id), 1);
      expect(await context.consumptionMovementCount(id), 0);
    });

    test('perawat cabang lain ditolak pada setiap jalur tulis', () async {
      final id = await draftOf(fixture.nurse);

      await expectLater(
        context
            .addConsumptionLine(clock: () => nowUtc)
            .call(
              actorUserId: fixture.otherBranchNurse.id,
              consumptionId: id,
              itemId: fixture.plainItem.id,
              qty: Quantity.parse('1'),
            ),
        // Ownership is checked before branch, so this is the failure that fires — and it
        // says nothing about which branch the document belongs to.
        throwsA(isA<ConsumptionNotOwnedFailure>()),
      );
    });

    test('kepala cabang tidak dapat memposting pemakaian', () async {
      final id = await draftOf(fixture.nurse);
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
      );

      await expectLater(
        context.postConsumption().call(
          actorUserId: fixture.branchHead.id,
          consumptionId: id,
        ),
        throwsA(isA<InvalidReviewerFailure>()),
      );
      expect(await context.consumptionMovementCount(id), 0);
    });
  });

  group('4. route guard', () {
    testWidgets('perawat dapat membuka daftarnya sendiri', (tester) async {
      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: AppRoutes.consumptions,
      );

      expect(find.text('Pemakaian'), findsWidgets);
      expect(find.text(accessDeniedMessage), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('kepala cabang ditolak pada daftar perawat', (tester) async {
      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: AppRoutes.consumptions,
      );

      // The synchronous redirect sends them home rather than rendering the section.
      expect(find.byKey(const ValueKey('consumptionList')), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('perawat ditolak pada riwayat cabang', (tester) async {
      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: AppRoutes.branchConsumptions,
      );

      expect(find.byKey(const ValueKey('branchConsumptionList')), findsNothing);
      await disposeWidget(tester);
    });

    testWidgets('URL langsung ke dokumen perawat lain ditolak', (tester) async {
      final theirs = await draftOf(fixture.otherNurse);
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: theirs,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '1.5',
        nowUtc: nowUtc,
        actorUserId: fixture.otherNurse.id,
      );

      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: '${AppRoutes.consumptions}/$theirs',
      );

      expect(find.text(accessDeniedMessage), findsOneWidget);
      await _expectNoDocumentContent(tester, context, theirs, fixture);
      await disposeWidget(tester);
    });

    testWidgets('URL langsung ke editor dokumen perawat lain ditolak', (
      tester,
    ) async {
      final theirs = await draftOf(fixture.otherNurse);

      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: '${AppRoutes.consumptions}/$theirs/edit',
      );

      expect(find.text(accessDeniedMessage), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('URL editor dokumen posted milik sendiri ditolak', (
      tester,
    ) async {
      // The editor accepts `draft` only: a posted document is read-only permanently
      // (G-S2), and the detail screen is what shows it.
      final mine = await postedOf(fixture.nurse);

      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: '${AppRoutes.consumptions}/$mine/edit',
      );

      expect(find.text(accessDeniedMessage), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('ID yang tidak ada dan ID asing memberi respons identik', (
      tester,
    ) async {
      final theirs = await draftOf(fixture.otherNurse);

      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: '${AppRoutes.consumptions}/$theirs',
      );
      final foreign = find.text(accessDeniedMessage).evaluate().length;
      await disposeWidget(tester);

      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.nurse,
        location: '${AppRoutes.consumptions}/tidak-ada-sama-sekali',
      );
      final missing = find.text(accessDeniedMessage).evaluate().length;
      expect(
        missing,
        foreign,
        reason:
            'Membedakan "tidak ada" dari "bukan milik Anda" akan membuat id '
            'dokumen dapat ditebak.',
      );
      await disposeWidget(tester);
    });

    testWidgets('kepala cabang ditolak pada draft via URL riwayat', (
      tester,
    ) async {
      final draft = await draftOf(fixture.nurse);
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: draft,
        itemId: fixture.expiryItem.id,
        batchId: fixture.validBatch.id,
        qty: '2.5',
        nowUtc: nowUtc,
      );

      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '${AppRoutes.branchConsumptions}/$draft',
      );

      expect(find.text(accessDeniedMessage), findsOneWidget);
      await _expectNoDocumentContent(tester, context, draft, fixture);
      await disposeWidget(tester);
    });

    testWidgets('kepala cabang cabang lain ditolak pada posted', (
      tester,
    ) async {
      final posted = await postedOf(fixture.nurse);

      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.otherBranchHead,
        location: '${AppRoutes.branchConsumptions}/$posted',
      );

      expect(find.text(accessDeniedMessage), findsOneWidget);
      await disposeWidget(tester);
    });

    testWidgets('kepala cabang dapat membuka posted cabangnya, read-only', (
      tester,
    ) async {
      final posted = await postedOf(fixture.nurse);

      useTabletSurface(tester);
      await pumpAppAt(
        tester,
        context: context,
        actingAs: fixture.branchHead,
        location: '${AppRoutes.branchConsumptions}/$posted',
      );

      expect(find.text(accessDeniedMessage), findsNothing);
      // And nothing that could change it.
      expect(find.byKey(const ValueKey('consumptionPostButton')), findsNothing);
      expect(
        find.byKey(const ValueKey('consumptionAddPositionButton')),
        findsNothing,
      );
      expect(find.text('Posting Pemakaian'), findsNothing);
      expect(find.text('Setujui'), findsNothing);
      expect(find.text('Ajukan'), findsNothing);
      await disposeWidget(tester);
    });
  });

  group('kebijakan akses', () {
    test('scope per route kind', () {
      expect(
        ConsumptionAccessPolicy.requiredScope(ConsumptionRouteKind.nurseList),
        ConsumptionQueryScope.ownDocuments,
      );
      expect(
        ConsumptionAccessPolicy.requiredScope(
          ConsumptionRouteKind.branchDocument,
        ),
        ConsumptionQueryScope.branchPosted,
      );
    });

    test('editor hanya menerima draft; riwayat cabang hanya posted', () {
      expect(
        ConsumptionAccessPolicy.visibleStatusesFor(
          ConsumptionRouteKind.nurseDraft,
        ),
        {ConsumptionStatus.draft},
      );
      expect(
        ConsumptionAccessPolicy.visibleStatusesFor(
          ConsumptionRouteKind.branchList,
        ),
        {ConsumptionStatus.posted},
      );
      expect(
        ConsumptionAccessPolicy.visibleStatusesFor(
          ConsumptionRouteKind.nurseDocument,
        ),
        {ConsumptionStatus.draft, ConsumptionStatus.posted},
      );
    });

    test('hanya layar perawat yang menulis', () {
      expect(
        ConsumptionAccessPolicy.isWriteScreen(ConsumptionRouteKind.nurseCreate),
        isTrue,
      );
      expect(
        ConsumptionAccessPolicy.isWriteScreen(ConsumptionRouteKind.nurseDraft),
        isTrue,
      );
      for (final kind in [
        ConsumptionRouteKind.nurseList,
        ConsumptionRouteKind.nurseDocument,
        ConsumptionRouteKind.branchList,
        ConsumptionRouteKind.branchDocument,
      ]) {
        expect(
          ConsumptionAccessPolicy.isWriteScreen(kind),
          isFalse,
          reason: '$kind bukan layar tulis.',
        );
      }
    });

    test(
      'canWrite hanya perawat; canReadBranchHistory hanya kepala cabang',
      () {
        expect(ConsumptionAccessPolicy.canWrite(UserRole.perawat), isTrue);
        for (final role in [
          UserRole.kepalaCabang,
          UserRole.warehouse,
          UserRole.superAdmin,
        ]) {
          expect(ConsumptionAccessPolicy.canWrite(role), isFalse);
        }
        expect(ConsumptionAccessPolicy.canWrite(null), isFalse);

        expect(
          ConsumptionAccessPolicy.canReadBranchHistory(UserRole.kepalaCabang),
          isTrue,
        );
        for (final role in [
          UserRole.perawat,
          UserRole.warehouse,
          UserRole.superAdmin,
        ]) {
          expect(ConsumptionAccessPolicy.canReadBranchHistory(role), isFalse);
        }
      },
    );

    test('akun nonaktif ditolak pada setiap layar', () {
      const inactive = MasterUser(
        id: 'u1',
        fullName: 'Perawat Nonaktif',
        email: 'x@test.local',
        role: UserRole.perawat,
        branchId: 'b1',
        isActive: false,
      );
      for (final kind in ConsumptionRouteKind.values) {
        expect(
          ConsumptionAccessPolicy.forSection(
            user: inactive,
            kind: kind,
          ).isDenied,
          isTrue,
        );
      }
    });

    test('sesi kosong ditolak dengan alasan noSession', () {
      expect(
        ConsumptionAccessPolicy.forSection(
          user: null,
          kind: ConsumptionRouteKind.nurseList,
        ).reason,
        ConsumptionAccessDenialReason.noSession,
      );
    });
  });

  group('tidak ada data pasien', () {
    test('kolom pasien tidak ada di kedua tabel', () async {
      // Asserted here as well as in the schema test, because this is the security
      // property rather than the schema one: a column that could hold personal health
      // information would put it inside a table every branch head reads (§9/§43).
      for (final table in ['consumptions', 'consumption_lines']) {
        final rows = await context.database
            .customSelect('PRAGMA table_xinfo($table);')
            .get();
        final columns = rows
            .map((row) => row.read<String>('name').toLowerCase())
            .toSet();
        for (final needle in const [
          'patient',
          'pasien',
          'diagnos',
          'medical',
          'rekam',
          'mrn',
        ]) {
          expect(
            columns.where((column) => column.contains(needle)),
            isEmpty,
            reason: '$table memuat kolom bernuansa data pasien: $needle.',
          );
        }
      }
    });

    test('movement note hanya berisi catatan stok', () async {
      final id = await draftOf(fixture.nurse);
      await context.updateConsumptionHeader.call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
        note: 'shift pagi',
      );
      await addConsumptionPosition(
        context,
        fixture,
        consumptionId: id,
        itemId: fixture.plainItem.id,
        qty: '1',
        nowUtc: nowUtc,
        note: 'kemasan rusak',
      );
      await context.postConsumption().call(
        actorUserId: fixture.nurse.id,
        consumptionId: id,
      );

      // Composed from the two note columns and nothing else — there is no third source a
      // patient identifier could arrive from.
      final movements = await context.consumptionMovements(id);
      expect(movements.single['note'], 'shift pagi · kemasan rusak');
    });
  });
}

/// Asserts that a refused screen leaked nothing about the document (§43).
///
/// Not merely "the denied message is shown": the number, the room, the item, the SKU, the
/// batch, the quantity and the note must all be absent from the widget tree, because a
/// guard that fetched the document and then hid it would pass a weaker assertion.
Future<void> _expectNoDocumentContent(
  WidgetTester tester,
  TestContext context,
  String consumptionId,
  ConsumptionFixture fixture,
) async {
  final docNumber = await context.consumptionColumn(
    consumptionId,
    'doc_number',
  );
  expect(find.textContaining(docNumber!), findsNothing);
  expect(find.textContaining(fixture.roomOne.name), findsNothing);
  expect(find.textContaining(fixture.roomOne.code), findsNothing);
  expect(find.textContaining(fixture.expiryItem.name), findsNothing);
  expect(find.textContaining(fixture.expiryItem.sku), findsNothing);
  expect(find.textContaining(fixture.validBatch.batchNo), findsNothing);
  expect(find.textContaining('1.5'), findsNothing);
  expect(find.textContaining('2.5'), findsNothing);
  expect(find.textContaining('Draft'), findsNothing);
  expect(find.textContaining(fixture.otherNurse.fullName), findsNothing);
  expect(find.textContaining(fixture.nurse.fullName), findsNothing);
}
