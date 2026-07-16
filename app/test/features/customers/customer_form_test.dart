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

    // Fill name + phones then save. PhoneInputFormatter dash-formats the
    // typed digits (10 digits -> xxxx-xxx-xxx).
    await tester.enterText(find.byType(TextFormField).at(0), 'Sinh');
    await tester.enterText(find.byType(TextFormField).at(1), '0901234567');
    await tester.enterText(find.byType(TextFormField).at(2), '0987654321');
    await tester.tap(find.text(VN.save));
    await tester.pumpAndSettle();

    expect(service.lastCreatedPhones, isNotNull);
    expect(service.lastCreatedPhones!.length, 2);
    expect(
      service.lastCreatedPhones!
          .firstWhere((p) => p.phone == '0987-654-321').isPrimary,
      isTrue,
    );
    expect(
      service.lastCreatedPhones!
          .firstWhere((p) => p.phone == '0901-234-567').isPrimary,
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
    // PhoneInputFormatter formats 10 digits as xxxx-xxx-xxx.
    expect(service.lastCreatedPhones!.single.phone, '0901-234-567');
    expect(service.lastCreatedPhones!.single.isPrimary, isTrue);
  });

  testWidgets('duplicate phone numbers are rejected with VN label',
      (tester) async {
    final service = _RecordingCustomerService();
    await _pumpForm(tester, service);

    // Add a second phone row.
    await tester.tap(find.text(VN.customerAddPhone));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Sinh');
    await tester.enterText(find.byType(TextFormField).at(1), '0901234567');
    await tester.enterText(find.byType(TextFormField).at(2), '0901234567');
    await tester.tap(find.text(VN.save));
    await tester.pumpAndSettle();

    // Save blocked: duplicate snackbar shown, no creation attempted.
    expect(service.lastCreated, isNull);
    expect(find.text(VN.customerPhoneDuplicate), findsOneWidget);
  });

  // DG-251 Phase 3 / §11 Risk: formatter changes the text the duplicate
  // detector compares. Two entries that normalize to the same formatted
  // string must still be flagged as duplicates.
  testWidgets(
      'duplicate detection fires for formatted duplicates (same digits, '
      'different dash placement)', (tester) async {
    final service = _RecordingCustomerService();
    await _pumpForm(tester, service);

    // Add a second phone row.
    await tester.tap(find.text(VN.customerAddPhone));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Sinh');
    // Row 1: typed digits get dash-formatted by PhoneInputFormatter.
    await tester.enterText(find.byType(TextFormField).at(1), '0901234567');
    // Row 2: same digits typed again -> identical formatted value.
    await tester.enterText(find.byType(TextFormField).at(2), '0901234567');
    await tester.tap(find.text(VN.save));
    await tester.pumpAndSettle();

    // Both rows format to '0901-234-567', so duplicate detection must fire.
    expect(service.lastCreated, isNull);
    expect(find.text(VN.customerPhoneDuplicate), findsOneWidget);
  });

  // CQ-1: a prefilled 11-digit phone (formatPhone leaves it raw since only
  // 9/10-digit inputs are dash-grouped) must still be flagged as a duplicate
  // of the same digits typed in another row (which PhoneInputFormatter dash-
  // formats). Duplicate detection compares digit-only keys, not raw strings.
  testWidgets(
      'duplicate detection fires for 11-digit prefilled vs same digits typed',
      (tester) async {
    final service = _RecordingCustomerService();
    // Stored phone is 11 digits; formatPhone returns it as-is (no dash
    // grouping for lengths other than 9/10), so the prefilled controller
    // shows the raw '09012345678'.
    const customer = Customer(
      id: 11,
      name: 'Long',
      phones: [CustomerPhone(phone: '09012345678', isPrimary: true)],
    );
    await _pumpForm(tester, service, customer: customer);

    // Add a second phone row and type the same 11 digits. PhoneInputFormatter
    // dash-formats them to '0901-234-5678'.
    await tester.tap(find.text(VN.customerAddPhone));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Long');
    await tester.enterText(find.byType(TextFormField).at(2), '09012345678');
    await tester.tap(find.text(VN.save));
    await tester.pumpAndSettle();

    // Despite different raw strings ('09012345678' vs '0901-234-5678'),
    // digit-only normalization must flag the duplicate.
    expect(service.lastUpdatedId, isNull);
    expect(find.text(VN.customerPhoneDuplicate), findsOneWidget);
  });

  // DG-251 Phase 3 / FR5: prefilled (edit-mode) phone values render
  // dash-formatted via formatPhone when the form opens.
  testWidgets('edit mode renders prefilled phones dash-formatted via formatPhone',
      (tester) async {
    final service = _RecordingCustomerService();
    const customer = Customer(
      id: 9,
      name: 'Hoa',
      phones: [
        CustomerPhone(phone: '0901234567', isPrimary: true),
        CustomerPhone(phone: '0987654321', isPrimary: false),
      ],
    );
    await _pumpForm(tester, service, customer: customer);

    // 10-digit stored values are displayed dash-formatted (xxxx-xxx-xxx).
    expect(find.text('0901-234-567'), findsOneWidget);
    expect(find.text('0987-654-321'), findsOneWidget);
    // Raw unformatted values must NOT be shown.
    expect(find.text('0901234567'), findsNothing);
    expect(find.text('0987654321'), findsNothing);
  });
}
