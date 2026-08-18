import 'package:bakery_app/shared/utils.dart' show formatVND;
import 'package:flutter/material.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
/// Editable shipping fee stepper section (+/− buttons with 5000đ increments)
/// for door/bus delivery orders. Extracted from [OrderDeliverySection] to keep
/// the parent widget under the 400-line Flutter coding-standards limit.
class ShippingFeeSection extends StatelessWidget {
  const ShippingFeeSection({
    super.key,
    required this.shippingFee,
    required this.onChanged,
    this.loading = false,
    this.error,
    this.onRetry,
  });

  final double? shippingFee;
  final ValueChanged<double> onChanged;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (error != null)
          _buildError(context)
        else
          _buildStepper(context),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              SharedLabels.errorLoading,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text(SharedLabels.retry),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepper(BuildContext context) {
    final fee = shippingFee ?? 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filled(
          onPressed: fee >= 5000
              ? () => onChanged(fee - 5000.0)
              : null,
          icon: const Icon(Icons.remove),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            fee == 0 ? OrdersLabels.shippingFree : formatVND(fee),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        IconButton.filled(
          onPressed: () => onChanged(fee + 5000.0),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
