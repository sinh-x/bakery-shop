import 'package:flutter/material.dart';

import '../../../data/models/enum_attribute.dart';

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
