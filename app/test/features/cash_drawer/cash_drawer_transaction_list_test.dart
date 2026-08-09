import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/features/cash_drawer/widgets/cash_drawer_transaction_list.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dio interceptor that serves a fixed transaction page for a single drawer
/// id. Captures the request path so tests can assert on the wiring.
class _TxnInterceptor extends Interceptor {
  _TxnInterceptor({
    required this.total,
    required this.items,
  });

  final int total;
  final List<Map<String, dynamic>> items;

  String? lastPath;
  Map<String, dynamic>? lastQuery;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    lastPath = options.path;
    lastQuery = options.queryParameters;
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'total': total,
          'limit': options.queryParameters['limit'] ?? 50,
          'offset': options.queryParameters['offset'] ?? 0,
          'items': items,
        },
      ),
    );
  }
}

Map<String, dynamic> _txn({
  String id = '1',
  String type = 'cash_drawer_open',
  int amount = 1000000,
  String timestamp = '2026-08-01T08:00:00Z',
  String note = '',
  String reference = '',
  String referenceDetail = '',
}) =>
    {
      'id': id,
      'type': type,
      'amount': amount,
      'timestamp': timestamp,
      'note': note,
      'reference': reference,
      'referenceDetail': referenceDetail,
    };

ProviderContainer _containerWith(Interceptor interceptor) => ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(
          Dio(BaseOptions(baseUrl: 'http://test'))
            ..interceptors.add(interceptor),
        ),
      ],
    );

Future<void> _pump(WidgetTester tester, Widget widget,
    {required ProviderContainer container}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: widget)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CashDrawerTransactionList (DG-343 Phase 3)', () {
    testWidgets(
        'AC1/AC3: renders each transaction with type label, signed amount, '
        'timestamp, and note', (tester) async {
      final interceptor = _TxnInterceptor(
        total: 3,
        items: [
          _txn(
              id: '1',
              type: 'cash_drawer_open',
              amount: 1000000,
              note: 'Mở quầy sáng'),
          _txn(
              id: '2',
              type: 'payment_transaction',
              amount: 50000,
              note: 'Bán bánh mì'),
          _txn(
              id: '3',
              type: 'cash_drawer_cash_out',
              amount: -200000,
              note: 'Rút tiền chủ'),
        ],
      );
      final container = _containerWith(interceptor);
      addTearDown(container.dispose);

      await _pump(
        tester,
        const CashDrawerTransactionList(drawerId: 7, poll: false),
        container: container,
      );

      // AC3: short type labels are rendered.
      expect(find.text(VN.cashDrawerTxnTypeOpen), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeSale), findsOneWidget);
      expect(find.text(VN.cashDrawerTxnTypeCashOut), findsOneWidget);
      // AC1: timestamps rendered via formatDisplay (dd/MM/yyyy HH:mm).
      expect(find.textContaining('01/08/2026'), findsNWidgets(3));
      // AC1: notes render when present.
      expect(find.text('Mở quầy sáng'), findsOneWidget);
      expect(find.text('Bán bánh mì'), findsOneWidget);
      expect(find.text('Rút tiền chủ'), findsOneWidget);
      // The request hit the right endpoint.
      expect(interceptor.lastPath, '/api/cash-drawer/7/transactions');
    });

    testWidgets(
        'AC5: inflow amounts show "+" prefix in green, outflow amounts show '
        '"-" prefix in red', (tester) async {
      final interceptor = _TxnInterceptor(
        total: 2,
        items: [
          _txn(id: '1', type: 'payment_transaction', amount: 75000),
          _txn(id: '2', type: 'cash_drawer_cash_out', amount: -300000),
        ],
      );
      final container = _containerWith(interceptor);
      addTearDown(container.dispose);

      await _pump(
        tester,
        const CashDrawerTransactionList(drawerId: 1, poll: false),
        container: container,
      );

      // AC5: inflow row shows "+75.000đ" in green, outflow row shows
      // "-300.000đ" in red. We assert the text is present and that the
      // TextStyle color matches the expected palette.
      final inflowFinder = find.text('+75.000đ');
      final outflowFinder = find.text('-300.000đ');
      expect(inflowFinder, findsOneWidget,
          reason: 'inflow amount should be prefixed with "+"');
      expect(outflowFinder, findsOneWidget,
          reason: 'outflow amount should be prefixed with "-"');

      final inflowText = tester.widget<Text>(inflowFinder);
      expect(inflowText.style?.color, Colors.green.shade700,
          reason: 'inflow amount should be green');

      final errorColor =
          Theme.of(tester.element(find.byType(MaterialApp))).colorScheme.error;
      final outflowText = tester.widget<Text>(outflowFinder);
      expect(outflowText.style?.color, errorColor,
          reason: 'outflow amount should be red');
    });

    testWidgets(
        'AC2/FR4: scroll near the bottom loads the next page (infinite '
        'scroll)', (tester) async {
      // Two pages: 50 items on the first page, 10 on the second, total 60.
      final firstPage = List.generate(
          50, (i) => _txn(id: '${i + 1}', type: 'payment_transaction'));
      final secondPage = List.generate(
          10, (i) => _txn(id: '${i + 51}', type: 'expense', amount: -1000));

      final interceptor = _PagedTxnInterceptor(
        pages: [firstPage, secondPage],
        total: 60,
      );
      final container = _containerWith(interceptor);
      addTearDown(container.dispose);

      await _pump(
        tester,
        const CashDrawerTransactionList(drawerId: 9, poll: false),
        container: container,
      );

      // First page loaded — sale-type rows are visible (ListView.builder is
      // lazy, so only the visible rows are built). The first page request
      // hit offset 0.
      expect(interceptor.requests.length, 1);
      expect(interceptor.requests.last['offset'], 0);
      expect(find.text(VN.cashDrawerTxnTypeSale), findsWidgets);
      // No expense-type rows yet (second page not loaded).
      expect(find.text(VN.cashDrawerTxnTypeExpense), findsNothing);

      // Scroll to the bottom to trigger infinite-scroll load of page 2.
      await tester.drag(
        find.byType(ListView),
        const Offset(0, -5000),
      );
      await tester.pumpAndSettle();

      // Second page loaded — expense rows now appear.
      expect(find.text(VN.cashDrawerTxnTypeExpense), findsWidgets);
      expect(interceptor.requests.length, greaterThanOrEqualTo(2));
      // The second request used offset=50.
      expect(interceptor.requests.last['offset'], 50);
    });

    testWidgets(
        'shows an empty state when the drawer has no transactions',
        (tester) async {
      final interceptor = _TxnInterceptor(total: 0, items: const []);
      final container = _containerWith(interceptor);
      addTearDown(container.dispose);

      await _pump(
        tester,
        const CashDrawerTransactionList(drawerId: 2, poll: false),
        container: container,
      );

      // Empty state surfaces the tab label as a hint.
      expect(find.text(VN.cashDrawerTransactionsTab), findsOneWidget);
    });
  });

  group('CashDrawerTransactionList (DG-343 Phase 4 — reference display)', () {
    testWidgets(
        'FR6/FR7: payment and expense rows render reference and referenceDetail '
        'below the note; drawer-only rows render neither', (tester) async {
      final interceptor = _TxnInterceptor(
        total: 3,
        items: [
          _txn(
            id: '1',
            type: 'cash_drawer_open',
            amount: 1000000,
            note: 'Mở quầy sáng',
          ),
          _txn(
            id: '2',
            type: 'payment_transaction',
            amount: 150000,
            note: 'Bán bánh kem',
            reference: 'BKS-16-001',
            referenceDetail: 'Khách A',
          ),
          _txn(
            id: '3',
            type: 'expense',
            amount: -50000,
            note: 'Chi phí vận chuyển',
            reference: 'Chi phí vận chuyển',
            referenceDetail: 'Phượng — Tiền mặt tại quầy',
          ),
        ],
      );
      final container = _containerWith(interceptor);
      addTearDown(container.dispose);

      await _pump(
        tester,
        const CashDrawerTransactionList(drawerId: 7, poll: false),
        container: container,
      );

      // FR6: payment_transaction row shows the order ref and customer name
      // joined by " — " below the note.
      expect(find.text('BKS-16-001 — Khách A'), findsOneWidget);
      // FR7: expense row shows the summary and "staff — provider" below the note.
      expect(
          find.text('Chi phí vận chuyển — Phượng — Tiền mặt tại quầy'),
          findsOneWidget);
      // Drawer-only rows (cash_drawer_open) render no reference line — the
      // "Mở quầy sáng" note appears once (as the note) and no reference
      // composite string is added for that row.
      expect(find.text('Mở quầy sáng'), findsOneWidget);
    });

    testWidgets(
        'reference line is hidden when both reference and referenceDetail are '
        'empty', (tester) async {
      final interceptor = _TxnInterceptor(
        total: 1,
        items: [
          _txn(
            id: '1',
            type: 'cash_drawer_cash_in',
            amount: 200000,
            note: 'bổ sung',
            reference: '',
            referenceDetail: '',
          ),
        ],
      );
      final container = _containerWith(interceptor);
      addTearDown(container.dispose);

      await _pump(
        tester,
        const CashDrawerTransactionList(drawerId: 1, poll: false),
        container: container,
      );

      // Note renders; no reference line is added (no " — " composite).
      expect(find.text('bổ sung'), findsOneWidget);
      // No composite reference string present (the only Text children are the
      // type label, timestamp, note, and amount).
      expect(find.textContaining(' — '), findsNothing);
    });
  });

  group('CashDrawerTransactionList (DG-379 Phase 4.3 — edit tap handler)', () {
    testWidgets(
        'AC1/AC2: tapping an open transaction card opens the edit dialog with '
        'pre-filled amount + notes', (tester) async {
      final interceptor = _EditInterceptor(
        items: [
          _txn(
            id: '12',
            type: 'cash_drawer_open',
            amount: 1000000,
            note: 'Mở quầy sáng',
          ),
        ],
      );
      final container = _containerWith(interceptor);
      addTearDown(container.dispose);

      await _pump(
        tester,
        const CashDrawerTransactionList(drawerId: 1, poll: false),
        container: container,
      );

      // The edit icon is rendered on the open transaction row.
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      // Tap the open transaction card to open the edit dialog.
      await tester.tap(find.text(VN.cashDrawerTxnTypeOpen));
      await tester.pumpAndSettle();

      // The dialog title includes the edit label + transaction type.
      expect(
        find.textContaining(VN.cashDrawerEditTxnTitle),
        findsOneWidget,
      );
      // The amount field is pre-filled with the current amount (formatted).
      expect(find.text('1,000,000'), findsOneWidget);
      // The notes field is pre-filled (the second EditableText in the dialog).
      final editableTexts =
          tester.widgetList<EditableText>(find.byType(EditableText));
      final notesField = editableTexts.last;
      expect(notesField.controller.text, 'Mở quầy sáng');
    });

    testWidgets(
        'AC7: saving the edit PATCHes the entry and refreshes the list',
        (tester) async {
      final interceptor = _EditInterceptor(
        items: [
          _txn(
            id: '12',
            type: 'cash_drawer_open',
            amount: 1000000,
            note: 'Mở quầy sáng',
          ),
        ],
      );
      final container = _containerWith(interceptor);
      addTearDown(container.dispose);

      await _pump(
        tester,
        const CashDrawerTransactionList(drawerId: 1, poll: false),
        container: container,
      );

      // Tap to open the edit dialog.
      await tester.tap(find.text(VN.cashDrawerTxnTypeOpen));
      await tester.pumpAndSettle();
      // Change the notes field (clear + enter new text).
      await tester.enterText(find.byType(TextFormField).last, 'ghi chú mới');
      // Tap Save.
      await tester.tap(find.text(VN.save));
      await tester.pumpAndSettle();

      // A PATCH request was recorded against the edit endpoint.
      expect(interceptor.patchRequests, hasLength(1));
      expect(
        interceptor.patchRequests.last.path,
        '/api/cash-drawer/1/transactions/12',
      );
      expect(interceptor.patchRequests.last.body, {'notes': 'ghi chú mới'});
      // The success snackbar is shown.
      expect(find.text(VN.cashDrawerEditTxnSaved), findsOneWidget);
    });

    testWidgets(
        'AC5: reconciled drawer shows lock-notice snackbar on tap (no dialog)',
        (tester) async {
      final interceptor = _EditInterceptor(
        items: [
          _txn(
            id: '12',
            type: 'cash_drawer_open',
            amount: 1000000,
            note: 'ca sáng',
          ),
        ],
      );
      final container = _containerWith(interceptor);
      addTearDown(container.dispose);

      await _pump(
        tester,
        const CashDrawerTransactionList(
          drawerId: 1,
          poll: false,
          reconciled: true,
        ),
        container: container,
      );

      // No edit icon on a reconciled drawer (AC5).
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      // Tap the open transaction card (the type label is unique to the row).
      await tester.tap(find.text(VN.cashDrawerTxnTypeOpen));
      await tester.pumpAndSettle();

      // The lock-notice snackbar is shown, not the edit dialog.
      expect(find.text(VN.cashDrawerEditLockedReconciled), findsOneWidget);
      expect(find.text(VN.save), findsNothing);
      // No PATCH request was sent.
      expect(interceptor.patchRequests, isEmpty);
    });

    testWidgets(
        'non-editable transaction types (sale, expense, cash-in, cash-out) '
        'are not tappable for editing', (tester) async {
      final interceptor = _EditInterceptor(
        items: [
          _txn(
              id: '1',
              type: 'payment_transaction',
              amount: 50000,
              note: 'bán bánh mì'),
          _txn(
              id: '2',
              type: 'cash_drawer_cash_in',
              amount: 200000,
              note: 'Nạp tiền'),
        ],
      );
      final container = _containerWith(interceptor);
      addTearDown(container.dispose);

      await _pump(
        tester,
        const CashDrawerTransactionList(drawerId: 1, poll: false),
        container: container,
      );

      // No edit icon on non-editable rows.
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      // Tapping the sale row does not open the edit dialog.
      await tester.tap(find.text(VN.cashDrawerTxnTypeSale));
      await tester.pumpAndSettle();
      expect(find.text(VN.save), findsNothing);
    });
  });
}

/// Multi-page interceptor: returns each page in sequence based on the
/// requested offset. Records every request so tests can assert on the
/// pagination wiring. Pages are 50 items wide; the request offset / 50
/// selects the page index.
class _PagedTxnInterceptor extends Interceptor {
  _PagedTxnInterceptor({required this.pages, required this.total});

  final List<List<Map<String, dynamic>>> pages;
  final int total;
  final List<Map<String, dynamic>> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final offset = (options.queryParameters['offset'] as int?) ?? 0;
    requests.add({'offset': offset, 'limit': options.queryParameters['limit']});
    final pageIndex = offset ~/ 50;
    final page =
        pageIndex < pages.length ? pages[pageIndex] : const <Map<String, dynamic>>[];
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'total': total,
          'limit': options.queryParameters['limit'] ?? 50,
          'offset': offset,
          'items': page,
        },
      ),
    );
  }
}

/// Captured PATCH request for the edit-transaction tests. Mirrors the
/// recording pattern used elsewhere in the suite.
class _PatchRequest {
  _PatchRequest({required this.path, required this.body});

  final String path;
  final Map<String, dynamic>? body;
}

/// DG-379 Phase 4.3: interceptor that serves the GET transactions list for a
/// single drawer and records PATCH edit-transaction requests. The GET
/// response is static (a single page with [items]); the PATCH response is a
/// fixed edit-result dict so the edit flow completes without error.
class _EditInterceptor extends Interceptor {
  _EditInterceptor({required this.items});

  final List<Map<String, dynamic>> items;
  final List<_PatchRequest> patchRequests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.method == 'PATCH') {
      patchRequests.add(_PatchRequest(
        path: options.path,
        body: options.data is Map<String, dynamic>
            ? Map<String, dynamic>.from(options.data as Map)
            : null,
      ));
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: {
            'drawerId': '1',
            'entryId': '12',
            'sourceType': 'cash_drawer_open',
            'amount': 1500000,
            'notes': 'ghi chú mới',
            'drawer': {
              'id': '1',
              'openedAt': '2026-08-01T00:00:00Z',
              'closedAt': null,
              'status': 'open',
              'openingBalance': 1000000,
              'expectedBalance': 1500000,
              'reconciled': false,
            },
          },
        ),
      );
      return;
    }
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: {
          'total': items.length,
          'limit': options.queryParameters['limit'] ?? 50,
          'offset': options.queryParameters['offset'] ?? 0,
          'items': items,
        },
      ),
    );
  }
}