import 'package:bakery_app/shared/labels/shared.dart';
import 'package:bakery_app/shared/widgets/app_bar_overflow_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _buildApp({
  List<PopupMenuEntry<String>> items = const [],
  PopupMenuItemSelected<String>? onSelected,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            title: const Text('Home'),
            actions: [AppBarOverflowMenu(items: items, onSelected: onSelected)],
          ),
          body: const Text('home-screen'),
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) =>
            const Scaffold(body: Text('settings-screen')),
      ),
    ],
  );

  return MaterialApp.router(routerConfig: router);
}

void main() {
  testWidgets('shows settings-only overflow menu', (tester) async {
    await tester.pumpWidget(_buildApp());

    await tester.tap(find.byTooltip(VN.moreActions));
    await tester.pumpAndSettle();

    final menuItems = tester.widgetList<PopupMenuItem<String>>(
      find.byType(PopupMenuItem<String>),
    );
    expect(menuItems.map((item) => item.value), [
      AppBarOverflowMenu.settingsValue,
    ]);

    await tester.tap(find.text(VN.openSettings));
    await tester.pumpAndSettle();

    expect(find.text('settings-screen'), findsOneWidget);
  });

  testWidgets('appends settings after local menu items', (tester) async {
    String? selectedValue;

    await tester.pumpWidget(
      _buildApp(
        items: const [
          PopupMenuItem<String>(value: 'local_action', child: Text('Local')),
        ],
        onSelected: (value) => selectedValue = value,
      ),
    );

    await tester.tap(find.byTooltip(VN.moreActions));
    await tester.pumpAndSettle();

    final menuItems = tester.widgetList<PopupMenuItem<String>>(
      find.byType(PopupMenuItem<String>),
    );
    expect(menuItems.map((item) => item.value), [
      'local_action',
      AppBarOverflowMenu.settingsValue,
    ]);

    await tester.tap(find.text('Local'));
    await tester.pumpAndSettle();

    expect(selectedValue, 'local_action');
  });
}
