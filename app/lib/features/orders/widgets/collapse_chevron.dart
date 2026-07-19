import 'package:flutter/material.dart';

import '../../../shared/labels/orders.dart';

class CollapseChevron extends StatelessWidget {
  const CollapseChevron({
    super.key,
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
