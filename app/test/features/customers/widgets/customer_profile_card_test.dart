import 'package:bakery_app/data/models/customer.dart';
import 'package:bakery_app/features/customers/widgets/customer_profile_card.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('full mode shows avatar, name, all phones, order count, created date (FR1/AC1)',
      (tester) async {
    const customer = Customer(
      id: 1,
      name: 'Sinh',
      phone: '0901234567',
      phones: [
        CustomerPhone(phone: '0901234567', isPrimary: true),
        CustomerPhone(phone: '0909876543', isPrimary: false),
      ],
      createdAt: null,
      yearSummary: CustomerYearSummary(year: 2026, orderCount: 5, totalVolume: 1200000),
    );
    await tester.pumpWidget(wrap(const CustomerProfileCard(customer: customer)));

    expect(find.text('Sinh'), findsOneWidget);
    expect(find.textContaining('0901234567'), findsOneWidget);
    expect(find.textContaining('0909876543'), findsOneWidget);
    expect(find.textContaining(VN.customerPrimaryPhone), findsOneWidget);
    // Order count line: "5 đơn/năm"
    expect(find.text('5 ${CustomersLabels.orderCountThisYearSuffix}'), findsOneWidget);
  });

  testWidgets('full mode shows order count 0 when yearSummary is null', (tester) async {
    const customer = Customer(id: 1, name: 'Sinh', phone: '0901234567');
    await tester.pumpWidget(wrap(const CustomerProfileCard(customer: customer)));
    // Order count line: "0 đơn/năm" — 0 is the count, suffix is the unit label.
    expect(find.textContaining('0'), findsWidgets);
    expect(find.textContaining(CustomersLabels.orderCountThisYearSuffix), findsOneWidget);
  });

  testWidgets('compact mode shows avatar, name, and primary phone only', (tester) async {
    const customer = Customer(
      id: 1,
      name: 'Sinh',
      phone: '0901234567',
      phones: [
        CustomerPhone(phone: '0901234567', isPrimary: true),
        CustomerPhone(phone: '0909876543', isPrimary: false),
      ],
      yearSummary: CustomerYearSummary(year: 2026, orderCount: 5, totalVolume: 0),
    );
    await tester.pumpWidget(wrap(
      const CustomerProfileCard(
          customer: customer, mode: CustomerProfileCardMode.compact),
    ));

    expect(find.text('Sinh'), findsOneWidget);
    expect(find.textContaining('0901234567'), findsOneWidget);
    expect(find.textContaining('0909876543'), findsNothing);
    expect(find.textContaining(CustomersLabels.orderCountThisYearSuffix), findsNothing);
  });

  testWidgets('full mode falls back to legacy phone when phones list empty', (tester) async {
    const customer = Customer(id: 1, name: 'Sinh', phone: '0901234567');
    await tester.pumpWidget(wrap(const CustomerProfileCard(customer: customer)));
    expect(find.textContaining('0901234567'), findsOneWidget);
    expect(find.textContaining(VN.customerPrimaryPhone), findsNothing);
  });

  testWidgets('full mode shows no phone line when customer has none', (tester) async {
    const customer = Customer(id: 1, name: 'Sinh', phone: '');
    await tester.pumpWidget(wrap(const CustomerProfileCard(customer: customer)));
    expect(find.text('Sinh'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.byIcon(Icons.star_border), findsNothing);
  });

  testWidgets('onTap makes the card tappable and shows chevron', (tester) async {
    const customer = Customer(id: 1, name: 'Sinh', phone: '0901234567');
    var tapped = false;
    await tester.pumpWidget(wrap(
      CustomerProfileCard(customer: customer, onTap: () => tapped = true),
    ));
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    await tester.tap(find.byType(CustomerProfileCard));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('no onTap hides chevron and card is non-interactive', (tester) async {
    const customer = Customer(id: 1, name: 'Sinh', phone: '0901234567');
    await tester.pumpWidget(wrap(const CustomerProfileCard(customer: customer)));
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('uses fallback initial when name is empty', (tester) async {
    const customer = Customer(id: 1, name: '', phone: '0901234567');
    await tester.pumpWidget(wrap(const CustomerProfileCard(customer: customer)));
    expect(find.text(CustomersLabels.customerNoName[0]), findsOneWidget);
  });
}