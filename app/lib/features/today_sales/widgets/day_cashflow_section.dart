import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/cashflow_summary.dart';
import '../../../shared/labels/shared.dart';
import 'cashflow_summary_section.dart';

/// Cashflow-summary section for the day tab.
///
/// Extracted from `day_tab_body.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class DayCashflowSection extends StatelessWidget {
  const DayCashflowSection({super.key, required this.asyncValue});

  final AsyncValue<CashflowSummary> asyncValue;

  @override
  Widget build(BuildContext context) {
    return asyncValue.when(
      data: (summary) => CashflowSummarySection(summary: summary),
      loading: () => const CashflowSummarySection(summary: null),
      error: (_, _) => Center(
        child: Text(
          SharedLabels.errorLoading,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}