import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'vietnamese_labels.dart';

class AppBarOverflowMenu extends StatelessWidget {
  const AppBarOverflowMenu({
    super.key,
    this.items = const [],
    this.onSelected,
    this.includeSettings = true,
  });

  static const settingsValue = 'settings';

  final List<PopupMenuEntry<String>> items;
  final PopupMenuItemSelected<String>? onSelected;
  final bool includeSettings;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: VN.moreActions,
      onSelected: (value) {
        if (includeSettings && value == settingsValue) {
          context.push('/settings');
          return;
        }
        onSelected?.call(value);
      },
      itemBuilder: (context) => [
        ...items,
        if (includeSettings)
          const PopupMenuItem<String>(
            value: settingsValue,
            child: Text(VN.openSettings),
          ),
      ],
    );
  }
}
