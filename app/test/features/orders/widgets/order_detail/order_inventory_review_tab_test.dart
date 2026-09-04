import 'package:bakery_app/data/models/order_inventory_audit.dart';
import 'package:bakery_app/data/providers/order/order_inventory_audit_provider.dart';
import 'package:bakery_app/features/orders/widgets/order_detail/order_inventory_review_tab.dart';
import 'package:bakery_app/shared/labels/stock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _entry(int id, String operationId) => <String, dynamic>{
  'id': id,
  'operationId': operationId,
  'orderId': 1,
  'orderRef': 'ORD-1',
  'trigger': 'status_action',
  'action': 'inventory_deduct',
  'statusBefore': 'new',
  'statusAfter': 'confirmed',
  'actor': <String, dynamic>{
    'identifier': 'cashier',
    'username': 'cashier',
    'staffId': 3,
    'staffName': 'Thu ngân',
    'role': 'staff',
  },
  'createdAt': '2026-09-04T03:00:0${9 - id}Z',
  'outcome': 'applied',
  'reasonCode': 'eligible_display_item',
  'detail': 'must not be rendered',
  'item': <String, dynamic>{
    'orderItemId': 90 + id,
    'productId': 31,
    'productCode': 'TB-31',
    'productName': 'Bánh trưng bày',
    'priceChipLabel': 'Miếng lớn',
    'resolvedPriceChipLabel': 'Miếng lớn',
  },
  'requestedDelta': -2,
  'appliedDelta': -2,
  'before': <String, dynamic>{'fifoAvailable': 5, 'negative': 0, 'net': 5},
  'after': <String, dynamic>{'fifoAvailable': 3, 'negative': 0, 'net': 3},
  'stockMovementId': 700 + id,
  'negativeMovementId': null,
  'relatedEntryId': null,
  'reconciliationSessionId': 12,
  'reconciliationSessionIds': <int>[12],
  'reconciliationLineIds': <int>[33],
  'reconciliationSaleRowIds': <int>[44],
};

OrderInventoryAuditState _state(
  List<Map<String, dynamic>> items, {
  bool hasMore = false,
  bool laterRequestFailed = false,
}) => OrderInventoryAuditState(
  initialized: true,
  items: items.map(OrderInventoryAuditEntry.fromJson).toList(growable: false),
  total: items.length + (hasMore ? 1 : 0),
  hasMore: hasMore,
  laterRequestFailed: laterRequestFailed,
);

class _FakeAuditNotifier extends OrderInventoryAuditNotifier {
  _FakeAuditNotifier(this.initial, {this.failInitially = false})
    : super('ORD-1');

  final OrderInventoryAuditState initial;
  final bool failInitially;

  @override
  Future<OrderInventoryAuditState> build() async {
    if (failInitially) throw Exception('secret stack');
    return initial;
  }

  @override
  Future<void> retry() async {
    state = AsyncData(initial);
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeAuditNotifier notifier, {
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        orderInventoryAuditProvider('ORD-1').overrideWith(() => notifier),
      ],
      child: const MaterialApp(
        home: Scaffold(body: OrderInventoryReviewTab(orderRef: 'ORD-1')),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  testWidgets('shows centralized Vietnamese loading state before selection', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeAuditNotifier(const OrderInventoryAuditState()),
      settle: false,
    );

    expect(find.text(StockLabels.inventoryAuditLoading), findsOneWidget);
  });

  testWidgets('groups newest-first entries and expands read-only details', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeAuditNotifier(
        _state([
          _entry(3, 'new-operation'),
          _entry(2, 'new-operation'),
          _entry(1, 'old-operation'),
        ]),
      ),
    );

    expect(
      find.byKey(const ValueKey('inventory-operation-new-operation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('inventory-operation-old-operation')),
      findsOneWidget,
    );
    expect(find.text(StockLabels.inventoryAuditActor), findsNothing);
    expect(find.textContaining('Thu ngân'), findsNWidgets(3));
    expect(find.byIcon(Icons.edit), findsNothing);
    expect(find.byIcon(Icons.delete), findsNothing);
    expect(find.text('must not be rendered'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('inventory-audit-entry-3')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(StockLabels.inventoryAuditDetails), findsOneWidget);
    expect(find.textContaining('new-operation'), findsOneWidget);
    expect(
      find.textContaining(StockLabels.inventoryAuditFifo),
      findsNWidgets(2),
    );
    expect(find.textContaining('33'), findsOneWidget);
  });

  testWidgets('retains rows after later failure and offers load more', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeAuditNotifier(
        _state(
          [_entry(3, 'new-operation')],
          hasMore: true,
          laterRequestFailed: true,
        ),
      ),
    );

    expect(find.textContaining('Bánh trưng bày'), findsOneWidget);
    expect(find.text(StockLabels.inventoryAuditRetainedError), findsOneWidget);
    expect(find.text(StockLabels.inventoryAuditLoadMore), findsOneWidget);
  });

  testWidgets('shows Vietnamese empty state', (tester) async {
    await _pump(tester, _FakeAuditNotifier(_state([])));

    expect(find.text(StockLabels.inventoryAuditEmpty), findsOneWidget);
    expect(find.text(StockLabels.inventoryAuditRefresh), findsOneWidget);
  });

  testWidgets('shows generic error and retries without raw diagnostics', (
    tester,
  ) async {
    await _pump(tester, _FakeAuditNotifier(_state([]), failInitially: true));

    expect(find.text(StockLabels.inventoryAuditError), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    await tester.tap(find.byKey(const Key('inventory-audit-retry')));
    await tester.pump();
    expect(find.text(StockLabels.inventoryAuditEmpty), findsOneWidget);
  });
}
