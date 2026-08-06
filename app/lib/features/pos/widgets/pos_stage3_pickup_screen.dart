import 'package:flutter/material.dart';

import '../../../shared/labels/orders.dart';

class PosStage3PickupScreen extends StatelessWidget {
  const PosStage3PickupScreen({
    super.key,
    required this.onDeliverNow,
    required this.onDeliverLater,
    this.onFastPath,
  });

  final VoidCallback onDeliverNow;
  final VoidCallback onDeliverLater;

  /// DG-370 Phase 5.6-c1 (UX-4): optional "Giao ngay & Thanh toán" fast-path
  /// callback. When provided, a third button is rendered alongside the
  /// existing "Giao ngay" / "Giao hàng sau" options so the user can jump
  /// directly to Stage 5 with Giao ngay walk-in defaults.
  final VoidCallback? onFastPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              OrdersLabels.pickupTitle,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              OrdersLabels.pickupSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: FilledButton.icon(
                onPressed: onDeliverNow,
                icon: const Icon(Icons.delivery_dining),
                label: Text(
                  OrdersLabels.pickupNow,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 64,
              child: OutlinedButton.icon(
                onPressed: onDeliverLater,
                icon: const Icon(Icons.schedule),
                label: Text(
                  OrdersLabels.pickupLater,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            // DG-370 Phase 5.6-c1 (UX-4): fast-path button alongside the
            // existing "Giao ngay" / "Giao hàng sau" options.
            if (onFastPath != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: FilledButton.icon(
                  onPressed: onFastPath,
                  icon: const Icon(Icons.bolt),
                  label: Text(
                    OrdersLabels.posGiaoNgayThanhToan,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
