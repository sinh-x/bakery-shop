import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/order/banner_collapse_provider.dart';
import '../../../shared/labels/orders.dart';
import '../../../shared/theme/bakery_theme.dart';
import '../../../shared/utils/order_helpers.dart';

class UrgencyBanner extends ConsumerWidget {
  const UrgencyBanner({
    super.key,
    required this.criticalCount,
    required this.urgentCount,
    required this.onTap,
  });

  final int criticalCount;
  final int urgentCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (criticalCount == 0 && urgentCount == 0) {
      return const SizedBox.shrink();
    }

    final collapsed = ref.watch(urgencyBannerCollapsedProvider);

    final criticalColor =
        BakeryTheme.urgencyTierColors[urgencyCritical] ?? Colors.red;
    final urgentColor =
        BakeryTheme.urgencyTierColors[urgencyUrgent] ?? Colors.amber;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, collapsed ? 0 : 8, 16, 0),
      child: Material(
        color: criticalColor.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        child: collapsed
            ? _buildCollapsed(context, ref, criticalColor, urgentColor)
            : _buildExpanded(context, ref, criticalColor, urgentColor),
      ),
    );
  }

  Widget _buildExpanded(
    BuildContext context,
    WidgetRef ref,
    Color criticalColor,
    Color urgentColor,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.warning_rounded, color: criticalColor, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    OrdersLabels.urgencyBannerTitle,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _buildSummary(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (criticalCount > 0)
              _CountChip(
                count: criticalCount,
                label: OrdersLabels.urgencyBannerCritical,
                color: criticalColor,
              ),
            if (urgentCount > 0) ...[
              const SizedBox(width: 6),
              _CountChip(
                count: urgentCount,
                label: OrdersLabels.urgencyBannerUrgent,
                color: urgentColor,
              ),
            ],
            const SizedBox(width: 4),
            _CollapseChevron(
              collapsed: false,
              onTap: () =>
                  ref.read(urgencyBannerCollapsedProvider.notifier).toggle(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsed(
    BuildContext context,
    WidgetRef ref,
    Color criticalColor,
    Color urgentColor,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(Icons.warning_rounded, color: criticalColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  OrdersLabels.urgencyBannerTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              if (criticalCount > 0)
                _CountChip(
                  count: criticalCount,
                  label: OrdersLabels.urgencyBannerCritical,
                  color: criticalColor,
                ),
              if (urgentCount > 0) ...[
                const SizedBox(width: 6),
                _CountChip(
                  count: urgentCount,
                  label: OrdersLabels.urgencyBannerUrgent,
                  color: urgentColor,
                ),
              ],
              const SizedBox(width: 4),
              _CollapseChevron(
                collapsed: true,
                onTap: () =>
                    ref.read(urgencyBannerCollapsedProvider.notifier).toggle(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildSummary() {
    return OrdersLabels.urgencyBannerText(criticalCount, urgentCount);
  }
}

class _CollapseChevron extends StatelessWidget {
  const _CollapseChevron({
    required this.collapsed,
    required this.onTap,
  });

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 20,
        icon: Icon(collapsed ? Icons.expand_more : Icons.expand_less),
        onPressed: onTap,
        tooltip: collapsed
            ? OrdersLabels.bannerExpandTooltip
            : OrdersLabels.bannerCollapseTooltip,
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.count,
    required this.label,
    required this.color,
  });

  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
