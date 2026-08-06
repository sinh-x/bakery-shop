import 'package:flutter/material.dart';

import '../../../data/models/enum_attribute.dart';
import '../../../data/models/product.dart';

/// Resolve the enum attributes defined on the product matching [productId].
///
/// Looks up the product by id (string compare) or `productCode` across the
/// supplied [products] list and returns its `enumAttributes`. Returns an
/// empty list when the product cannot be found or the inputs are empty.
///
/// Shared by the cake queue card, cake detail body, and order work-item
/// section so all three views render identical enum lines
/// (DG-362 Phase 3/4 / FR1-3 / AC1-3, AC6).
List<EnumAttribute> enumAttributesFor(
  String productId,
  List<Product> products,
) {
  if (productId.isEmpty || products.isEmpty) return const [];
  for (final p in products) {
    if (p.id.toString() == productId || p.productCode == productId) {
      return p.enumAttributes;
    }
  }
  return const [];
}

/// Build display rows for enum attribute selections on an order item.
///
/// For every enum attribute the product carries that has a non-empty value
/// stored on the item, render one line: `<labelVi>: <valueVi>` (e.g.
/// `Nhân: Sô-cô-la`). One row per attribute (Q3 / R3 — never collapsed).
List<Widget> buildEnumAttributeLines(
  BuildContext context,
  Map<String, dynamic> attributes,
  List<EnumAttribute> enumAttributes,
) {
  if (enumAttributes.isEmpty) return const [];
  final theme = Theme.of(context);
  final rows = <Widget>[];
  for (final ea in enumAttributes) {
    final raw = attributes[ea.attributeType]?.toString();
    if (raw == null || raw.isEmpty) continue;
    rows.add(
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          '${ea.labelVi}: $raw',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ),
    );
  }
  return rows;
}
