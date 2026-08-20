import '../../../data/models/enum_attribute.dart';
import 'enum_option_form_row.dart';

/// Per-attribute editor state. Mirrors the price-chip rows/list pattern
/// but for one enum attribute (e.g. `nhan_banh`).
///
/// Extracted from `product_form_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class EnumAttributeFormSection {
  EnumAttributeFormSection({
    required this.attribute,
    required List<EnumOption> originalOptions,
    required this.originalDefaultId,
  }) : _originalOptions = List<EnumOption>.of(originalOptions),
       rows = originalOptions
            .map(
              (opt) => EnumOptionFormRow(
                id: opt.id,
                valueVi: opt.valueVi,
                sortOrder: opt.sortOrder,
                active: opt.active,
                isDefault: opt.id == originalDefaultId,
              ),
            )
            .toList();

  factory EnumAttributeFormSection.fromAttribute(EnumAttribute attribute) {
    return EnumAttributeFormSection(
      attribute: attribute,
      originalOptions: attribute.options,
      originalDefaultId: attribute.defaultOptionId,
    );
  }

  final EnumAttribute attribute;
  final List<EnumOptionFormRow> rows;
  List<EnumOption> _originalOptions;
  int? originalDefaultId;
  String? _error;

  String? get error => _error;

  Map<int, EnumOption> get originalById => {
    for (final opt in _originalOptions) opt.id: opt,
  };

  bool clearError() {
    if (_error == null) return false;
    _error = null;
    return true;
  }

  bool setError(String? error) {
    if (_error == error) return false;
    _error = error;
    return true;
  }

  bool hasChanges() {
    final originalMap = originalById;
    final liveRows = rows.where((r) => !r.removed).toList();

    if (rows.any((r) => r.id != null && r.removed)) return true;
    if (rows.any((r) => r.id == null && !r.removed)) return true;
    if (liveRows.length != _originalOptions.length) return true;

    int? selectedDefaultId;
    for (final r in liveRows) {
      if (r.isDefault) {
        selectedDefaultId = r.id;
        break;
      }
    }
    if (selectedDefaultId != originalDefaultId) return true;

    for (var i = 0; i < liveRows.length; i++) {
      final row = liveRows[i];
      final original = originalMap[row.id];
      if (original == null) return true;
      if (original.valueVi != row.valueController.text.trim()) return true;
      if (_originalOptions[i].id != row.id) return true;
    }
    return false;
  }

  void applySaved() {
    rows.removeWhere((r) {
      if (r.removed) {
        r.dispose();
        return true;
      }
      return false;
    });
    _originalOptions = [
      for (var i = 0; i < rows.length; i++)
        EnumOption(
          id: rows[i].id ?? -1,
          valueVi: rows[i].valueController.text.trim(),
          sortOrder: i,
          active: rows[i].active,
          isDefault: rows[i].isDefault,
        ),
    ];
    for (var i = 0; i < rows.length; i++) {
      rows[i].sortOrder = i;
    }
  }

  void dispose() {
    for (final row in rows) {
      row.dispose();
    }
  }
}