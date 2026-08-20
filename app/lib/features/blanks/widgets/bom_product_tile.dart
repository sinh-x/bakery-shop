import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/blank.dart';
import '../../../shared/labels/blanks.dart';
import '../../../shared/utils/format_double.dart';

/// A dense [ListTile] for one BOM-linked product on the blank detail screen.
///
/// Renders the product name (em dash when empty), the BOM quantity, and
/// navigates to the product edit route when the product id is non-null.
/// Extracted from `blank_detail_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class BomProductTile extends StatelessWidget {
  const BomProductTile({super.key, required this.product});

  final BlankBomProduct product;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.cake_outlined, size: 20),
      title: Text(
        product.productName.isEmpty ? '—' : product.productName,
      ),
      subtitle: Text(
        '${BlanksLabels.linkedBomQuantity}: ${formatDecimal(product.quantity)}',
      ),
      onTap: product.productId == null
          ? null
          : () => context.push('/products/${product.productId}/edit'),
    );
  }
}