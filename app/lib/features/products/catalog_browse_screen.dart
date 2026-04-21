import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../providers/catalog_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';
import 'widgets/catalog_photo_browse_card.dart';

class CatalogBrowseScreen extends ConsumerStatefulWidget {
  const CatalogBrowseScreen({super.key});

  @override
  ConsumerState<CatalogBrowseScreen> createState() =>
      _CatalogBrowseScreenState();
}

class _CatalogBrowseScreenState extends ConsumerState<CatalogBrowseScreen> {
  final Set<String> _selectedTags = {};

  @override
  Widget build(BuildContext context) {
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final tagDefsAsync = ref.watch(catalogTagDefsProvider);
    final browseParams = (tags: _selectedTags.toList(), page: 1);
    final photosAsync = ref.watch(catalogBrowseProvider(browseParams));

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.browseScreenTitle),
      ),
      body: Column(
        children: [
          // Tag filter bar
          tagDefsAsync.when(
            loading: () => const SizedBox(
              height: 56,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const SizedBox(height: 56),
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
                          ref.invalidate(catalogBrowseProvider(browseParams)),
                      child: const Text(VN.retry),
                    ),
                  ],
                ),
              ),
              data: (photos) {
                if (photos.isEmpty) {
                  return Center(
                    child: Text(
                      VN.noBrowsePhotos,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Colors.grey,
                          ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => ref
                      .read(catalogBrowseProvider(browseParams).notifier)
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
                    itemBuilder: (context, index) =>
                        CatalogPhotoBrowseCard(
                      photo: photos[index],
                      baseUrl: baseUrl,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TagFilterBar extends StatelessWidget {
  const _TagFilterBar({
    required this.tagDefs,
    required this.selectedTags,
    required this.onTagToggle,
  });

  final List tagDefs;
  final Set<String> selectedTags;
  final void Function(String tag) onTagToggle;

  @override
  Widget build(BuildContext context) {
    // Group by category
    final audience = tagDefs.where((t) => t.category == 'audience').toList();
    final occasion = tagDefs.where((t) => t.category == 'occasion').toList();
    final style = tagDefs.where((t) => t.category == 'style').toList();

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          if (audience.isNotEmpty) ..._buildGroup(VN.doiTuong, audience),
          if (occasion.isNotEmpty) ..._buildGroup(VN.dip, occasion),
          if (style.isNotEmpty) ..._buildGroup(VN.phongCach, style),
        ],
      ),
    );
  }

  List<Widget> _buildGroup(String label, List tagDefs) {
    return [
      Padding(
        padding: const EdgeInsets.only(right: 8, top: 4),
        child: Chip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          backgroundColor: Colors.grey.shade200,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
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
    ];
  }
}
