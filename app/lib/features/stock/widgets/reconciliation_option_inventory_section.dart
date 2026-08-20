import 'package:flutter/material.dart';

import '../../../data/api/reconciliation_service.dart';
import 'reconciliation_option_inventory_header.dart';

class OptionInventorySection extends StatelessWidget {
  const OptionInventorySection({
    required this.optionKey,
    required this.option,
    required this.visibleChipLabels,
    required this.countedQty,
    required this.saleQty,
    required this.wasteQty,
    required this.variance,
    required this.surplus,
    required this.hasError,
    required this.canCollapse,
    required this.isExpanded,
    required this.onToggle,
    required this.child,
    super.key,
  });

  final String optionKey;
  final ReconciliationDraftOption option;
  final String visibleChipLabels;
  final int countedQty;
  final int saleQty;
  final int wasteQty;
  final int variance;
  final int surplus;
  final bool hasError;
  final bool canCollapse;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canCollapse)
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: OptionInventoryHeader(
                option: option,
                visibleChipLabels: visibleChipLabels,
                optionKey: optionKey,
                countedQty: countedQty,
                saleQty: saleQty,
                wasteQty: wasteQty,
                variance: variance,
                surplus: surplus,
                hasError: hasError,
                trailing: Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: OptionInventoryHeader(
              option: option,
              visibleChipLabels: visibleChipLabels,
              optionKey: optionKey,
              countedQty: countedQty,
              saleQty: saleQty,
              wasteQty: wasteQty,
              variance: variance,
              surplus: surplus,
              hasError: hasError,
            ),
          ),
        if (isExpanded) ...[const SizedBox(height: 6), child],
      ],
    );
  }
}