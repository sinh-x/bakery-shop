import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/phone_formatter.dart';

/// Shared phone-number text field used by every phone edit location in the
/// app (DG-251 Phase 1).
///
/// Combines the phone keyboard, [PhoneInputFormatter] (dash grouping), and a
/// 20-character [LengthLimitingTextInputFormatter] so all phone inputs behave
/// identically. The visible label is supplied per-screen via [labelText] to
/// honor the VN label policy (no inline strings here).
///
/// Callers that need extra [InputDecoration] tweaks (e.g. hint text) pass
/// them via [decorationExtras]; values supplied there win over the defaults
/// via [InputDecoration.copyWith].
class PhoneTextField extends StatelessWidget {
  const PhoneTextField({
    super.key,
    required this.controller,
    required this.labelText,
    this.textInputAction,
    this.validator,
    this.decorationExtras,
    this.focusNode,
    this.onEditingComplete,
    this.onFieldSubmitted,
    this.enabled,
  });

  /// Owns the phone text. Callers retain ownership and must dispose it.
  final TextEditingController controller;

  /// Per-screen VN label (e.g. [VN.customerPhone], [OrdersLabels.deliveryPhone],
  /// [VN.customerPhoneField]).
  final String labelText;

  /// Optional keyboard action (e.g. [TextInputAction.next] for customer-form
  /// rows).
  final TextInputAction? textInputAction;

  /// Optional validator forwarded to the underlying [TextFormField].
  final String? Function(String?)? validator;

  /// Extra [InputDecoration] fields merged on top of the default decoration.
  /// Caller-supplied values override defaults via [InputDecoration.copyWith].
  final InputDecoration? decorationExtras;

  /// Optional focus node for advanced focus handling.
  final FocusNode? focusNode;

  /// See [TextFormField.onEditingComplete].
  final VoidCallback? onEditingComplete;

  /// See [TextFormField.onFieldSubmitted].
  final ValueChanged<String>? onFieldSubmitted;

  /// See [TextFormField.enabled].
  final bool? enabled;

  @override
  Widget build(BuildContext context) {
    // Start from the caller's decoration (when supplied) and fill in our
    // defaults only where the caller did not provide a value. This preserves
    // every field the caller set (e.g. counterText, fillColor, contentPadding)
    // instead of silently dropping the ones not listed in the old manual
    // copyWith whitelist.
    final decoration = decorationExtras == null
        ? InputDecoration(
            labelText: labelText,
            border: const OutlineInputBorder(),
          )
        : decorationExtras!.copyWith(
            labelText: decorationExtras!.labelText ?? labelText,
            border:
                decorationExtras!.border ?? const OutlineInputBorder(),
          );

    return TextFormField(
      controller: controller,
      decoration: decoration,
      keyboardType: TextInputType.phone,
      textInputAction: textInputAction,
      validator: validator,
      focusNode: focusNode,
      onEditingComplete: onEditingComplete,
      onFieldSubmitted: onFieldSubmitted,
      enabled: enabled,
      inputFormatters: [
        PhoneInputFormatter(),
        LengthLimitingTextInputFormatter(20),
      ],
    );
  }
}
