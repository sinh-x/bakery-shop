// DG-150 Phase 4 temporary exemption: screen coordinator remains above 300 lines while enum option persistence and photo workflow are preserved in-place; review in Phase 6 (2026-05-29).
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/api/api_client.dart';
import '../../data/api/product_service.dart';
import '../../data/models/catalog_photo.dart';
import '../../data/models/enum_attribute.dart';
import '../../data/models/price_chip.dart';
import '../../data/models/category.dart';
import '../../data/models/product.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/categories_provider.dart';
import '../../providers/products_provider.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'widgets/catalog_photo_viewer.dart';
import 'widgets/catalog_tag_chips.dart';
import 'widgets/catalog_tag_edit_sheet.dart';
import 'product_form/widgets/product_form_attributes_section.dart';
import 'product_form/widgets/product_form_basic_info_section.dart';
import 'product_form/widgets/product_form_catalog_integration_section.dart';
import 'product_form/widgets/product_form_pricing_section.dart';

/// Shared form for creating and editing products.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.product, this.initialCategory});

  /// If null, we're creating a new product; otherwise editing.
  final Product? product;

  /// Pre-selected category slug (e.g. from catalog tab).
  final String? initialCategory;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  static const int _maxPriceChips = 6;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _codeCtrl;
  late final List<PriceChip> _originalPriceChips;
  late final List<_PriceChipFormRow> _priceChipRows;
  late final List<_EnumAttributeFormSection> _enumSections;
  late String _category;
  late bool _rutTien;
  late bool _trungBay;
  late bool _tangKem;
  XFile? _pickedPhoto;
  bool _saving = false;

  bool get _isEditing => widget.product != null;

  /// Extracts the suffix part after the first '-' in a product code.
  /// E.g. "BKS-016" → "016", "BKS" → "BKS", "" → "".
  static String _extractSuffix(String? fullCode) {
    if (fullCode == null || fullCode.isEmpty || !fullCode.contains('-')) {
      return fullCode ?? '';
    }
    return fullCode.substring(fullCode.indexOf('-') + 1);
  }

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _priceCtrl = TextEditingController(
      text: p != null ? p.basePrice.toInt().toString() : '',
    );
    _costCtrl = TextEditingController(
      text: p != null && p.cost > 0 ? p.cost.toInt().toString() : '',
    );
    _notesCtrl = TextEditingController(text: p?.recipeNotes ?? '');
    _originalPriceChips = List<PriceChip>.of(
      p?.priceChips ?? const <PriceChip>[],
    );
    _priceChipRows = _originalPriceChips
        .map(
          (chip) => _PriceChipFormRow(
            id: chip.id,
            label: chip.label,
            price: chip.price.toInt().toString(),
          ),
        )
        .toList();
    _enumSections = (p?.enumAttributes ?? const <EnumAttribute>[])
        .map(_EnumAttributeFormSection.fromAttribute)
        .toList();
    // Store only the suffix portion so the prefix can be shown read-only.
    _codeCtrl = TextEditingController(text: _extractSuffix(p?.productCode));
    _category = widget.initialCategory ?? p?.category ?? 'banh_kem';
    _rutTien = p?.attributes['rut_tien']?.toString() == 'true';
    _trungBay = p?.attributes['trung_bay']?.toString() == 'true';
    _tangKem = p?.attributes['tang_kem']?.toString() == 'true';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _costCtrl.dispose();
    _notesCtrl.dispose();
    _codeCtrl.dispose();
    for (final row in _priceChipRows) {
      row.dispose();
    }
    for (final section in _enumSections) {
      section.dispose();
    }
    super.dispose();
  }

  void _addPriceChip() {
    if (_priceChipRows.length >= _maxPriceChips) return;
    setState(() {
      _priceChipRows.add(_PriceChipFormRow());
    });
  }

  Future<void> _removePriceChip(int index) async {
    final row = _priceChipRows[index];
    if (row.id != null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Xác nhận xóa mức giá nhanh'),
          content: const Text(
            'Bạn có chắc muốn xóa mức giá nhanh đã lưu này không?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(VN.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(VN.remove),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() {
      row.dispose();
      _priceChipRows.removeAt(index);
    });
  }

  void _reorderPriceChips(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      final row = _priceChipRows.removeAt(oldIndex);
      _priceChipRows.insert(newIndex, row);
    });
  }

  double? _parseChipPrice(String text) {
    final value = text.trim();
    if (value.isEmpty) return null;
    return double.tryParse(value);
  }

  Map<int, _PriceChipValidationErrors> _validatePriceChipRows() {
    final errors = <int, _PriceChipValidationErrors>{};

    for (var index = 0; index < _priceChipRows.length; index++) {
      final row = _priceChipRows[index];
      final label = row.labelController.text.trim();
      final priceText = row.priceController.text.trim();
      final parsedPrice = _parseChipPrice(priceText);

      final rowErrors = _PriceChipValidationErrors(
        labelError: label.isEmpty ? VN.priceChipLabelRequired : null,
        priceError: parsedPrice == null || parsedPrice < 0
            ? VN.priceChipPriceInvalid
            : null,
      );

      if (rowErrors.hasError) {
        errors[index] = rowErrors;
      }
    }

    final changed = _applyPriceChipRowErrors(errors);
    if (changed) setState(() {});
    return errors;
  }

  bool _applyPriceChipRowErrors(Map<int, _PriceChipValidationErrors> errors) {
    var changed = false;
    for (var index = 0; index < _priceChipRows.length; index++) {
      final row = _priceChipRows[index];
      final rowErrors = errors[index] ?? const _PriceChipValidationErrors();
      changed = row.clearErrors() || changed;
      changed =
          row.updateErrors(
            labelError: rowErrors.labelError,
            priceError: rowErrors.priceError,
          ) ||
          changed;
    }
    return changed;
  }

  bool _hasPriceChipChanges() {
    if (_priceChipRows.length > _maxPriceChips) return true;
    if (_priceChipRows.length != _originalPriceChips.length) return true;

    final originalMap = <int, PriceChip>{
      for (final chip in _originalPriceChips) chip.id: chip,
    };
    final seenIds = <int>{};

    for (var i = 0; i < _priceChipRows.length; i++) {
      final row = _priceChipRows[i];
      if (row.id == null) return true;
      final original = originalMap[row.id];
      if (original == null) return true;
      seenIds.add(row.id!);

      final label = row.labelController.text.trim();
      final parsedPrice = _parseChipPrice(row.priceController.text.trim());
      if (parsedPrice == null) return true;

      if (original.label != label ||
          original.price != parsedPrice ||
          original.position != i) {
        return true;
      }
    }

    return seenIds.length != _originalPriceChips.length;
  }

  Future<void> _syncPriceChipEdits(int productId) async {
    final productSvc = ref.read(productServiceProvider);
    final originalMap = <int, PriceChip>{
      for (final chip in _originalPriceChips) chip.id: chip,
    };
    final editedIds = <int>{};

    for (var i = 0; i < _priceChipRows.length; i++) {
      final row = _priceChipRows[i];
      final label = row.labelController.text.trim();
      final price = _parseChipPrice(row.priceController.text.trim()) ?? 0;

      if (row.id == null) {
        final created = await productSvc.createPriceChip(
          productId: productId,
          label: label,
          price: price,
          position: i,
        );
        row.id = created.id;
        continue;
      }

      editedIds.add(row.id!);
      final original = originalMap[row.id];
      if (original == null ||
          original.label != label ||
          original.price != price ||
          original.position != i) {
        await productSvc.updatePriceChip(
          productId,
          row.id!,
          label: original?.label != label ? label : null,
          price: original?.price != price ? price : null,
          position: original?.position != i ? i : null,
        );
      }
    }

    for (final original in _originalPriceChips) {
      if (original.id >= 0 && !editedIds.contains(original.id)) {
        await productSvc.deletePriceChip(productId, original.id);
      }
    }

    await ref.read(productsProvider.notifier).refresh();
    _applyPriceChipChangesToUi();
  }

  void _applyPriceChipChangesToUi() {
    _originalPriceChips
      ..clear()
      ..addAll(
        _priceChipRows.where((row) => row.id != null).map((row) {
          return PriceChip(
            id: row.id!,
            label: row.labelController.text.trim(),
            price: _parseChipPrice(row.priceController.text.trim()) ?? 0,
            position: _priceChipRows.indexOf(row),
          );
        }),
      );
  }

  Widget _buildPriceChipSection() {
    if (_priceChipRows.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(VN.priceChips, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _addPriceChip,
            icon: const Icon(Icons.add),
            label: const Text(VN.addPriceChip),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(VN.priceChips, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ReorderableListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: _priceChipRows.length,
          // ignore: deprecated_member_use
          onReorder: _reorderPriceChips,
          buildDefaultDragHandles: false,
          itemBuilder: (context, index) {
            final row = _priceChipRows[index];
            return Padding(
              key: ValueKey(row),
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: row.labelController,
                      decoration: InputDecoration(
                        labelText: VN.priceChipLabel,
                        errorText: row.labelError,
                      ),
                      onChanged: (_) {
                        if (row.labelError != null) {
                          setState(() {
                            row.updateErrors(
                              labelError: null,
                              priceError: row.priceError,
                            );
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: row.priceController,
                      decoration: InputDecoration(
                        labelText: VN.priceChipPrice,
                        suffixText: VN.currency,
                        errorText: row.priceError,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) {
                        if (row.priceError != null) {
                          setState(() {
                            row.updateErrors(
                              labelError: row.labelError,
                              priceError: null,
                            );
                          });
                        }
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: VN.remove,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _removePriceChip(index),
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _priceChipRows.length >= _maxPriceChips
              ? null
              : _addPriceChip,
          icon: const Icon(Icons.add),
          label: const Text(VN.addPriceChip),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ----- Enum attribute options editor (DG-092 Phase 4.5) -----

  void _addEnumOption(_EnumAttributeFormSection section) {
    setState(() {
      section.rows.add(_EnumOptionFormRow(sortOrder: section.rows.length));
    });
  }

  void _toggleRemoveEnumOption(_EnumAttributeFormSection section, int index) {
    final row = section.rows[index];
    setState(() {
      if (row.id == null) {
        row.dispose();
        section.rows.removeAt(index);
      } else {
        row.removed = !row.removed;
        if (row.removed && row.isDefault) {
          row.isDefault = false;
        }
      }
    });
  }

  void _setEnumDefault(_EnumAttributeFormSection section, int index) {
    setState(() {
      for (var i = 0; i < section.rows.length; i++) {
        section.rows[i].isDefault = i == index;
      }
    });
  }

  void _reorderEnumOptions(
    _EnumAttributeFormSection section,
    int oldIndex,
    int newIndex,
  ) {
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      final row = section.rows.removeAt(oldIndex);
      section.rows.insert(newIndex, row);
    });
  }

  /// Returns true if all enum sections validate (every section with at least
  /// one non-removed row must have exactly one default selected, and no row
  /// has an empty value). Reports per-row errors via setState.
  bool _validateEnumOptions() {
    var ok = true;
    var changed = false;
    for (final section in _enumSections) {
      var sectionChanged = section.clearError();
      var defaultCount = 0;
      var liveRowCount = 0;
      for (final row in section.rows) {
        final newError = !row.removed && row.valueController.text.trim().isEmpty
            ? VN.enumOptionValueRequired
            : null;
        sectionChanged = row.setValueError(newError) || sectionChanged;
        if (row.valueError != null) ok = false;
        if (!row.removed) {
          liveRowCount++;
          if (row.isDefault) defaultCount++;
        }
      }
      if (liveRowCount > 0 && defaultCount != 1) {
        sectionChanged =
            section.setError(VN.enumOptionDefaultRequired) || sectionChanged;
        ok = false;
      }
      changed = changed || sectionChanged;
    }
    if (changed) setState(() {});
    return ok;
  }

  bool _hasEnumOptionChanges() {
    for (final section in _enumSections) {
      if (section.hasChanges()) return true;
    }
    return false;
  }

  Future<void> _syncEnumOptionEdits() async {
    final productSvc = ref.read(productServiceProvider);
    for (final section in _enumSections) {
      if (!section.hasChanges()) continue;

      // 1. Deletions (rows that have an id and are flagged removed)
      for (final row in section.rows.where((r) => r.id != null && r.removed)) {
        await productSvc.deleteEnumOption(row.id!);
      }

      // 2. Updates (rows that have an id, not removed, with value/sort/active diff)
      final liveRows = section.rows.where((r) => !r.removed).toList();
      for (var i = 0; i < liveRows.length; i++) {
        final row = liveRows[i];
        if (row.id == null) continue;
        final original = section.originalById[row.id!];
        final newValue = row.valueController.text.trim();
        if (original == null) continue;
        final valueChanged = original.valueVi != newValue;
        final sortChanged = original.sortOrder != i;
        if (valueChanged || sortChanged) {
          await productSvc.updateEnumOption(
            row.id!,
            valueVi: valueChanged ? newValue : null,
            sortOrder: sortChanged ? i : null,
          );
        }
      }

      // 3. Inserts (rows without id, not removed)
      for (var i = 0; i < liveRows.length; i++) {
        final row = liveRows[i];
        if (row.id != null) continue;
        final newValue = row.valueController.text.trim();
        final created = await productSvc.createEnumOption(
          attributeType: section.attribute.attributeType,
          valueVi: newValue,
          sortOrder: i,
        );
        row.id = created.id;
      }

      // 4. Default change (after inserts so new-row defaults have ids)
      final defaultRow = liveRows.firstWhere(
        (r) => r.isDefault,
        orElse: () => liveRows.first,
      );
      if (defaultRow.id != null && defaultRow.id != section.originalDefaultId) {
        await productSvc.setEnumAttributeDefault(
          section.attribute.attributeType,
          defaultRow.id!.toString(),
        );
        section.originalDefaultId = defaultRow.id;
      }

      // 5. Reset baseline so subsequent saves don't replay history
      section.applySaved();
    }
  }

  Widget _buildEnumOptionsSection() {
    if (_enumSections.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          VN.enumOptionsSection,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          VN.enumOptionsHintAttributeWide,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final section in _enumSections) _buildEnumSection(section),
      ],
    );
  }

  Widget _buildEnumSection(_EnumAttributeFormSection section) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            section.attribute.labelVi,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (section.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              section.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ReorderableListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: section.rows.length,
          // ignore: deprecated_member_use
          onReorder: (oldIndex, newIndex) =>
              _reorderEnumOptions(section, oldIndex, newIndex),
          buildDefaultDragHandles: false,
          itemBuilder: (context, index) {
            final row = section.rows[index];
            return Padding(
              key: ValueKey(row),
              padding: const EdgeInsets.only(bottom: 8),
              child: Opacity(
                opacity: row.removed ? 0.5 : 1.0,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: VN.enumOptionDefaultLabel,
                      icon: Icon(
                        row.isDefault
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: row.isDefault
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      onPressed: row.removed
                          ? null
                          : () => _setEnumDefault(section, index),
                    ),
                    Expanded(
                      child: TextFormField(
                        controller: row.valueController,
                        enabled: !row.removed,
                        decoration: InputDecoration(
                          labelText: VN.enumOptionValueLabel,
                          errorText: row.valueError,
                          helperText: row.removed ? VN.enumOptionRemoved : null,
                        ),
                        onChanged: (_) {
                          if (row.valueError != null) {
                            setState(() => row.setValueError(null));
                          }
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: row.removed ? VN.enumOptionRestore : VN.remove,
                      icon: Icon(
                        row.removed ? Icons.restore : Icons.delete_outline,
                      ),
                      onPressed: () => _toggleRemoveEnumOption(section, index),
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _addEnumOption(section),
            icon: const Icon(Icons.add),
            label: const Text(VN.addEnumOption),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text(VN.takePhoto),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text(VN.fromGallery),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picker = ImagePicker();
    final file = await picker.pickImage(source: source);
    if (file != null) {
      setState(() => _pickedPhoto = file);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_validatePriceChipRows().isNotEmpty) return;
    if (!_validateEnumOptions()) return;
    setState(() => _saving = true);

    try {
      final notifier = ref.read(productsProvider.notifier);
      final price = double.tryParse(_priceCtrl.text) ?? 0;
      final cost = double.tryParse(_costCtrl.text) ?? 0;
      final hasPriceChipChanges = _hasPriceChipChanges();

      Product saved;
      // Build full product code: prefix (from category) + '-' + suffix (user input).
      final suffix = _codeCtrl.text.trim();
      final cats = ref.read(categoriesProvider).asData?.value;
      final prefix =
          cats
              ?.firstWhere(
                (c) => c.slug == _category,
                orElse: () => const Category(
                  id: 0,
                  slug: '',
                  name: '',
                  codePrefix: '',
                  active: 1,
                ),
              )
              .codePrefix ??
          '';
      final code = prefix.isNotEmpty && suffix.isNotEmpty
          ? '$prefix-$suffix'
          : suffix;
      if (_isEditing) {
        final orig = widget.product!;
        final newName = _nameCtrl.text.trim();
        final newNotes = _notesCtrl.text.trim();
        final newCode = code.isNotEmpty ? code : null;
        final origRutTien = orig.attributes['rut_tien']?.toString() == 'true';
        final origTrungBay = orig.attributes['trung_bay']?.toString() == 'true';
        final origTangKem = orig.attributes['tang_kem']?.toString() == 'true';
        final hasEnumOptionChanges = _hasEnumOptionChanges();
        final hasChanges =
            newName != orig.name ||
            _category != orig.category ||
            price != orig.basePrice ||
            cost != orig.cost ||
            newNotes != orig.recipeNotes ||
            newCode != orig.productCode ||
            _pickedPhoto != null ||
            hasPriceChipChanges ||
            hasEnumOptionChanges ||
            _rutTien != origRutTien ||
            _trungBay != origTrungBay ||
            _tangKem != origTangKem;
        if (!hasChanges) {
          if (mounted) context.pop();
          return;
        }
        final hasFieldChanges =
            newName != orig.name ||
            _category != orig.category ||
            price != orig.basePrice ||
            cost != orig.cost ||
            newNotes != orig.recipeNotes ||
            newCode != orig.productCode;
        if (hasFieldChanges) {
          saved = await notifier.updateProduct(
            orig.id,
            name: newName != orig.name ? newName : null,
            category: _category != orig.category ? _category : null,
            basePrice: price != orig.basePrice ? price : null,
            cost: cost != orig.cost ? cost : null,
            recipeNotes: newNotes != orig.recipeNotes ? newNotes : null,
            productCode: newCode != orig.productCode ? newCode : null,
          );
        } else {
          saved = orig;
        }

        // Sync rut_tien attribute if changed
        if (_rutTien != origRutTien) {
          final productSvc = ref.read(productServiceProvider);
          if (_rutTien) {
            await productSvc.setProductAttribute(saved.id, 'rut_tien', 'true');
          } else {
            await productSvc.deleteProductAttribute(saved.id, 'rut_tien');
          }
          await notifier.refresh();
        }
        // Sync trung_bay attribute if changed
        if (_trungBay != origTrungBay) {
          final productSvc = ref.read(productServiceProvider);
          if (_trungBay) {
            await productSvc.setProductAttribute(saved.id, 'trung_bay', 'true');
          } else {
            await productSvc.deleteProductAttribute(saved.id, 'trung_bay');
          }
          await notifier.refresh();
        }
        // Sync tang_kem attribute if changed
        if (_tangKem != origTangKem) {
          final productSvc = ref.read(productServiceProvider);
          if (_tangKem) {
            await productSvc.setProductAttribute(saved.id, 'tang_kem', 'true');
          } else {
            await productSvc.deleteProductAttribute(saved.id, 'tang_kem');
          }
          await notifier.refresh();
        }
      } else {
        saved = await notifier.createProduct(
          name: _nameCtrl.text.trim(),
          category: _category,
          basePrice: price,
          cost: cost,
          recipeNotes: _notesCtrl.text.trim(),
          productCode: code.isNotEmpty ? code : null,
        );
        // Sync rut_tien attribute for new products
        if (_rutTien) {
          final productSvc = ref.read(productServiceProvider);
          await productSvc.setProductAttribute(saved.id, 'rut_tien', 'true');
          await notifier.refresh();
        }
        // Sync trung_bay attribute for new products
        if (_trungBay) {
          final productSvc = ref.read(productServiceProvider);
          await productSvc.setProductAttribute(saved.id, 'trung_bay', 'true');
          await notifier.refresh();
        }
        // Sync tang_kem attribute for new products
        if (_tangKem) {
          final productSvc = ref.read(productServiceProvider);
          await productSvc.setProductAttribute(saved.id, 'tang_kem', 'true');
          await notifier.refresh();
        }
      }

      if (hasPriceChipChanges) {
        await _syncPriceChipEdits(saved.id);
      }

      if (_hasEnumOptionChanges()) {
        await _syncEnumOptionEdits();
        await ref.read(productsProvider.notifier).refresh();
      }

      if (_pickedPhoto != null) {
        await notifier.uploadPhoto(saved.id, _pickedPhoto!);
      }

      if (mounted) {
        showTopSnackBar(
          context,
          _isEditing ? VN.productUpdated : VN.productCreated,
        );
        context.pop();
      }
    } on DioException catch (e) {
      if (mounted) {
        final detail = e.response?.data is Map
            ? e.response!.data['detail'] as String?
            : null;
        showTopSnackBar(context, detail ?? e.message ?? VN.apiError);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(VN.deleteProduct),
        content: const Text(VN.deleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(VN.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(VN.remove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(productsProvider.notifier)
          .deleteProduct(widget.product!.id);
      if (mounted) {
        showTopSnackBar(context, VN.productDeleted);
        context.pop();
      }
    } on DioException catch (e) {
      if (mounted) {
        showTopSnackBar(context, e.message ?? VN.apiError);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reactivate() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(productsProvider.notifier)
          .reactivateProduct(widget.product!.id);
      if (mounted) {
        showTopSnackBar(context, VN.productUpdated);
        context.pop();
      }
    } on DioException catch (e) {
      if (mounted) {
        showTopSnackBar(context, e.message ?? VN.apiError);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final photoRefreshTick = ref.watch(productPhotoRefreshTickProvider);

    // Compute the read-only prefix for the current category.
    final currentPrefix = categoriesAsync.maybeWhen(
      data: (cats) => cats
          .firstWhere(
            (c) => c.slug == _category,
            orElse: () => const Category(
              id: 0,
              slug: '',
              name: '',
              codePrefix: '',
              active: 1,
            ),
          )
          .codePrefix,
      orElse: () => '',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? VN.editProduct : VN.createProduct),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: widget.product!.active == 0
                  ? VN.showProduct
                  : VN.deleteProduct,
              icon: Icon(
                widget.product!.active == 0
                    ? Icons.visibility_outlined
                    : Icons.delete_outline,
              ),
              onPressed: _saving
                  ? null
                  : widget.product!.active == 0
                  ? _reactivate
                  : _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ProductFormBasicInfoSection(
              productId: widget.product?.id,
              pickedPhoto: _pickedPhoto,
              baseUrl: baseUrl,
              onPickPhoto: _pickPhoto,
              cacheBuster: photoRefreshTick.toString(),
              nameController: _nameCtrl,
              codeController: _codeCtrl,
              currentPrefix: currentPrefix,
              categoriesAsync: categoriesAsync,
              category: _category,
              onCategoryChanged: (v) => setState(() => _category = v),
              photoSection: _PhotoSection(
                productId: widget.product?.id,
                pickedPhoto: _pickedPhoto,
                baseUrl: baseUrl,
                onPickPhoto: _pickPhoto,
                cacheBuster: photoRefreshTick.toString(),
              ),
            ),
            const SizedBox(height: 16),
            ProductFormPricingSection(
              priceController: _priceCtrl,
              costController: _costCtrl,
              priceChipSection: _buildPriceChipSection(),
            ),
            const SizedBox(height: 16),
            ProductFormAttributesSection(
              enumOptionsSection: _buildEnumOptionsSection(),
              notesController: _notesCtrl,
              rutTien: _rutTien,
              trungBay: _trungBay,
              tangKem: _tangKem,
              isEditing: _isEditing,
              onRutTienChanged: (v) => setState(() => _rutTien = v),
              onTrungBayChanged: (v) => setState(() => _trungBay = v),
              onTangKemChanged: (v) => setState(() => _tangKem = v),
            ),
            const SizedBox(height: 16),

            // Save button
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(VN.save),
            ),

            ProductFormCatalogIntegrationSection(
              isEditing: _isEditing,
              catalogGallery: _isEditing
                  ? _CatalogGallerySection(productId: widget.product!.id)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceChipFormRow {
  _PriceChipFormRow({this.id, String label = '', String price = ''})
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

class _PriceChipValidationErrors {
  const _PriceChipValidationErrors({this.labelError, this.priceError});

  final String? labelError;
  final String? priceError;

  bool get hasError => labelError != null || priceError != null;
}

/// Mutable per-row state for an enum attribute option in the product form.
class _EnumOptionFormRow {
  _EnumOptionFormRow({
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

/// Per-attribute editor state. Mirrors `_originalPriceChips` / `_priceChipRows`
/// but for one enum attribute (e.g. `nhan_banh`).
class _EnumAttributeFormSection {
  _EnumAttributeFormSection({
    required this.attribute,
    required List<EnumOption> originalOptions,
    required this.originalDefaultId,
  }) : _originalOptions = List<EnumOption>.of(originalOptions),
       rows = originalOptions
           .map(
             (opt) => _EnumOptionFormRow(
               id: opt.id,
               valueVi: opt.valueVi,
               sortOrder: opt.sortOrder,
               active: opt.active,
               isDefault: opt.id == originalDefaultId,
             ),
           )
           .toList();

  factory _EnumAttributeFormSection.fromAttribute(EnumAttribute attribute) {
    return _EnumAttributeFormSection(
      attribute: attribute,
      originalOptions: attribute.options,
      originalDefaultId: attribute.defaultOptionId,
    );
  }

  final EnumAttribute attribute;
  final List<_EnumOptionFormRow> rows;
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

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.productId,
    required this.pickedPhoto,
    required this.baseUrl,
    required this.onPickPhoto,
    this.cacheBuster,
  });

  final int? productId;
  final XFile? pickedPhoto;
  final String baseUrl;
  final VoidCallback onPickPhoto;
  final String? cacheBuster;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onPickPhoto,
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    // Show picked photo (not yet uploaded)
    if (pickedPhoto != null) {
      return FutureBuilder<Uint8List>(
        future: pickedPhoto!.readAsBytes(),
        builder: (ctx, snap) {
          if (!snap.hasData) return _placeholder();
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(
                snap.data!,
                fit: BoxFit.cover,
                errorBuilder: (_, e, s) => _placeholder(),
              ),
              _overlayButton(),
            ],
          );
        },
      );
    }

    // Show existing photo from API (always try if product exists)
    if (productId != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            '$baseUrl/api/products/$productId/photo${cacheBuster != null ? '?v=$cacheBuster' : ''}',
            fit: BoxFit.cover,
            errorBuilder: (_, e, s) => _placeholder(),
          ),
          _overlayButton(),
        ],
      );
    }

    return _placeholder();
  }

  Widget _placeholder() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_a_photo, size: 48, color: Colors.grey),
        SizedBox(height: 8),
        Text(VN.choosePhoto, style: TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _overlayButton() {
    return Positioned(
      right: 8,
      bottom: 8,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.edit, color: Colors.white, size: 20),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Catalog gallery section
// ---------------------------------------------------------------------------

class _CatalogGallerySection extends ConsumerStatefulWidget {
  const _CatalogGallerySection({required this.productId});

  final int productId;

  @override
  ConsumerState<_CatalogGallerySection> createState() =>
      _CatalogGallerySectionState();
}

class _CatalogGallerySectionState
    extends ConsumerState<_CatalogGallerySection> {
  bool _uploading = false;
  bool _promoting = false;
  int _uploadTotal = 0;
  int _uploadDone = 0;

  Future<void> _pickAndUpload() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text(VN.takePhoto),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text(VN.fromGallery),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picker = ImagePicker();

    if (source == ImageSource.gallery) {
      // Multi-select from gallery
      final files = await picker.pickMultiImage();
      if (files.isEmpty) return;

      setState(() {
        _uploading = true;
        _uploadTotal = files.length;
        _uploadDone = 0;
      });
      int failed = 0;
      for (final file in files) {
        try {
          await ref
              .read(catalogProvider(widget.productId).notifier)
              .addPhoto(file);
          if (mounted) setState(() => _uploadDone++);
        } on DioException {
          failed++;
        } catch (_) {
          failed++;
        }
      }
      if (mounted) {
        final added = files.length - failed;
        showTopSnackBar(
          context,
          failed == 0
              ? (added == 1 ? VN.catalogPhotoAdded : 'Đã thêm $added ảnh mẫu')
              : 'Đã thêm $added ảnh, $failed ảnh lỗi',
        );
      }
    } else {
      // Camera: single photo only
      final file = await picker.pickImage(source: source);
      if (file == null) return;

      setState(() {
        _uploading = true;
        _uploadTotal = 1;
        _uploadDone = 0;
      });
      try {
        await ref
            .read(catalogProvider(widget.productId).notifier)
            .addPhoto(file);
        if (mounted) {
          showTopSnackBar(context, VN.catalogPhotoAdded);
        }
      } on DioException catch (e) {
        if (mounted) {
          showTopSnackBar(context, e.message ?? VN.apiError);
        }
      }
    }

    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _confirmDelete(CatalogPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(VN.deleteCatalogPhoto),
        content: const Text(VN.deleteCatalogConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(VN.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(VN.remove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(catalogProvider(widget.productId).notifier)
          .deletePhoto(photo.id);
      if (mounted) {
        showTopSnackBar(context, VN.catalogPhotoDeleted);
      }
    } on DioException catch (e) {
      if (mounted) {
        showTopSnackBar(context, e.message ?? VN.apiError);
      }
    }
  }

  Future<void> _promotePhoto(CatalogPhoto photo) async {
    setState(() => _promoting = true);
    try {
      await ref
          .read(catalogProvider(widget.productId).notifier)
          .promotePhotoToProductMain(photo.id);
      if (mounted) {
        showTopSnackBar(context, VN.productPhotoSetFromCatalog);
      }
    } on DioException catch (e) {
      if (mounted) {
        showTopSnackBar(context, e.message ?? VN.apiError);
      }
    } finally {
      if (mounted) {
        setState(() => _promoting = false);
      }
    }
  }

  void _openFullScreen(
    List<CatalogPhoto> photos,
    int initialIndex,
    String baseUrl,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => CatalogPhotoViewer(
          photos: photos,
          initialIndex: initialIndex,
          productId: widget.productId,
          baseUrl: baseUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(catalogProvider(widget.productId));
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text(VN.catalogTitle, style: theme.textTheme.titleMedium),
              if (_uploading || _promoting) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                if (_uploadTotal > 1) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$_uploadDone/$_uploadTotal',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ],
          ),
        ),
        catalogAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Text(
            VN.errorLoading,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          data: (photos) => Column(
            children: [
              if (photos.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    VN.noCatalogPhotos,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: photos.length + 1,
                itemBuilder: (ctx, index) {
                  if (index == photos.length) {
                    return _AddPhotoCard(
                      uploading: _uploading,
                      onTap: _pickAndUpload,
                    );
                  }
                  final photo = photos[index];
                  final url =
                      '$baseUrl/api/products/${widget.productId}/catalog/${photo.id}/photo';
                  return _CatalogPhotoCard(
                    photo: photo,
                    productId: widget.productId,
                    url: url,
                    onTap: () => _openFullScreen(photos, index, baseUrl),
                    onDelete: () => _confirmDelete(photo),
                    onPromote: () => _promotePhoto(photo),
                    promoting: _promoting,
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddPhotoCard extends StatelessWidget {
  const _AddPhotoCard({required this.uploading, required this.onTap});

  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 1,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: uploading ? null : onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              uploading
                  ? const CircularProgressIndicator()
                  : const Icon(Icons.add_photo_alternate_outlined, size: 36),
              const SizedBox(height: 8),
              Text(
                VN.addCatalogPhoto,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogPhotoCard extends StatelessWidget {
  const _CatalogPhotoCard({
    required this.photo,
    required this.productId,
    required this.url,
    required this.onTap,
    required this.onDelete,
    required this.onPromote,
    required this.promoting,
  });

  final CatalogPhoto photo;
  final int productId;
  final String url;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onPromote;
  final bool promoting;

  void _openEditSheet(BuildContext context) {
    showEditCatalogTagsSheet(
      context: context,
      photo: photo,
      productId: productId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, e, s) => Container(
                      color: Colors.grey[200],
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                  // Label edit button
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _openEditSheet(context),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.label_outline,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                  // Delete button
                  Positioned(
                    top: 4,
                    left: 4,
                    child: GestureDetector(
                      onTap: onDelete,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Material(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: promoting ? null : onPromote,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star_outline,
                                color: Colors.white,
                                size: 12,
                              ),
                              SizedBox(width: 4),
                              Text(
                                VN.setAsProductPhoto,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Tag chips row (max 3)
          if (photo.tags.isNotEmpty) ...[
            const SizedBox(height: 4),
            CatalogTagChips(tags: photo.tags, maxChips: 3),
          ],
        ],
      ),
    );
  }
}
