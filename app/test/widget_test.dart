import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

import 'package:bakery_app/app.dart';
import 'package:bakery_app/shared/labels/shared.dart';

void main() {
  testWidgets('App launches with bakery title', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: BakeryApp()),
    );

    // Dashboard tab is the initial route — verify it renders
    expect(find.text('Tổng quan'), findsWidgets);
    expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);

    await tester.tap(find.text(VN.banHang).first);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.storefront), findsOneWidget);
  });
}
