import 'package:flutter/material.dart';

import '../../../shared/labels/shared.dart';

/// Alert section of the management dashboard.
///
/// Renders a dismissible banner that surfaces urgent info (currently critical
/// orders). The count is supplied by the parent screen; tapping the banner
/// triggers [onTap], which delegates to the existing
/// `critical_alert_provider` (FR5/AC9), reused unchanged.
///
/// When [count] is 0, nothing is rendered (the section is hidden).
class AlertSection extends StatelessWidget {
  const AlertSection({
    super.key,
    required this.count,
    required this.onTap,
    this.onDismiss,
  });

  /// Number of critical orders detected. `0` hides the section.
  final int count;

  /// Tap handler — opens the critical-orders detail/alert.
  final VoidCallback onTap;

  /// Optional dismiss handler. When provided, a dismiss (X) button is shown.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: theme.colorScheme.onErrorContainer,
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  SharedLabels.dashboardCriticalOrdersAlert(count),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  icon: const Icon(Icons.close),
                  iconSize: 20,
                  color: theme.colorScheme.onErrorContainer,
                  onPressed: onDismiss,
                  tooltip: SharedLabels.dashboardCriticalAlertsDismiss,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
