import 'package:flutter/services.dart';

/// [TextInputFormatter] that upper-cases all entered text.
///
/// Used by the category form's code-prefix field to enforce uppercase
/// letter input.
///
/// Extracted from `category_form.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}