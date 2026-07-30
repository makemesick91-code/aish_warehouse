import 'package:aish_warehouse/core/time/app_date_time_formatter.dart';
import 'package:aish_warehouse/features/good_receipt/domain/models/good_receipt_models.dart';
import 'package:aish_warehouse/features/good_receipt/domain/services/good_receipt_reminder_builder.dart';
import 'package:aish_warehouse/features/good_receipt/domain/services/good_receipt_reminder_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_inspection.dart';
import '../helpers/test_context.dart';

/// G-G6 — *"GR harus di-posting maksimal 2×24 jam setelah DO diterima (pengingat
/// otomatis)"* (§46).
///
/// The deadline is anchored to `delivery_orders.shipped_at`, which stands in as a proxy
/// for physical arrival: spec §2.3 gives the schema no arrival timestamp, and the
/// substitution can only make the deadline *earlier* than the letter of the rule, never
/// later. When an arrival event exists, only `GoodReceiptReminderPolicy.deadlineFor`
/// changes.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = fixedWednesdayUtc();

  /// The fixture is built ten days before "now", so a shipment can be *aged* without
  /// predating the Purchase Request it belongs to — which the timestamp policy refuses
  /// (§36), correctly. Ten days is comfortably more than the longest age these tests
  /// use.
  final fixtureUtc = nowUtc.subtract(const Duration(days: 10));

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: fixtureUtc);
  });

  tearDown(() => context.dispose());

  /// A shipment sent [age] before [nowUtc].
  ///
  /// The whole document is stamped at the same backdated instant, because the timestamp
  /// policy refuses a shipment that predates its own creation (§36) — and the fixture's
  /// Purchase Request is anchored an hour before `nowUtc`, so anything older than that
  /// would fail against `processing_at` instead.
  Future<String> shipmentAged(Duration age, {String qty = '0.5'}) {
    final shippedAt = nowUtc.subtract(age);
    return shipDeliveryOrderFor(
      context,
      fixture,
      nowUtc: shippedAt,
      shippedAtUtc: shippedAt,
      allocations: [simpleAllocation(fixture, qty: qty)],
    );
  }

  group('kebijakan tenggat', () {
    final shippedAt = DateTime.utc(2026, 7, 29, 3);

    test('tenggat adalah 48 jam setelah pengiriman', () {
      expect(GoodReceiptReminderPolicy.deadline, const Duration(hours: 48));
      expect(
        GoodReceiptReminderPolicy.deadlineFor(shippedAt),
        DateTime.utc(2026, 7, 31, 3),
      );
    });

    test('belum 48 jam bukan overdue', () {
      expect(
        GoodReceiptReminderPolicy.isOverdue(
          shippedAtUtc: shippedAt,
          nowUtc: shippedAt.add(const Duration(hours: 47, minutes: 59)),
        ),
        isFalse,
      );
    });

    test('tepat 48 jam belum overdue', () {
      // The rule is "within 2×24 hours", so the boundary instant is still inside it.
      // Comparing the other way round would report every shipment late one instant
      // early — the kind of off-by-one that erodes trust in the badge.
      expect(
        GoodReceiptReminderPolicy.isOverdue(
          shippedAtUtc: shippedAt,
          nowUtc: shippedAt.add(const Duration(hours: 48)),
        ),
        isFalse,
      );
      expect(
        GoodReceiptReminderPolicy.stageFor(
          shippedAtUtc: shippedAt,
          nowUtc: shippedAt.add(const Duration(hours: 48)),
        ),
        GoodReceiptReminderStage.dueSoon,
      );
    });

    test('satu mikrodetik setelah 48 jam sudah overdue', () {
      expect(
        GoodReceiptReminderPolicy.isOverdue(
          shippedAtUtc: shippedAt,
          nowUtc: shippedAt.add(const Duration(hours: 48, microseconds: 1)),
        ),
        isTrue,
      );
    });

    test('tiga tahap dinilai dari sisa waktu', () {
      GoodReceiptReminderStage stageAfter(Duration elapsed) =>
          GoodReceiptReminderPolicy.stageFor(
            shippedAtUtc: shippedAt,
            nowUtc: shippedAt.add(elapsed),
          );

      expect(
        stageAfter(const Duration(hours: 1)),
        GoodReceiptReminderStage.due,
      );
      expect(
        stageAfter(const Duration(hours: 35, minutes: 59)),
        GoodReceiptReminderStage.due,
      );
      // 12 hours left is the window's edge, and it counts as due soon.
      expect(
        stageAfter(const Duration(hours: 36)),
        GoodReceiptReminderStage.dueSoon,
      );
      expect(
        stageAfter(const Duration(hours: 49)),
        GoodReceiptReminderStage.overdue,
      );
    });

    test('jam terlambat dihitung terpotong dan tidak negatif', () {
      expect(
        GoodReceiptReminderPolicy.hoursLate(
          shippedAtUtc: shippedAt,
          nowUtc: shippedAt.add(const Duration(hours: 51, minutes: 59)),
        ),
        3,
      );
      expect(
        GoodReceiptReminderPolicy.hoursLate(
          shippedAtUtc: shippedAt,
          nowUtc: shippedAt.add(const Duration(hours: 10)),
        ),
        0,
      );
    });

    test('umur pengiriman dihitung dalam jam penuh', () {
      expect(
        GoodReceiptReminderPolicy.ageInHours(
          shippedAtUtc: shippedAt,
          nowUtc: shippedAt.add(const Duration(hours: 25, minutes: 30)),
        ),
        25,
      );
    });

    test('urutan prioritas menempatkan overdue lebih dulu', () {
      expect(
        GoodReceiptReminderStage.overdue.priority,
        lessThan(GoodReceiptReminderStage.dueSoon.priority),
      );
      expect(
        GoodReceiptReminderStage.dueSoon.priority,
        lessThan(GoodReceiptReminderStage.due.priority),
      );
    });
  });

  group('antrean pengingat cabang', () {
    test('Surat Jalan tanpa GR masuk antrean', () async {
      final doId = await shipmentAged(const Duration(hours: 5));

      final awaiting = await context.receipts.awaitingDeliveryOrders(
        branchId: fixture.branch.id,
      );

      expect(awaiting, hasLength(1));
      expect(awaiting.single.doId, doId);
      expect(awaiting.single.hasReceipt, isFalse);
      expect(awaiting.single.lineCount, 1);
      expect(awaiting.single.decidedCount, 0);
    });

    test('GR checking tetap di antrean dengan progres', () async {
      final doId = await shipmentAged(const Duration(hours: 5));
      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );

      final awaiting = await context.receipts.awaitingDeliveryOrders(
        branchId: fixture.branch.id,
      );

      expect(awaiting, hasLength(1));
      expect(awaiting.single.hasReceipt, isTrue);
      expect(awaiting.single.receiptId, grId);
      expect(awaiting.single.decidedCount, 1);
    });

    test('GR posted hilang dari antrean', () async {
      final doId = await shipmentAged(const Duration(hours: 5));
      final grId = await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );
      await checkEveryGoodReceiptLine(
        context,
        fixture,
        grId: grId,
        nowUtc: nowUtc,
      );
      await context.postGoodReceipt().call(
        actorUserId: fixture.branchHead.id,
        goodReceiptId: grId,
      );

      // Posting moves the shipment to `received`, and the queue asks for `shipped`.
      expect(
        await context.receipts.awaitingDeliveryOrders(
          branchId: fixture.branch.id,
        ),
        isEmpty,
      );
    });

    test('Surat Jalan preparing tidak masuk antrean', () async {
      await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '0.5')],
      );

      expect(
        await context.receipts.awaitingDeliveryOrders(
          branchId: fixture.branch.id,
        ),
        isEmpty,
      );
    });

    test('cabang lain tidak melihat antrean cabang ini', () async {
      await shipmentAged(const Duration(hours: 5));

      expect(
        await context.receipts.awaitingDeliveryOrders(
          branchId: fixture.otherBranch.id,
        ),
        isEmpty,
      );
    });

    test('Warehouse melihat antrean lintas cabang', () async {
      final doId = await shipmentAged(const Duration(hours: 5));

      // `branchId: null` widens the queue to every branch, which is how the warehouse
      // sees who is late (spec §4.2).
      final all = await context.receipts.awaitingDeliveryOrders();

      expect(all.map((row) => row.doId), contains(doId));
    });
  });

  group('pembangun pengingat', () {
    test('tahap dan jam terlambat diselesaikan dari satu instan', () async {
      await shipmentAged(const Duration(hours: 60));

      final reminders = GoodReceiptReminderBuilder.build(
        awaiting: await context.receipts.awaitingDeliveryOrders(
          branchId: fixture.branch.id,
        ),
        nowUtc: nowUtc,
      );

      expect(reminders, hasLength(1));
      expect(reminders.single.stage, GoodReceiptReminderStage.overdue);
      expect(reminders.single.isOverdue, isTrue);
      expect(reminders.single.hoursLate, 12);
      expect(
        reminders.single.deadlineUtc,
        nowUtc.subtract(const Duration(hours: 12)),
      );
    });

    test('belum 48 jam tidak ditandai overdue', () async {
      await shipmentAged(const Duration(hours: 10));

      final reminders = GoodReceiptReminderBuilder.build(
        awaiting: await context.receipts.awaitingDeliveryOrders(
          branchId: fixture.branch.id,
        ),
        nowUtc: nowUtc,
      );

      expect(reminders.single.stage, GoodReceiptReminderStage.due);
      expect(reminders.single.isOverdue, isFalse);
      expect(reminders.single.hoursLate, 0);
    });

    test('urutan overdue lebih dulu, lalu due soon, lalu terlama', () {
      GoodReceiptReminder reminder(String id, Duration age) {
        final shippedAt = nowUtc.subtract(age);
        return GoodReceiptReminder(
          doId: id,
          doDocNumber: 'TMP-DO-$id',
          prDocNumber: 'TMP-PR-1',
          branchId: fixture.branch.id,
          branchCode: fixture.branch.code,
          branchName: fixture.branch.name,
          shippedAtUtc: shippedAt,
          deadlineUtc: GoodReceiptReminderPolicy.deadlineFor(shippedAt),
          stage: GoodReceiptReminderPolicy.stageFor(
            shippedAtUtc: shippedAt,
            nowUtc: nowUtc,
          ),
          hoursLate: GoodReceiptReminderPolicy.hoursLate(
            shippedAtUtc: shippedAt,
            nowUtc: nowUtc,
          ),
          lineCount: 1,
          decidedCount: 0,
        );
      }

      final ordered = GoodReceiptReminderBuilder.sorted([
        reminder('due-new', const Duration(hours: 1)),
        reminder('overdue-new', const Duration(hours: 50)),
        reminder('due-soon', const Duration(hours: 40)),
        reminder('overdue-old', const Duration(hours: 90)),
        reminder('due-old', const Duration(hours: 20)),
      ]);

      expect(ordered.map((row) => row.doId), [
        // Both overdue rows first, oldest shipment of the two leading.
        'overdue-old',
        'overdue-new',
        'due-soon',
        'due-old',
        'due-new',
      ]);
    });

    test('hanya overdue dan due soon dianggap mendesak', () async {
      final overdue = await shipmentAged(const Duration(hours: 60));
      final dueSoon = await shipmentAged(const Duration(hours: 40));
      await shipmentAged(const Duration(hours: 2));

      final urgent = GoodReceiptReminderBuilder.urgentOnly(
        GoodReceiptReminderBuilder.build(
          awaiting: await context.receipts.awaitingDeliveryOrders(
            branchId: fixture.branch.id,
          ),
          nowUtc: nowUtc,
        ),
      );

      expect(urgent.map((row) => row.doId), [overdue, dueSoon]);
    });

    test('pengingat membawa jumlah baris yang belum diputuskan', () async {
      final doId = await shipmentAged(const Duration(hours: 60));
      await startGoodReceiptFor(
        context,
        fixture,
        deliveryOrderId: doId,
        nowUtc: nowUtc,
      );

      final reminders = GoodReceiptReminderBuilder.build(
        awaiting: await context.receipts.awaitingDeliveryOrders(
          branchId: fixture.branch.id,
        ),
        nowUtc: nowUtc,
      );

      expect(reminders.single.hasReceipt, isTrue);
      expect(reminders.single.pendingCount, 1);
    });
  });

  group('tampilan dan jam', () {
    test('tenggat ditampilkan dalam GMT+8', () {
      final shippedAt = DateTime.utc(2026, 7, 29, 3);
      final deadline = GoodReceiptReminderPolicy.deadlineFor(shippedAt);

      // 2026-07-31T03:00Z is 11:00 on 31 Jul in operational time. `toLocal()` is never
      // called, so this is the same on every device (T-2/T-4).
      expect(
        AppDateTimeFormatter.dateTimeWithZone(deadline),
        '31 Jul 2026, 11:00 GMT+8',
      );
    });

    test(
      'ringkasan GR menandai overdue hanya selama belum diposting',
      () async {
        final doId = await shipmentAged(const Duration(hours: 60));
        final grId = await startGoodReceiptFor(
          context,
          fixture,
          deliveryOrderId: doId,
          nowUtc: nowUtc,
        );

        var detail = await context.receipts.getDetail(grId);
        expect(detail!.summary.isOverdueOn(nowUtc), isTrue);
        expect(
          detail.summary.deadlineUtc,
          nowUtc.subtract(const Duration(hours: 12)),
        );

        await checkEveryGoodReceiptLine(
          context,
          fixture,
          grId: grId,
          nowUtc: nowUtc,
        );
        await context.postGoodReceipt().call(
          actorUserId: fixture.branchHead.id,
          goodReceiptId: grId,
        );

        // The work is done, so it is not late any more.
        detail = await context.receipts.getDetail(grId);
        expect(detail!.summary.isOverdueOn(nowUtc), isFalse);
      },
    );

    test('antrean menunggu diurutkan pengiriman terlama lebih dulu', () async {
      final oldest = await shipmentAged(const Duration(hours: 60));
      final newest = await shipmentAged(const Duration(hours: 2));

      final awaiting = await context.receipts.awaitingDeliveryOrders(
        branchId: fixture.branch.id,
      );

      expect(awaiting.map((row) => row.doId), [oldest, newest]);
    });
  });

  group('tanpa notifikasi platform', () {
    test('tidak ada paket notifikasi atau background task', () {
      // G-G6 asks for a reminder, and an in-app badge is one. A notification package
      // would be a platform dependency this milestone cannot test, and a permission
      // prompt nobody asked for.
      final pubspec = readLibrarySource('pubspec.yaml');
      for (final forbidden in [
        'flutter_local_notifications',
        'awesome_notifications',
        'workmanager',
        'android_alarm_manager',
        'firebase_messaging',
      ]) {
        expect(
          pubspec.contains(forbidden),
          isFalse,
          reason: 'pubspec.yaml menambahkan $forbidden.',
        );
      }
    });

    test('kebijakan pengingat tidak membaca jam sendiri', () {
      // Every method takes the instant as a parameter. That is what makes the badge on a
      // row, the count on the dashboard and the sort order agree (T-7).
      final code = readCodeOnly(
        'lib/features/good_receipt/domain/services/'
        'good_receipt_reminder_policy.dart',
      );
      expect(code, isNot(contains('DateTime.now')));
      expect(code, isNot(contains('toLocal')));
    });

    test('pembangun pengingat juga tidak membaca jam sendiri', () {
      final code = readCodeOnly(
        'lib/features/good_receipt/domain/services/'
        'good_receipt_reminder_builder.dart',
      );
      expect(code, isNot(contains('DateTime.now')));
      expect(code, isNot(contains('toLocal')));
    });
  });
}
