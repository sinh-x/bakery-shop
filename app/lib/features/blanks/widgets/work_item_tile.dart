import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/work_item.dart';
import '../../../shared/labels/blanks.dart';

/// A dense [ListTile] for one linked work item on the blank detail screen.
///
/// Renders the work item product name (em dash when empty), the order id and
/// quantity, and navigates to the order detail route when tapped. Extracted
/// from `blank_detail_screen.dart` per §2 of
/// `docs/flutter-coding-standards.md`.
class WorkItemTile extends StatelessWidget {
  const WorkItemTile({super.key, required this.item});

  final WorkItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.receipt_outlined, size: 20),
      title: Text(item.productName.isEmpty ? '—' : item.productName),
      subtitle: Text(
        '#${item.orderId} • ${BlanksLabels.linkedWorkItemQuantity}: ${item.quantity}',
      ),
      onTap: () => context.push('/orders/${item.orderId}'),
    );
  }
}