import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import '../../../data/models/category.dart';
import '../../../data/providers/categories_provider.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'active_category_tile.dart';
import 'inactive_category_tile.dart';

/// Reorderable list of active categories followed by a sliver of
/// inactive (hidden) categories.
///
/// Active categories can be reordered via drag-and-drop (persisted
/// through [CategoriesNotifier.reorderCategories]). Inactive categories
/// are displayed below a "Hidden categories" header and are not
/// reorderable.
///
/// Extracted from `category_management_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CategoryList extends ConsumerStatefulWidget {
  const CategoryList({super.key, required this.categories});

  final List<Category> categories;

  @override
  ConsumerState<CategoryList> createState() => _CategoryListState();
}

class _CategoryListState extends ConsumerState<CategoryList> {
  late List<Category> _activeCategories;

  @override
  void initState() {
    super.initState();
    _activeCategories = _sortedActive(widget.categories);
  }

  @override
  void didUpdateWidget(CategoryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categories != widget.categories) {
      _activeCategories = _sortedActive(widget.categories);
    }
  }

  List<Category> _sortedActive(List<Category> categories) {
    return categories.where((c) => c.active == 1).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      final item = _activeCategories.removeAt(oldIndex);
      _activeCategories.insert(newIndex, item);
    });
    final ids = _activeCategories.map((c) => c.id).toList();
    try {
      await ref.read(categoriesProvider.notifier).reorderCategories(ids);
      if (mounted) {
        showTopSnackBar(context, ProductsLabels.orderUpdated);
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inactive = widget.categories.where((c) => c.active == 0).toList();

    return CustomScrollView(
      slivers: [
        SliverReorderableList(
          itemCount: _activeCategories.length,
          itemBuilder: (context, index) {
            final category = _activeCategories[index];
            return ActiveCategoryTile(
              key: ValueKey(category.id),
              category: category,
              index: index,
            );
          },
          // ignore: deprecated_member_use
          onReorder: _onReorder,
        ),
        if (inactive.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                ProductsLabels.hiddenCategories,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: Colors.grey),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  InactiveCategoryTile(category: inactive[index]),
              childCount: inactive.length,
            ),
          ),
        ],
      ],
    );
  }
}