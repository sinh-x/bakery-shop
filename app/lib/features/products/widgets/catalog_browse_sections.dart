import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/catalog_browse_photo.dart';
import '../../../data/models/catalog_tag.dart';
import '../../../data/models/category.dart' as models;
import '../../../providers/categories_provider.dart';
import '../../../shared/labels/products.dart';
import 'catalog_photo_browse_card.dart';

class CatalogBrowseBulkActions extends StatelessWidget {
  const CatalogBrowseBulkActions({
    super.key,
    required this.selectMode,
    required this.bulkInProgress,
    required this.hasSelection,
    required this.onEnterSelectMode,
    required this.onSelectAll,
    required this.onShare,
    required this.onDownload,
    required this.onClearSelection,
  });

  final bool selectMode;
  final bool bulkInProgress;
  final bool hasSelection;
  final VoidCallback onEnterSelectMode;
  final VoidCallback onSelectAll;
  final VoidCallback onShare;
  final VoidCallback onDownload;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    if (!selectMode) {
      return [
        IconButton(
          icon: const Icon(Icons.check_circle),
          onPressed: onEnterSelectMode,
          tooltip: VN.chonAnh,
        ),
      ].first;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.select_all),
          onPressed: onSelectAll,
          tooltip: VN.chon20,
        ),
        if (bulkInProgress)
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
            onPressed: hasSelection ? onShare : null,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: hasSelection ? onDownload : null,
          ),
        ],
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: onClearSelection,
          tooltip: VN.huy,
        ),
      ],
    );
  }
}

class CatalogBrowsePhotoGrid extends StatelessWidget {
  const CatalogBrowsePhotoGrid({
    super.key,
    required this.photos,
    required this.baseUrl,
    required this.selectedPhotoIds,
    required this.selectMode,
    required this.onPhotoToggle,
    required this.onRefresh,
    required this.emptyMessage,
  });

  final List<CatalogBrowsePhoto> photos;
  final String baseUrl;
  final Set<int> selectedPhotoIds;
  final bool selectMode;
  final Future<void> Function() onRefresh;
  final void Function(int photoId, bool selected) onPhotoToggle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return Center(
        child: Text(
          emptyMessage,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.75,
        ),
        itemCount: photos.length,
        itemBuilder: (context, index) {
          final photo = photos[index];
          final isSelected = selectedPhotoIds.contains(photo.id);
          return CatalogPhotoBrowseCard(
            photo: photo,
            baseUrl: baseUrl,
            selected: isSelected,
            onSelectToggle: selectMode ? (sel) => onPhotoToggle(photo.id, sel) : null,
          );
        },
      ),
    );
  }
}

class CatalogBrowseFilterBar extends ConsumerWidget {
  const CatalogBrowseFilterBar({
    super.key,
    required this.tagDefs,
    required this.selectedTags,
    required this.selectedCategories,
    required this.onTagToggle,
    required this.onCategoryToggle,
    required this.onClearAll,
  });

  final List<CatalogTagDef> tagDefs;
  final Set<String> selectedTags;
  final Set<String> selectedCategories;
  final void Function(String tag) onTagToggle;
  final void Function(String slug) onCategoryToggle;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audience = tagDefs.where((t) => t.category == 'audience').toList();
    final occasion = tagDefs.where((t) => t.category == 'occasion').toList();
    final style = tagDefs.where((t) => t.category == 'style').toList();
    final categoriesAsync = ref.watch(categoriesProvider);
    final hasSelection = selectedTags.isNotEmpty || selectedCategories.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          categoriesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (categories) {
              final active = categories.where((c) => c.active != 0).toList()
                ..sort((a, b) => a.position.compareTo(b.position));
              if (active.isEmpty) return const SizedBox.shrink();
              return _CatalogFilterRow(
                label: VN.danhMuc,
                categories: active,
                selectedCategories: selectedCategories,
                onCategoryToggle: onCategoryToggle,
              );
            },
          ),
          _CatalogFilterRow(
            label: VN.doiTuong,
            tagDefs: audience,
            selectedTags: selectedTags,
            onTagToggle: onTagToggle,
          ),
          _CatalogFilterRow(
            label: VN.dip,
            tagDefs: occasion,
            selectedTags: selectedTags,
            onTagToggle: onTagToggle,
          ),
          _CatalogFilterRow(
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

class _CatalogFilterRow extends StatelessWidget {
  const _CatalogFilterRow({
    required this.label,
    this.tagDefs,
    this.selectedTags,
    this.onTagToggle,
    this.showClear = false,
    this.onClearAll,
    this.categories,
    this.selectedCategories,
    this.onCategoryToggle,
  });

  final String label;
  final List<CatalogTagDef>? tagDefs;
  final Set<String>? selectedTags;
  final void Function(String tag)? onTagToggle;
  final bool showClear;
  final VoidCallback? onClearAll;
  final List<models.Category>? categories;
  final Set<String>? selectedCategories;
  final void Function(String slug)? onCategoryToggle;

  static const _labelWidth = 80.0;

  @override
  Widget build(BuildContext context) {
    if (categories != null && categories!.isNotEmpty) {
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
                child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
            ...categories!.map(
              (c) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text('${c.icon.isNotEmpty ? c.icon : '📦'} ${c.name}', style: const TextStyle(fontSize: 12)),
                  selected: selectedCategories!.contains(c.slug),
                  onSelected: (_) => onCategoryToggle!(c.slug),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (tagDefs == null || tagDefs!.isEmpty) return const SizedBox.shrink();

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
              child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
          ...tagDefs!.map(
            (t) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(t.label, style: const TextStyle(fontSize: 12)),
                selected: selectedTags!.contains(t.key),
                onSelected: (_) => onTagToggle!(t.key),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          if (showClear && onClearAll != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: const Text(VN.xoaLoc, style: TextStyle(fontSize: 12)),
                onSelected: (_) => onClearAll!(),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}
