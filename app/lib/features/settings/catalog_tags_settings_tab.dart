import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/catalog_tag.dart';
import '../../providers/catalog_provider.dart';
import '../../shared/labels/shared.dart';

class CatalogTagsSettingsTab extends ConsumerWidget {
  const CatalogTagsSettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(catalogTagDefsProvider);

    return Scaffold(
      body: tagsAsync.when(
        data: (tags) => _TagList(tags: tags),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text('Error: $err'),
        ),
      ),
    );
  }
}

class _TagList extends StatelessWidget {
  const _TagList({required this.tags});

  final List<CatalogTagDef> tags;

  @override
  Widget build(BuildContext context) {
    // Group tags by category in fixed order: Đối tượng → Dịp → Phong cách
    final objectTags = <CatalogTagDef>[];
    final occasionTags = <CatalogTagDef>[];
    final styleTags = <CatalogTagDef>[];

    for (final tag in tags) {
      switch (tag.category) {
        case 'doi_tuong':
          objectTags.add(tag);
        case 'dip':
          occasionTags.add(tag);
        case 'phong_cach':
          styleTags.add(tag);
      }
    }

    // Sort each group alphabetically by label
    objectTags.sort((a, b) => a.label.compareTo(b.label));
    occasionTags.sort((a, b) => a.label.compareTo(b.label));
    styleTags.sort((a, b) => a.label.compareTo(b.label));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Group: Đối tượng
        _TagGroup(
          category: 'doi_tuong',
          tags: objectTags,
        ),
        const SizedBox(height: 24),

        // Group: Dịp
        _TagGroup(
          category: 'dip',
          tags: occasionTags,
        ),
        const SizedBox(height: 24),

        // Group: Phong cách
        _TagGroup(
          category: 'phong_cach',
          tags: styleTags,
        ),
      ],
    );
  }
}

class _TagGroup extends StatelessWidget {
  const _TagGroup({required this.category, required this.tags});

  final String category;
  final List<CatalogTagDef> tags;

  String _getCategoryLabel() {
    switch (category) {
      case 'doi_tuong':
        return VN.doiTuong;
      case 'dip':
        return VN.dip;
      case 'phong_cach':
        return VN.phongCach;
      default:
        return category;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group header with category label and count
        Row(
          children: [
            Text(
              _getCategoryLabel(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${tags.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Tag list or placeholder
        if (tags.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              VN.noTagsInCategory,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          )
        else
          ...[
            for (final tag in tags)
              _TagRow(tag: tag),
          ],
      ],
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({required this.tag});

  final CatalogTagDef tag;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // Coloured chip preview
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _getColor(tag.category),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              tag.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Key text in monospace
          Expanded(
            child: Text(
              tag.key,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Edit button
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            onPressed: () {
              // TODO: Implement edit functionality in Phase 4.3
            },
          ),

          // Delete button
          IconButton(
            icon: const Icon(Icons.delete, size: 20),
            onPressed: () {
              // TODO: Implement delete functionality in Phase 4.3
            },
          ),
        ],
      ),
    );
  }

  Color _getColor(String category) {
    switch (category) {
      case 'doi_tuong': // audience
        return const Color(0xFF2196F3);
      case 'dip': // occasion
        return const Color(0xFFFF9800);
      case 'phong_cach': // style
        return const Color(0xFF4CAF50);
      default:
        return Colors.grey.shade300;
    }
  }
}