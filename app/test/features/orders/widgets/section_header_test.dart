import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/features/orders/widgets/section_header.dart';

void main() {
  testWidgets('SectionHeader renders the provided title text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SectionHeader('Hình thức nhận hàng')),
      ),
    );

    expect(find.text('Hình thức nhận hàng'), findsOneWidget);
    expect(find.byType(SectionHeader), findsOneWidget);
  });

  testWidgets('SectionHeader renders with empty title without error',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SectionHeader(''))),
    );

    expect(find.byType(SectionHeader), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
  });
}