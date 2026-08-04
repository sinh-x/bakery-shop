import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/order/incomplete_count_provider.dart';
import '../../../providers/order/urgency_count_provider.dart';
import 'package:bakery_app/shared/labels/shared.dart';

/// Shell scaffold with the bottom navigation bar. Wraps the active child
/// widget and highlights the current tab based on the router location.
class ShellScaffold extends ConsumerWidget {
  const ShellScaffold({super.key, required this.child});

  final Widget child;

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/dashboard')) {
      return 0;
    }
    if (location.startsWith('/orders')) {
      return 1;
    }
    if (location.startsWith('/products')) {
      return 2;
    }
    if (location.startsWith('/knowledge-base') ||
        location.startsWith('/events') ||
        location.startsWith('/checklist') ||
        location.startsWith('/knowledge')) {
      return 3;
    }
    if (location.startsWith('/pos')) {
      return 4;
    }
    return 0;
  }

  void _onDestinationSelected(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/dashboard');
      case 1:
        context.go('/orders');
      case 2:
        context.go('/products');
      case 3:
        context.go('/knowledge-base');
      case 4:
        context.go('/pos');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urgencyCount = ref.watch(urgencyCountProvider);
    final incompleteCount = ref.watch(incompleteCountProvider);
    final showUrgencyBadge = urgencyCount > 0;
    final showIncompleteBadge = incompleteCount > 0;

    Widget ordersIcon({required IconData icon}) {
      if (!showUrgencyBadge && !showIncompleteBadge) {
        return Icon(icon);
      }
      final children = <Widget>[
        Icon(icon),
      ];
      if (showUrgencyBadge) {
        children.add(
          Positioned(
            right: -2,
            top: -2,
            child: BadgeCircle(color: Colors.red, count: urgencyCount),
          ),
        );
      }
      if (showIncompleteBadge) {
        children.add(
          Positioned(
            right: -2,
            top: showUrgencyBadge ? 14 : -2,
            child: BadgeCircle(color: Colors.amber, count: incompleteCount),
          ),
        );
      }
      return Stack(clipBehavior: Clip.none, children: children);
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex(context),
        onDestinationSelected: (index) =>
            _onDestinationSelected(context, index),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: SharedLabels.tabDashboard,
          ),
          NavigationDestination(
            icon: ordersIcon(icon: Icons.receipt_long_outlined),
            selectedIcon: ordersIcon(icon: Icons.receipt_long),
            label: SharedLabels.tabOrders,
          ),
          const NavigationDestination(
            icon: Icon(Icons.cake_outlined),
            selectedIcon: Icon(Icons.cake),
            label: SharedLabels.tabProducts,
          ),
          const NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: SharedLabels.tabKnowledgeBase,
          ),
          const NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: VN.banHang,
          ),
        ],
      ),
    );
  }
}

/// Small circular badge dot for nav tab indicators.
class BadgeCircle extends StatelessWidget {
  const BadgeCircle({
    super.key,
    required this.color,
    required this.count,
  });

  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}