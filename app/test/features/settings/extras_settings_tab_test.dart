import 'package:bakery_app/features/settings/widgets/settings_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bakery_app/shared/labels/orders.dart';

void main() {
  testWidgets('shows deprecation guidance and no edit actions', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ExtrasSettingsTab()),
      ),
    );

    expect(find.text(OrdersLabels.extrasSettingsDeprecatedTitle), findsOneWidget);
    expect(find.text(OrdersLabels.extrasSettingsDeprecatedBody), findsOneWidget);
    expect(find.text(OrdersLabels.extrasSettingsDeprecatedAction), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
