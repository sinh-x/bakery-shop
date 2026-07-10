import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/data/models/payment_transaction.dart';
import 'package:bakery_app/data/models/work_item.dart';
import 'package:bakery_app/features/orders/widgets/rut_tien_section.dart';
import 'package:bakery_app/providers/order/order_crud_providers.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

const _testRef = 'TEST-ORDER-RUT';

class _FakeWorkItemsNotifier extends OrderWorkItemsNotifier {
  final List<WorkItem> _items;
  _FakeWorkItemsNotifier(this._items) : super(_testRef);

  @override
  Future<List<WorkItem>> build() async => _items;
}

class _FakeTxnsNotifier extends OrderPaymentTransactionsNotifier {
  final List<PaymentTransaction> _txns;
  _FakeTxnsNotifier(this._txns) : super(_testRef);

  @override
  Future<List<PaymentTransaction>> build() async => _txns;
}

void main() {
  testWidgets('RutTienSection renders nothing when no rut_tien work items',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderWorkItemsProvider(_testRef)
              .overrideWith(() => _FakeWorkItemsNotifier(const [])),
          orderPaymentTransactionsProvider(_testRef)
              .overrideWith(() => _FakeTxnsNotifier(const [])),
        ],
        child: const MaterialApp(
          home: Scaffold(body: RutTienSection(orderRef: _testRef)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RutTienSection), findsOneWidget);
    expect(find.text(VN.rutTienSection), findsNothing);
  });

  testWidgets('RutTienSection renders section header + totals when rut_tien item present',
      (tester) async {
    final items = [
      const WorkItem(
        id: 'w1',
        orderId: '100',
        productName: 'Bánh rút tiền',
        attributes: {
          'rut_tien': 'true',
          'cash_amount': '500000',
          'cash_fee': '10000',
        },
      ),
    ];
    final txns = [
      const PaymentTransaction(
        id: 't1',
        orderId: '100',
        type: 'tien_rut',
        amount: 200000,
      ),
    ];
    var recorded = 0.0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderWorkItemsProvider(_testRef)
              .overrideWith(() => _FakeWorkItemsNotifier(items)),
          orderPaymentTransactionsProvider(_testRef)
              .overrideWith(() => _FakeTxnsNotifier(txns)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: RutTienSection(
              orderRef: _testRef,
              onRecordPayment: (r) => recorded = r,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RutTienSection), findsOneWidget);
    expect(find.text(VN.rutTienSection), findsOneWidget);
    expect(find.text('Bánh rút tiền'), findsOneWidget);
    expect(find.text('${VN.soTienRut}: ${formatVND(500000)}'), findsOneWidget);
    expect(find.text('${VN.phiRutTien}: ${formatVND(10000)}'), findsOneWidget);
    expect(find.textContaining(formatVND(200000)), findsOneWidget);
    expect(find.textContaining('500.000đ'), findsNWidgets(2));
    final button = find.byType(OutlinedButton);
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(recorded, 300000);
  });
}