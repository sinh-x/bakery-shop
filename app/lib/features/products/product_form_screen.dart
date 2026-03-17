import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/api/api_client.dart';
import '../../data/models/product.dart';
import '../../providers/categories_provider.dart';
import '../../providers/products_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';

/// Shared form for creating and editing products.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.product});

  /// If null, we're creating a new product; otherwise editing.
  final Product? product;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _codeCtrl;
  late String _category;
  String? _pickedPhotoPath;
  bool _saving = false;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _priceCtrl = TextEditingController(
        text: p != null ? p.basePrice.toInt().toString() : '');
    _costCtrl = TextEditingController(
        text: p != null && p.cost > 0 ? p.cost.toInt().toString() : '');
    _notesCtrl = TextEditingController(text: p?.recipeNotes ?? '');
    _codeCtrl = TextEditingController(text: p?.productCode ?? '');
    _category = p?.category ?? 'banh_kem';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _costCtrl.dispose();
    _notesCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
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
    final file = await picker.pickImage(source: source, maxWidth: 1200);
    if (file != null) {
      setState(() => _pickedPhotoPath = file.path);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final notifier = ref.read(productsProvider.notifier);
      final price = double.tryParse(_priceCtrl.text) ?? 0;
      final cost = double.tryParse(_costCtrl.text) ?? 0;

      Product saved;
      final code = _codeCtrl.text.trim();
      if (_isEditing) {
        saved = await notifier.updateProduct(
          widget.product!.id,
          name: _nameCtrl.text.trim(),
          category: _category,
          basePrice: price,
          cost: cost,
          recipeNotes: _notesCtrl.text.trim(),
          productCode: code.isNotEmpty ? code : null,
        );
      } else {
        saved = await notifier.createProduct(
          name: _nameCtrl.text.trim(),
          category: _category,
          basePrice: price,
          cost: cost,
          recipeNotes: _notesCtrl.text.trim(),
          productCode: code.isNotEmpty ? code : null,
        );
      }

      if (_pickedPhotoPath != null) {
        await notifier.uploadPhoto(saved.id, _pickedPhotoPath!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                _isEditing ? VN.productUpdated : VN.productCreated),
          ),
        );
        context.pop();
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? VN.apiError)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(VN.deleteProduct),
        content: Text(VN.deleteConfirm),
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
      await ref.read(productsProvider.notifier).deleteProduct(widget.product!.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(VN.productDeleted)),
        );
        context.pop();
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? VN.apiError)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? VN.editProduct : VN.createProduct),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Photo section
            _PhotoSection(
              productId: widget.product?.id,
              pickedPhotoPath: _pickedPhotoPath,
              baseUrl: baseUrl,
              onPickPhoto: _pickPhoto,
            ),
            const SizedBox(height: 24),

            // Name
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: VN.productName,
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? VN.fieldRequired : null,
            ),
            const SizedBox(height: 16),

            // Product code
            TextFormField(
              controller: _codeCtrl,
              decoration: const InputDecoration(
                labelText: VN.productCode,
                hintText: 'VD: BKS-16',
                helperText: 'Tự động tạo nếu để trống',
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 16),

            // Category dropdown (from API)
            categoriesAsync.when(
              loading: () => DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: VN.productCategory),
                items: categoryMap.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text('${categoryEmojiMap[e.key] ?? ''} ${e.value}'),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _category = v);
                },
              ),
              error: (err, st) => DropdownButtonFormField<String>(
                value: categoryMap.containsKey(_category) ? _category : categoryMap.keys.first,
                decoration: const InputDecoration(labelText: VN.productCategory),
                items: categoryMap.entries
                    .map((e) => DropdownMenuItem(
                          value: e.key,
                          child: Text('${categoryEmojiMap[e.key] ?? ''} ${e.value}'),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _category = v);
                },
              ),
              data: (categories) {
                final active = categories.where((c) => c.active == 1).toList();
                // Ensure _category is valid
                final validSlugs = active.map((c) => c.slug).toList();
                if (!validSlugs.contains(_category) && validSlugs.isNotEmpty) {
                  _category = validSlugs.first;
                }
                return DropdownButtonFormField<String>(
                  value: _category,
                  decoration: const InputDecoration(labelText: VN.productCategory),
                  items: active
                      .map((cat) => DropdownMenuItem(
                            value: cat.slug,
                            child: Text(
                                '${categoryEmojiMap[cat.slug] ?? ''} ${cat.name}'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _category = v);
                  },
                );
              },
            ),
            const SizedBox(height: 16),

            // Price
            TextFormField(
              controller: _priceCtrl,
              decoration: const InputDecoration(
                labelText: VN.productPrice,
                suffixText: VN.currency,
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return VN.fieldRequired;
                if (double.tryParse(v) == null) return VN.invalidPrice;
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Cost
            TextFormField(
              controller: _costCtrl,
              decoration: const InputDecoration(
                labelText: VN.productCost,
                suffixText: VN.currency,
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),

            // Notes
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: VN.productNotes,
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            // Save button
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(VN.save),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.productId,
    required this.pickedPhotoPath,
    required this.baseUrl,
    required this.onPickPhoto,
  });

  final int? productId;
  final String? pickedPhotoPath;
  final String baseUrl;
  final VoidCallback onPickPhoto;

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
    if (pickedPhotoPath != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(pickedPhotoPath!),
            fit: BoxFit.cover,
            errorBuilder: (_, e, s) => _placeholder(),
          ),
          _overlayButton(),
        ],
      );
    }

    // Show existing photo from API (always try if product exists)
    if (productId != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            '$baseUrl/api/products/$productId/photo',
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
