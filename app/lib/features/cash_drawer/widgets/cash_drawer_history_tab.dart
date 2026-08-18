import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/cash_drawer.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'cash_drawer_history_list.dart';

/// History-tab body for [CashDrawerScreen]. Renders the loading / error /
/// data states for the drawer history list, delegating to
/// [CashDrawerHistoryList] when data resolves.
///
/// Extracted from `cash_drawer_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CashDrawerHistoryTab extends StatelessWidget {
  const CashDrawerHistoryTab({
    super.key,
    required this.historyAsync,
    this.onTapClosedDrawer,
  });

  final AsyncValue<CashDrawerHistoryResponse> historyAsync;

  /// DG-343 Phase 3 FR4/AC2: invoked when the user taps a closed drawer row.
  /// The screen pushes a transaction-detail route for that drawer.
  final void Function(CashDrawer drawer)? onTapClosedDrawer;

  @override
  Widget build(BuildContext context) {
    return historyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(SharedLabels.apiError),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {},
              child: const Text(SharedLabels.retry),
            ),
          ],
        ),
      ),
      data: (resp) => SingleChildScrollView(
        child: CashDrawerHistoryList(
          items: resp.items,
          onTapClosedDrawer: onTapClosedDrawer,
        ),
      ),
    );
  }
}