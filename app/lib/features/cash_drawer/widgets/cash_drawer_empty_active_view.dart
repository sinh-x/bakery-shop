import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:bakery_app/shared/labels/cash_drawer.dart';

/// Empty-state view rendered by [CashDrawerActiveTab] when no drawer is
/// open. Shows the 1101 reference balance line and previous-close line,
/// plus the "Open drawer" button.
///
/// Extracted from `cash_drawer_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CashDrawerEmptyActiveView extends StatelessWidget {
  const CashDrawerEmptyActiveView({
    super.key,
    required this.onOpen,
    required this.mutating,
    required this.accountingBalance1101Async,
    required this.previousCloseAsync,
  });

  final Future<void> Function() onOpen;
  final bool mutating;
  final AsyncValue<int> accountingBalance1101Async;
  final AsyncValue<int?> previousCloseAsync;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_open_outlined, size: 48),
            const SizedBox(height: 12),
            const Text(CashDrawerLabels.cashDrawerNoActive),
            // FR1/AC1: render the 1101 reference balance line at any value
            // (negative, zero, or positive) — DG-360 Phase 2 removed the old
            // `<= 0` guard so an over-drawn 1101 balance is surfaced too.
            // While loading, show a small inline placeholder so the line does
            // not silently disappear on slow networks (PWA bug root cause).
            // On error, the line is omitted rather than crashing the whole
            // screen. NFR1: negative values render in `colorScheme.error`
            // following the `_BalanceRow` pattern.
            accountingBalance1101Async.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (_, _) => const SizedBox.shrink(),
              data: (balance1101) {
                final isNegative = balance1101 < 0;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${CashDrawerLabels.cashDrawerReferenceBalance}: ${formatVND(balance1101.toDouble())}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isNegative
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                  ),
                );
              },
            ),
            previousCloseAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 4),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (_, _) => const SizedBox.shrink(),
              data: (previousClose) {
                if (previousClose == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${CashDrawerLabels.cashDrawerPreviousCloseBalance}: ${formatVND(previousClose.toDouble())}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: mutating ? null : onOpen,
              icon: const Icon(Icons.lock_open),
              label: const Text(CashDrawerLabels.cashDrawerOpen),
            ),
          ],
        ),
      ),
    );
  }
}