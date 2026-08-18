/// Validation errors snapshot for a single price-chip form row.
///
/// Extracted from `product_form_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class PriceChipValidationErrors {
  const PriceChipValidationErrors({this.labelError, this.priceError});

  final String? labelError;
  final String? priceError;

  bool get hasError => labelError != null || priceError != null;
}