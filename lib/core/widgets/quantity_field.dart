import 'package:flutter/material.dart';

import '../quantity/quantity.dart';
import '../quantity/quantity_input_formatter.dart';

/// The shared decimal quantity input (spec Q-8).
///
/// Every quantity the user types goes through this field: opname counts, PR
/// lines, shipped and received quantities. It accepts `0.5` and `0,5` alike,
/// limits the input to three decimals, and — deliberately — does not complain
/// while the user is mid-word. Validation runs when the field loses focus and
/// again when the surrounding [Form] is submitted.
class QuantityField extends StatefulWidget {
  const QuantityField({
    super.key,
    this.controller,
    this.focusNode,
    this.initialValue,
    required this.label,
    this.unit,
    this.helperText,
    this.allowZero = false,
    this.enabled = true,
    this.autofocus = false,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController? controller;

  /// Focus node owned by the caller.
  ///
  /// Supplied when something outside the field needs to *put the cursor here* — a
  /// form that scrolls to the first invalid line and then focuses it (§31.5). When
  /// omitted the field makes its own, exactly as before, and disposes it. Ownership
  /// follows the same rule as [controller]: whoever created it disposes it.
  final FocusNode? focusNode;

  /// Starting value, used only when [controller] is not supplied.
  final Quantity? initialValue;

  final String label;

  /// Item unit shown as a suffix (`box`, `botol`, `pcs`).
  final String? unit;

  final String? helperText;

  /// Whether zero passes validation. A physical count may be zero; a shipment
  /// may not.
  final bool allowZero;

  final bool enabled;
  final bool autofocus;
  final TextInputAction? textInputAction;

  /// Fires on every keystroke with the parsed value, or `null` while the text
  /// is not (yet) a valid quantity.
  final ValueChanged<Quantity?>? onChanged;

  final ValueChanged<Quantity?>? onSubmitted;

  @override
  State<QuantityField> createState() => _QuantityFieldState();
}

class _QuantityFieldState extends State<QuantityField> {
  final GlobalKey<FormFieldState<String>> _fieldKey =
      GlobalKey<FormFieldState<String>>();
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        TextEditingController(text: widget.initialValue?.format() ?? '');
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = (widget.focusNode ?? FocusNode())..addListener(_onFocusChange);
  }

  @override
  void dispose() {
    // The listener always comes off, whoever owns the node: leaving one attached to
    // a caller-owned node would fire `_onFocusChange` against a dead State.
    _focusNode.removeListener(_onFocusChange);
    if (_ownsFocusNode) _focusNode.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  /// Validating on blur keeps the error out of the way while typing but still
  /// reports it before the user moves on.
  void _onFocusChange() {
    if (!_focusNode.hasFocus) _fieldKey.currentState?.validate();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: _fieldKey,
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      textInputAction: widget.textInputAction,
      textAlign: TextAlign.end,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [QuantityInputFormatter()],
      autovalidateMode: AutovalidateMode.disabled,
      validator: (value) =>
          validateQuantityInput(value, allowZero: widget.allowZero),
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
        suffixText: widget.unit,
      ),
      onChanged: (value) => widget.onChanged?.call(Quantity.tryParse(value)),
      onFieldSubmitted: (value) =>
          widget.onSubmitted?.call(Quantity.tryParse(value)),
    );
  }
}
