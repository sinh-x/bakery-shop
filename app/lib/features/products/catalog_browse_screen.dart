// DG-150 Phase 4 temporary exemption: screen coordinator remains above 300 lines due to in-place bulk action flow wiring; review in Phase 5 (2026-05-29).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../data/providers/catalog_provider.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'providers/catalog_browse_notifier.dart';
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
  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _onBulkShare() async {
    final browseState = ref.read(catalogBrowseNotifierProvider);
    final photos = ref
        .read(catalogBrowseProvider(browseState.filterKey))
        .value;
    if (photos == null) return;
    final selectedPhotos = photos
        .where((p) => browseState.selectedPhotoIds.contains(p.id))
        .toList();
    if (selectedPhotos.isEmpty) return;

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
      if (mounted) {
        ref.read(catalogBrowseNotifierProvider.notifier).setBulkInProgress(false);
      }
    }
  }

  Future<void> _onBulkDownload() async {
    final browseState = ref.read(catalogBrowseNotifierProvider);
    final photos = ref
        .read(catalogBrowseProvider(browseState.filterKey))
        .value;
    if (photos == null) return;
    final selectedPhotos = photos
        .where((p) => browseState.selectedPhotoIds.contains(p.id))
        .toList();
    if (selectedPhotos.isEmpty) return;

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
      if (mounted) {
        ref.read(catalogBrowseNotifierProvider.notifier).setBulkInProgress(false);
      }
    }
  }

  void _onPhotoToggle(int photoId, bool selected) {
    final notifier = ref.read(catalogBrowseNotifierProvider.notifier);
    final browseState = ref.read(catalogBrowseNotifierProvider);
    if (selected && browseState.selectedPhotoIds.length >= 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(SharedLabels.toiDa20Anh),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    notifier.onPhotoToggle(photoId, selected);
  }

  Future<void> _onSelectModeMenuSelected(String value) async {
    final notifier = ref.read(catalogBrowseNotifierProvider.notifier);
    final browseState = ref.read(catalogBrowseNotifierProvider);
    switch (value) {
      case 'bulk_share':
        if (browseState.selectedPhotoIds.isNotEmpty &&
            !browseState.bulkInProgress) {
          notifier.setBulkInProgress(true);
          await _onBulkShare();
        }
        return;
      case 'bulk_download':
        if (browseState.selectedPhotoIds.isNotEmpty &&
            !browseState.bulkInProgress) {
          notifier.setBulkInProgress(true);
          await _onBulkDownload();
        }
        return;
      case 'cancel_selection':
        notifier.clearSelection();
        return;
      default:
        assert(() {
          debugPrint('Unknown catalog browse menu action: $value');
          return true;
        }());
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final tagDefsAsync = ref.watch(catalogTagDefsProvider);
    final browseState = ref.watch(catalogBrowseNotifierProvider);
    final notifier = ref.read(catalogBrowseNotifierProvider.notifier);
    final photosAsync =
        ref.watch(catalogBrowseProvider(browseState.filterKey));

    return PopScope(
      canPop: !browseState.selectMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && browseState.selectMode) {
          notifier.clearSelection();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            browseState.selectMode
                ? '${browseState.selectedPhotoIds.length} ${SharedLabels.daChon}'
                : ProductsLabels.browseScreenTitle,
          ),
          leading: browseState.selectMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: notifier.clearSelection,
                )
              : null,
          actions: [
            if (!browseState.selectMode)
              IconButton(
                icon: const Icon(Icons.check_circle),
                onPressed: notifier.toggleSelectMode,
                tooltip: SharedLabels.chonAnh,
              ),
            if (!browseState.selectMode) const AppBarOverflowMenu(),
            if (browseState.selectMode)
              IconButton(
                icon: const Icon(Icons.select_all),
                onPressed: () {
                  final photos = photosAsync.value;
                  if (photos != null) {
                    notifier.selectAll20(photos);
                  }
                },
                tooltip: SharedLabels.chon20,
              ),
            if (browseState.selectMode && browseState.bulkInProgress)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (browseState.selectMode)
              AppBarOverflowMenu(
                onSelected: _onSelectModeMenuSelected,
                items: [
                  PopupMenuItem<String>(
                    value: 'bulk_share',
                    enabled: browseState.selectedPhotoIds.isNotEmpty &&
                        !browseState.bulkInProgress,
                    child: const Text(ProductsLabels.chiaSe),
                  ),
                  PopupMenuItem<String>(
                    value: 'bulk_download',
                    enabled: browseState.selectedPhotoIds.isNotEmpty &&
                        !browseState.bulkInProgress,
                    child: const Text(ProductsLabels.taiAnh),
                  ),
                  const PopupMenuItem<String>(
                    value: 'cancel_selection',
                    child: Text(SharedLabels.huy),
                  ),
                ],
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
                      const Text(ProductsLabels.catalogFilterLoadError),
                      const SizedBox(height: 6),
                      FilledButton.tonal(
                        onPressed: () => ref.invalidate(catalogTagDefsProvider),
                        child: const Text(OrdersLabels.taiLai),
                      ),
                    ],
                  ),
                ),
              ),
              data: (tagDefs) => CatalogBrowseFilterBar(
                tagDefs: tagDefs,
                selectedTags: browseState.selectedTags,
                selectedCategories: browseState.selectedCategorySlugs,
                onTagToggle: notifier.toggleTag,
                onCategoryToggle: notifier.toggleCategory,
                onClearAll: notifier.clearAll,
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
                      const Text(SharedLabels.apiError),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () => ref.invalidate(
                          catalogBrowseProvider(browseState.filterKey),
                        ),
                        child: const Text(SharedLabels.retry),
                      ),
                    ],
                  ),
                ),
                data: (photos) {
                  if (photos.isEmpty) {
                    final msg = browseState.selectedTags.isEmpty
                        ? ProductsLabels.noBrowsePhotos
                        : ProductsLabels.noBrowsePhotosForFilter;
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
                    selectedPhotoIds: browseState.selectedPhotoIds,
                    selectMode: browseState.selectMode,
                    onPhotoToggle: _onPhotoToggle,
                    onRefresh: () => ref
                        .read(catalogBrowseProvider(browseState.filterKey).notifier)
                        .refresh(),
                    emptyMessage: browseState.selectedTags.isEmpty
                        ? ProductsLabels.noBrowsePhotos
                        : ProductsLabels.noBrowsePhotosForFilter,
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
