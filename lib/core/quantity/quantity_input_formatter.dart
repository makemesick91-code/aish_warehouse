import 'package:flutter/services.dart';

import 'quantity.dart';

/// Validation messages shown next to a quantity input (spec Q-8).
abstract final class QuantityMessages {
  static const String invalid = 'Masukkan jumlah yang valid.';
  static const String mustBePositive = 'Jumlah harus lebih dari 0.';
  static const String tooManyDecimals = 'Maksimal 3 angka di belakang koma.';
}

/// Keeps a quantity field typeable while blocking anything that could never
/// become a valid quantity.
///
/// Accepts both separators (`0.5` and `0,5`) and, importantly, accepts the
/// half-finished states `0.` and `0,` — rejecting those would make it
/// impossible to type a decimal at all. Digits beyond
/// [Quantity.decimalDigits] are refused so the user cannot enter a precision
/// the ledger does not store; the final check still runs on submit or blur.
class QuantityInputFormatter extends TextInputFormatter {
  const QuantityInputFormatter();

  static final RegExp _typeable = RegExp(r'^\d*[.,]?\d{0,3}$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    return _typeable.hasMatch(newValue.text) ? newValue : oldValue;
  }
}

/// Validates a raw quantity input, returning `null` when it is acceptable and
/// an Indonesian message otherwise.
///
/// Set [allowZero] for fields where zero is a legitimate answer — a physical
/// count of nothing is valid, a shipment of nothing is not.
String? validateQuantityInput(String? raw, {bool allowZero = false}) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return QuantityMessages.invalid;

  final Quantity value;
  try {
    value = Quantity.parse(text);
  } on QuantityFormatException catch (error) {
    return switch (error.reason) {
      QuantityFormatReason.tooManyDecimals => QuantityMessages.tooManyDecimals,
      QuantityFormatReason.negative => QuantityMessages.mustBePositive,
      QuantityFormatReason.empty ||
      QuantityFormatReason.notANumber => QuantityMessages.invalid,
    };
  }

  if (value.isNegative) return QuantityMessages.mustBePositive;
  if (!allowZero && value.isZero) return QuantityMessages.mustBePositive;
  return null;
}
