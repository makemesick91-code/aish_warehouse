import 'package:aish_warehouse/core/quantity/quantity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parse', () {
    test('bilangan bulat', () {
      expect(Quantity.parse('1').milliUnits, 1000);
      expect(Quantity.parse('10').milliUnits, 10000);
      expect(Quantity.parse('0').milliUnits, 0);
    });

    test('satu angka desimal dengan titik', () {
      expect(Quantity.parse('0.5').milliUnits, 500);
    });

    test('satu angka desimal dengan koma', () {
      expect(Quantity.parse('0,5').milliUnits, 500);
    });

    test('dua angka desimal', () {
      expect(Quantity.parse('1.25').milliUnits, 1250);
      expect(Quantity.parse('1,25').milliUnits, 1250);
    });

    test('tiga angka desimal', () {
      expect(Quantity.parse('2.375').milliUnits, 2375);
    });

    test('spasi di sekitar angka diabaikan', () {
      expect(Quantity.parse('  1.5  ').milliUnits, 1500);
    });

    test('nol di belakang koma tidak mengubah nilai', () {
      expect(Quantity.parse('0.50'), Quantity.parse('0.5'));
      expect(Quantity.parse('1.000'), Quantity.fromWhole(1));
    });

    test('input kosong ditolak', () {
      expect(
        () => Quantity.parse(''),
        _throwsReason(QuantityFormatReason.empty),
      );
      expect(
        () => Quantity.parse('   '),
        _throwsReason(QuantityFormatReason.empty),
      );
    });

    test('input negatif ditolak', () {
      expect(
        () => Quantity.parse('-1'),
        _throwsReason(QuantityFormatReason.negative),
      );
      expect(
        () => Quantity.parse('-0.5'),
        _throwsReason(QuantityFormatReason.negative),
      );
    });

    test('lebih dari tiga angka desimal ditolak tanpa pembulatan', () {
      expect(
        () => Quantity.parse('0.0001'),
        _throwsReason(QuantityFormatReason.tooManyDecimals),
      );
      expect(
        () => Quantity.parse('1.2345'),
        _throwsReason(QuantityFormatReason.tooManyDecimals),
      );
    });

    test('bukan angka ditolak', () {
      for (final input in ['abc', 'NaN', 'Infinity', '1.2.3', '1.', '1 000']) {
        expect(
          () => Quantity.parse(input),
          _throwsReason(QuantityFormatReason.notANumber),
          reason: '"$input" harus ditolak',
        );
      }
    });

    test('tryParse mengembalikan null tanpa melempar', () {
      expect(Quantity.tryParse('abc'), isNull);
      expect(Quantity.tryParse('1.2345'), isNull);
      expect(Quantity.tryParse('0,5'), Quantity.fromMilliUnits(500));
    });
  });

  group('format', () {
    test('menghapus nol yang tidak diperlukan', () {
      expect(const Quantity.fromMilliUnits(1000).format(), '1');
      expect(const Quantity.fromMilliUnits(500).format(), '0.5');
      expect(const Quantity.fromMilliUnits(1250).format(), '1.25');
      expect(const Quantity.fromMilliUnits(2375).format(), '2.375');
    });

    test('tidak menampilkan 0.500 atau 1.000', () {
      expect(const Quantity.fromMilliUnits(500).format(), isNot('0.500'));
      expect(const Quantity.fromMilliUnits(1000).format(), isNot('1.000'));
    });

    test('nol dan nilai negatif', () {
      expect(Quantity.zero().format(), '0');
      expect(const Quantity.fromMilliUnits(-1500).format(), '-1.5');
    });

    test('menyertakan satuan barang', () {
      expect(
        const Quantity.fromMilliUnits(500).formatWithUnit('box'),
        '0.5 box',
      );
      expect(
        const Quantity.fromMilliUnits(10000).formatWithUnit('pcs'),
        '10 pcs',
      );
      expect(
        const Quantity.fromMilliUnits(1250).formatWithUnit('botol'),
        '1.25 botol',
      );
      expect(const Quantity.fromMilliUnits(1000).formatWithUnit('  '), '1');
    });

    test('nilai milli-unit tidak pernah muncul pada hasil format', () {
      expect(Quantity.parse('0.5').format(), isNot(contains('500')));
    });
  });

  group('aritmatika tepat', () {
    test('0.1 + 0.2 menghasilkan tepat 0.3', () {
      final sum = Quantity.parse('0.1') + Quantity.parse('0.2');

      expect(sum, Quantity.parse('0.3'));
      expect(sum.milliUnits, 300);
      expect(sum.format(), '0.3');
    });

    test('1.5 - 0.5 menghasilkan tepat 1', () {
      final result = Quantity.parse('1.5') - Quantity.parse('0.5');

      expect(result, Quantity.fromWhole(1));
      expect(result.format(), '1');
    });

    test('pengurangan boleh menghasilkan nilai negatif', () {
      final difference = Quantity.parse('0.5') - Quantity.parse('2');

      expect(difference.isNegative, isTrue);
      expect(difference.format(), '-1.5');
      expect(difference.absolute, Quantity.parse('1.5'));
    });

    test('negasi membalik tanda', () {
      expect(-Quantity.parse('1.25'), const Quantity.fromMilliUnits(-1250));
      expect(-Quantity.zero(), Quantity.zero());
    });

    test('penjumlahan berulang tidak menumpuk galat', () {
      var total = Quantity.zero();
      for (var i = 0; i < 10; i++) {
        total += Quantity.parse('0.1');
      }

      expect(total, Quantity.fromWhole(1));
      expect(total.format(), '1');
    });

    test('sum menjumlahkan koleksi', () {
      expect(
        Quantity.sum([
          Quantity.parse('0.5'),
          Quantity.parse('0.25'),
          Quantity.parse('0.25'),
        ]),
        Quantity.fromWhole(1),
      );
      expect(Quantity.sum(const <Quantity>[]), Quantity.zero());
    });

    test('min memilih nilai terkecil', () {
      expect(
        Quantity.min(Quantity.parse('1.5'), Quantity.parse('0.5')),
        Quantity.parse('0.5'),
      );
    });
  });

  group('perbandingan', () {
    test('operator perbandingan bekerja', () {
      final half = Quantity.parse('0.5');
      final one = Quantity.fromWhole(1);

      expect(half < one, isTrue);
      expect(half <= half, isTrue);
      expect(one > half, isTrue);
      expect(one >= one, isTrue);
      expect(half > one, isFalse);
    });

    test('compareTo mengurutkan menaik', () {
      final values = [
        Quantity.parse('2.375'),
        Quantity.parse('0.5'),
        Quantity.fromWhole(1),
      ]..sort();

      expect(values.map((q) => q.format()).toList(), ['0.5', '1', '2.375']);
    });

    test('predikat tanda', () {
      expect(Quantity.zero().isZero, isTrue);
      expect(Quantity.parse('0.001').isPositive, isTrue);
      expect(const Quantity.fromMilliUnits(-1).isNegative, isTrue);
      expect(Quantity.zero().isPositive, isFalse);
    });
  });

  group('equality dan hashCode', () {
    test('nilai yang sama dianggap sama', () {
      expect(Quantity.parse('0,5'), Quantity.parse('0.5'));
      expect(Quantity.fromWhole(2), const Quantity.fromMilliUnits(2000));
    });

    test('hashCode konsisten dengan equality', () {
      expect(Quantity.parse('1.25').hashCode, Quantity.parse('1,25').hashCode);
      expect({Quantity.parse('0.5'), Quantity.parse('0,5')}, hasLength(1));
    });

    test('nilai berbeda tidak sama', () {
      expect(Quantity.parse('0.5'), isNot(Quantity.parse('0.6')));
    });
  });

  test('skala penyimpanan adalah 1000', () {
    expect(Quantity.scale, 1000);
    expect(Quantity.decimalDigits, 3);
    expect(Quantity.fromWhole(1).milliUnits, 1000);
  });
}

Matcher _throwsReason(QuantityFormatReason reason) => throwsA(
  isA<QuantityFormatException>().having((e) => e.reason, 'reason', reason),
);
