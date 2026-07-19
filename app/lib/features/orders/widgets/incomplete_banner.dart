import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/order/banner_collapse_provider.dart';
import '../../../shared/labels/orders.dart';
import '../../../shared/theme/bakery_theme.dart';
import 'collapse_chevron.dart';

class IncompleteBanner extends ConsumerWidget {
  const IncompleteBanner({
    super.key,
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (count == 0) {
      return const SizedBox.shrink();
    }

    final collapsed = ref.watch(incompleteBannerCollapsedProvider);
    final color =
        BakeryTheme.completenessTierColors['incomplete'] ?? Colors.amber;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, collapsed ? 0 : 8, 16, 0),
      child: Material(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        child: collapsed
            ? _buildCollapsed(context, ref, color)
            : _buildExpanded(context, ref, color),
      ),
    );
  }

  Widget _buildExpanded(
    BuildContext context,
    WidgetRef ref,
    Color color,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: color, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    OrdersLabels.incompleteBannerTitle,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    OrdersLabels.incompleteBannerText(count),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            _CountChip(count: count, color: color),
            const SizedBox(width: 4),
            CollapseChevron(
              collapsed: false,
              onTap: () =>
                  ref.read(incompleteBannerCollapsedProvider.notifier).toggle(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsed(
    BuildContext context,
    WidgetRef ref,
    Color color,
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
              Icon(Icons.warning_amber_rounded, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  OrdersLabels.incompleteBannerTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              _CountChip(count: count, color: color),
              const SizedBox(width: 4),
              CollapseChevron(
                collapsed: true,
                onTap: () =>
                    ref.read(incompleteBannerCollapsedProvider.notifier).toggle(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.count,
    required this.color,
  });

  final int count;
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
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
