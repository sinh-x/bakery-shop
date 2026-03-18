import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/category.dart';
import '../../providers/categories_provider.dart';
import '../../shared/widgets/vietnamese_labels.dart';

class CategoryManagementScreen extends ConsumerWidget {
  const CategoryManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(VN.manageCategories),
      ),
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
        onPressed: () {
          // Phase 4: show add-category form
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = categories.where((c) => c.active == 1).toList();
    final inactive = categories.where((c) => c.active == 0).toList();

    return ListView(
      children: [
        for (final category in active) _ActiveCategoryTile(category: category),
        if (inactive.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              VN.hiddenCategories,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ),
          for (final category in inactive)
            _InactiveCategoryTile(category: category),
        ],
      ],
    );
  }
}

class _ActiveCategoryTile extends ConsumerWidget {
  const _ActiveCategoryTile({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emoji = categoryEmojiMap[category.slug] ?? '🎂';

    return Dismissible(
      key: ValueKey(category.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        final confirmed = await showDialog<bool>(
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text(VN.categoryDeactivated)),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(e.toString())),
            );
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
        leading: Text(emoji, style: const TextStyle(fontSize: 24)),
        title: Text(category.name),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CodePrefixBadge(codePrefix: category.codePrefix),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () {
          // Phase 4: show edit-category form
        },
      ),
    );
  }
}

class _InactiveCategoryTile extends ConsumerWidget {
  const _InactiveCategoryTile({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emoji = categoryEmojiMap[category.slug] ?? '🎂';

    return ListTile(
      leading: Text(
        emoji,
        style: const TextStyle(fontSize: 24, color: Colors.grey),
      ),
      title: Text(
        category.name,
        style: const TextStyle(color: Colors.grey),
      ),
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text(VN.categoryReactivated)),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              }
            },
          ),
        ],
      ),
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
        color: muted
            ? Colors.grey.shade200
            : colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        codePrefix,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: muted
              ? Colors.grey
              : colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
