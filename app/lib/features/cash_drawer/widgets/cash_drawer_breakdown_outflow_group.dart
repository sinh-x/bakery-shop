/// Outflow group ("Tiền ra") of the cash drawer breakdown card (DG-363
/// Phase 3 / FR1/FR2/FR3). Renders the Hoàn tiền, Chi phí, Rút tiền, Phí ship
/// bus, and Đóng quầy rows followed by the outflow group total. Each row
/// shows the category label, signed colored amount (red −), and transaction
/// count.
///
/// Extracted from `cash_drawer_breakdown_card.dart` per NFR3 (file ≤ 300
/// lines). Standalone: imports its own dependencies.
library;

import 'package:flutter/material.dart';
import 'package:bakery_app/shared/labels/cash_drawer.dart';
import 'cash_drawer_breakdown_card.dart';
import 'cash_drawer_breakdown_row.dart';

class CashDrawerBreakdownOutflowGroup extends StatelessWidget {
  const CashDrawerBreakdownOutflowGroup({
    super.key,
    required this.rows,
    required this.totalOut,
  });

  final List<CashDrawerBreakdownRow> rows;
  final int totalOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          CashDrawerLabels.cashDrawerBreakdownOutflowGroup,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        const CashDrawerBreakdownHeaderRow(),
        for (final r in rows) CashDrawerBreakdownRowWidget(row: r),
        CashDrawerBreakdownGroupTotalRow(
          label: CashDrawerLabels.cashDrawerBreakdownTotalOut,
          amount: totalOut,
          inflow: false,
        ),
      ],
    );
  }
}