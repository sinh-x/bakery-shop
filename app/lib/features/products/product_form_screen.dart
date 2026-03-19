import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/api/api_client.dart';
import '../../data/models/catalog_photo.dart';
import '../../data/models/category.dart';
import '../../data/models/product.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/categories_provider.dart';
import '../../providers/products_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';
import 'widgets/catalog_photo_viewer.dart';

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
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _codeCtrl;
  late String _category;
  String? _pickedPhotoPath;
  String _photoCacheBuster = '';
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
        text: p != null ? p.basePrice.toInt().toString() : '');
    _costCtrl = TextEditingController(
        text: p != null && p.cost > 0 ? p.cost.toInt().toString() : '');
    _notesCtrl = TextEditingController(text: p?.recipeNotes ?? '');
    // Store only the suffix portion so the prefix can be shown read-only.
    _codeCtrl = TextEditingController(text: _extractSuffix(p?.productCode));
    _category = widget.initialCategory ?? p?.category ?? 'banh_kem';
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
    final file = await picker.pickImage(source: source);
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
      // Build full product code: prefix (from category) + '-' + suffix (user input).
      final suffix = _codeCtrl.text.trim();
      final cats = ref.read(categoriesProvider).asData?.value;
      final prefix = cats
              ?.firstWhere(
                (c) => c.slug == _category,
                orElse: () =>
                    const Category(id: 0, slug: '', name: '', codePrefix: '', active: 1),
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
        final hasChanges = newName != orig.name ||
            _category != orig.category ||
            price != orig.basePrice ||
            cost != orig.cost ||
            newNotes != orig.recipeNotes ||
            newCode != orig.productCode ||
            _pickedPhotoPath != null;
        if (!hasChanges) {
          if (mounted) context.pop();
          return;
        }
        final hasFieldChanges = newName != orig.name ||
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
        // Clear image cache so updated photo shows immediately
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
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
        final detail = e.response?.data is Map
            ? e.response!.data['detail'] as String?
            : null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(detail ?? e.message ?? VN.apiError)),
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

    // Compute the read-only prefix for the current category.
    final currentPrefix = categoriesAsync.maybeWhen(
      data: (cats) => cats
          .firstWhere(
            (c) => c.slug == _category,
            orElse: () =>
                const Category(id: 0, slug: '', name: '', codePrefix: '', active: 1),
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
              cacheBuster: _photoCacheBuster.isNotEmpty ? _photoCacheBuster : null,
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

            // Product code — prefix is read-only, user edits suffix only
            TextFormField(
              controller: _codeCtrl,
              decoration: InputDecoration(
                labelText: VN.productCode,
                prefixText: currentPrefix.isNotEmpty ? '$currentPrefix-' : null,
                hintText: currentPrefix.isEmpty ? 'VD: BKS-16' : '16',
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

            // Catalog gallery (editing only)
            if (_isEditing) ...[
              const SizedBox(height: 32),
              _CatalogGallerySection(productId: widget.product!.id),
            ],
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
    this.cacheBuster,
  });

  final int? productId;
  final String? pickedPhotoPath;
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
              .addPhoto(file.path);
          if (mounted) setState(() => _uploadDone++);
        } on DioException {
          failed++;
        } catch (_) {
          failed++;
        }
      }
      if (mounted) {
        final added = files.length - failed;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failed == 0
                  ? (added == 1 ? VN.catalogPhotoAdded : 'Đã thêm $added ảnh mẫu')
                  : 'Đã thêm $added ảnh, $failed ảnh lỗi',
            ),
          ),
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
            .addPhoto(file.path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(VN.catalogPhotoAdded)),
          );
        }
      } on DioException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? VN.apiError)),
          );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(VN.catalogPhotoDeleted)),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? VN.apiError)),
        );
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
              if (_uploading) ...[
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
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.grey),
                  ),
                ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
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
                    url: url,
                    onTap: () => _openFullScreen(photos, index, baseUrl),
                    onDelete: () => _confirmDelete(photo),
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
    required this.url,
    required this.onTap,
    required this.onDelete,
  });

  final String url;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
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
            Positioned(
              top: 4,
              right: 4,
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
          ],
        ),
      ),
    );
  }
}
