import 'package:bakery_app/features/customers/widgets/phone_count_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: SizedBox(width: 60, height: 60, child: child));

  testWidgets('renders +N when phoneCount > 1 (AC4)', (tester) async {
    await tester.pumpWidget(wrap(const PhoneCountBadge(phoneCount: 3)));
    expect(find.text('+2'), findsOneWidget);
  });

  testWidgets('renders +1 when phoneCount == 2', (tester) async {
    await tester.pumpWidget(wrap(const PhoneCountBadge(phoneCount: 2)));
    expect(find.text('+1'), findsOneWidget);
  });

  testWidgets('renders nothing when phoneCount <= 1', (tester) async {
    await tester.pumpWidget(wrap(const PhoneCountBadge(phoneCount: 1)));
    expect(find.byType(PhoneCountBadge), findsOneWidget);
    expect(find.byType(SizedBox), findsWidgets);
    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets('renders nothing when phoneCount == 0', (tester) async {
    await tester.pumpWidget(wrap(const PhoneCountBadge(phoneCount: 0)));
    expect(find.textContaining('+'), findsNothing);
  });
}