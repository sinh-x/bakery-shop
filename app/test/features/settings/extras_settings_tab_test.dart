import 'package:bakery_app/features/settings/widgets/settings_sections.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows deprecation guidance and no edit actions', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ExtrasSettingsTab()),
      ),
    );

    expect(find.text(VN.extrasSettingsDeprecatedTitle), findsOneWidget);
    expect(find.text(VN.extrasSettingsDeprecatedBody), findsOneWidget);
    expect(find.text(VN.extrasSettingsDeprecatedAction), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
