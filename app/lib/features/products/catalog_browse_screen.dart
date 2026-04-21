import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../data/models/catalog_tag.dart';
import '../../providers/catalog_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';
import 'services/bulk_share_service.dart';
import 'services/bulk_download_android.dart'
    if (kIsWeb) 'services/bulk_download_web.dart' as download_impl;
import 'widgets/catalog_photo_browse_card.dart';

class CatalogBrowseScreen extends ConsumerStatefulWidget {
  const CatalogBrowseScreen({super.key});

  @override
  ConsumerState<CatalogBrowseScreen> createState() =>
      _CatalogBrowseScreenState();
}

class _CatalogBrowseScreenState extends ConsumerState<CatalogBrowseScreen> {
  final Set<String> _selectedTags = {};
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
    final sorted = _selectedTags.toList()..sort();
    return sorted.join('|');
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
    final selectedPhotos =
        photos.where((p) => _selectedPhotoIds.contains(p.id)).toList();
    if (selectedPhotos.isEmpty) return;

    setState(() => _bulkInProgress = true);
    try {
      final dio = ref.read(dioProvider);
      final service = BulkShareService(dio);
      final result = await service.share(selectedPhotos);
      final resultStr = result.failCount == 0
          ? 'Đã chia sẻ ${result.successCount} ảnh'
          : 'Đã chia sẻ ${result.successCount}/${selectedPhotos.length} ảnh';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resultStr)),
        );
      }
    } finally {
      setState(() => _bulkInProgress = false);
    }
  }

  Future<void> _onBulkDownload() async {
    final photos = ref.read(catalogBrowseProvider(_filterKey)).value;
    if (photos == null) return;
    final selectedPhotos =
        photos.where((p) => _selectedPhotoIds.contains(p.id)).toList();
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
          SnackBar(content: Text(resultStr)),
        );
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

  void _selectAll20(List photos) {
    final count = photos.length >= 20 ? 20 : photos.length;
    setState(() {
      _selectedPhotoIds = photos
          .take(count)
          .map((p) => p.id as int)
          .toSet();
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
            if (_selectMode) ...[
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
              if (_bulkInProgress)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: _selectedPhotoIds.isEmpty ? null : _onBulkShare,
                ),
                IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: _selectedPhotoIds.isEmpty ? null : _onBulkDownload,
                ),
              ],
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
                tooltip: VN.huy,
              ),
            ],
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
              error: (err, stack) => const SizedBox(height: 120),
              data: (tagDefs) => _TagFilterBar(
                tagDefs: tagDefs,
                selectedTags: _selectedTags,
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
                onClearAll: () {
                  setState(() {
                    _selectedTags.clear();
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
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(VN.apiError),
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
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Colors.grey,
                            ),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () => ref
                        .read(catalogBrowseProvider(_filterKey).notifier)
                        .refresh(),
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: photos.length,
                      itemBuilder: (context, index) {
                        final photo = photos[index];
                        final isSelected = _selectedPhotoIds.contains(photo.id);
                        return CatalogPhotoBrowseCard(
                          photo: photo,
                          baseUrl: baseUrl,
                          selected: isSelected,
                          onSelectToggle: _selectMode
                              ? (sel) => _onPhotoToggle(photo.id, sel)
                              : null,
                        );
                      },
                    ),
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

class _TagFilterBar extends StatelessWidget {
  const _TagFilterBar({
    required this.tagDefs,
    required this.selectedTags,
    required this.onTagToggle,
    required this.onClearAll,
  });

  final List<CatalogTagDef> tagDefs;
  final Set<String> selectedTags;
  final void Function(String tag) onTagToggle;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final audience = tagDefs.where((t) => t.category == 'audience').toList();
    final occasion = tagDefs.where((t) => t.category == 'occasion').toList();
    final style = tagDefs.where((t) => t.category == 'style').toList();
    final hasSelection = selectedTags.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FilterRow(
            label: VN.doiTuong,
            tagDefs: audience,
            selectedTags: selectedTags,
            onTagToggle: onTagToggle,
          ),
          _FilterRow(
            label: VN.dip,
            tagDefs: occasion,
            selectedTags: selectedTags,
            onTagToggle: onTagToggle,
          ),
          _FilterRow(
            label: VN.phongCach,
            tagDefs: style,
            selectedTags: selectedTags,
            onTagToggle: onTagToggle,
            showClear: hasSelection,
            onClearAll: onClearAll,
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.label,
    required this.tagDefs,
    required this.selectedTags,
    required this.onTagToggle,
    this.showClear = false,
    this.onClearAll,
  });

  final String label;
  final List<CatalogTagDef> tagDefs;
  final Set<String> selectedTags;
  final void Function(String tag) onTagToggle;
  final bool showClear;
  final VoidCallback? onClearAll;

  static const _labelWidth = 80.0;

  @override
  Widget build(BuildContext context) {
    if (tagDefs.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          SizedBox(
            width: _labelWidth,
            child: Padding(
              padding: const EdgeInsets.only(right: 6, top: 6),
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          ...tagDefs.map((t) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(t.label, style: const TextStyle(fontSize: 12)),
                  selected: selectedTags.contains(t.key),
                  onSelected: (_) => onTagToggle(t.key),
                  visualDensity: VisualDensity.compact,
                ),
              )),
          if (showClear && onClearAll != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(VN.xoaLoc, style: const TextStyle(fontSize: 12)),
                onSelected: (_) => onClearAll!(),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}