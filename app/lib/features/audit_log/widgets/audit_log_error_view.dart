import 'package:flutter/material.dart';

import '../../../shared/labels/audit_log.dart';

/// Error-state placeholder shown when the audit log request fails.
class AuditLogErrorView extends StatelessWidget {
  const AuditLogErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 56, color: Colors.red),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text(AuditLogLabels.retry),
          ),
        ],
      ),
    );
  }
}