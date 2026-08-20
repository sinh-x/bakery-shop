import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/cash_drawer.dart';
import '../../../data/models/cash_drawer_transaction.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'cash_drawer_action_bar.dart';
import 'cash_drawer_empty_active_view.dart';
import 'cash_drawer_status_card.dart';

/// Active-drawer tab body for [CashDrawerScreen].
///
/// Renders the loading / error / data states for the active drawer status.
/// When no drawer is open, renders [CashDrawerEmptyActiveView]; otherwise
/// renders the [CashDrawerStatusCard] followed by the [CashDrawerActionBar].
///
/// Extracted from `cash_drawer_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CashDrawerActiveTab extends StatelessWidget {
  const CashDrawerActiveTab({
    super.key,
    required this.statusAsync,
    required this.transactionsResponseAsync,
    required this.mutating,
    required this.accountingBalance1101Async,
    required this.previousCloseAsync,
    required this.onOpen,
    required this.onCashIn,
    required this.onCashOut,
    required this.onClose,
  });

  final AsyncValue<CashDrawer?> statusAsync;

  /// DG-359 Phase 2: transactions for the active drawer, used to render the
  /// breakdown card inside [CashDrawerStatusCard]. Resolved from
  /// `cashDrawerTransactionsProvider` (first page) in
  /// `_CashDrawerScreenState.build`. `null` when no drawer is open.
  final AsyncValue<CashDrawerTransactionResponse>? transactionsResponseAsync;

  final bool mutating;
  final AsyncValue<int> accountingBalance1101Async;
  final AsyncValue<int?> previousCloseAsync;
  final Future<void> Function() onOpen;
  final Future<void> Function() onCashIn;
  final Future<void> Function() onCashOut;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    return statusAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(SharedLabels.apiError),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onOpen,
              child: const Text(SharedLabels.retry),
            ),
          ],
        ),
      ),
      data: (drawer) {
        if (drawer == null) {
          return CashDrawerEmptyActiveView(
            onOpen: onOpen,
            mutating: mutating,
            accountingBalance1101Async: accountingBalance1101Async,
            previousCloseAsync: previousCloseAsync,
          );
        }
        // DG-359 Phase 2 FR5/AC4: when transactions have not loaded yet,
        // pass an empty list so the breakdown renders an all-zero table
        // rather than crashing. Once data resolves, the card rebuilds via
        // Riverpod's watch with the real transaction list.
        final transactions =
            transactionsResponseAsync?.value?.items ?? const <CashDrawerTransaction>[];
        return ListView(
          children: [
            CashDrawerStatusCard(
              drawer: drawer,
              transactions: transactions,
            ),
            const SizedBox(height: 8),
            CashDrawerActionBar(
              isOpen: drawer.isOpen,
              mutating: mutating,
              onOpen: onOpen,
              onCashIn: onCashIn,
              onCashOut: onCashOut,
              onClose: onClose,
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}