import 'package:flutter/material.dart';

/// Mutable per-row state for an enum attribute option in the product form.
///
/// Extracted from `product_form_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class EnumOptionFormRow {
  EnumOptionFormRow({
    this.id,
    String valueVi = '',
    this.sortOrder = 0,
    this.active = 1,
    this.isDefault = false,
  }) : valueController = TextEditingController(text: valueVi);

  int? id;
  final TextEditingController valueController;
  int sortOrder;
  int active;
  bool isDefault;
  bool removed = false;
  String? _valueError;

  String? get valueError => _valueError;

  bool setValueError(String? error) {
    if (_valueError == error) return false;
    _valueError = error;
    return true;
  }

  void dispose() {
    valueController.dispose();
  }
}