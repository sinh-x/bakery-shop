import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/features/cash_drawer/cash_drawer_screen.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dio interceptor that serves the cash-drawer status + history endpoints
/// with a configurable active drawer (or null for "no active drawer") and an
/// empty history list. Mirrors the pattern in `cash_drawer_service_test.dart`.
class _CashDrawerInterceptor extends Interceptor {
  _CashDrawerInterceptor({this.activeDrawer, this.historyItems = const []});

  final Map<String, dynamic>? activeDrawer;
  final List<Map<String, dynamic>> historyItems;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/api/cash-drawer/status' && options.method == 'GET') {
      handler.resolve(
        Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: activeDrawer,
        ),
      );
      return;
    }
    if (options.path == '/api/cash-drawer/history' && options.method == 'GET') {
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            'total': historyItems.length,
            'limit': 50,
            'offset': 0,
            'items': historyItems,
          },
        ),
      );
      return;
    }
    handler.next(options);
  }
}

Map<String, dynamic> _drawerJson({
  String id = '1',
  String status = 'open',
  int openingBalance = 1000000,
  int cashSales = 0,
  int ownerIn = 0,
  int ownerOut = 0,
  int cashExpenses = 0,
  int expectedBalance = 1000000,
  int? countedAmount,
  int? discrepancy,
}) =>
    {
      'id': id,
      'openedAt': '2026-08-01T00:00:00Z',
      'closedAt': null,
      'status': status,
      'openingBalance': openingBalance,
      'cashSales': cashSales,
      'ownerIn': ownerIn,
      'ownerOut': ownerOut,
      'cashExpenses': cashExpenses,
      'countedAmount': countedAmount,
      'discrepancy': discrepancy,
      'expectedBalance': expectedBalance,
    };

ProviderContainer _containerWith(Map<String, dynamic>? active,
        {List<Map<String, dynamic>> history = const []}) =>
    ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(
          Dio(BaseOptions(baseUrl: 'http://test'))
            ..interceptors.add(
              _CashDrawerInterceptor(activeDrawer: active, historyItems: history),
            ),
        ),
      ],
    );

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: CashDrawerScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders no-active-drawer state with open button (FR1/AC1)',
      (tester) async {
    final container = _containerWith(null);
    addTearDown(container.dispose);
    await _pump(tester, container);

    expect(find.text(VN.cashDrawerNoActive), findsOneWidget);
    expect(find.widgetWithText(FilledButton, VN.cashDrawerOpen), findsOneWidget);
  });

  testWidgets('renders active drawer status card with expected balance (FR4/AC6)',
      (tester) async {
    final container = _containerWith(
      _drawerJson(
        openingBalance: 1000000,
        cashSales: 500000,
        ownerIn: 200000,
        ownerOut: 100000,
        cashExpenses: 50000,
        expectedBalance: 1550000,
      ),
    );
    addTearDown(container.dispose);
    await _pump(tester, container);

    expect(find.text(VN.cashDrawerStatusOpen), findsWidgets);
    expect(find.text(VN.cashDrawerCashIn), findsOneWidget);
    expect(find.text(VN.cashDrawerCashOut), findsOneWidget);
    expect(find.text(VN.cashDrawerClose), findsOneWidget);
    // 1.550.000đ is the expected balance per AC6 formula.
    expect(find.textContaining('1.550.000'), findsOneWidget);
  });

  testWidgets('cash in button opens dialog with amount field (AC2)',
      (tester) async {
    final container = _containerWith(_drawerJson());
    addTearDown(container.dispose);
    await _pump(tester, container);

    await tester.tap(find.text(VN.cashDrawerCashIn));
    await tester.pumpAndSettle();

    expect(find.text(VN.cashDrawerCashIn), findsWidgets);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.widgetWithText(FilledButton, VN.xacNhan), findsOneWidget);
  });

  testWidgets('cash out button opens dialog (AC3)', (tester) async {
    final container = _containerWith(_drawerJson());
    addTearDown(container.dispose);
    await _pump(tester, container);

    await tester.tap(find.text(VN.cashDrawerCashOut));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.widgetWithText(FilledButton, VN.xacNhan), findsOneWidget);
  });

  testWidgets('close button opens dialog showing expected balance (AC7)',
      (tester) async {
    final container = _containerWith(
      _drawerJson(expectedBalance: 1550000),
    );
    addTearDown(container.dispose);
    await _pump(tester, container);

    await tester.tap(find.text(VN.cashDrawerClose));
    await tester.pumpAndSettle();

    expect(find.text(VN.cashDrawerClose), findsWidgets);
    expect(find.textContaining('1.550.000'), findsWidgets);
    // The dialog confirm button is inside the AlertDialog.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, VN.cashDrawerClose),
      ),
      findsOneWidget,
    );
  });

  testWidgets('history tab renders past drawers (FR10)', (tester) async {
    final container = _containerWith(
      null,
      history: [
        _drawerJson(
          id: '7',
          status: 'closed',
          expectedBalance: 1550000,
          countedAmount: 1540000,
          discrepancy: -10000,
        ),
      ],
    );
    addTearDown(container.dispose);
    await _pump(tester, container);

    // Switch to history tab.
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.history), findsWidgets);
    // The closed drawer's expected balance appears in the history card.
    expect(find.textContaining('1.550.000'), findsOneWidget);
    // Discrepancy chip shows the shortage label.
    expect(find.textContaining(VN.cashDrawerShortage), findsOneWidget);
  });

  testWidgets('open dialog cancels without mutating when cancelled',
      (tester) async {
    final container = _containerWith(null);
    addTearDown(container.dispose);
    await _pump(tester, container);

    await tester.tap(find.widgetWithText(FilledButton, VN.cashDrawerOpen));
    await tester.pumpAndSettle();

    await tester.tap(find.text(VN.cancel));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(VN.cashDrawerNoActive), findsOneWidget);
  });

  testWidgets(
      'FR9 carry-over: open flow surfaces proposal dialog and retries with '
      'carryOverConfirmed: true on accept (AC8)', (tester) async {
    final interceptor = _CarryOverInterceptor();
    final container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(
          Dio(BaseOptions(baseUrl: 'http://test'))
            ..interceptors.add(interceptor),
        ),
      ],
    );
    addTearDown(container.dispose);
    await _pump(tester, container);

    // Tap "Mở quỹ" → amount dialog.
    await tester.tap(find.widgetWithText(FilledButton, VN.cashDrawerOpen));
    await tester.pumpAndSettle();
    // Enter an opening balance and confirm (dialog's confirm button).
    await tester.enterText(find.byType(TextFormField).first, '1550000');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, VN.cashDrawerOpen),
      ),
    );
    await tester.pumpAndSettle();

    // The first open returned 409 → carry-over proposal dialog should appear.
    expect(find.text(VN.cashDrawerCarryOverTitle), findsOneWidget);
    expect(find.text(VN.cashDrawerCarryOverQuestion), findsOneWidget);
    expect(find.textContaining('1.550.000'), findsOneWidget);
    expect(find.text(VN.cashDrawerCarryOverAccept), findsOneWidget);

    // Accept the carry-over.
    await tester.tap(find.text(VN.cashDrawerCarryOverAccept));
    await tester.pumpAndSettle();

    // The second open call must carry carryOverConfirmed: true.
    expect(interceptor.openCalls, [
      {'openingBalance': 1550000, 'note': '', 'carryOverConfirmed': false},
      {'openingBalance': 1550000, 'note': '', 'carryOverConfirmed': true},
    ]);
    // Success snackbar appears.
    expect(find.text(VN.cashDrawerOpenSuccess), findsOneWidget);
  });

  testWidgets(
      'FR9 carry-over: declining re-opens with carryOverConfirmed: false',
      (tester) async {
    final interceptor = _CarryOverInterceptor();
    final container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(
          Dio(BaseOptions(baseUrl: 'http://test'))
            ..interceptors.add(interceptor),
        ),
      ],
    );
    addTearDown(container.dispose);
    await _pump(tester, container);

    await tester.tap(find.widgetWithText(FilledButton, VN.cashDrawerOpen));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '1550000');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, VN.cashDrawerOpen),
      ),
    );
    await tester.pumpAndSettle();

    // Decline the carry-over.
    await tester.tap(find.text(VN.cashDrawerCarryOverDecline));
    await tester.pumpAndSettle();

    expect(interceptor.openCalls.last['carryOverConfirmed'], false);
    expect(find.text(VN.cashDrawerOpenSuccess), findsOneWidget);
  });

  testWidgets(
      'FR9 carry-over: cancelling the proposal dialog does not call open '
      'a second time', (tester) async {
    final interceptor = _CarryOverInterceptor();
    final container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(
          Dio(BaseOptions(baseUrl: 'http://test'))
            ..interceptors.add(interceptor),
        ),
      ],
    );
    addTearDown(container.dispose);
    await _pump(tester, container);

    await tester.tap(find.widgetWithText(FilledButton, VN.cashDrawerOpen));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '1550000');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, VN.cashDrawerOpen),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(VN.cashDrawerCarryOverTitle), findsOneWidget);
    // Press the cancel TextButton (not accept/decline).
    await tester.tap(find.text(VN.cancel));
    await tester.pumpAndSettle();

    // Only the first (409) open call occurred.
    expect(interceptor.openCalls.length, 1);
    // No success snackbar.
    expect(find.text(VN.cashDrawerOpenSuccess), findsNothing);
  });
}

/// Dio interceptor that serves status/history GETs and implements the FR9
/// carry-over open flow: the first POST /open returns 409 with a
/// `carryOverProposal`; subsequent POST /open calls return 201 with an open
/// drawer. Captures every open request body in [openCalls].
class _CarryOverInterceptor extends Interceptor {
  _CarryOverInterceptor();

  final List<Map<String, dynamic>> openCalls = [];
  bool _proposalSent = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/api/cash-drawer/status' && options.method == 'GET') {
      handler.resolve(
        Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: null,
        ),
      );
      return;
    }
    if (options.path == '/api/cash-drawer/history' && options.method == 'GET') {
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {'total': 0, 'limit': 50, 'offset': 0, 'items': const []},
        ),
      );
      return;
    }
    if (options.path == '/api/cash-drawer/open' && options.method == 'POST') {
      final body = options.data is Map<String, dynamic>
          ? Map<String, dynamic>.from(options.data as Map)
          : <String, dynamic>{};
      openCalls.add(body);
      if (!_proposalSent) {
        _proposalSent = true;
        handler.reject(
          DioException(
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: 409,
              data: {
                'detail': {
                  'message':
                      'Quỹ hôm trước chưa đóng — xác nhận số dư chuyển sang hôm nay.',
                  'carryOverProposal': {
                    'amount': 1550000,
                    'fromDrawerId': '7',
                    'fromOpenedAt': '2026-07-28T08:00:00Z',
                    'fromExpectedBalance': 1550000,
                  },
                },
              },
            ),
          ),
        );
        return;
      }
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 201,
          data: {
            'id': '8',
            'openedAt': '2026-08-01T00:00:00Z',
            'closedAt': null,
            'status': 'open',
            'openingBalance': body['openingBalance'] as int? ?? 1550000,
            'cashSales': 0,
            'ownerIn': 0,
            'ownerOut': 0,
            'cashExpenses': 0,
            'countedAmount': null,
            'discrepancy': null,
            'expectedBalance': body['openingBalance'] as int? ?? 1550000,
          },
        ),
      );
      return;
    }
    handler.next(options);
  }
}