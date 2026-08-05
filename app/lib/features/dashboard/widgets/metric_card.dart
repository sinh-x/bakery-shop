import 'package:flutter/material.dart';

/// A single metric card for the management dashboard.
///
/// Displays one business metric (today's orders, today's revenue, low-stock
/// count) with an icon, value, and label. Supports a loading state
/// (`value == null`) that renders a skeleton placeholder, satisfying NFR2
/// (per-section loading indicators) during the progressive data fetch in
/// Phase 3.
///
/// Phase 1 (this file): UI scaffolding only — values are passed in from the
/// parent screen. Phase 3 will wire the real API providers that supply
/// `value`.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color,
    this.onTap,
  });

  /// Icon identifying the metric category.
  final IconData icon;

  /// Vietnamese label shown under the value.
  final String label;

  /// The metric value. `null` indicates "loading" — a skeleton placeholder is
  /// shown in its place (NFR2).
  final String? value;

  /// Accent color for the icon and value. Defaults to the theme primary.
  final Color? color;

  /// Optional tap handler (e.g. to navigate to a detail screen).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, size: 22, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(180),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _MetricValue(value: value, accent: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricValue extends StatelessWidget {
  const _MetricValue({required this.value, required this.accent});

  final String? value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (value == null) {
      // Loading skeleton (NFR2 — per-section loading indicator).
      return Container(
        height: 28,
        width: 96,
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface.withAlpha(20),
          borderRadius: BorderRadius.circular(6),
        ),
      );
    }
    return Text(
      value!,
      style: theme.textTheme.headlineSmall?.copyWith(
        color: accent,
        fontWeight: FontWeight.bold,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}