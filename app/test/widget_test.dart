import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bakery_app/app.dart';

void main() {
  testWidgets('App launches with bakery title', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: BakeryApp()),
    );

    // Dashboard tab is the initial route — verify it renders
    expect(find.text('Tổng quan'), findsWidgets);
  });
}
