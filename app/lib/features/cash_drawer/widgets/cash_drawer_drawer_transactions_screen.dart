import 'package:flutter/material.dart';

import '../../../data/models/cash_drawer.dart';
import '../../../shared/utils/date_formatting.dart';
import 'package:bakery_app/shared/labels/cash_drawer.dart';
import 'cash_drawer_transaction_list.dart';

/// DG-343 Phase 3 FR4/AC2: full-screen transaction detail view for a closed
/// drawer. Pushed by the parent screen's `_navigateToDrawerTransactions`
/// handler when the user taps a closed drawer in the History tab. Reuses
/// [CashDrawerTransactionList] with `poll: false` (closed drawers don't
/// change) and infinite-scroll pagination.
///
/// Extracted from `cash_drawer_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CashDrawerDrawerTransactionsScreen extends StatelessWidget {
  const CashDrawerDrawerTransactionsScreen({
    super.key,
    required this.drawer,
    required this.drawerId,
  });

  final CashDrawer drawer;
  final int drawerId;

  @override
  Widget build(BuildContext context) {
    final title = '${CashDrawerLabels.cashDrawerTransactionsTab} — ${formatDisplayDate(drawer.openedAt)}';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: CashDrawerTransactionList(
        drawerId: drawerId,
        poll: false,
        reconciled: drawer.reconciled,
      ),
    );
  }
}