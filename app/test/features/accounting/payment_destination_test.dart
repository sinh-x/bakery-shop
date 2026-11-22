import 'dart:async';

import 'package:bakery_app/data/api/payment_destination_service.dart';
import 'package:bakery_app/data/models/payment_transaction.dart';
import 'package:bakery_app/data/providers/payment_destination_provider.dart';
import 'package:bakery_app/features/accounting/widgets/assign_payment_destination_button.dart';
import 'package:bakery_app/features/accounting/widgets/unresolved_receipts_tab.dart';
import 'package:bakery_app/providers/payment_destination_query_provider.dart';
import 'package:bakery_app/shared/labels/accounting.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDestinationService extends PaymentDestinationService {
  FakeDestinationService() : super(Dio());
  int assignments = 0;
  bool fail = false;
  Completer<void>? pending;
  static const transaction = PaymentTransaction(
    id: '1',
    orderId: '2',
    amount: 100000,
    method: 'unknown',
    destinationStatus: 'unresolved',
  );

  @override
  Future<UnresolvedReceiptPage> list({
    String search = '',
    int offset = 0,
  }) async {
    if (fail) throw Exception('offline');
    return const UnresolvedReceiptPage(
      items: [UnresolvedReceipt(transaction, 'ORD', 'Khách')],
      total: 1,
      amount: 100000,
      hasMore: false,
    );
  }

  @override
  Future<PaymentTransaction> assign(
    String orderRef,
    String transactionId, {
    required String method,
    String paymentSource = '',
  }) async {
    assignments++;
    await pending?.future;
    if (fail) {
      throw DioException(
        requestOptions: RequestOptions(),
        response: Response(
          requestOptions: RequestOptions(),
          statusCode: 409,
          data: {'detail': 'Cần mở ngăn kéo tiền'},
        ),
      );
    }
    return transaction.copyWith(method: method, destinationStatus: 'resolved');
  }
}

void main() {
  test('query search resets page and previous never goes negative', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sub = container.listen(paymentDestinationQueryProvider, (_, _) {});
    addTearDown(sub.close);
    final notifier = container.read(paymentDestinationQueryProvider.notifier);
    notifier.nextPage();
    expect(container.read(paymentDestinationQueryProvider), ('', 50));
    notifier.previousPage();
    notifier.previousPage();
    expect(container.read(paymentDestinationQueryProvider), ('', 0));
    notifier.nextPage();
    notifier.search(' ORD ');
    expect(container.read(paymentDestinationQueryProvider), ('ORD', 0));
  });

  test(
    'assignment isolates receipts, rejects duplicate submits and supports retry',
    () async {
      final fake = FakeDestinationService()..pending = Completer<void>();
      final container = ProviderContainer(
        overrides: [paymentDestinationServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      final provider = assignPaymentDestinationProvider(('ORD', '1'));
      await container.read(provider.future);
      final notifier = container.read(provider.notifier);
      final first = notifier.assign('cash', '');
      expect(await notifier.assign('cash', ''), false);
      expect(container.read(provider).isLoading, true);
      await container.read(
        assignPaymentDestinationProvider(('OTHER', '1')).future,
      );
      expect(
        container
            .read(assignPaymentDestinationProvider(('OTHER', '1')))
            .isLoading,
        false,
      );
      fake.pending!.complete();
      expect(await first, true);
      fake.fail = true;
      expect(await notifier.assign('cash', ''), false);
      expect(container.read(provider).hasError, true);
      fake.fail = false;
      expect(await notifier.assign('cash', ''), true);
      expect(container.read(provider).hasError, false);
    },
  );

  testWidgets('unresolved tab renders receipts and retries loading failures', (
    tester,
  ) async {
    final fake = FakeDestinationService()..fail = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [paymentDestinationServiceProvider.overrideWithValue(fake)],
        child: const MaterialApp(home: Scaffold(body: UnresolvedReceiptsTab())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining(SharedLabels.retry), findsOneWidget);
    fake.fail = false;
    await tester.tap(find.textContaining(SharedLabels.retry));
    await tester.pumpAndSettle();
    expect(find.text('ORD · Khách'), findsOneWidget);
    expect(find.text(AccountingLabels.assignDestination), findsOneWidget);
  });

  testWidgets('assignment confirms, cancels, shows drawer error and retries', (
    tester,
  ) async {
    final fake = FakeDestinationService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [paymentDestinationServiceProvider.overrideWithValue(fake)],
        child: const MaterialApp(
          home: Scaffold(
            body: AssignPaymentDestinationButton(
              orderRef: 'ORD',
              transactionId: '1',
            ),
          ),
        ),
      ),
    );
    Future<void> chooseCash() async {
      await tester.tap(find.text(AccountingLabels.assignDestination).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(OrdersLabels.methodCash));
      await tester.pumpAndSettle();
    }

    await chooseCash();
    await tester.tap(find.text(SharedLabels.cancel));
    await tester.pumpAndSettle();
    expect(fake.assignments, 0);
    fake.fail = true;
    await chooseCash();
    await tester.tap(
      find.widgetWithText(FilledButton, AccountingLabels.assignDestination),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cần mở ngăn kéo tiền'), findsOneWidget);
    fake.fail = false;
    await chooseCash();
    await tester.tap(
      find.widgetWithText(FilledButton, AccountingLabels.assignDestination),
    );
    await tester.pumpAndSettle();
    expect(fake.assignments, 2);
    expect(find.text('Cần mở ngăn kéo tiền'), findsNothing);
  });
}
