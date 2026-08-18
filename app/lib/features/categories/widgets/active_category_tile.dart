import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import '../../../data/models/category.dart';
import '../../../data/providers/categories_provider.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import '../category_form.dart';
import 'category_icon.dart';
import 'code_prefix_badge.dart';

/// Reorderable list tile for an active category.
///
/// Supports swipe-to-deactivate (via [Dismissible]) and tap-to-edit
/// (via [showCategoryForm]). Shows the category icon, name, code-prefix
/// badge, and a drag handle for reordering.
///
/// Extracted from `category_management_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class ActiveCategoryTile extends ConsumerWidget {
  const ActiveCategoryTile({
    super.key,
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
                content: const Text(ProductsLabels.deactivateConfirm),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text(SharedLabels.cancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(ProductsLabels.deactivateCategory),
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
            showTopSnackBar(context, ProductsLabels.categoryDeactivated);
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
        leading: buildCategoryIcon(category),
        title: Text(category.name),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CodePrefixBadge(codePrefix: category.codePrefix),
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