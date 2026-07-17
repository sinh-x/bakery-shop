import 'package:bakery_app/data/api/customer_service.dart';
import 'package:bakery_app/data/models/customer.dart';
import 'package:bakery_app/features/customers/customer_form.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingCustomerService extends CustomerService {
  _RecordingCustomerService({this.searchResults = const {}})
      : super(Dio());

  /// Map of search query -> list of customers returned by `listCustomers`.
  /// Used by the duplicate-warning tests to simulate matches. An empty map
  /// (the default) means every search returns an empty list.
  final Map<String, List<Customer>> searchResults;

  Customer? lastCreated;
  List<CustomerPhone>? lastCreatedPhones;
  int? lastUpdatedId;
  List<CustomerPhone>? lastUpdatedPhones;
  Customer? usedExisting;
  int createCallCount = 0;

  @override
  Future<List<Customer>> listCustomers({String? search}) async {
    final q = (search ?? '').trim();
    return searchResults[q] ?? const <Customer>[];
  }

  @override
  Future<CustomerMutationResult> createCustomer({
    required String name,
    String phone = '',
    List<CustomerPhone>? phones,
  }) async {
    createCallCount += 1;
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
  ValueChanged<Customer>? onUseExisting,
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
                onPressed: () => showCustomerForm(
                  ctx,
                  customer: customer,
                  onUseExisting: onUseExisting,
                ),
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

  // CQ-6: prefilled and typed 11-digit phones render identically via
  // formatPhone / PhoneInputFormatter (both produce 'xxxx-xxx-xxxx' with
  // trailing digits appended). Duplicate detection compares digit-only keys.
  testWidgets(
      'duplicate detection fires for 11-digit prefilled vs same digits typed',
      (tester) async {
    final service = _RecordingCustomerService();
    // Stored phone is 11 digits; formatPhone now formats it to
    // '0901-234-5678' (matching PhoneInputFormatter behavior).
    const customer = Customer(
      id: 11,
      name: 'Long',
      phones: [CustomerPhone(phone: '09012345678', isPrimary: true)],
    );
    await _pumpForm(tester, service, customer: customer);

    // Prefilled controller shows formatted 11-digit value.
    expect(find.text('0901-234-5678'), findsOneWidget);
    expect(find.text('09012345678'), findsNothing);

    // Add a second phone row and type the same 11 digits. PhoneInputFormatter
    // dash-formats them to '0901-234-5678' as well.
    await tester.tap(find.text(VN.customerAddPhone));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Long');
    await tester.enterText(find.byType(TextFormField).at(2), '09012345678');
    await tester.tap(find.text(VN.save));
    await tester.pumpAndSettle();

    // Both rows render identically; digit-only normalization flags duplicate.
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

  // ---------------------------------------------------------------------------
  // DG-252 Phase 6 — Duplicate warning at manual customer create (FR8/AC6).
  // ---------------------------------------------------------------------------

  testWidgets(
      'no duplicate warning when name and phone do not match any customer '
      '(FR8/AC6)', (tester) async {
    final service = _RecordingCustomerService();
    await _pumpForm(tester, service);

    await tester.enterText(find.byType(TextFormField).at(0), 'Sinh');
    await tester.enterText(find.byType(TextFormField).at(1), '0901234567');
    await tester.tap(find.text(VN.save));
    await tester.pumpAndSettle();

    // No dialog shown, create proceeds.
    expect(service.createCallCount, 1);
    expect(service.lastCreated, isNotNull);
    expect(service.lastCreated!.name, 'Sinh');
    expect(find.text(CustomersLabels.duplicateWarningTitle), findsNothing);
  });

  testWidgets(
      'duplicate warning shown when name matches existing customer; '
      'create-anyway proceeds with create (FR8/AC6)', (tester) async {
    const existing = Customer(
      id: 42,
      name: 'Sinh',
      phone: '0901-234-567',
    );
    final service = _RecordingCustomerService(searchResults: {
      'Sinh': [existing],
      '0901234567': [existing],
    });
    await _pumpForm(tester, service);

    await tester.enterText(find.byType(TextFormField).at(0), 'Sinh');
    await tester.enterText(find.byType(TextFormField).at(1), '0901234567');
    await tester.tap(find.text(VN.save));
    await tester.pumpAndSettle();

    // Warning dialog shown with the existing customer.
    expect(find.text(CustomersLabels.duplicateWarningTitle), findsOneWidget);
    expect(find.text('Sinh'), findsWidgets);
    expect(find.text(CustomersLabels.duplicateWarningCreateAnyway),
        findsOneWidget);
    // Create has NOT happened yet.
    expect(service.createCallCount, 0);

    // Choose "create anyway".
    await tester.tap(find.text(CustomersLabels.duplicateWarningCreateAnyway));
    await tester.pumpAndSettle();

    // Create proceeds.
    expect(service.createCallCount, 1);
    expect(service.lastCreated!.name, 'Sinh');
  });

  testWidgets(
      'duplicate warning: "use existing" invokes onUseExisting and skips '
      'create (FR8/AC6)', (tester) async {
    const existing = Customer(
      id: 42,
      name: 'Sinh',
      phone: '0901-234-567',
    );
    final service = _RecordingCustomerService(searchResults: {
      'Sinh': [existing],
    });
    Customer? picked;
    await _pumpForm(
      tester,
      service,
      onUseExisting: (c) => picked = c,
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'Sinh');
    await tester.enterText(find.byType(TextFormField).at(1), '0901234567');
    await tester.tap(find.text(VN.save));
    await tester.pumpAndSettle();

    expect(find.text(CustomersLabels.duplicateWarningTitle), findsOneWidget);

    // Tap the existing customer's list tile (scoped to the dialog) to
    // "use existing".
    final tile = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Sinh'),
    );
    await tester.tap(tile);
    await tester.pumpAndSettle();

    // onUseExisting fired with the chosen customer.
    expect(picked, isNotNull);
    expect(picked!.id, 42);
    // No create call was made.
    expect(service.createCallCount, 0);
  });

  testWidgets(
      'duplicate warning: explicit "Dùng khách sẵn có" button invokes onUseExisting with the first match (DG-252 review Mn8)',
      (tester) async {
    const existing = Customer(
      id: 42,
      name: 'Sinh',
      phone: '0901-234-567',
    );
    final service = _RecordingCustomerService(searchResults: {
      'Sinh': [existing],
    });
    Customer? picked;
    await _pumpForm(
      tester,
      service,
      onUseExisting: (c) => picked = c,
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'Sinh');
    await tester.enterText(find.byType(TextFormField).at(1), '0901234567');
    await tester.tap(find.text(VN.save));
    await tester.pumpAndSettle();

    expect(find.text(CustomersLabels.duplicateWarningTitle), findsOneWidget);

    // Tap the explicit "Dùng khách sẵn có" button in the dialog.
    final useExistingButton = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(CustomersLabels.duplicateWarningUseExisting),
    );
    await tester.tap(useExistingButton);
    await tester.pumpAndSettle();

    // onUseExisting fired with the first match.
    expect(picked, isNotNull);
    expect(picked!.id, 42);
    expect(service.createCallCount, 0);
  });

  testWidgets(
      'duplicate warning: cancel does not create and keeps the form open '
      '(FR8/AC6)', (tester) async {
    const existing = Customer(
      id: 42,
      name: 'Sinh',
      phone: '0901-234-567',
    );
    final service = _RecordingCustomerService(searchResults: {
      'Sinh': [existing],
    });
    await _pumpForm(tester, service);

    await tester.enterText(find.byType(TextFormField).at(0), 'Sinh');
    await tester.enterText(find.byType(TextFormField).at(1), '0901234567');
    await tester.tap(find.text(VN.save));
    await tester.pumpAndSettle();

    expect(find.text(CustomersLabels.duplicateWarningTitle), findsOneWidget);

    // Tap "Hủy" (cancel) — scoped to the dialog so it does not match the
    // bottom-sheet's own VN.cancel button.
    final dialogCancel = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(CustomersLabels.duplicateWarningCancel),
    );
    await tester.tap(dialogCancel);
    await tester.pumpAndSettle();

    // No create, form still visible.
    expect(service.createCallCount, 0);
    expect(find.text(VN.save), findsOneWidget);
    expect(find.text(VN.addCustomer), findsOneWidget);
  });

  testWidgets(
      'duplicate warning aggregates matches from name and phone queries, '
      'deduped by id (FR8/AC6)', (tester) async {
    const byName = Customer(id: 1, name: 'Sinh', phone: '');
    const byPhone = Customer(
      id: 2,
      name: 'An',
      phone: '0901-234-567',
    );
    // Same customer returned by both queries must be deduped.
    const shared = Customer(
      id: 3,
      name: 'Hoa',
      phone: '0901-234-567',
    );
    final service = _RecordingCustomerService(searchResults: {
      'Sinh': [byName, shared],
      '0901234567': [byPhone, shared],
    });
    await _pumpForm(tester, service);

    await tester.enterText(find.byType(TextFormField).at(0), 'Sinh');
    await tester.enterText(find.byType(TextFormField).at(1), '0901234567');
    await tester.tap(find.text(VN.save));
    await tester.pumpAndSettle();

    // Dialog shown with three unique customers (1, 2, 3) — shared appears
    // only once even though both queries returned it. Scoped to the dialog
    // so the form's name field value does not double-count.
    expect(find.text(CustomersLabels.duplicateWarningTitle), findsOneWidget);
    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('Sinh')),
        findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('An')),
        findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Hoa')),
        findsOneWidget);
  });

  testWidgets(
      'edit mode does not show duplicate warning (FR8 only applies to create)',
      (tester) async {
    const existing = Customer(
      id: 42,
      name: 'Sinh',
      phone: '0901-234-567',
    );
    final service = _RecordingCustomerService(searchResults: {
      'Sinh': [existing],
    });
    const editing = Customer(
      id: 7,
      name: 'Sinh',
      phones: [CustomerPhone(phone: '0901234567', isPrimary: true)],
    );
    await _pumpForm(tester, service, customer: editing);

    await tester.tap(find.text(VN.save));
    await tester.pumpAndSettle();

    // Edit goes straight through; no duplicate dialog.
    expect(find.text(CustomersLabels.duplicateWarningTitle), findsNothing);
    expect(service.lastUpdatedId, 7);
  });
}
