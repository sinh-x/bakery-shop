import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/customer_service.dart';
import 'package:bakery_app/data/models/customer.dart';
import 'package:bakery_app/features/customers/customer_detail_screen.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/auth/login_screen_test_helpers.dart';

class _FakeCustomerService extends CustomerService {
  _FakeCustomerService(this._customer, this._orders, {this.deleteError})
      : super(Dio());

  final Customer _customer;
  final List<Map<String, dynamic>> _orders;

  /// When set, `deleteCustomer` throws this instead of succeeding. Used by
  /// the DELETE 409/403 path tests (DG-252 review r2 [M2]).
  final Object? deleteError;

  @override
  Future<Customer> getCustomer(int id) async => _customer;

  @override
  Future<List<Map<String, dynamic>>> getCustomerOrders(int id) async =>
      _orders;

  @override
  Future<void> deleteCustomer(int id) async {
    final error = deleteError;
    if (error != null) throw error;
  }
}

/// Builds a DioException simulating a backend 409/403 with a VN `detail`
/// message, matching the shape produced by `src/baker/api/customers.py`.
DioException _dioErrorWithDetail(int statusCode, String detail) {
  final response = Response<Map<String, dynamic>>(
    requestOptions: RequestOptions(path: '/api/customers/1'),
    statusCode: statusCode,
    data: {'detail': detail},
  );
  return DioException(
    requestOptions: response.requestOptions,
    response: response,
    type: DioExceptionType.badResponse,
  );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  CustomerService service, {
  String role = 'admin',
}) async {
  final prefs = await seedAuthenticatedPrefs(role: role);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        customerServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const CustomerDetailScreen(customerId: 1),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Builds a DioException simulating a backend 403 with NO `detail` body
/// (e.g. a reverse-proxy/auth-gateway 403 that did not originate from the
/// app's centralized exception handler). Used by the r4 [Mn1] fallback
/// label test.
DioException _dioError403WithoutDetail() {
  final response = Response<Map<String, dynamic>>(
    requestOptions: RequestOptions(path: '/api/customers/1'),
    statusCode: 403,
    data: null,
  );
  return DioException(
    requestOptions: response.requestOptions,
    response: response,
    type: DioExceptionType.badResponse,
  );
}

void main() {
  testWidgets(
      'detail card shows all phones with primary highlighted (AC9)',
      (tester) async {
    const customer = Customer(
      id: 1,
      name: 'Sinh',
      phone: '0901234567',
      phones: [
        CustomerPhone(phone: '0901234567', isPrimary: true),
        CustomerPhone(phone: '0909876543', isPrimary: false),
      ],
    );
    await _pumpScreen(tester, _FakeCustomerService(customer, const []));

    // Both phone numbers should appear.
    expect(find.textContaining('0901234567'), findsOneWidget);
    expect(find.textContaining('0909876543'), findsOneWidget);
    // The primary phone label marker should appear once.
    expect(find.textContaining(VN.customerPrimaryPhone), findsOneWidget);
  });

  testWidgets(
      'detail card falls back to legacy phone when phones list empty',
      (tester) async {
    const customer =
        Customer(id: 1, name: 'Sinh', phone: '0901234567');
    await _pumpScreen(tester, _FakeCustomerService(customer, const []));

    expect(find.textContaining('0901234567'), findsOneWidget);
    // No "(Số chính)" marker is appended in legacy fallback mode.
    expect(find.textContaining(VN.customerPrimaryPhone), findsNothing);
  });

  testWidgets('detail card shows no phone line when customer has none',
      (tester) async {
    const customer = Customer(id: 1, name: 'Sinh', phone: '');
    await _pumpScreen(tester, _FakeCustomerService(customer, const []));

    expect(find.text('Sinh'), findsOneWidget);
    // No star icons (phone lines) should be rendered.
    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.byIcon(Icons.star_border), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // DG-252 review r2 [M2] — DELETE contract changes (409 guard + admin-only).
  // ---------------------------------------------------------------------------

  testWidgets('admin sees the delete menu item (FR10/AC7)', (tester) async {
    const customer = Customer(id: 1, name: 'Sinh', phone: '0901234567');
    await _pumpScreen(tester, _FakeCustomerService(customer, const []));

    // Open the overflow menu.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text(VN.deleteCustomer), findsOneWidget);
  });

  testWidgets('staff does not see the delete menu item (admin-only)',
      (tester) async {
    const customer = Customer(id: 1, name: 'Sinh', phone: '0901234567');
    await _pumpScreen(
      tester,
      _FakeCustomerService(customer, const []),
      role: 'staff',
    );

    // Open the overflow menu.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    // Delete item is gated by role; only edit + settings appear.
    expect(find.text(VN.deleteCustomer), findsNothing);
    expect(find.text(VN.editCustomer), findsOneWidget);
  });

  testWidgets(
      'delete 409 surfaces the backend VN guidance detail instead of a raw '
      'DioException string', (tester) async {
    const customer = Customer(id: 1, name: 'Sinh', phone: '0901234567');
    // The backend's centralized 409 message (FR10/AC7).
    const detail =
        'Khách hàng đang có đơn hàng liên kết. Hãy gộp khách hoặc huỷ liên kết '
        'đơn trước khi xóa.';
    final service = _FakeCustomerService(
      customer,
      const [],
      deleteError: _dioErrorWithDetail(409, detail),
    );
    await _pumpScreen(tester, service);

    // Open the overflow menu and pick delete.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(VN.deleteCustomer));
    await tester.pumpAndSettle();

    // Confirm in the AlertDialog.
    await tester.tap(find.text(VN.deleteCustomer));
    await tester.pumpAndSettle();

    // The backend's VN guidance must be surfaced, not a raw DioException
    // string.
    expect(find.textContaining(detail), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });

  testWidgets(
      'delete 403 surfaces the backend VN permission detail (admin-only API)',
      (tester) async {
    const customer = Customer(id: 1, name: 'Sinh', phone: '0901234567');
    // The backend's RequireRole("admin") 403 detail (auth.py) — a VN message,
    // not a raw English string.
    const detail = 'Bạn không có quyền thực hiện thao tác này.';
    final service = _FakeCustomerService(
      customer,
      const [],
      deleteError: _dioErrorWithDetail(403, detail),
    );
    await _pumpScreen(tester, service);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(VN.deleteCustomer));
    await tester.pumpAndSettle();
    await tester.tap(find.text(VN.deleteCustomer));
    await tester.pumpAndSettle();

    // The backend's VN permission message is surfaced.
    expect(find.textContaining(detail), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });

  testWidgets(
      'delete error with no backend detail falls back to the generic VN '
      'label', (tester) async {
    const customer = Customer(id: 1, name: 'Sinh', phone: '0901234567');
    // A network error with no response body — no `detail` to extract.
    final service = _FakeCustomerService(
      customer,
      const [],
      deleteError: DioException(
        requestOptions: RequestOptions(path: '/api/customers/1'),
        type: DioExceptionType.connectionError,
      ),
    );
    await _pumpScreen(tester, service);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(VN.deleteCustomer));
    await tester.pumpAndSettle();
    await tester.tap(find.text(VN.deleteCustomer));
    await tester.pumpAndSettle();

    // The generic VN fallback label is shown, not raw exception text.
    expect(find.text(CustomersLabels.customerDeleteFailed), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });

  testWidgets(
      'delete 403 with no backend detail falls back to the admin-only VN '
      'label instead of the generic failure (r4 Mn1)', (tester) async {
    const customer = Customer(id: 1, name: 'Sinh', phone: '0901234567');
    // A 403 with no `detail` body — the r4 [Mn1] path must surface the
    // dedicated admin-only VN label (VN Label Policy preferred over the
    // generic deletion-failed string) so the user understands the cause
    // is permissions, not a generic failure.
    final service = _FakeCustomerService(
      customer,
      const [],
      deleteError: _dioError403WithoutDetail(),
    );
    await _pumpScreen(tester, service);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(VN.deleteCustomer));
    await tester.pumpAndSettle();
    await tester.tap(find.text(VN.deleteCustomer));
    await tester.pumpAndSettle();

    // The admin-only VN fallback label is shown, not the generic failure
    // label and not a raw DioException string.
    expect(
      find.text(CustomersLabels.customerDeleteAdminOnly),
      findsOneWidget,
    );
    expect(find.text(CustomersLabels.customerDeleteFailed), findsNothing);
    expect(find.textContaining('DioException'), findsNothing);
  });
}