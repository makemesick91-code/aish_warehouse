import 'package:aish_warehouse/core/quantity/quantity_input_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs [text] through the formatter as if it had just been typed and returns
/// what the field would end up showing.
String typed(String previous, String text) {
  const formatter = QuantityInputFormatter();
  return formatter
      .formatEditUpdate(
        TextEditingValue(
          text: previous,
          selection: TextSelection.collapsed(offset: previous.length),
        ),
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      )
      .text;
}

void main() {
  group('formatter input', () {
    test('menerima angka bulat dan desimal', () {
      expect(typed('', '1'), '1');
      expect(typed('0', '0.5'), '0.5');
      expect(typed('0', '0,5'), '0,5');
      expect(typed('1.2', '1.25'), '1.25');
      expect(typed('2.37', '2.375'), '2.375');
    });

    test('tidak menghalangi ketikan antara "0." dan "0,"', () {
      expect(typed('0', '0.'), '0.');
      expect(typed('0', '0,'), '0,');
    });

    test('membatasi tiga angka di belakang koma', () {
      expect(typed('2.375', '2.3751'), '2.375');
    });

    test('menolak tanda minus dan huruf', () {
      expect(typed('', '-'), '');
      expect(typed('1', '1a'), '1');
      expect(typed('', 'abc'), '');
    });

    test('mengizinkan pengosongan field', () {
      expect(typed('1.5', ''), '');
    });
  });

  group('validasi saat submit atau kehilangan fokus', () {
    test('nilai valid tidak menghasilkan pesan', () {
      expect(validateQuantityInput('1'), isNull);
      expect(validateQuantityInput('0.5'), isNull);
      expect(validateQuantityInput('0,5'), isNull);
      expect(validateQuantityInput('2.375'), isNull);
    });

    test('kosong meminta jumlah yang valid', () {
      expect(validateQuantityInput(''), QuantityMessages.invalid);
      expect(validateQuantityInput(null), QuantityMessages.invalid);
      expect(validateQuantityInput('0.'), QuantityMessages.invalid);
    });

    test('nol ditolak kecuali diizinkan', () {
      expect(validateQuantityInput('0'), QuantityMessages.mustBePositive);
      expect(validateQuantityInput('0', allowZero: true), isNull);
    });

    test('negatif meminta jumlah lebih dari nol', () {
      expect(validateQuantityInput('-1'), QuantityMessages.mustBePositive);
    });

    test('lebih dari tiga desimal memberi pesan khusus', () {
      expect(validateQuantityInput('1.2345'), QuantityMessages.tooManyDecimals);
      expect(validateQuantityInput('0.0001'), QuantityMessages.tooManyDecimals);
    });

    test('pesan memakai Bahasa Indonesia', () {
      expect(QuantityMessages.invalid, 'Masukkan jumlah yang valid.');
      expect(QuantityMessages.mustBePositive, 'Jumlah harus lebih dari 0.');
      expect(
        QuantityMessages.tooManyDecimals,
        'Maksimal 3 angka di belakang koma.',
      );
    });
  });
}
