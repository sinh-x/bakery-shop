import 'package:flutter/material.dart';

import 'package:bakery_app/shared/labels/cash_drawer.dart';

/// DG-343 Phase 3 FR3: placeholder shown in the "Chi tiết giao dịch" tab
/// body when no drawer is open. The tab itself is disabled (snap-back to the
/// status tab via the [TabController] listener in the parent screen state),
/// so this widget is rendered but not interactive — it exists solely so the
/// [TabBarView] has 3 children matching the [TabController] length.
///
/// Extracted from `cash_drawer_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CashDrawerDisabledTransactionsPlaceholder extends StatelessWidget {
  const CashDrawerDisabledTransactionsPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long,
              size: 48,
              color: Theme.of(context).disabledColor,
            ),
            const SizedBox(height: 12),
            Text(
              CashDrawerLabels.cashDrawerNoActive,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}