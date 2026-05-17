import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/catalog_tag.dart';
import '../../../providers/catalog_provider.dart';

/// Shared widget for rendering catalog tag chips in fixed category order
/// (audience → occasion → style) with distinct colours per category.
///
/// Used by: catalog_photo_browse_card, catalog_photo_viewer caption overlay,
/// and product_form_screen _CatalogPhotoCard chip row.
class CatalogTagChips extends ConsumerWidget {
  const CatalogTagChips({
    super.key,
    required this.tags,
    this.maxChips,
  });

  /// Raw tags string (e.g. "audience:nam,occasion:sinh-nhat,style:hoa")
  final String tags;

  /// Maximum chips to show (null = show all)
  final int? maxChips;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagDefsAsync = ref.watch(catalogTagDefsProvider);
    final defs = tagDefsAsync.value ?? [];

    final chips = _buildChips(defs);

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: maxChips != null ? chips.take(maxChips!).toList() : chips,
    );
  }

  List<Widget> _buildChips(List<CatalogTagDef> defs) {
    final tagKeys = tags.isNotEmpty
        ? tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList()
        : <String>[];

    // Separate into category buckets in fixed order
    final audience = <String>[];
    final occasion = <String>[];
    final style = <String>[];

    for (final key in tagKeys) {
      final category = _getCategory(key);
      switch (category) {
        case 'audience':
          audience.add(key);
        case 'occasion':
          occasion.add(key);
        case 'style':
          style.add(key);
        default:
          // Unknown category — treat as audience for ordering, will render grey
          audience.add(key);
      }
    }

    final chips = <Widget>[];

    for (final key in audience) {
      chips.add(_Chip(
        tagKey: key,
        defs: defs,
        category: 'audience',
      ));
    }
    for (final key in occasion) {
      chips.add(_Chip(
        tagKey: key,
        defs: defs,
        category: 'occasion',
      ));
    }
    for (final key in style) {
      chips.add(_Chip(
        tagKey: key,
        defs: defs,
        category: 'style',
      ));
    }

    return chips;
  }

  String _getCategory(String tagKey) {
    if (tagKey.contains(':')) {
      return tagKey.split(':')[0];
    }
    return '';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.tagKey,
    required this.defs,
    required this.category,
  });

  final String tagKey;
  final List<CatalogTagDef> defs;
  final String category;

  @override
  Widget build(BuildContext context) {
    final label = _resolveLabel(tagKey);
    final color = _getColor(category, tagKey);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: _getTextColor(category),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _resolveLabel(String key) {
    // key may be "category:key" or just "key"
    final keyPart = key.contains(':') ? key.split(':')[1] : key;
    for (final d in defs) {
      if (d.key == key || d.key == keyPart) return d.label;
    }
    return '?';
  }

  Color _getColor(String category, String key) {
    // Unknown key renders grey
    final keyPart = key.contains(':') ? key.split(':')[1] : key;
    final isKnown = defs.any((d) => d.key == key || d.key == keyPart);
    if (!isKnown) return Colors.grey.shade300;

    switch (category) {
      case 'audience':
        return const Color(0xFF2196F3);
      case 'occasion':
        return const Color(0xFFFF9800);
      case 'style':
        return const Color(0xFF4CAF50);
      default:
        return Colors.grey.shade300;
    }
  }

  Color _getTextColor(String category) {
    switch (category) {
      case 'audience':
      case 'style':
        return Colors.white;
      case 'occasion':
        return Colors.black87;
      default:
        return Colors.black87;
    }
  }
}