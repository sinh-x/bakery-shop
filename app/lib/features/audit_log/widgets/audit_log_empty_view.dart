import 'package:flutter/material.dart';

import '../../../shared/labels/audit_log.dart';

/// Empty-state placeholder shown when the audit log has no entries.
class AuditLogEmptyView extends StatelessWidget {
  const AuditLogEmptyView({super.key, required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.history, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          const Text(AuditLogLabels.empty),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRefresh,
            child: const Text(AuditLogLabels.retry),
          ),
        ],
      ),
    );
  }
}