import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/blank_demand_provider.dart';
import '../../../shared/labels/blanks.dart';
import '../../../shared/utils/format_double.dart';
import 'demand_row.dart';
import 'summary_card.dart';

/// Demand summary card for a single blank (FR5 / AC4).
///
/// Shows demand, current stock, and shortage from the demand calculation
/// endpoint. Extracted from `blank_detail_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class DemandSummarySection extends ConsumerWidget {
  const DemandSummarySection({super.key, required this.blankId});

  final int blankId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demandAsync = ref.watch(blankDemandByIdProvider(blankId));
    return SummaryCard(
      title: BlanksLabels.sectionDemand,
      icon: Icons.trending_up_outlined,
      child: demandAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(),
        ),
        error: (e, _) => const Text(BlanksLabels.emptyData),
        data: (d) {
          if (d == null) return const Text(BlanksLabels.emptyData);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DemandRow(
                label: BlanksLabels.demand,
                value: formatDecimal(d.demand),
              ),
              DemandRow(
                label: BlanksLabels.demandStock,
                value: formatDecimal(d.stock),
              ),
              DemandRow(
                label: BlanksLabels.demandShortage,
                value: formatDecimal(d.shortage),
                emphasize: d.shortage > 0,
              ),
            ],
          );
        },
      ),
    );
  }
}