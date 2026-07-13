import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/catalog_tag.dart';
import '../widgets/catalog_tags_dialogs.dart';
import '../../../shared/labels/shared.dart';

class TagRow extends ConsumerWidget {
  const TagRow({required this.tag, super.key});

  final CatalogTagDef tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              showEditDialog(context, ref, tag);
            },
          ),

          // Delete button
          IconButton(
            icon: const Icon(Icons.delete, size: 20),
            onPressed: () {
              showDeleteDialog(context, ref, tag);
            },
          ),
        ],
      ),
    );
  }

  Color _getColor(String category) {
    switch (category) {
      case VN.tagCategoriesDoiTuong: // audience
        return const Color(0xFF2196F3);
      case VN.tagCategoriesDip: // occasion
        return const Color(0xFFFF9800);
      case VN.tagCategoriesPhongCach: // style
        return const Color(0xFF4CAF50);
      default:
        return Colors.grey.shade300;
    }
  }
}
