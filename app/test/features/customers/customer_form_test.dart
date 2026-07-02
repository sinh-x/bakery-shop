import 'package:bakery_app/data/api/customer_service.dart';
import 'package:bakery_app/data/models/customer.dart';
import 'package:bakery_app/features/customers/customer_form.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingCustomerService extends CustomerService {
  _RecordingCustomerService() : super(Dio());

  Customer? lastCreated;
  List<CustomerPhone>? lastCreatedPhones;
  int? lastUpdatedId;
  List<CustomerPhone>? lastUpdatedPhones;

  @override
  Future<CustomerMutationResult> createCustomer({
    required String name,
    String phone = '',
    List<CustomerPhone>? phones,
  }) async {
    lastCreated = Customer(id: 1, name: name, phones: phones ?? const []);
    lastCreatedPhones = phones;
    return (
      customer: lastCreated!,
      sharedPhoneCustomers: const <Customer>[],
    );
  }

  @override
  Future<CustomerMutationResult> updateCustomer(
    int id, {
    String? name,
    String? phone,
    List<CustomerPhone>? phones,
  }) async {
    lastUpdatedId = id;
    lastUpdatedPhones = phones;
    final c = Customer(id: id, name: name ?? '', phones: phones ?? const []);
    return (customer: c, sharedPhoneCustomers: const <Customer>[]);
  }
}

Future<void> _pumpForm(
  WidgetTester tester,
  CustomerService service, {
  Customer? customer,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [customerServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showCustomerForm(ctx, customer: customer),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('add mode starts with one empty phone row', (tester) async {
    final service = _RecordingCustomerService();
    await _pumpForm(tester, service);

    // One phone field by default.
    expect(find.byType(TextFormField), findsNWidgets(2)); // name + 1 phone
    expect(find.text(VN.customerAddPhone), findsOneWidget);
    // Remove button disabled when only one row.
    final removeBtn = find.byIcon(Icons.remove_circle_outline);
    expect(removeBtn, findsOneWidget);
    expect(
      tester.widget<IconButton>(find.ancestor(
        of: removeBtn,
        matching: find.byType(IconButton),
      ).first).onPressed,
      isNull,
    );
  });

  testWidgets('can add and remove phone rows', (tester) async {
    final service = _RecordingCustomerService();
    await _pumpForm(tester, service);

    await tester.tap(find.text(VN.customerAddPhone));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(3)); // name + 2 phones

    // Now remove button on first row is enabled.
    final removeBtns = find.byIcon(Icons.remove_circle_outline);
    expect(removeBtns, findsNWidgets(2));

    await tester.tap(removeBtns.first);
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));
  });

  testWidgets('primary toggle deselects other rows', (tester) async {
    final service = _RecordingCustomerService();
    await _pumpForm(tester, service);

    // Add a second phone row.
    await tester.tap(find.text(VN.customerAddPhone));
    await tester.pumpAndSettle();

    // Tap star on the second phone row to mark it primary.
    final stars = find.byIcon(Icons.star_border);
    await tester.tap(stars.at(0));
    await tester.pumpAndSettle();

    // Fill name + phones then save.
    await tester.enterText(find.byType(TextFormField).at(0), 'Sinh');
    await tester.enterText(find.byType(TextFormField).at(1), '0901');
    await tester.enterText(find.byType(TextFormField).at(2), '0902');
    await tester.tap(find.text(VN.save));
    await tester.pumpAndSettle();

    expect(service.lastCreatedPhones, isNotNull);
    expect(service.lastCreatedPhones!.length, 2);
    expect(
      service.lastCreatedPhones!.firstWhere((p) => p.phone == '0902').isPrimary,
      isTrue,
    );
    expect(
      service.lastCreatedPhones!.firstWhere((p) => p.phone == '0901').isPrimary,
      isFalse,
    );
  });

  testWidgets('edit mode pre-populates phones from customer.phones',
      (tester) async {
    final service = _RecordingCustomerService();
    const customer = Customer(
      id: 7,
      name: 'An',
      phone: '0901',
      phones: [
        CustomerPhone(phone: '0901', isPrimary: true),
        CustomerPhone(phone: '0902', isPrimary: false),
      ],
    );
    await _pumpForm(tester, service, customer: customer);

    expect(find.text('An'), findsOneWidget);
    expect(find.text('0901'), findsOneWidget);
    expect(find.text('0902'), findsOneWidget);
  });

  testWidgets('saves with at least one phone; emits phones array',
      (tester) async {
    final service = _RecordingCustomerService();
    await _pumpForm(tester, service);

    await tester.enterText(find.byType(TextFormField).at(0), 'Sinh');
    await tester.enterText(find.byType(TextFormField).at(1), '0901234567');
    await tester.tap(find.text(VN.save));
    await tester.pumpAndSettle();

    expect(service.lastCreatedPhones, isNotNull);
    expect(service.lastCreatedPhones!.length, 1);
    expect(service.lastCreatedPhones!.single.phone, '0901234567');
    expect(service.lastCreatedPhones!.single.isPrimary, isTrue);
  });
}