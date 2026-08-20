import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/products_provider.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import '../product_form_screen.dart';

/// Loads the product from the API before showing the edit form.
class ProductEditLoader extends ConsumerWidget {
  const ProductEditLoader({super.key, required this.productId});

  final int productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);
    // Try to find the product in the already-loaded list.
    return productsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text(ProductsLabels.editProduct)),
        body: const Center(child: Text(SharedLabels.apiError)),
      ),
      data: (products) {
        final product = products.where((p) => p.id == productId).firstOrNull;
        if (product != null) {
          return ProductFormScreen(product: product);
        }

        final productAsync = ref.watch(productByIdProvider(productId));
        return productAsync.when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(
            appBar: AppBar(title: const Text(ProductsLabels.editProduct)),
            body: const Center(child: Text(SharedLabels.apiError)),
          ),
          data: (product) => ProductFormScreen(product: product),
        );
      },
    );
  }
}