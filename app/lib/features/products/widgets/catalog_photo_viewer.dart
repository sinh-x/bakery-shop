import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/api/api_client.dart';
import '../../../data/models/catalog_photo.dart';
import '../../../data/models/catalog_tag.dart';
import '../../../providers/catalog_provider.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'catalog_tag_chips.dart';
import 'catalog_tag_edit_sheet.dart';

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
  bool _downloading = false;
  bool _sharing = false;

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

  Future<void> _downloadPhoto(List<CatalogPhoto> photos) async {
    if (_downloading || _currentIndex >= photos.length) return;
    setState(() => _downloading = true);
    final photo = photos[_currentIndex];
    final url =
        '${widget.baseUrl}/api/products/${widget.productId}/catalog/${photo.id}/photo';
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (resp.data == null) throw Exception('No data');
      await Gal.putImageBytes(Uint8List.fromList(resp.data!));
      if (mounted) showTopSnackBar(context, VN.daLuuAnh);
    } catch (e) {
      if (mounted) showTopSnackBar(context, VN.khongTheTaiAnh);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _sharePhoto(List<CatalogPhoto> photos) async {
    if (_sharing || _currentIndex >= photos.length) return;
    setState(() => _sharing = true);
    final photo = photos[_currentIndex];
    final url =
        '${widget.baseUrl}/api/products/${widget.productId}/catalog/${photo.id}/photo';
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (resp.data == null) throw Exception('No data');
      final tmpDir = await getTemporaryDirectory();
      final tmpFile = File('${tmpDir.path}/catalog_photo_${photo.id}.jpg');
      await tmpFile.writeAsBytes(Uint8List.fromList(resp.data!));
      await Share.shareXFiles(
        [XFile(tmpFile.path)],
        text: 'Tiệm Bánh Ninh Diêm',
      );
    } catch (e) {
      if (mounted) showTopSnackBar(context, VN.khongTheChiaSe);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _openEditSheet(CatalogPhoto photo) {
    showEditCatalogTagsSheet(
      context: context,
      photo: photo,
      productId: widget.productId,
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
          if (photos.isNotEmpty) ...[
            IconButton(
              icon: _downloading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download, color: Colors.white),
              tooltip: VN.taiAnh,
              onPressed: _downloading ? null : () => _downloadPhoto(photos),
            ),
            IconButton(
              icon: _sharing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.share, color: Colors.white),
              tooltip: VN.chiaSe,
              onPressed: _sharing ? null : () => _sharePhoto(photos),
            ),
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
                                CatalogTagChips(tags: photo.tags),
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
  final Set<String> _selectedTags = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _captionCtrl = TextEditingController(text: widget.photo.caption);
    if (widget.photo.tags.isNotEmpty) {
      _selectedTags.addAll(
        widget.photo.tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty),
      );
    }
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
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
            tags: _selectedTags.join(','),
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
    final tagDefsAsync = ref.watch(catalogTagDefsProvider);

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
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              VN.tagsLabel,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          tagDefsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Row(
              children: [
                const Expanded(child: Text(VN.apiError)),
                TextButton.icon(
                  onPressed: () =>
                      ref.read(catalogTagDefsProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh),
                  label: const Text(VN.retry),
                ),
              ],
            ),
            data: (tagDefs) => _TagChipSelector(
              tagDefs: tagDefs,
              selectedTags: _selectedTags,
              onToggle: (tag) {
                setState(() {
                  if (_selectedTags.contains(tag)) {
                    _selectedTags.remove(tag);
                  } else {
                    _selectedTags.add(tag);
                  }
                });
              },
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

class _TagChipSelector extends StatelessWidget {
  const _TagChipSelector({
    required this.tagDefs,
    required this.selectedTags,
    required this.onToggle,
  });

  final List<CatalogTagDef> tagDefs;
  final Set<String> selectedTags;
  final void Function(String tag) onToggle;

  @override
  Widget build(BuildContext context) {
    final audience = tagDefs.where((t) => t.category == 'audience').toList();
    final occasion = tagDefs.where((t) => t.category == 'occasion').toList();
    final style = tagDefs.where((t) => t.category == 'style').toList();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (audience.isNotEmpty) ...[
          const Text(VN.doiTuong, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          ...audience.map((t) => FilterChip(
                label: Text(t.label, style: const TextStyle(fontSize: 12)),
                selected: selectedTags.contains(t.key),
                onSelected: (_) => onToggle(t.key),
                visualDensity: VisualDensity.compact,
              )),
        ],
        if (occasion.isNotEmpty) ...[
          const Text(VN.dip, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          ...occasion.map((t) => FilterChip(
                label: Text(t.label, style: const TextStyle(fontSize: 12)),
                selected: selectedTags.contains(t.key),
                onSelected: (_) => onToggle(t.key),
                visualDensity: VisualDensity.compact,
              )),
        ],
        if (style.isNotEmpty) ...[
          const Text(VN.phongCach, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          ...style.map((t) => FilterChip(
                label: Text(t.label, style: const TextStyle(fontSize: 12)),
                selected: selectedTags.contains(t.key),
                onSelected: (_) => onToggle(t.key),
                visualDensity: VisualDensity.compact,
              )),
        ],
      ],
    );
  }
}
