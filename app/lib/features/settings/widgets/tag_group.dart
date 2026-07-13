import 'package:flutter/material.dart';

import '../../../shared/labels/shared.dart';
import '../../../data/models/catalog_tag.dart';
import 'tag_row.dart';

class TagGroup extends StatelessWidget {
  const TagGroup({required this.category, required this.tags, super.key});

  final String category;
  final List<CatalogTagDef> tags;

  String _getCategoryLabel() {
    switch (category) {
      case VN.tagCategoriesDoiTuong:
        return VN.doiTuong;
      case VN.tagCategoriesDip:
        return VN.dip;
      case VN.tagCategoriesPhongCach:
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
              TagRow(tag: tag),
          ],
      ],
    );
  }
}