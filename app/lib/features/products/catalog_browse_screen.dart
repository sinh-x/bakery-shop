// DG-150 Phase 4 temporary exemption: screen coordinator remains above 300 lines due to in-place bulk action flow wiring; review in Phase 5 (2026-05-29).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../data/models/catalog_browse_photo.dart';
import '../../providers/catalog_provider.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'services/bulk_share_service.dart';
import 'services/bulk_download_android.dart'
    if (kIsWeb) 'services/bulk_download_web.dart'
    as download_impl;
import 'widgets/catalog_browse_sections.dart';

class CatalogBrowseScreen extends ConsumerStatefulWidget {
  const CatalogBrowseScreen({super.key});

  @override
  ConsumerState<CatalogBrowseScreen> createState() =>
      _CatalogBrowseScreenState();
}

class _CatalogBrowseScreenState extends ConsumerState<CatalogBrowseScreen> {
  final Set<String> _selectedTags = {};
  final Set<String> _selectedCategorySlugs = {};
  String _filterKey = '';
  bool _selectMode = false;
  Set<int> _selectedPhotoIds = {};
  bool _bulkInProgress = false;

  @override
  void dispose() {
    _selectedPhotoIds.clear();
    super.dispose();
  }

  String _computeFilterKey() {
    final sortedTags = _selectedTags.toList()..sort();
    final sortedCats = _selectedCategorySlugs.toList()..sort();
    final tagPart = 'tags:${sortedTags.join('|')}';
    final catPart = 'cats:${sortedCats.join('|')}';
    return '$tagPart;$catPart';
  }

  void _clearSelection() {
    setState(() {
      _selectMode = false;
      _selectedPhotoIds.clear();
    });
  }

  Future<void> _onBulkShare() async {
    final photos = ref.read(catalogBrowseProvider(_filterKey)).value;
    if (photos == null) return;
    final selectedPhotos = photos
        .where((p) => _selectedPhotoIds.contains(p.id))
        .toList();
    if (selectedPhotos.isEmpty) return;

    setState(() => _bulkInProgress = true);
    try {
      final dio = ref.read(dioProvider);
      final service = BulkShareService(dio);
      final result = await service.share(selectedPhotos);
      final action = result.usedBrowserDownloadFallback
          ? 'Đã tải'
          : 'Đã chia sẻ';
      final resultStr = result.failCount == 0
          ? '$action ${result.successCount} ảnh'
          : '$action ${result.successCount}/${selectedPhotos.length} ảnh';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resultStr),
            duration: Duration(seconds: result.failCount == 0 ? 2 : 5),
          ),
        );
        if (result.failCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi: ${result.errors.first}'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } finally {
      setState(() => _bulkInProgress = false);
    }
  }

  Future<void> _onBulkDownload() async {
    final photos = ref.read(catalogBrowseProvider(_filterKey)).value;
    if (photos == null) return;
    final selectedPhotos = photos
        .where((p) => _selectedPhotoIds.contains(p.id))
        .toList();
    if (selectedPhotos.isEmpty) return;

    setState(() => _bulkInProgress = true);
    try {
      final dio = ref.read(dioProvider);
      final service = download_impl.BulkDownloadService(dio);
      final result = await service.download(selectedPhotos);
      final total = selectedPhotos.length;
      final resultStr = result.failCount == 0
          ? 'Đã lưu ${result.successCount}/$total ảnh'
          : 'Đã lưu ${result.successCount}/$total ảnh';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resultStr),
            duration: Duration(seconds: result.errors.isEmpty ? 2 : 5),
          ),
        );
        if (result.errors.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi: ${result.errors.first}'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } finally {
      setState(() => _bulkInProgress = false);
    }
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) {
        _selectedPhotoIds.clear();
      }
    });
  }

  void _selectAll20(List<CatalogBrowsePhoto> photos) {
    final count = photos.length >= 20 ? 20 : photos.length;
    setState(() {
      _selectedPhotoIds = photos.take(count).map((p) => p.id).toSet();
    });
  }

  void _onPhotoToggle(int photoId, bool selected) {
    setState(() {
      if (selected) {
        if (_selectedPhotoIds.length >= 20) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(VN.toiDa20Anh),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        _selectedPhotoIds.add(photoId);
      } else {
        _selectedPhotoIds.remove(photoId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final tagDefsAsync = ref.watch(catalogTagDefsProvider);
    final photosAsync = ref.watch(catalogBrowseProvider(_filterKey));

    return PopScope(
      canPop: !_selectMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectMode) {
          _clearSelection();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _selectMode
                ? '${_selectedPhotoIds.length} ${VN.daChon}'
                : VN.browseScreenTitle,
          ),
          leading: _selectMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _clearSelection,
                )
              : null,
          actions: [
            if (!_selectMode)
              IconButton(
                icon: const Icon(Icons.check_circle),
                onPressed: _toggleSelectMode,
                tooltip: VN.chonAnh,
              ),
            if (_selectMode)
              IconButton(
                icon: const Icon(Icons.select_all),
                onPressed: () {
                  final photos = photosAsync.value;
                  if (photos != null) {
                    _selectAll20(photos);
                  }
                },
                tooltip: VN.chon20,
              ),
            if (_selectMode && _bulkInProgress)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (_selectMode && !_bulkInProgress)
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: _selectedPhotoIds.isEmpty ? null : _onBulkShare,
              ),
            if (_selectMode && !_bulkInProgress)
              IconButton(
                icon: const Icon(Icons.download),
                onPressed: _selectedPhotoIds.isEmpty ? null : _onBulkDownload,
              ),
            if (_selectMode)
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
                tooltip: VN.huy,
              ),
          ],
        ),
        body: Column(
          children: [
            // Tag filter bar
            tagDefsAsync.when(
              loading: () => const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, stack) => SizedBox(
                height: 120,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(VN.catalogFilterLoadError),
                      const SizedBox(height: 6),
                      FilledButton.tonal(
                        onPressed: () => ref.invalidate(catalogTagDefsProvider),
                        child: const Text(VN.taiLai),
                      ),
                    ],
                  ),
                ),
              ),
              data: (tagDefs) => CatalogBrowseFilterBar(
                tagDefs: tagDefs,
                selectedTags: _selectedTags,
                selectedCategories: _selectedCategorySlugs,
                onTagToggle: (tag) {
                  setState(() {
                    if (_selectedTags.contains(tag)) {
                      _selectedTags.remove(tag);
                    } else {
                      _selectedTags.add(tag);
                    }
                    _filterKey = _computeFilterKey();
                    // Clear selection when tag filter changes
                    _selectedPhotoIds.clear();
                  });
                },
                onCategoryToggle: (slug) {
                  setState(() {
                    if (_selectedCategorySlugs.contains(slug)) {
                      _selectedCategorySlugs.remove(slug);
                    } else {
                      _selectedCategorySlugs.add(slug);
                    }
                    _filterKey = _computeFilterKey();
                    // Clear selection when category filter changes
                    _selectedPhotoIds.clear();
                  });
                },
                onClearAll: () {
                  setState(() {
                    _selectedTags.clear();
                    _selectedCategorySlugs.clear();
                    _filterKey = _computeFilterKey();
                    // Clear selection when tag filter changes
                    _selectedPhotoIds.clear();
                  });
                },
              ),
            ),
            // Photo grid
            Expanded(
              child: photosAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(VN.apiError),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () =>
                            ref.invalidate(catalogBrowseProvider(_filterKey)),
                        child: const Text(VN.retry),
                      ),
                    ],
                  ),
                ),
                data: (photos) {
                  if (photos.isEmpty) {
                    final msg = _selectedTags.isEmpty
                        ? VN.noBrowsePhotos
                        : VN.noBrowsePhotosForFilter;
                    return Center(
                      child: Text(
                        msg,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                      ),
                    );
                  }
                  return CatalogBrowsePhotoGrid(
                    photos: photos,
                    baseUrl: baseUrl,
                    selectedPhotoIds: _selectedPhotoIds,
                    selectMode: _selectMode,
                    onPhotoToggle: _onPhotoToggle,
                    onRefresh: () => ref
                        .read(catalogBrowseProvider(_filterKey).notifier)
                        .refresh(),
                    emptyMessage: _selectedTags.isEmpty
                        ? VN.noBrowsePhotos
                        : VN.noBrowsePhotosForFilter,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
