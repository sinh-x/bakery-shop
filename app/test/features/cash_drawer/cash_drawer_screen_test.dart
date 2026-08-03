import 'dart:async';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/models/cash_drawer.dart';
import 'package:bakery_app/features/cash_drawer/cash_drawer_screen.dart';
import 'package:bakery_app/providers/cash_drawer_provider.dart';
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

    // Tap "Mở quầy" → amount dialog.
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

    // The second open call must carry carryOverConfirmed: true. The other
    // confirmation flags default to false and are sent because the open
    // dialog's confirmation loop re-issues the full open body.
    expect(interceptor.openCalls, [
      {
        'openingBalance': 1550000,
        'note': '',
        'carryOverConfirmed': false,
        'transferConfirmed': false,
        'stockReconciliationConfirmed': false,
        'unidentifiedSaleConfirmed': false,
        'ownerCapitalConfirmed': false,
      },
      {
        'openingBalance': 1550000,
        'note': '',
        'carryOverConfirmed': true,
        'transferConfirmed': false,
        'stockReconciliationConfirmed': false,
        'unidentifiedSaleConfirmed': false,
        'ownerCapitalConfirmed': false,
      },
    ]);
    // Success snackbar appears.
    expect(find.text(VN.cashDrawerOpenSuccess), findsOneWidget);
  });

  testWidgets(
      'FR9 carry-over: declining re-opens with carryOverConfirmed: true '
      '(CQ-4: flag confirms awareness, not acceptance)', (tester) async {
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

    // CQ-4: even on decline, `carryOverConfirmed` must be `true` — the flag
    // confirms awareness of the carry-over proposal, not acceptance. Sending
    // `false` would cause the backend to re-emit a 409 and re-loop the dialog.
    expect(interceptor.openCalls.last['carryOverConfirmed'], true);
    expect(find.text(VN.cashDrawerOpenSuccess), findsOneWidget);
  });

  // UI-1: widget test coverage for loading/error states in _EmptyActiveView.
  // The _EmptyActiveView is a private widget rendered when the active status
  // resolves to null. Its 1101 and previous-close reference lines branch on
  // AsyncValue loading/error/data, so we override those providers directly
  // to exercise each branch without spinning up a real Dio flow.
  testWidgets(
      'UI-1 _EmptyActiveView shows inline progress while the 1101 and '
      'previous-close providers are loading', (tester) async {
    // Use never-completing Completers so the providers stay in the loading
    // branch. We pump only a single frame (not pumpAndSettle, which would
    // block waiting for the pending futures to resolve).
    final balanceCompleter = Completer<int>();
    final previousCloseCompleter = Completer<int?>();
    final container = ProviderContainer(
      overrides: [
        cashDrawerStatusProvider.overrideWith((ref) async => null),
        cashDrawerHistoryProvider(const CashDrawerHistoryFilter())
            .overrideWith((ref) async => const CashDrawerHistoryResponse(
                  total: 0,
                  limit: 50,
                  offset: 0,
                  items: <CashDrawer>[],
                )),
        cashDrawerAccountingBalance1101Provider
            .overrideWith((ref) => balanceCompleter.future),
        cashDrawerPreviousCloseProvider
            .overrideWith((ref) => previousCloseCompleter.future),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() {
      if (!balanceCompleter.isCompleted) balanceCompleter.complete(0);
      if (!previousCloseCompleter.isCompleted) previousCloseCompleter.complete(null);
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CashDrawerScreen()),
      ),
    );
    // Pump a few frames so the status provider resolves to null and the
    // _EmptyActiveView renders, without settling the pending references.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(VN.cashDrawerNoActive), findsOneWidget);
    // Two inline CircularProgressIndicator spinners (one per reference line).
    expect(
      find.byType(CircularProgressIndicator),
      findsNWidgets(2),
    );
  });

  testWidgets(
      'UI-1 _EmptyActiveView hides the 1101 and previous-close lines when '
      'those providers error (error branch renders SizedBox.shrink)',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        cashDrawerStatusProvider.overrideWith((ref) async => null),
        cashDrawerHistoryProvider(const CashDrawerHistoryFilter())
            .overrideWith((ref) async => const CashDrawerHistoryResponse(
                  total: 0,
                  limit: 50,
                  offset: 0,
                  items: <CashDrawer>[],
                )),
        cashDrawerAccountingBalance1101Provider
            .overrideWith((ref) => Future<int>.error(Exception('1101 boom'))),
        cashDrawerPreviousCloseProvider
            .overrideWith((ref) => Future<int?>.error(Exception('prev boom'))),
      ],
    );
    addTearDown(container.dispose);
    await _pump(tester, container);

    expect(find.text(VN.cashDrawerNoActive), findsOneWidget);
    // The reference-balance labels must NOT appear on error — the lines
    // collapse to SizedBox.shrink rather than crashing the screen.
    expect(find.textContaining(VN.cashDrawerReferenceBalance), findsNothing);
    expect(find.textContaining(VN.cashDrawerPreviousCloseBalance), findsNothing);
    // No inline spinners remain once both providers settle to error.
    expect(find.byType(CircularProgressIndicator), findsNothing);
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
      // CQ-4: a retry after the carry-over proposal must send
      // `carryOverConfirmed: true`. Sending `false` means the owner has not
      // acknowledged the carry-over, so the backend re-emits a 409 to
      // re-loop the proposal dialog. This guard enforces the CQ-4 fix.
      if (body['carryOverConfirmed'] != true) {
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