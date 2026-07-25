import 'package:flutter/material.dart';

import '../../../shared/utils/category_grouping.dart';
import 'package:bakery_app/shared/labels/blanks.dart';

/// Category-grouped list for the blanks feature.
///
/// Reuses [groupItemsByCategory] for the grouping algorithm (DG-291 review
/// CQ-4) and a shared category-header widget, removing the duplicate
/// grouping logic that existed in `blank_stock_screen.dart` and
/// `blank_demand_screen.dart`. Categories for blanks are free-form strings
/// (not managed [Category] rows), so an empty `categories` list is passed
/// to [groupItemsByCategory] — it falls back to the raw category key as the
/// display name and sorts alphabetically.
class BlanksCategoryGroupedList<T> extends StatelessWidget {
  const BlanksCategoryGroupedList({
    super.key,
    required this.items,
    required this.categoryKeyOf,
    required this.itemLabelOf,
    required this.itemBuilder,
  });

  final List<T> items;
  final String Function(T) categoryKeyOf;
  final String Function(T) itemLabelOf;
  final Widget Function(BuildContext context, T item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final sections = groupItemsByCategory<T>(
      items: items,
      categories: const [],
      categoryKeyOf: categoryKeyOf,
      itemLabelOf: itemLabelOf,
    );
    return ListView(
      children: [
        for (final section in sections) ...[
          _BlanksCategoryHeader(category: section.categoryName),
          for (final item in section.items) itemBuilder(context, item),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

class _BlanksCategoryHeader extends StatelessWidget {
  const _BlanksCategoryHeader({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(
        category.isEmpty ? BlanksLabels.categoryFilterAll : category,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}