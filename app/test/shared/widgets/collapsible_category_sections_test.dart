import 'package:bakery_app/shared/utils/category_grouping.dart';
import 'package:bakery_app/shared/widgets/collapsible_category_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('collapsed by default and toggles expansion', (tester) async {
    final sections = [
      GroupedCategorySection<String>(
        categoryKey: 'banh_kem',
        categoryName: 'Banh kem',
        categoryPosition: 1,
        items: const ['Kem dau', 'Kem matcha'],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CollapsibleCategorySections<String>(
            sections: sections,
            itemBuilder: (context, item) => ListTile(title: Text(item)),
          ),
        ),
      ),
    );

    expect(find.text('Banh kem'), findsOneWidget);
    expect(find.text('2 mặt hàng'), findsOneWidget);
    expect(find.text('Kem dau'), findsNothing);

    await tester.tap(find.text('Banh kem'));
    await tester.pumpAndSettle();
    expect(find.text('Kem dau'), findsOneWidget);

    await tester.tap(find.text('Banh kem'));
    await tester.pumpAndSettle();
    expect(find.text('Kem dau'), findsNothing);
  });

  testWidgets('controller preserves expansion state during rebuild', (
    tester,
  ) async {
    final controller = CategorySectionExpansionController();
    final sections = [
      GroupedCategorySection<String>(
        categoryKey: 'phu_kien',
        categoryName: 'Phu kien',
        categoryPosition: 1,
        items: const ['No'],
      ),
    ];

    Widget buildHarness() {
      return MaterialApp(
        home: Scaffold(
          body: CollapsibleCategorySections<String>(
            sections: sections,
            expansionController: controller,
            itemBuilder: (context, item) => ListTile(title: Text(item)),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildHarness());
    await tester.tap(find.text('Phu kien'));
    await tester.pumpAndSettle();
    expect(find.text('No'), findsOneWidget);

    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();
    expect(find.text('No'), findsOneWidget);
  });
}
