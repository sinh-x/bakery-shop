import 'dart:async';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/models/cash_drawer.dart';
import 'package:bakery_app/features/cash_drawer/cash_drawer_screen.dart';
import 'package:bakery_app/features/cash_drawer/widgets/cash_drawer_transaction_list.dart';
import 'package:bakery_app/providers/cash_drawer_provider.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dio interceptor that serves the cash-drawer status + history endpoints
/// with a configurable active drawer (or null for "no active drawer") and an
/// empty history list. Mirrors the pattern in `cash_drawer_service_test.dart`.
///
/// DG-343 Phase 3: also serves the per-drawer transactions endpoint so the
/// "Chi tiết giao dịch" tab and history tap navigation can be exercised.
class _CashDrawerInterceptor extends Interceptor {
  _CashDrawerInterceptor({
    this.activeDrawer,
    this.historyItems = const [],
    this.transactionItems = const [],
    this.transactionTotal = 0,
  });

  final Map<String, dynamic>? activeDrawer;
  final List<Map<String, dynamic>> historyItems;
  final List<Map<String, dynamic>> transactionItems;
  final int transactionTotal;

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
    // DG-343 Phase 3: serve the per-drawer transactions endpoint for the
    // active drawer and any closed drawer tapped in History.
    if (options.path.startsWith('/api/cash-drawer/') &&
        options.path.endsWith('/transactions') &&
        options.method == 'GET') {
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            'total': transactionTotal,
            'limit': options.queryParameters['limit'] ?? 50,
            'offset': options.queryParameters['offset'] ?? 0,
            'items': transactionItems,
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
  int expectedBalance = 1000000,
  int? countedAmount,
  int? discrepancy,
  int? closingBalance,
}) =>
    {
      'id': id,
      'openedAt': '2026-08-01T00:00:00Z',
      'closedAt': null,
      'status': status,
      'openingBalance': openingBalance,
      'countedAmount': countedAmount,
      'discrepancy': discrepancy,
      'expectedBalance': expectedBalance,
      'closingBalance': closingBalance,
    };

ProviderContainer _containerWith(Map<String, dynamic>? active,
        {List<Map<String, dynamic>> history = const [],
        List<Map<String, dynamic>> transactions = const [],
        int transactionTotal = 0}) =>
    ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(
          Dio(BaseOptions(baseUrl: 'http://test'))
            ..interceptors.add(
              _CashDrawerInterceptor(
                activeDrawer: active,
                historyItems: history,
                transactionItems: transactions,
                transactionTotal: transactionTotal,
              ),
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
        expectedBalance: 1550000,
      ),
    );
    addTearDown(container.dispose);
    await _pump(tester, container);

    expect(find.text(VN.cashDrawerStatusOpen), findsWidgets);
    // DG-363 Phase 3: the breakdown card is taller now (8 categories in 2
    // groups + group totals + expected balance), so the action bar sits
    // below the fold. Drag up to reveal it before asserting on its buttons.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text(VN.cashDrawerCashIn), findsOneWidget);
    expect(find.text(VN.cashDrawerCashOut), findsOneWidget);
    // DG-359 Phase 2: the breakdown card now renders a "Đóng quầy" category
    // label that collides with the close action button label, so scope the
    // assertion to a FilledButton.
    expect(
      find.widgetWithText(FilledButton, VN.cashDrawerClose),
      findsOneWidget,
    );
    // 1.550.000đ is the expected balance per AC6 formula.
    expect(find.textContaining('1.550.000'), findsOneWidget);
  });

  testWidgets('cash in button opens dialog with amount field (AC2)',
      (tester) async {
    final container = _containerWith(_drawerJson());
    addTearDown(container.dispose);
    await _pump(tester, container);

    // DG-360 Phase 2: the status card now always renders the 1101 reference
    // row (even at 0), which makes the card one row taller and pushes the
    // action bar below the default 600px viewport. Drag the list up to
    // bring the cash-in button into view — same pattern as the close
    // button test above.
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
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

    // DG-360 Phase 2: drag the list up so the cash-out button is tappable
    // (see the cash-in test above for the reason).
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
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

    // DG-359 Phase 2: scope the tap to the close action button by its unique
    // icon — the breakdown card now also renders a "Đóng quầy" category
    // label. The breakdown card also makes the status card taller, so we
    // drag the list up to bring the action bar into the viewport.
    await tester.drag(
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.lock_outline));
    await tester.pumpAndSettle();

    expect(find.text(VN.cashDrawerClose), findsWidgets);
    expect(find.textContaining('1.550.000'), findsWidgets);
    // The dialog confirm button is inside the AlertDialog.
    expect(find.byType(AlertDialog), findsOneWidget);
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

    // The second open call must carry carryOverConfirmed: true. DG-360
    // Phase 2: the open body now uses surplusConfirmed/shortageConfirmed
    // (matching the close flow) — the obsolete transfer/excess flags are
    // gone. The confirmation loop re-issues the open body with only the
    // carryOverConfirmed flag set on the retry.
    expect(interceptor.openCalls, [
      {
        'openingBalance': 1550000,
        'note': '',
        'carryOverConfirmed': false,
      },
      {
        'openingBalance': 1550000,
        'note': '',
        'carryOverConfirmed': true,
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

  // ── DG-343 Phase 3: "Chi tiết giao dịch" tab + history tap navigation ─────
  testWidgets(
      'FR3: renders the "Chi tiết giao dịch" tab as the 3rd tab',
      (tester) async {
    final container = _containerWith(_drawerJson());
    addTearDown(container.dispose);
    await _pump(tester, container);

    // All three tab labels are present in the TabBar.
    expect(find.text(VN.cashDrawerStatusOpen), findsWidgets);
    expect(find.text(VN.cashDrawerHistory), findsWidgets);
    expect(find.text(VN.cashDrawerTransactionsTab), findsOneWidget);
  });

  testWidgets(
      'FR3/AC1: transaction tab shows the active drawer transactions when a '
      'drawer is open', (tester) async {
    final container = _containerWith(
      _drawerJson(id: '5', expectedBalance: 1000000),
      transactions: [
        {
          'id': '1',
          'type': 'cash_drawer_open',
          'amount': 1000000,
          'timestamp': '2026-08-04T08:00:00Z',
          'note': 'Mở quầy sáng',
        },
        {
          'id': '2',
          'type': 'payment_transaction',
          'amount': 75000,
          'timestamp': '2026-08-04T09:30:00Z',
          'note': 'Bán bánh mì',
        },
      ],
      transactionTotal: 2,
    );
    addTearDown(container.dispose);
    await _pump(tester, container);

    // Switch to the transaction tab (3rd tab).
    await tester.tap(find.byIcon(Icons.receipt_long));
    await tester.pumpAndSettle();

    // The active drawer's transactions render with short type labels (AC3).
    expect(find.text(VN.cashDrawerTxnTypeOpen), findsOneWidget);
    expect(find.text(VN.cashDrawerTxnTypeSale), findsOneWidget);
    expect(find.text('Mở quầy sáng'), findsOneWidget);
    expect(find.text('Bán bánh mì'), findsOneWidget);
  });

  testWidgets(
      'FR3: transaction tab is disabled (greyed) when no drawer is open',
      (tester) async {
    final container = _containerWith(null);
    addTearDown(container.dispose);
    await _pump(tester, container);

    // The tab label is present.
    final tabFinder = find.ancestor(
      of: find.text(VN.cashDrawerTransactionsTab),
      matching: find.byType(Tab),
    );
    expect(tabFinder, findsOneWidget);
    // The tab icon uses the disabled color (no active drawer).
    final icon = tester.widget<Icon>(
      find.descendant(of: tabFinder, matching: find.byType(Icon)),
    );
    expect(icon.color, Theme.of(tester.element(tabFinder)).disabledColor);

    // Tapping the disabled tab snaps back to the status tab rather than
    // showing the transaction list. The placeholder must not surface the
    // active-drawer transaction rows.
    await tester.tap(tabFinder);
    await tester.pumpAndSettle();
    expect(find.byType(CashDrawerTransactionList), findsNothing);
  });

  testWidgets(
      'FR4/AC2: tapping a closed drawer in History navigates to the '
      'transaction detail screen', (tester) async {
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
      transactions: [
        {
          'id': '1',
          'type': 'cash_drawer_open',
          'amount': 1000000,
          'timestamp': '2026-08-01T08:00:00Z',
          'note': 'Mở quầy sáng',
        },
        {
          'id': '2',
          'type': 'cash_drawer_close_adjust',
          'amount': -10000,
          'timestamp': '2026-08-01T20:00:00Z',
          'note': 'Đóng quầy tối',
        },
      ],
      transactionTotal: 2,
    );
    addTearDown(container.dispose);
    await _pump(tester, container);

    // Switch to the history tab.
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    // Expand the closed drawer card to reveal the "Chi tiết giao dịch"
    // affordance button (FR4/AC2).
    await tester.tap(find.textContaining('01/08/2026'));
    await tester.pumpAndSettle();

    // Tap the "Chi tiết giao dịch" TextButton inside the expanded card to
    // navigate to the transaction detail screen for this closed drawer.
    await tester.tap(find.widgetWithText(TextButton, VN.cashDrawerTransactionsTab));
    await tester.pumpAndSettle();

    // The pushed screen shows the transaction list for drawer 7.
    expect(find.byType(CashDrawerTransactionList), findsOneWidget);
    expect(find.text(VN.cashDrawerTxnTypeOpen), findsOneWidget);
    expect(find.text(VN.cashDrawerTxnTypeClose), findsOneWidget);
    // The notes (distinct from the short type labels) are present.
    expect(find.text('Mở quầy sáng'), findsOneWidget);
    expect(find.text('Đóng quầy tối'), findsOneWidget);
    // AppBar includes the openedAt date for the closed drawer.
    expect(find.textContaining('01/08/2026'), findsWidgets);
  });

  // ── DG-360 Phase 2: 1101 reference at any value + surplus/shortage open flow
  testWidgets(
      'AC1: _EmptyActiveView renders the 1101 line at a negative value with '
      'the error color (no longer hidden by the old `<= 0` guard)',
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
            .overrideWith((ref) async => -200000),
        cashDrawerPreviousCloseProvider
            .overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);
    await _pump(tester, container);

    // The 1101 reference line is rendered with the negative value.
    final refLine = find.textContaining(VN.cashDrawerReferenceBalance);
    expect(refLine, findsOneWidget);
    expect(find.textContaining('-200.000'), findsOneWidget);
    // NFR1: the negative value uses the error color.
    final errorColor = Theme.of(tester.element(refLine)).colorScheme.error;
    final refText = tester.widget<Text>(refLine);
    expect(refText.style?.color, errorColor);
  });

  testWidgets(
      'AC2: _EmptyActiveView renders the 1101 line at zero (no longer hidden '
      'by the old `<= 0` guard)', (tester) async {
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
        cashDrawerAccountingBalance1101Provider.overrideWith((ref) async => 0),
        cashDrawerPreviousCloseProvider
            .overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);
    await _pump(tester, container);

    expect(find.textContaining(VN.cashDrawerReferenceBalance), findsOneWidget);
    expect(find.textContaining('0'), findsWidgets);
  });

  testWidgets(
      'AC6: CashDrawerStatusCard renders the 1101 line at a negative value '
      'with the error color (no longer hidden by the old `> 0` guard)',
      (tester) async {
    // The default _containerWith interceptor serves status from
    // `activeDrawer` without an `accountingBalance1101` field, so build a
    // container that injects a negative 1101 balance directly.
    final container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(
          Dio(BaseOptions(baseUrl: 'http://test'))
            ..interceptors.add(
              _CashDrawerInterceptor(
                activeDrawer: <String, dynamic>{
                  'id': '5',
                  'openedAt': '2026-08-01T00:00:00Z',
                  'closedAt': null,
                  'status': 'open',
                  'openingBalance': -200000,
                  'countedAmount': null,
                  'discrepancy': null,
                  'expectedBalance': 500000,
                  'accountingBalance1101': -200000,
                },
                historyItems: const <Map<String, dynamic>>[],
                transactionItems: const <Map<String, dynamic>>[],
                transactionTotal: 0,
              ),
            ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await _pump(tester, container);

    // The 1101 reference line is rendered inside the status card with the
    // negative value and the error color (NFR1 via `_BalanceRow`).
    final refRow = find.text(VN.cashDrawerReferenceBalance);
    expect(refRow, findsOneWidget);
    expect(find.textContaining('-200.000'), findsWidgets);
    // The _BalanceRow value Text is rendered with colorScheme.error. Walk
    // every Text widget in the tree and assert at least one whose data
    // contains the negative value is styled with the error color.
    final errorColor = Theme.of(tester.element(refRow)).colorScheme.error;
    final hasErrorColoredNegative = tester
        .widgetList<Text>(find.byType(Text))
        .any((t) =>
            t.data != null &&
            t.data!.contains('-200.000') &&
            t.style?.color == errorColor);
    expect(hasErrorColoredNegative, isTrue);
  });

  testWidgets(
      'DG-360 Phase 2 FR7: open flow surfaces the surplus proposal dialog on '
      '409 surplusProposal and retries with surplusConfirmed + surplusSource',
      (tester) async {
    final interceptor = _OpenSurplusShortageInterceptor(
      proposal: _OpenProposal.surplus,
    );
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
    // Enter an opening balance greater than the 1101 reference and confirm.
    await tester.enterText(find.byType(TextFormField).first, '500000');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, VN.cashDrawerOpen),
      ),
    );
    await tester.pumpAndSettle();

    // The first open returned 409 → surplus proposal dialog should appear.
    // The dialog reuses showCloseSurplusDialog with openFlow: true, so its
    // title/question/labels are the open surplus variants.
    expect(find.text(VN.cashDrawerOpenSurplusTitle), findsOneWidget);
    expect(find.text(VN.cashDrawerOpenSurplusQuestion), findsOneWidget);
    expect(find.textContaining('700.000'), findsOneWidget);

    // Accept the surplus as owner_cash.
    await tester.tap(find.text(VN.cashDrawerCloseSurplusOwnerCash));
    await tester.pumpAndSettle();

    // The retry must carry surplusConfirmed + surplusSource=owner_cash.
    expect(interceptor.openCalls.length, 2);
    expect(interceptor.openCalls.last['surplusConfirmed'], true);
    expect(interceptor.openCalls.last['surplusSource'], 'owner_cash');
    expect(find.text(VN.cashDrawerOpenSuccess), findsOneWidget);
  });

  testWidgets(
      'DG-360 Phase 2 FR7: open flow surfaces the shortage proposal dialog on '
      '409 shortageProposal and retries with shortageConfirmed + shortageSource',
      (tester) async {
    final interceptor = _OpenSurplusShortageInterceptor(
      proposal: _OpenProposal.shortage,
    );
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
    await tester.enterText(find.byType(TextFormField).first, '100000');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, VN.cashDrawerOpen),
      ),
    );
    await tester.pumpAndSettle();

    // The first open returned 409 → shortage proposal dialog should appear.
    // The dialog reuses showCloseShortageDialog with openFlow: true, so its
    // title/question/labels are the open shortage variants.
    expect(find.text(VN.cashDrawerOpenShortageTitle), findsOneWidget);
    expect(find.text(VN.cashDrawerOpenShortageQuestion), findsOneWidget);
    expect(find.textContaining('400.000'), findsOneWidget);

    // Accept the shortage as equity_loss.
    await tester.tap(find.text(VN.cashDrawerCloseShortageEquityLoss));
    await tester.pumpAndSettle();

    expect(interceptor.openCalls.length, 2);
    expect(interceptor.openCalls.last['shortageConfirmed'], true);
    expect(interceptor.openCalls.last['shortageSource'], 'equity_loss');
    expect(find.text(VN.cashDrawerOpenSuccess), findsOneWidget);
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

/// DG-360 Phase 2: selects which 409 proposal the
/// [_OpenSurplusShortageInterceptor] emits on the first POST /open.
enum _OpenProposal { surplus, shortage }

/// Dio interceptor that serves status/history GETs and implements the
/// DG-360 Phase 2 surplus/shortage open flow: the first POST /open returns
/// 409 with a `surplusProposal` or `shortageProposal`; subsequent POST /open
/// calls return 201 with an open drawer. Captures every open request body in
/// [openCalls] so tests can assert the confirmation flags + source on retry.
class _OpenSurplusShortageInterceptor extends Interceptor {
  _OpenSurplusShortageInterceptor({required this.proposal});

  final _OpenProposal proposal;
  final List<Map<String, dynamic>> openCalls = [];
  bool _proposalSent = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/api/cash-drawer/status' && options.method == 'GET') {
      // No active drawer; no previous close; 1101 reference is injected via
      // the proposal body itself (the open dialog displays whatever the
      // service returns — here 0, which still renders after the guard
      // removal).
      handler.resolve(
        Response<dynamic>(
          requestOptions: options,
          statusCode: 200,
          data: <String, dynamic>{
            'activeDrawer': null,
            'previousCloseCountedAmount': null,
            'accountingBalance1101': proposal == _OpenProposal.surplus
                ? -200000
                : 500000,
          },
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
            'total': 0,
            'limit': 50,
            'offset': 0,
            'items': const <Map<String, dynamic>>[],
          },
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
        if (proposal == _OpenProposal.surplus) {
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 409,
                data: {
                  'detail': {
                    'message':
                        'Chênh lệch thỺ 700000 VND. Số dư kế toán 1101: '
                        '-200000. Số tiền mở quầy: 500000.',
                    'surplusProposal': {
                      'referenceBalance': -200000,
                      'openingBalance': 500000,
                      'surplus': 700000,
                    },
                  },
                },
              ),
            ),
          );
        } else {
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 409,
                data: {
                  'detail': {
                    'message':
                        'Chênh lệch thiếu 400000 VND. Số dư kế toán 1101: '
                        '500000. Số tiền mở quầy: 100000.',
                    'shortageProposal': {
                      'referenceBalance': 500000,
                      'openingBalance': 100000,
                      'shortage': 400000,
                    },
                  },
                },
              ),
            ),
          );
        }
        return;
      }
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 201,
          data: {
            'id': '9',
            'openedAt': '2026-08-05T00:00:00Z',
            'closedAt': null,
            'status': 'open',
            'openingBalance': body['openingBalance'] as int? ?? 0,
            'countedAmount': null,
            'discrepancy': null,
            'expectedBalance': body['openingBalance'] as int? ?? 0,
          },
        ),
      );
      return;
    }
    handler.next(options);
  }
}