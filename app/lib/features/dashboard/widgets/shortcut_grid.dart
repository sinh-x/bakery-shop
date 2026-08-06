import 'package:flutter/material.dart';

import '../../../shared/labels/shared.dart';

/// A single shortcut tile inside the management dashboard shortcut grid.
///
/// `onTap` is wired to `context.go()` by the parent screen; the route targets
/// come from `app_router.dart` (/stock, /categories/manage, /customers,
/// /expenses, /blanks).
class ShortcutTile extends StatelessWidget {
  const ShortcutTile({
    super.key,
    required this.icon,
    required this.label,
    required this.route,
    required this.onTap,
  });

  final IconData icon;
  final String label;

  /// GoRouter path the tile navigates to. Stored (not used directly here) so
  /// tests can assert on the target without depending on a real router.
  final String route;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 30, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The shortcut grid for the management dashboard.
///
/// Displays the five management navigation shortcuts in a 2-column grid:
/// Kho hàng, Quản lý danh mục, Quản lý khách hàng, Chi phí, Quản lý phôi bánh
/// (FR3). Each tile navigates via `context.go()`.
class ShortcutGrid extends StatelessWidget {
  const ShortcutGrid({
    super.key,
    required this.onNavigate,
  });

  /// Callback invoked with the route path when a tile is tapped. The parent
  /// screen calls `context.go(route)`.
  final void Function(String route) onNavigate;

  static const List<_ShortcutDef> _shortcuts = [
    _ShortcutDef(
      icon: Icons.inventory_2_outlined,
      label: SharedLabels.dashboardShortcutStock,
      route: '/stock',
    ),
    _ShortcutDef(
      icon: Icons.category_outlined,
      label: SharedLabels.dashboardShortcutCategories,
      route: '/categories/manage',
    ),
    _ShortcutDef(
      icon: Icons.people_outline,
      label: SharedLabels.dashboardShortcutCustomers,
      route: '/customers',
    ),
    _ShortcutDef(
      icon: Icons.payments_outlined,
      label: SharedLabels.dashboardShortcutExpenses,
      route: '/expenses',
    ),
    _ShortcutDef(
      icon: Icons.cake_outlined,
      label: SharedLabels.dashboardShortcutBlanks,
      route: '/blanks',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _shortcuts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final s = _shortcuts[index];
        return ShortcutTile(
          icon: s.icon,
          label: s.label,
          route: s.route,
          onTap: () => onNavigate(s.route),
        );
      },
    );
  }
}

class _ShortcutDef {
  const _ShortcutDef({
    required this.icon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final String label;
  final String route;
}
