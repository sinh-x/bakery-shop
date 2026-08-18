import 'package:flutter/material.dart';

import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Shared error-state widget for the blanks feature screens.
///
/// Shows a `cloud_off` icon, the standard API error label, and a retry
/// button. Extracted from the 6 near-identical `_XxxErrorView` widgets that
/// were duplicated across the blanks screens (DG-291 review CQ-3).
class BlanksErrorView extends StatelessWidget {
  const BlanksErrorView({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(VN.apiError, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text(VN.retry),
          ),
        ],
      ),
    );
  }
}

/// Shared empty-state widget for the blanks feature screens.
///
/// Shows a domain-specific [icon] (size 64) and a [label]. Extracted from
/// the 6 near-identical `_XxxEmptyView` widgets that were duplicated across
/// the blanks screens (DG-291 review CQ-3).
class BlanksEmptyView extends StatelessWidget {
  const BlanksEmptyView({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(label, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}