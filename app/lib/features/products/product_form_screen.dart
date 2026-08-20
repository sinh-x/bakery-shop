// DG-150 Phase 4 temporary exemption: screen coordinator remains above 300 lines while enum option persistence and photo workflow are preserved in-place; review in Phase 6 (2026-05-29).
import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/api/api_client.dart';
import '../../data/api/product_service.dart';
import '../../data/models/enum_attribute.dart';
import '../../data/models/price_chip.dart';
import '../../data/models/category.dart';
import '../../data/models/product.dart';
import '../../data/providers/categories_provider.dart';
import '../../data/providers/products_provider.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'providers/product_form_notifier.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'widgets/catalog_gallery_section.dart';
import 'widgets/enum_attribute_form_section.dart';
import 'widgets/enum_option_form_row.dart';
import 'widgets/photo_section.dart';
import 'widgets/price_chip_form_row.dart';
import 'widgets/price_chip_validation_errors.dart';
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
  late final List<PriceChipFormRow> _priceChipRows;
  late final List<EnumAttributeFormSection> _enumSections;

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
          (chip) => PriceChipFormRow(
            id: chip.id,
            label: chip.label,
            price: chip.price.toInt().toString(),
          ),
        )
        .toList();
    _enumSections = (p?.enumAttributes ?? const <EnumAttribute>[])
        .map(EnumAttributeFormSection.fromAttribute)
        .toList();
    // Store only the suffix portion so the prefix can be shown read-only.
    _codeCtrl = TextEditingController(text: _extractSuffix(p?.productCode));
    // Seed the notifier with the initial form values derived from the
    // product (or defaults for new products). All subsequent mutations
    // go through the notifier; no setState is required.
    final initialCategory = widget.initialCategory ?? p?.category ?? 'banh_kem';
    final initialRutTien = p?.attributes['rut_tien']?.toString() == 'true';
    final initialTrungBay = p?.attributes['trung_bay']?.toString() == 'true';
    final initialTangKem = p?.attributes['tang_kem']?.toString() == 'true';
    // Defer provider mutation to a microtask because Riverpod disallows
    // provider mutation during widget life-cycle hooks (initState/build).
    Future.microtask(() {
      if (!mounted) return;
      ref.read(productFormProvider.notifier).seed(
            initialCategory: initialCategory,
            rutTien: initialRutTien,
            trungBay: initialTrungBay,
            tangKem: initialTangKem,
          );
    });
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
    _priceChipRows.add(PriceChipFormRow());
    ref.read(productFormProvider.notifier).rebuild();
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
              child: const Text(SharedLabels.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(SharedLabels.remove),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    row.dispose();
    _priceChipRows.removeAt(index);
    ref.read(productFormProvider.notifier).rebuild();
  }

  void _reorderPriceChips(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final row = _priceChipRows.removeAt(oldIndex);
    _priceChipRows.insert(newIndex, row);
    ref.read(productFormProvider.notifier).rebuild();
  }

  double? _parseChipPrice(String text) {
    final value = text.trim();
    if (value.isEmpty) return null;
    return double.tryParse(value);
  }

  Map<int, PriceChipValidationErrors> _validatePriceChipRows() {
    final errors = <int, PriceChipValidationErrors>{};

    for (var index = 0; index < _priceChipRows.length; index++) {
      final row = _priceChipRows[index];
      final label = row.labelController.text.trim();
      final priceText = row.priceController.text.trim();
      final parsedPrice = _parseChipPrice(priceText);

      final rowErrors = PriceChipValidationErrors(
        labelError: label.isEmpty ? ProductsLabels.priceChipLabelRequired : null,
        priceError: parsedPrice == null || parsedPrice < 0
            ? ProductsLabels.priceChipPriceInvalid
            : null,
      );

      if (rowErrors.hasError) {
        errors[index] = rowErrors;
      }
    }

    final changed = _applyPriceChipRowErrors(errors);
    if (changed) ref.read(productFormProvider.notifier).rebuild();
    return errors;
  }

  bool _applyPriceChipRowErrors(Map<int, PriceChipValidationErrors> errors) {
    var changed = false;
    for (var index = 0; index < _priceChipRows.length; index++) {
      final row = _priceChipRows[index];
      final rowErrors = errors[index] ?? const PriceChipValidationErrors();
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
          Text(ProductsLabels.priceChips, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _addPriceChip,
            icon: const Icon(Icons.add),
            label: const Text(ProductsLabels.addPriceChip),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(ProductsLabels.priceChips, style: Theme.of(context).textTheme.titleMedium),
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
                        labelText: ProductsLabels.priceChipLabel,
                        errorText: row.labelError,
                      ),
                      onChanged: (_) {
                        if (row.labelError != null) {
                          row.updateErrors(
                            labelError: null,
                            priceError: row.priceError,
                          );
                          ref.read(productFormProvider.notifier).rebuild();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: row.priceController,
                      decoration: InputDecoration(
                        labelText: ProductsLabels.priceChipPrice,
                        suffixText: SharedLabels.currency,
                        errorText: row.priceError,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) {
                        if (row.priceError != null) {
                          row.updateErrors(
                            labelError: row.labelError,
                            priceError: null,
                          );
                          ref.read(productFormProvider.notifier).rebuild();
                        }
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: SharedLabels.remove,
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
          label: const Text(ProductsLabels.addPriceChip),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ----- Enum attribute options editor (DG-092 Phase 4.5) -----

  void _addEnumOption(EnumAttributeFormSection section) {
    section.rows.add(EnumOptionFormRow(sortOrder: section.rows.length));
    ref.read(productFormProvider.notifier).rebuild();
  }

  void _toggleRemoveEnumOption(EnumAttributeFormSection section, int index) {
    final row = section.rows[index];
    if (row.id == null) {
      row.dispose();
      section.rows.removeAt(index);
    } else {
      row.removed = !row.removed;
      if (row.removed && row.isDefault) {
        row.isDefault = false;
      }
    }
    ref.read(productFormProvider.notifier).rebuild();
  }

  void _setEnumDefault(EnumAttributeFormSection section, int index) {
    for (var i = 0; i < section.rows.length; i++) {
      section.rows[i].isDefault = i == index;
    }
    ref.read(productFormProvider.notifier).rebuild();
  }

  void _reorderEnumOptions(
    EnumAttributeFormSection section,
    int oldIndex,
    int newIndex,
  ) {
    if (newIndex > oldIndex) newIndex -= 1;
    final row = section.rows.removeAt(oldIndex);
    section.rows.insert(newIndex, row);
    ref.read(productFormProvider.notifier).rebuild();
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
            ? ProductsLabels.enumOptionValueRequired
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
            section.setError(ProductsLabels.enumOptionDefaultRequired) || sectionChanged;
        ok = false;
      }
      changed = changed || sectionChanged;
    }
    if (changed) ref.read(productFormProvider.notifier).rebuild();
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
          ProductsLabels.enumOptionsSection,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          ProductsLabels.enumOptionsHintAttributeWide,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final section in _enumSections) _buildEnumSection(section),
      ],
    );
  }

  Widget _buildEnumSection(EnumAttributeFormSection section) {
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
                      tooltip: ProductsLabels.enumOptionDefaultLabel,
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
                          labelText: ProductsLabels.enumOptionValueLabel,
                          errorText: row.valueError,
                          helperText: row.removed ? ProductsLabels.enumOptionRemoved : null,
                        ),
                        onChanged: (_) {
                          if (row.valueError != null) {
                            row.setValueError(null);
                            ref.read(productFormProvider.notifier).rebuild();
                          }
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: row.removed ? ProductsLabels.enumOptionRestore : SharedLabels.remove,
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
            label: const Text(ProductsLabels.addEnumOption),
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
              title: const Text(ProductsLabels.takePhoto),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text(ProductsLabels.fromGallery),
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
      ref.read(productFormProvider.notifier).setPickedPhoto(file);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_validatePriceChipRows().isNotEmpty) return;
    if (!_validateEnumOptions()) return;
    final formNotifier = ref.read(productFormProvider.notifier);
    final formState = ref.read(productFormProvider);
    formNotifier.setSaving(true);

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
                (c) => c.slug == formState.category,
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
            formState.category != orig.category ||
            price != orig.basePrice ||
            cost != orig.cost ||
            newNotes != orig.recipeNotes ||
            newCode != orig.productCode ||
            formState.pickedPhoto != null ||
            hasPriceChipChanges ||
            hasEnumOptionChanges ||
            formState.rutTien != origRutTien ||
            formState.trungBay != origTrungBay ||
            formState.tangKem != origTangKem;
        if (!hasChanges) {
          if (mounted) context.pop();
          return;
        }
        final hasFieldChanges =
            newName != orig.name ||
            formState.category != orig.category ||
            price != orig.basePrice ||
            cost != orig.cost ||
            newNotes != orig.recipeNotes ||
            newCode != orig.productCode;
        if (hasFieldChanges) {
          saved = await notifier.updateProduct(
            orig.id,
            name: newName != orig.name ? newName : null,
            category: formState.category != orig.category
                ? formState.category
                : null,
            basePrice: price != orig.basePrice ? price : null,
            cost: cost != orig.cost ? cost : null,
            recipeNotes: newNotes != orig.recipeNotes ? newNotes : null,
            productCode: newCode != orig.productCode ? newCode : null,
          );
        } else {
          saved = orig;
        }

        // Sync rut_tien attribute if changed
        if (formState.rutTien != origRutTien) {
          final productSvc = ref.read(productServiceProvider);
          if (formState.rutTien) {
            await productSvc.setProductAttribute(saved.id, 'rut_tien', 'true');
          } else {
            await productSvc.deleteProductAttribute(saved.id, 'rut_tien');
          }
          await notifier.refresh();
        }
        // Sync trung_bay attribute if changed
        if (formState.trungBay != origTrungBay) {
          final productSvc = ref.read(productServiceProvider);
          if (formState.trungBay) {
            await productSvc.setProductAttribute(saved.id, 'trung_bay', 'true');
          } else {
            await productSvc.deleteProductAttribute(saved.id, 'trung_bay');
          }
          await notifier.refresh();
        }
        // Sync tang_kem attribute if changed
        if (formState.tangKem != origTangKem) {
          final productSvc = ref.read(productServiceProvider);
          if (formState.tangKem) {
            await productSvc.setProductAttribute(saved.id, 'tang_kem', 'true');
          } else {
            await productSvc.deleteProductAttribute(saved.id, 'tang_kem');
          }
          await notifier.refresh();
        }
      } else {
        saved = await notifier.createProduct(
          name: _nameCtrl.text.trim(),
          category: formState.category,
          basePrice: price,
          cost: cost,
          recipeNotes: _notesCtrl.text.trim(),
          productCode: code.isNotEmpty ? code : null,
        );
        // Sync rut_tien attribute for new products
        if (formState.rutTien) {
          final productSvc = ref.read(productServiceProvider);
          await productSvc.setProductAttribute(saved.id, 'rut_tien', 'true');
          await notifier.refresh();
        }
        // Sync trung_bay attribute for new products
        if (formState.trungBay) {
          final productSvc = ref.read(productServiceProvider);
          await productSvc.setProductAttribute(saved.id, 'trung_bay', 'true');
          await notifier.refresh();
        }
        // Sync tang_kem attribute for new products
        if (formState.tangKem) {
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

      if (formState.pickedPhoto != null) {
        await notifier.uploadPhoto(saved.id, formState.pickedPhoto!);
      }

      ref.invalidate(phuKienProductsProvider);

      if (mounted) {
        showTopSnackBar(
          context,
          _isEditing ? ProductsLabels.productUpdated : ProductsLabels.productCreated,
        );
        context.pop();
      }
    } on DioException catch (e) {
      if (mounted) {
        final detail = e.response?.data is Map
            ? e.response!.data['detail'] as String?
            : null;
        showTopSnackBar(context, detail ?? e.message ?? SharedLabels.apiError);
      }
    } finally {
      if (mounted) formNotifier.setSaving(false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(ProductsLabels.deleteProduct),
        content: const Text(ProductsLabels.deleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(SharedLabels.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(SharedLabels.remove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final formNotifier = ref.read(productFormProvider.notifier);
    formNotifier.setSaving(true);
    try {
      await ref
          .read(productsProvider.notifier)
          .deleteProduct(widget.product!.id);
      if (mounted) {
        showTopSnackBar(context, ProductsLabels.productDeleted);
        context.pop();
      }
    } on DioException catch (e) {
      if (mounted) {
        showTopSnackBar(context, e.message ?? SharedLabels.apiError);
      }
    } finally {
      if (mounted) formNotifier.setSaving(false);
    }
  }

  Future<void> _reactivate() async {
    final formNotifier = ref.read(productFormProvider.notifier);
    formNotifier.setSaving(true);
    try {
      await ref
          .read(productsProvider.notifier)
          .reactivateProduct(widget.product!.id);
      if (mounted) {
        showTopSnackBar(context, ProductsLabels.productUpdated);
        context.pop();
      }
    } on DioException catch (e) {
      if (mounted) {
        showTopSnackBar(context, e.message ?? SharedLabels.apiError);
      }
    } finally {
      if (mounted) formNotifier.setSaving(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final photoRefreshTick = ref.watch(productPhotoRefreshTickProvider);
    final formState = ref.watch(productFormProvider);
    final formNotifier = ref.read(productFormProvider.notifier);

    // Compute the read-only prefix for the current category.
    final currentPrefix = categoriesAsync.maybeWhen(
      data: (cats) => cats
          .firstWhere(
            (c) => c.slug == formState.category,
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
        title: Text(_isEditing ? ProductsLabels.editProduct : ProductsLabels.createProduct),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: widget.product!.active == 0
                  ? ProductsLabels.showProduct
                  : ProductsLabels.deleteProduct,
              icon: Icon(
                widget.product!.active == 0
                    ? Icons.visibility_outlined
                    : Icons.delete_outline,
              ),
              onPressed: formState.saving
                  ? null
                  : widget.product!.active == 0
                  ? _reactivate
                  : _delete,
            ),
          const AppBarOverflowMenu(),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ProductFormBasicInfoSection(
              productId: widget.product?.id,
              pickedPhoto: formState.pickedPhoto,
              baseUrl: baseUrl,
              onPickPhoto: _pickPhoto,
              cacheBuster: photoRefreshTick.toString(),
              nameController: _nameCtrl,
              codeController: _codeCtrl,
              currentPrefix: currentPrefix,
              categoriesAsync: categoriesAsync,
              category: formState.category,
              onCategoryChanged: formNotifier.setCategory,
              photoSection: PhotoSection(
                productId: widget.product?.id,
                pickedPhoto: formState.pickedPhoto,
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
              rutTien: formState.rutTien,
              trungBay: formState.trungBay,
              tangKem: formState.tangKem,
              isEditing: _isEditing,
              onRutTienChanged: formNotifier.setRutTien,
              onTrungBayChanged: formNotifier.setTrungBay,
              onTangKemChanged: formNotifier.setTangKem,
            ),
            const SizedBox(height: 16),

            // Save button
            FilledButton(
              onPressed: formState.saving ? null : _save,
              child: formState.saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(SharedLabels.save),
            ),

            ProductFormCatalogIntegrationSection(
              isEditing: _isEditing,
              catalogGallery: _isEditing
                  ? CatalogGallerySection(productId: widget.product!.id)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
