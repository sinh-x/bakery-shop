import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import '../../../data/models/category.dart';
import '../../../data/providers/categories_provider.dart';
import 'package:bakery_app/shared/labels/products.dart';
import '../category_form.dart';
import 'category_icon.dart';
import 'code_prefix_badge.dart';

/// List tile for an inactive (hidden) category.
///
/// Shows the category icon (muted), name (grey), code-prefix badge
/// (muted), and a reactivate button. Tap navigates to the edit form.
///
/// Extracted from `category_management_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class InactiveCategoryTile extends ConsumerWidget {
  const InactiveCategoryTile({super.key, required this.category});

  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: buildCategoryIcon(category, muted: true),
      title: Text(category.name, style: const TextStyle(color: Colors.grey)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CodePrefixBadge(codePrefix: category.codePrefix, muted: true),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.visibility),
            tooltip: ProductsLabels.reactivateCategory,
            onPressed: () async {
              try {
                await ref
                    .read(categoriesProvider.notifier)
                    .reactivateCategory(category.id);
                if (context.mounted) {
                  showTopSnackBar(context, ProductsLabels.categoryReactivated);
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