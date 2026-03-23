import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/catalog_photo.dart';
import '../../../providers/catalog_provider.dart';
import '../../../shared/widgets/vietnamese_labels.dart';

/// Full-screen swipeable photo viewer for catalog photos.
///
/// Receives the initial photo list and index from the gallery grid.
/// Watches [catalogProvider] so caption edits are reflected immediately.
class CatalogPhotoViewer extends ConsumerStatefulWidget {
  const CatalogPhotoViewer({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.productId,
    required this.baseUrl,
  });

  final List<CatalogPhoto> photos;
  final int initialIndex;
  final int productId;
  final String baseUrl;

  @override
  ConsumerState<CatalogPhotoViewer> createState() =>
      _CatalogPhotoViewerState();
}

class _CatalogPhotoViewerState extends ConsumerState<CatalogPhotoViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openEditSheet(CatalogPhoto photo) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EditCaptionSheet(
        photo: photo,
        productId: widget.productId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(catalogProvider(widget.productId));
    final photos = catalogAsync.value ?? widget.photos;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: photos.isEmpty
            ? null
            : Text(
                '${_currentIndex + 1} / ${photos.length}',
                style: const TextStyle(color: Colors.white),
              ),
        actions: [
          if (photos.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.white),
              tooltip: VN.editCatalogPhoto,
              onPressed: () {
                if (_currentIndex < photos.length) {
                  _openEditSheet(photos[_currentIndex]);
                }
              },
            ),
        ],
      ),
      body: photos.isEmpty
          ? const Center(
              child: Icon(
                Icons.photo_library_outlined,
                color: Colors.white38,
                size: 64,
              ),
            )
          : PageView.builder(
              controller: _pageController,
              itemCount: photos.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
              },
              itemBuilder: (ctx, index) {
                final photo = photos[index];
                final url =
                    '${widget.baseUrl}/api/products/${widget.productId}/catalog/${photo.id}/photo';
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    InteractiveViewer(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        errorBuilder: (_, e, s) => const Center(
                          child: Icon(
                            Icons.broken_image,
                            color: Colors.white54,
                            size: 64,
                          ),
                        ),
                      ),
                    ),
                    if (photo.caption.isNotEmpty || photo.tags.isNotEmpty)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Colors.black87, Colors.transparent],
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (photo.caption.isNotEmpty)
                                Text(
                                  photo.caption,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                  ),
                                ),
                              if (photo.tags.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  photo.tags,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit caption / tags bottom sheet
// ---------------------------------------------------------------------------

class _EditCaptionSheet extends ConsumerStatefulWidget {
  const _EditCaptionSheet({required this.photo, required this.productId});

  final CatalogPhoto photo;
  final int productId;

  @override
  ConsumerState<_EditCaptionSheet> createState() => _EditCaptionSheetState();
}

class _EditCaptionSheetState extends ConsumerState<_EditCaptionSheet> {
  late final TextEditingController _captionCtrl;
  late final TextEditingController _tagsCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _captionCtrl = TextEditingController(text: widget.photo.caption);
    _tagsCtrl = TextEditingController(text: widget.photo.tags);
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(catalogProvider(widget.productId).notifier)
          .updatePhoto(
            widget.photo.id,
            caption: _captionCtrl.text.trim(),
            tags: _tagsCtrl.text.trim(),
          );
      if (mounted) {
        Navigator.pop(context);
        showTopSnackBar(context, VN.catalogPhotoUpdated);
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
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            VN.editCatalogPhoto,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _captionCtrl,
            decoration: const InputDecoration(labelText: VN.captionLabel),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tagsCtrl,
            decoration: const InputDecoration(
              labelText: VN.tagsLabel,
              hintText: VN.tagsHint,
            ),
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
