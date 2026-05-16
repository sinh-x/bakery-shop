import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/category.dart';
import '../../providers/categories_provider.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'category_form.dart';

class CategoryManagementScreen extends ConsumerWidget {
  const CategoryManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(VN.manageCategories)),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(VN.apiError),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () =>
                    ref.read(categoriesProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text(VN.retry),
              ),
            ],
          ),
        ),
        data: (categories) => _CategoryList(categories: categories),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: VN.addCategory,
        onPressed: () => showCategoryForm(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _CategoryList extends ConsumerStatefulWidget {
  const _CategoryList({required this.categories});

  final List<Category> categories;

  @override
  ConsumerState<_CategoryList> createState() => _CategoryListState();
}

class _CategoryListState extends ConsumerState<_CategoryList> {
  late List<Category> _activeCategories;

  @override
  void initState() {
    super.initState();
    _activeCategories = _sortedActive(widget.categories);
  }

  @override
  void didUpdateWidget(_CategoryList oldWidget) {
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
        showTopSnackBar(context, VN.orderUpdated);
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
            return _ActiveCategoryTile(
              key: ValueKey(category.id),
              category: category,
              index: index,
            );
          },
          onReorder: _onReorder,
        ),
        if (inactive.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                VN.hiddenCategories,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: Colors.grey),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  _InactiveCategoryTile(category: inactive[index]),
              childCount: inactive.length,
            ),
          ),
        ],
      ],
    );
  }
}

Widget _buildCategoryIcon(Category category, {bool muted = false}) {
  final emoji = category.icon.isNotEmpty
      ? category.icon
      : (categoryEmojiMap[category.slug] ?? '🎂');
  return Text(
    emoji,
    style: TextStyle(fontSize: 24, color: muted ? Colors.grey : null),
  );
}

class _ActiveCategoryTile extends ConsumerWidget {
  const _ActiveCategoryTile({
    required super.key,
    required this.category,
    required this.index,
  });

  final Category category;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('dismiss_${category.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        final confirmed =
            await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                content: const Text(VN.deactivateConfirm),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text(VN.cancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(VN.deactivateCategory),
                  ),
                ],
              ),
            ) ??
            false;
        if (!confirmed) return false;
        try {
          await ref
              .read(categoriesProvider.notifier)
              .deactivateCategory(category.id);
          if (context.mounted) {
            showTopSnackBar(context, VN.categoryDeactivated);
          }
        } catch (e) {
          if (context.mounted) {
            showTopSnackBar(context, e.toString());
          }
        }
        // Return false — the provider refresh rebuilds the list
        return false;
      },
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.visibility_off, color: Colors.white),
      ),
      child: ListTile(
        leading: _buildCategoryIcon(category),
        title: Text(category.name),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CodePrefixBadge(codePrefix: category.codePrefix),
            const SizedBox(width: 4),
            ReorderableDragStartListener(
              index: index,
              child: const Icon(Icons.drag_handle, color: Colors.grey),
            ),
          ],
        ),
        onTap: () => showCategoryForm(context, category: category),
      ),
    );
  }
}

class _InactiveCategoryTile extends ConsumerWidget {
  const _InactiveCategoryTile({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: _buildCategoryIcon(category, muted: true),
      title: Text(category.name, style: const TextStyle(color: Colors.grey)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CodePrefixBadge(codePrefix: category.codePrefix, muted: true),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.visibility),
            tooltip: VN.reactivateCategory,
            onPressed: () async {
              try {
                await ref
                    .read(categoriesProvider.notifier)
                    .reactivateCategory(category.id);
                if (context.mounted) {
                  showTopSnackBar(context, VN.categoryReactivated);
                }
              } catch (e) {
                if (context.mounted) {
                  showTopSnackBar(context, e.toString());
                }
              }
            },
          ),
        ],
      ),
      onTap: () => showCategoryForm(context, category: category),
    );
  }
}

class _CodePrefixBadge extends StatelessWidget {
  const _CodePrefixBadge({required this.codePrefix, this.muted = false});

  final String codePrefix;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: muted ? Colors.grey.shade200 : colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        codePrefix,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: muted ? Colors.grey : colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
