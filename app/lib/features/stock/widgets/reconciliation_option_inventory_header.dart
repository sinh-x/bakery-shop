import 'package:flutter/material.dart';

import '../../../data/api/reconciliation_service.dart';
import 'package:bakery_app/shared/labels/stock.dart';
import 'reconciliation_option_header.dart';
import 'reconciliation_shared_widgets.dart';
import 'reconciliation_status_chip.dart';
import 'reconciliation_surplus_indicator.dart';
import 'reconciliation_variance_indicator.dart';

class OptionInventoryHeader extends StatelessWidget {
  const OptionInventoryHeader({
    required this.option,
    required this.visibleChipLabels,
    required this.optionKey,
    required this.countedQty,
    required this.saleQty,
    required this.wasteQty,
    required this.variance,
    required this.surplus,
    required this.hasError,
    this.trailing,
    super.key,
  });

  final ReconciliationDraftOption option;
  final String visibleChipLabels;
  final String optionKey;
  final int countedQty;
  final int saleQty;
  final int wasteQty;
  final int variance;
  final int surplus;
  final bool hasError;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OptionHeader(
                option: option,
                visibleChipLabels: visibleChipLabels,
              ),
              Wrap(
                key: ValueKey('reconciliation-option-summary-$optionKey'),
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ReconciliationSummaryChip(label: StockLabels.tonDaDem, value: countedQty),
                  ReconciliationSummaryChip(label: StockLabels.soLuongBan, value: saleQty),
                  ReconciliationSummaryChip(label: StockLabels.soLuongHaoHut, value: wasteQty),
                  ReconciliationVarianceIndicator(variance: variance),
                  if (surplus > 0)
                    ReconciliationSurplusIndicator(surplus: surplus),
                  StatusChip(hasError: hasError),
                ],
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    );
  }
}