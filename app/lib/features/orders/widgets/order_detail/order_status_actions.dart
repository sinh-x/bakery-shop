import 'package:flutter/material.dart';

import 'package:bakery_app/shared/labels/orders.dart';
import '../section_header.dart';

/// Status transition action buttons (forward, backward, cancel, completed-
/// blocked). Shown only when the order has available transitions.
class OrderStatusActions extends StatelessWidget {
  const OrderStatusActions({
    super.key,
    required this.transitions,
    required this.backwardTransitions,
    required this.remaining,
    required this.transitioning,
    required this.onTransition,
  });

  final List<String> transitions;
  final List<String> backwardTransitions;
  final double remaining;
  final bool transitioning;
  final void Function(String targetStatus) onTransition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (transitions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        const SectionHeader(VN.actions),
        if (transitioning)
          const Center(child: CircularProgressIndicator())
        else
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: transitions.map((t) {
              final isCancel = t == 'cancelled';
              final isBackwardBtn = backwardTransitions.contains(t);
              final isCompletedBlocked = t == 'completed' && remaining > 0;
              if (isCancel) {
                return OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                  ),
                  onPressed: () => onTransition(t),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: Text(statusActionLabel(t)),
                );
              }
              if (isBackwardBtn) {
                return OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade700,
                    side: BorderSide(color: Colors.orange.shade300),
                  ),
                  onPressed: () => onTransition(t),
                  icon: const Icon(Icons.undo, size: 18),
                  label: Text(statusActionLabel(t)),
                );
              }
              return FilledButton.icon(
                onPressed: isCompletedBlocked
                    ? () {
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(
                                'Chưa thanh toán đủ — còn thiếu ${formatVND(remaining)}',
                              ),
                              behavior: SnackBarBehavior.floating,
                              margin: const EdgeInsets.only(
                                bottom: 16,
                                left: 16,
                                right: 16,
                              ),
                            ),
                          );
                      }
                    : () => onTransition(t),
                style: isCompletedBlocked
                    ? FilledButton.styleFrom(
                        backgroundColor: theme.disabledColor,
                      )
                    : null,
                icon: Icon(_transitionIcon(t), size: 18),
                label: Text(statusActionLabel(t)),
              );
            }).toList(),
          ),
      ],
    );
  }

  IconData _transitionIcon(String targetStatus) {
    switch (targetStatus) {
      case 'confirmed':
        return Icons.check_circle_outline;
      case 'in_progress':
        return Icons.bakery_dining_outlined;
      case 'ready':
        return Icons.done_all_outlined;
      case 'delivered':
        return Icons.local_shipping_outlined;
      case 'completed':
        return Icons.verified_outlined;
      default:
        return Icons.arrow_forward;
    }
  }
}