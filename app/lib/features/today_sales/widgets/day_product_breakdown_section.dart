import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/product_breakdown.dart';
import '../../../shared/labels/shared.dart';
import 'product_breakdown_section.dart';

/// Product-breakdown section for the day tab. While the period=day fetch is
/// loading the section widget receives `null` and renders its built-in
/// loading/empty state; on error a compact error line is shown.
///
/// Extracted from `day_tab_body.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class DayProductBreakdownSection extends StatelessWidget {
  const DayProductBreakdownSection({super.key, required this.asyncValue});

  final AsyncValue<ProductBreakdown> asyncValue;

  @override
  Widget build(BuildContext context) {
    return asyncValue.when(
      data: (breakdown) => ProductBreakdownSection(breakdown: breakdown),
      loading: () => const ProductBreakdownSection(breakdown: null),
      error: (_, _) => Center(
        child: Text(
          SharedLabels.errorLoading,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}