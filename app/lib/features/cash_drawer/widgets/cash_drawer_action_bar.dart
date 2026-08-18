import 'package:flutter/material.dart';

import 'package:bakery_app/shared/labels/cash_drawer.dart';

/// Action-bar widget rendered below [CashDrawerStatusCard] on the active
/// tab. Shows cash-in / cash-out / close / open buttons, disabled while a
/// mutation is in flight.
///
/// Extracted from `cash_drawer_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class CashDrawerActionBar extends StatelessWidget {
  const CashDrawerActionBar({
    super.key,
    required this.isOpen,
    required this.mutating,
    required this.onOpen,
    required this.onCashIn,
    required this.onCashOut,
    required this.onClose,
  });

  final bool isOpen;
  final bool mutating;
  final Future<void> Function() onOpen;
  final Future<void> Function() onCashIn;
  final Future<void> Function() onCashOut;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: mutating ? null : onCashIn,
            icon: const Icon(Icons.south_west),
            label: const Text(CashDrawerLabels.cashDrawerCashIn),
          ),
          FilledButton.tonalIcon(
            onPressed: mutating ? null : onCashOut,
            icon: const Icon(Icons.north_east),
            label: const Text(CashDrawerLabels.cashDrawerCashOut),
          ),
          FilledButton.tonalIcon(
            onPressed: mutating ? null : onClose,
            icon: const Icon(Icons.lock_outline),
            label: const Text(CashDrawerLabels.cashDrawerClose),
          ),
          if (!isOpen)
            FilledButton.icon(
              onPressed: mutating ? null : onOpen,
              icon: const Icon(Icons.lock_open),
              label: const Text(CashDrawerLabels.cashDrawerOpen),
            ),
        ],
      ),
    );
  }
}