import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/blank_stock_provider.dart';
import '../../../shared/labels/blanks.dart';
import '../../../shared/utils/format_double.dart';
import 'summary_card.dart';

/// Stock summary card for a single blank (FR4 / AC4).
///
/// Shows the current net stock level from `blank_stock`. Renders nothing when
/// the API has no row. Extracted from `blank_detail_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class StockSummarySection extends ConsumerWidget {
  const StockSummarySection({super.key, required this.blankId});

  final int blankId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockAsync = ref.watch(blankStockByIdProvider(blankId));
    return SummaryCard(
      title: BlanksLabels.sectionStock,
      icon: Icons.inventory_2_outlined,
      child: stockAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(),
        ),
        error: (e, _) => const Text(BlanksLabels.emptyData),
        data: (s) => Text(
          s == null
              ? BlanksLabels.emptyData
              // ignore: use_build_context_synchronously
              : _formatStock(s.stock, s.unit),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }

  String _formatStock(double stock, String unit) {
    final unitLabel = unit.isEmpty ? '' : ' $unit';
    return '${formatDecimal(stock)}$unitLabel';
  }
}