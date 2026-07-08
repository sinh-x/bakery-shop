import 'package:flutter/material.dart';

import 'package:bakery_app/shared/labels/orders.dart';

class _StageInfo {
  final String label;
  final String desc;
  const _StageInfo(this.label, this.desc);
}

const _stages = [
  _StageInfo(OrdersLabels.stage1Label, OrdersLabels.stage1Desc),
  _StageInfo(OrdersLabels.stage2Label, OrdersLabels.stage2Desc),
  _StageInfo(OrdersLabels.stage3Label, OrdersLabels.stage3Desc),
  _StageInfo(OrdersLabels.stage4Label, OrdersLabels.stage4Desc),
];

class OrderStageIndicator extends StatelessWidget {
  const OrderStageIndicator({
    super.key,
    required this.currentStage,
    this.onStageTap,
  });

  final int currentStage;

  /// Called when the user taps a stage circle. Receives the 1-based stage
  /// number. When null, the indicator is non-interactive. The caller decides
  /// whether navigation is allowed (e.g. only after a product is selected).
  final void Function(int stage)? onStageTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < _stages.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: 14),
                  height: 2,
                  color: i <= currentStage - 1
                      ? theme.colorScheme.primary
                      : Colors.grey.shade300,
                ),
              ),
            _buildStageItem(i, theme),
          ],
        ],
      ),
    );
  }

  Widget _buildStageItem(int index, ThemeData theme) {
    final stage = index + 1;
    final canTap = onStageTap != null;
    final isCompleted = index < currentStage - 1;
    final isCurrent = index == currentStage - 1;

    final color = isCompleted || isCurrent
        ? theme.colorScheme.primary
        : Colors.grey.shade400;

    return SizedBox(
      width: 64,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canTap ? () => onStageTap!(stage) : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCurrent
                    ? color
                    : (isCompleted ? color.withAlpha(50) : Colors.transparent),
                border: Border.all(color: color, width: 2),
              ),
              child: Center(
                child: isCompleted
                    ? Icon(Icons.check, size: 12, color: color)
                    : Text(
                        '$stage',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isCurrent
                              ? theme.colorScheme.onPrimary
                              : color,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _stages[index].label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                color: isCurrent || isCompleted ? color : Colors.grey.shade500,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _stages[index].desc,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 8,
                color: Colors.grey.shade400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
