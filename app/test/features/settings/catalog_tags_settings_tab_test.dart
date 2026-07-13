import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bakery_app/features/settings/catalog_tags_settings_tab.dart';

void main() {
  testWidgets('CatalogTagsSettingsTab renders without errors',
      (tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CatalogTagsSettingsTab(),
          ),
        ),
      ),
    );

    // Verify that the tab renders without errors
    expect(find.byType(CatalogTagsSettingsTab), findsOneWidget);
  });
}