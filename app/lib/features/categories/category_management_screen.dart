import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/categories_provider.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'category_form.dart';
import 'widgets/category_list.dart';

class CategoryManagementScreen extends ConsumerWidget {
  const CategoryManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(ProductsLabels.manageCategories),
        actions: const [AppBarOverflowMenu()],
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(SharedLabels.apiError),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () =>
                    ref.read(categoriesProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text(SharedLabels.retry),
              ),
            ],
          ),
        ),
        data: (categories) => CategoryList(categories: categories),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: ProductsLabels.addCategory,
        onPressed: () => showCategoryForm(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}