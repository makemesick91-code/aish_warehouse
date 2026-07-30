import 'package:aish_warehouse/core/errors/failures.dart';
import 'package:aish_warehouse/core/time/app_date_time_formatter.dart';
import 'package:aish_warehouse/core/time/app_time_zone.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_inspection.dart';
import '../helpers/test_context.dart';

/// Timestamp rules for a shipment (T-1 … T-7, §8).
///
/// Two things are checked, and they pull in opposite directions on purpose.
///
/// **Storage is UTC.** Every persisted instant is a UTC instant, and the ordering
/// between them is decided by `DocumentTimestampPolicy` on `DateTime`s — never by
/// SQL, because timestamps are ISO-8601 TEXT and `>=` on text compares characters
/// rather than moments.
///
/// **Display is GMT+8.** Nothing on the display path calls `toLocal()`, so what a
/// clinic sees does not depend on how the tablet's clock is configured.
///
/// A device whose clock is behind must not be able to stamp a shipment before the
/// document it belongs to existed — and when it is refused, the rollback has to take
/// the movements, the balances, the document and the request with it.
void main() {
  late TestContext context;
  late DeliveryFixture fixture;

  final nowUtc = DateTime.utc(2026, 7, 30, 3, 0);

  setUp(() async {
    context = TestContext.create(clock: () => nowUtc);
    fixture = await buildDeliveryFixture(context, nowUtc: nowUtc);
  });

  tearDown(() => context.dispose());

  group('penyimpanan UTC', () {
    test('created_at Surat Jalan adalah instan UTC', () async {
      final order = await context.createDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        purchaseRequestId: fixture.purchaseRequestId,
      );

      expect(order.createdAt.isUtc, isTrue);
      final stored = await context.deliveryOrderColumn(order.id, 'created_at');
      // Stored with a `Z` suffix, not an offset: an instant, not a wall clock.
      expect(stored, endsWith('Z'));
    });

    test(
      'shipped_at adalah instan UTC dan berpasangan dengan shipped_by',
      () async {
        final doId = await prepareDeliveryOrder(
          context,
          fixture,
          nowUtc: nowUtc,
          allocations: [simpleAllocation(fixture, qty: '1')],
        );
        final result = await context.shipDeliveryOrder().call(
          actorUserId: fixture.warehouseUser.id,
          deliveryOrderId: doId,
        );

        expect(result.order.shippedAt!.isUtc, isTrue);
        expect(result.order.shippedAt, nowUtc);
        expect(result.order.shippedBy, fixture.warehouseUser.id);
        expect(
          await context.deliveryOrderColumn(doId, 'shipped_at'),
          endsWith('Z'),
        );
        expect(
          await context.deliveryOrderColumn(doId, 'shipped_by'),
          fixture.warehouseUser.id,
        );
      },
    );

    test('movement mewarisi instan pengiriman yang sama', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );
      await context.shipDeliveryOrder().call(
        actorUserId: fixture.warehouseUser.id,
        deliveryOrderId: doId,
      );

      final movements = await context.inventory.movementsByRef(
        refDocType: 'DO',
        refDocId: doId,
      );
      expect(movements.single.createdAt.isUtc, isTrue);
    });

    test('waktu kirim sama dengan waktu buat diterima', () async {
      // Two transitions really can land on the same microsecond on a fast device,
      // and there is nothing wrong with that document. Only a genuinely earlier
      // instant is refused.
      final order = await context
          .createDeliveryOrder(clock: () => nowUtc)
          .call(
            actorUserId: fixture.warehouseUser.id,
            purchaseRequestId: fixture.purchaseRequestId,
          );
      await context.deliveries.replacePreparingLines(
        doId: order.id,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );

      await context
          .shipDeliveryOrder(clock: () => order.createdAt)
          .call(
            actorUserId: fixture.warehouseUser.id,
            deliveryOrderId: order.id,
          );
      expect(await context.deliveryOrderStatusOf(order.id), 'shipped');
    });
  });

  group('jam perangkat yang tertinggal', () {
    test('kirim sebelum dokumen dibuat ditolak', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );
      final behind = nowUtc.subtract(const Duration(hours: 2));

      await expectLater(
        () => context
            .shipDeliveryOrder(clock: () => behind)
            .call(actorUserId: fixture.warehouseUser.id, deliveryOrderId: doId),
        throwsA(
          isA<InvalidDocumentTimestampFailure>()
              .having((failure) => failure.laterLabel, 'label', 'shipped_at')
              .having(
                (failure) => failure.skew.isNegative,
                'skew positif',
                isFalse,
              ),
        ),
      );
    });

    test('kirim sebelum PR mulai diproses ditolak', () async {
      // The fixture's request was processed one hour before `nowUtc`. A shipment
      // stamped before that would claim the goods left before the warehouse took the
      // order on.
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc.subtract(const Duration(hours: 2)),
        allocations: [simpleAllocation(fixture, qty: '1')],
      );

      await expectLater(
        () => context
            .shipDeliveryOrder(
              clock: () => nowUtc.subtract(const Duration(minutes: 90)),
            )
            .call(actorUserId: fixture.warehouseUser.id, deliveryOrderId: doId),
        throwsA(
          isA<InvalidDocumentTimestampFailure>().having(
            (failure) => failure.earlierLabel,
            'label',
            'processing_at',
          ),
        ),
      );
    });

    test('penolakan jam membatalkan movement, saldo, DO dan PR', () async {
      final doId = await prepareDeliveryOrder(
        context,
        fixture,
        nowUtc: nowUtc,
        allocations: [simpleAllocation(fixture, qty: '1')],
      );
      final before = await context.balancesAt(fixture.warehouse.id);
      final behind = nowUtc.subtract(const Duration(hours: 2));

      await expectLater(
        () => context
            .shipDeliveryOrder(clock: () => behind)
            .call(actorUserId: fixture.warehouseUser.id, deliveryOrderId: doId),
        throwsA(isA<InvalidDocumentTimestampFailure>()),
      );

      // The clock check runs *after* the ledger posting, which is exactly why this
      // assertion matters: the movements were written and then rolled back.
      expect(await context.shipmentMovementCount(doId), 0);
      expect(await context.balancesAt(fixture.warehouse.id), before);
      expect(await context.deliveryOrderStatusOf(doId), 'preparing');
      expect(await context.deliveryOrderColumn(doId, 'shipped_at'), isNull);
      expect(await context.deliveryOrderColumn(doId, 'shipped_by'), isNull);
      expect(
        await context.purchaseRequestStatusOf(fixture.purchaseRequestId),
        'processing',
      );
    });
  });

  group('tampilan operasional', () {
    test('instan UTC ditampilkan dalam GMT+8', () {
      // 2026-07-30 03:00 UTC is 11:00 in operational time.
      expect(
        AppDateTimeFormatter.dateTimeWithZone(nowUtc),
        '30 Jul 2026, 11:00 GMT+8',
      );
      // And an instant late in the UTC day belongs to the *next* operational day.
      expect(
        AppDateTimeFormatter.date(DateTime.utc(2026, 7, 30, 17, 0)),
        '31 Jul 2026',
      );
      expect(
        AppTimeZone.operationalDate(DateTime.utc(2026, 7, 30, 17, 0)).day,
        31,
      );
    });

    test('tidak ada toLocal pada jalur Delivery Order', () {
      // T-4: `toLocal()` follows the device timezone, so a clinic tablet set to the
      // wrong zone would show — and, worse, *compute* — the wrong operational day.
      for (final file in [
        ...dartFilesUnder('lib/features/delivery'),
        'lib/core/db/daos/delivery_order_dao.dart',
        'lib/core/db/tables/delivery_tables.dart',
        'lib/app/guards/delivery_order_route_guard.dart',
      ]) {
        expect(
          readCodeOnly(file).contains('toLocal()'),
          isFalse,
          reason: '$file memakai toLocal(); gunakan AppTimeZone.',
        );
      }
    });

    test('tidak ada penyebaran offset delapan jam di luar AppTimeZone', () {
      // T-5: every conversion goes through the one utility. Scattering
      // `add(Duration(hours: 8))` is how two screens end up disagreeing about what
      // day it is.
      for (final file in dartFilesUnder('lib/features/delivery')) {
        expect(
          RegExp(r'Duration\(hours:\s*8\)').hasMatch(readCodeOnly(file)),
          isFalse,
          reason: '$file menyebarkan offset GMT+8 sendiri.',
        );
      }
    });

    test('tidak ada perbandingan timestamp leksikal di SQL', () {
      // Timestamps are ISO-8601 TEXT. `shipped_at >= created_at` in SQL compares
      // characters, so two instants written in different but equally valid forms
      // compare by their spelling — the defect schema v4 removed.
      for (final file in [
        'lib/core/db/daos/delivery_order_dao.dart',
        'lib/core/db/tables/delivery_tables.dart',
      ]) {
        final code = readCodeOnly(file);
        for (final pattern in [
          'shipped_at >=',
          'shipped_at >',
          'shipped_at <',
          '>= created_at',
          '>= processing_at',
        ]) {
          expect(
            code.contains(pattern),
            isFalse,
            reason: '$file membandingkan timestamp sebagai teks ($pattern).',
          );
        }
      }
    });

    test('use case tidak membaca jam sendiri di luar default', () {
      // Every clock is injected so a test can sit on the day a batch expires (T-7).
      // The one `DateTime.now()` each use case is allowed is its `_defaultClock`.
      for (final file in dartFilesUnder(
        'lib/features/delivery/domain/use_cases',
      )) {
        expect(
          RegExp(r'DateTime\.now\(\)').allMatches(readCodeOnly(file)).length,
          lessThanOrEqualTo(1),
          reason:
              '$file membaca jam lebih dari sekali; hanya _defaultClock yang '
              'boleh.',
        );
      }
    });
  });
}
