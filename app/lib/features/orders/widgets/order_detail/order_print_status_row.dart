import 'package:flutter/material.dart';

import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Row showing the work-ticket print status with mark/unmark actions.
class OrderPrintStatusRow extends StatelessWidget {
  const OrderPrintStatusRow({
    super.key,
    required this.printedAt,
    required this.onMarkPrinted,
    required this.onUnmarkPrinted,
  });

  final String? printedAt;
  final VoidCallback onMarkPrinted;
  final VoidCallback onUnmarkPrinted;

  @override
  Widget build(BuildContext context) {
    final isPrinted = printedAt != null && printedAt!.isNotEmpty;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isPrinted ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPrinted ? Colors.green.shade300 : Colors.orange.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPrinted ? Icons.check_circle_outline : Icons.print_outlined,
            size: 20,
            color: isPrinted ? Colors.green.shade700 : Colors.orange.shade700,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPrinted ? VN.printStatusPrinted : VN.printStatusUnprinted,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isPrinted
                        ? Colors.green.shade800
                        : Colors.orange.shade800,
                  ),
                ),
                if (isPrinted && printedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    printedAt!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.green.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isPrinted)
            TextButton(
              onPressed: onUnmarkPrinted,
              child: Text(
                VN.unmarkPrinted,
                style: TextStyle(color: Colors.red.shade700),
              ),
            )
          else
            FilledButton(
              onPressed: onMarkPrinted,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text(VN.markAsPrinted),
            ),
        ],
      ),
    );
  }
}