import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/catalog_tag.dart';
import 'tag_group.dart';
import '../../../shared/labels/shared.dart';

class TagList extends StatelessWidget {
  const TagList({required this.tags, required this.ref, super.key});

  final List<CatalogTagDef> tags;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    // Group tags by category in fixed order: Đối tượng → Dịp → Phong cách
    final objectTags = <CatalogTagDef>[];
    final occasionTags = <CatalogTagDef>[];
    final styleTags = <CatalogTagDef>[];

    for (final tag in tags) {
      switch (tag.category) {
        case VN.tagCategoriesDoiTuong:
          objectTags.add(tag);
        case VN.tagCategoriesDip:
          occasionTags.add(tag);
        case VN.tagCategoriesPhongCach:
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
        TagGroup(
          category: VN.tagCategoriesDoiTuong,
          tags: objectTags,
        ),
        const SizedBox(height: 24),

        // Group: Dịp
        TagGroup(
          category: VN.tagCategoriesDip,
          tags: occasionTags,
        ),
        const SizedBox(height: 24),

        // Group: Phong cách
        TagGroup(
          category: VN.tagCategoriesPhongCach,
          tags: styleTags,
        ),
      ],
    );
  }
}