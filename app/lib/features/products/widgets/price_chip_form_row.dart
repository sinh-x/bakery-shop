import 'package:flutter/material.dart';

/// Mutable per-row state for a price-chip entry in the product form.
///
/// Holds the controller pair and per-field error state so the parent
/// form can validate, reorder, and sync price-chip edits without
/// rebuilding the whole tree.
///
/// Extracted from `product_form_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class PriceChipFormRow {
  PriceChipFormRow({this.id, String label = '', String price = ''})
    : labelController = TextEditingController(text: label),
      priceController = TextEditingController(text: price);

  int? id;
  final TextEditingController labelController;
  final TextEditingController priceController;
  String? _labelError;
  String? _priceError;

  String? get labelError => _labelError;
  String? get priceError => _priceError;

  bool clearErrors() {
    if (_labelError == null && _priceError == null) {
      return false;
    }
    _labelError = null;
    _priceError = null;
    return true;
  }

  bool updateErrors({String? labelError, String? priceError}) {
    if (_labelError == labelError && _priceError == priceError) {
      return false;
    }
    _labelError = labelError;
    _priceError = priceError;
    return true;
  }

  void dispose() {
    labelController.dispose();
    priceController.dispose();
  }
}