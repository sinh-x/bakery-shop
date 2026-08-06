/// Inflow group ("Tiền vào") of the cash drawer breakdown card (DG-363
/// Phase 3 / FR1/FR2/FR3). Renders the Bán hàng, Nạp tiền, and Mở quầy rows
/// followed by the inflow group total. Each row shows the category label,
/// signed colored amount (green +), and transaction count.
///
/// Extracted from `cash_drawer_breakdown_card.dart` per NFR3 (file ≤ 300
/// lines). Standalone: imports its own dependencies.
library;

import 'package:flutter/material.dart';

import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'cash_drawer_breakdown_card.dart';
import 'cash_drawer_breakdown_row.dart';

class CashDrawerBreakdownInflowGroup extends StatelessWidget {
  const CashDrawerBreakdownInflowGroup({
    super.key,
    required this.rows,
    required this.totalIn,
  });

  final List<CashDrawerBreakdownRow> rows;
  final int totalIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          VN.cashDrawerBreakdownInflowGroup,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        const CashDrawerBreakdownHeaderRow(),
        for (final r in rows) CashDrawerBreakdownRowWidget(row: r),
        CashDrawerBreakdownGroupTotalRow(
          label: VN.cashDrawerBreakdownTotalIn,
          amount: totalIn,
          inflow: true,
        ),
      ],
    );
  }
}