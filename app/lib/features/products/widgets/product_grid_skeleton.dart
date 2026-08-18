import 'package:flutter/material.dart';

/// Loading skeleton shown while the first product page loads (DG-409
/// Phase 4 / loading indicators).
///
/// Extracted from `product_catalog_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class ProductGridSkeleton extends StatelessWidget {
  const ProductGridSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: 6,
      itemBuilder: (context, _) => const Card(
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      ),
    );
  }
}