import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/api/api_client.dart';
import '../../../data/models/catalog_photo.dart';
import '../../../data/providers/catalog_provider.dart';
import '../../../providers/photo_upload_provider.dart';
import '../../../shared/widgets/upload_progress_indicator.dart';
import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:bakery_app/shared/labels/products.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import '../providers/catalog_gallery_notifier.dart';
import 'add_photo_card.dart';
import 'catalog_photo_card.dart';
import 'catalog_photo_viewer.dart';

/// Catalog gallery section of the product form.
///
/// Loads and renders the multi-photo catalog for an existing product,
/// supporting add (camera/gallery, multi-select), delete, promote to
/// product main photo, and full-screen viewing. Upload progress is
/// surfaced via [UploadProgressIndicator].
///
/// Extracted from `product_form_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CatalogGallerySection extends ConsumerStatefulWidget {
  const CatalogGallerySection({super.key, required this.productId});

  final int productId;

  @override
  ConsumerState<CatalogGallerySection> createState() =>
      _CatalogGallerySectionState();
}

class _CatalogGallerySectionState extends ConsumerState<CatalogGallerySection> {
  Future<void> _pickAndUpload() async {
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
    final catalogNotifier = ref.read(
      catalogProvider(widget.productId).notifier,
    );
    final upload = ref.read(photoUploadNotifierProvider.notifier);
    upload.reset();

    if (source == ImageSource.gallery) {
      // Multi-select from gallery
      final files = await picker.pickMultiImage();
      if (files.isEmpty) return;

      await upload.uploadAll(
        files,
        catalogNotifier.addPhoto,
      );
      if (!mounted) return;
      final batch = ref.read(photoUploadNotifierProvider);
      final added = batch.completedCount;
      final failed = batch.failedCount;
      showTopSnackBar(
        context,
        failed == 0
            ? (added == 1 ? ProductsLabels.catalogPhotoAdded : 'Đã thêm $added ảnh mẫu')
            : 'Đã thêm $added ảnh, $failed ảnh lỗi',
      );
    } else {
      // Camera: single photo only
      final file = await picker.pickImage(source: source);
      if (file == null) return;

      await upload.uploadAll(
        [file],
        catalogNotifier.addPhoto,
      );
      if (!mounted) return;
      final batch = ref.read(photoUploadNotifierProvider);
      if (batch.hasErrors) {
        final err = batch.items.firstWhere(
          (i) => i.state.status == PhotoUploadStatus.error,
          orElse: () => batch.items.first,
        );
        showTopSnackBar(context, err.state.errorMessage ?? SharedLabels.apiError);
      } else {
        showTopSnackBar(context, ProductsLabels.catalogPhotoAdded);
      }
    }
  }

  Future<void> _confirmDelete(CatalogPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(ProductsLabels.deleteCatalogPhoto),
        content: const Text(ProductsLabels.deleteCatalogConfirm),
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

    try {
      await ref
          .read(catalogProvider(widget.productId).notifier)
          .deletePhoto(photo.id);
      if (mounted) {
        showTopSnackBar(context, ProductsLabels.catalogPhotoDeleted);
      }
    } on DioException catch (e) {
      if (mounted) {
        showTopSnackBar(context, e.message ?? SharedLabels.apiError);
      }
    }
  }

  Future<void> _promotePhoto(CatalogPhoto photo) async {
    final galleryNotifier =
        ref.read(catalogGalleryProvider(widget.productId).notifier);
    galleryNotifier.setPromoting(true);
    try {
      await ref
          .read(catalogProvider(widget.productId).notifier)
          .promotePhotoToProductMain(photo.id);
      if (mounted) {
        showTopSnackBar(context, ProductsLabels.productPhotoSetFromCatalog);
      }
    } on DioException catch (e) {
      if (mounted) {
        showTopSnackBar(context, e.message ?? SharedLabels.apiError);
      }
    } finally {
      if (mounted) {
        galleryNotifier.setPromoting(false);
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
    final uploadState = ref.watch(photoUploadNotifierProvider);
    final galleryState = ref.watch(catalogGalleryProvider(widget.productId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text(ProductsLabels.catalogTitle, style: theme.textTheme.titleMedium),
              if (galleryState.promoting) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),
        UploadProgressIndicator(states: uploadState.states),
        catalogAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Text(
            SharedLabels.errorLoading,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          data: (photos) => Column(
            children: [
              if (photos.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    ProductsLabels.noCatalogPhotos,
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
                    return AddPhotoCard(
                      uploading: uploadState.isUploading,
                      onTap: _pickAndUpload,
                    );
                  }
                  final photo = photos[index];
                  final url =
                      '$baseUrl/api/products/${widget.productId}/catalog/${photo.id}/photo';
                  return CatalogPhotoCard(
                    photo: photo,
                    productId: widget.productId,
                    url: url,
                    onTap: () => _openFullScreen(photos, index, baseUrl),
                    onDelete: () => _confirmDelete(photo),
                    onPromote: () => _promotePhoto(photo),
                    promoting: galleryState.promoting,
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