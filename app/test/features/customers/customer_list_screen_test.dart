import 'package:bakery_app/data/api/customer_service.dart';
import 'package:bakery_app/data/models/customer.dart';
import 'package:bakery_app/features/customers/customer_list_screen.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeCustomerService extends CustomerService {
  _FakeCustomerService(this._customers, {this.searchResults = const {}})
      : super(Dio());

  final List<Customer> _customers;

  /// Map of search query -> list of customers returned by `listCustomers`.
  /// Used by the duplicate-warning screen test to simulate matches.
  final Map<String, List<Customer>> searchResults;

  @override
  Future<List<Customer>> listCustomers({String? search}) async {
    if (search == null || search.trim().isEmpty) return List.of(_customers);
    final q = search.trim();
    if (searchResults.containsKey(q)) return searchResults[q]!;
    final lower = q.toLowerCase();
    return _customers
        .where(
          (c) => c.name.toLowerCase().contains(lower) || c.phone.contains(q),
        )
        .toList();
  }
}

/// Test router mirroring the app's customer routes so the list screen's
/// `context.push('/customers/:id')` navigation is observable. The detail
/// route renders a sentinel text so the test can assert the navigation
/// landed on the chosen customer (DG-252 review r2 M1).
GoRouter _buildRouter() {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/customers',
        builder: (context, state) => const CustomerListScreen(),
      ),
      GoRoute(
        path: '/customers/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return Scaffold(body: Text('detail-$id'));
        },
      ),
    ],
    initialLocation: '/customers',
  );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  CustomerService service,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [customerServiceProvider.overrideWithValue(service)],
      child: MaterialApp.router(routerConfig: _buildRouter()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders customers and shows empty state', (tester) async {
    await _pumpScreen(tester, _FakeCustomerService(const []));
    expect(find.text(VN.noCustomers), findsOneWidget);
  });

  testWidgets('lists customers with name and phone', (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
      const Customer(id: 2, name: 'An', phone: '0909876543'),
    ];
    await _pumpScreen(tester, _FakeCustomerService(customers));

    expect(find.text('Sinh'), findsOneWidget);
    expect(find.text('An'), findsOneWidget);
    expect(find.textContaining('0901234567'), findsOneWidget);
  });

  testWidgets('search filters customers by name', (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
      const Customer(id: 2, name: 'An', phone: '0909876543'),
    ];
    await _pumpScreen(tester, _FakeCustomerService(customers));

    await tester.enterText(find.byType(TextField), 'Sin');
    await tester.pumpAndSettle();

    expect(find.text('Sinh'), findsOneWidget);
    expect(find.text('An'), findsNothing);
  });

  testWidgets('search filters customers by phone', (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
      const Customer(id: 2, name: 'An', phone: '0909876543'),
    ];
    await _pumpScreen(tester, _FakeCustomerService(customers));

    await tester.enterText(find.byType(TextField), '765');
    await tester.pumpAndSettle();

    expect(find.text('Sinh'), findsNothing);
    expect(find.text('An'), findsOneWidget);
  });

  testWidgets('list tile shows primary phone from phones list', (tester) async {
    final customers = [
      const Customer(
        id: 1,
        name: 'Sinh',
        phone: '0901234567',
        phones: [
          CustomerPhone(phone: '0901234567', isPrimary: true),
          CustomerPhone(phone: '0909876543', isPrimary: false),
        ],
      ),
    ];
    await _pumpScreen(tester, _FakeCustomerService(customers));

    // The primary phone should be shown in the subtitle; the secondary phone
    // should NOT appear in the list tile (only on the detail screen).
    expect(find.textContaining('0901234567'), findsOneWidget);
    expect(find.textContaining('0909876543'), findsNothing);
  });

  testWidgets('list tile falls back to legacy phone field when phones empty',
      (tester) async {
    final customers = [
      const Customer(id: 1, name: 'Sinh', phone: '0901234567'),
    ];
    await _pumpScreen(tester, _FakeCustomerService(customers));

    expect(find.textContaining('0901234567'), findsOneWidget);
  });

  // DG-252 review r2 [M1]: the production add-mode call site must wire
  // onUseExisting so the duplicate-warning "use existing" choice navigates
  // to the chosen customer detail instead of being a silent no-op.
  testWidgets(
      'create form "Dùng khách sẵn có" navigates to chosen customer detail '
      '(FR8/AC6)', (tester) async {
    const existing = Customer(
      id: 42,
      name: 'Sinh',
      phone: '0901-234-567',
    );
    final service = _FakeCustomerService(
      const [],
      searchResults: {
        'Sinh': [existing],
        '0901234567': [existing],
      },
    );
    await _pumpScreen(tester, service);

    // Open the create form via the FAB.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // Type a name + phone that match the existing customer to trigger the
    // duplicate-warning dialog.
    await tester.enterText(find.byType(TextFormField).at(0), 'Sinh');
    await tester.enterText(find.byType(TextFormField).at(1), '0901234567');
    await tester.tap(find.text(VN.save));
    await tester.pumpAndSettle();

    expect(find.text(CustomersLabels.duplicateWarningTitle), findsOneWidget);

    // Tap the "Dùng khách sẵn có" button — the production wiring must push
    // the /customers/42 detail route.
    final useExistingButton = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(CustomersLabels.duplicateWarningUseExisting),
    );
    await tester.tap(useExistingButton);
    await tester.pumpAndSettle();

    // The sentinel detail route renders 'detail-42' on navigation.
    expect(find.text('detail-42'), findsOneWidget);
  });
}