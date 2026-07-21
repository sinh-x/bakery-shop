import 'package:bakery_app/data/api/reconciliation_service.dart';
import 'package:bakery_app/features/stock/stock_reconciliation_history_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHistoryDetailService extends ReconciliationService {
  _FakeHistoryDetailService() : super(Dio());

  @override
  Future<ReconciliationHistoryDetail> getHistoryDetail(int sessionId) async {
    return ReconciliationHistoryDetail(
      id: sessionId,
      reconciliationDate: '2026-05-04',
      staffName: 'An',
      paymentMethod: 'cash',
      wasteReason: '',
      linkedOrderRef: 'ORD-TOP',
      linkedPaymentRef: 'PAY-TOP',
      createdAt: '2026-05-04T10:00:00Z',
      lines: [
        ReconciliationHistoryLine(
          id: 1,
          productId: 1,
          productName: 'Banh mi',
          expectedQty: 10,
          countedQty: 8,
          saleQty: 2,
          wasteQty: 0,
          wasteReason: '',
          manualUnitPrice: null,
          linkedOrderItemId: null,
          linkedStockMovementSaleId: null,
          linkedStockMovementWasteId: null,
          saleRows: [
            ReconciliationHistorySaleRow(
              id: 101,
              quantity: 1,
              unitPrice: 12000,
              paymentMethod: 'cash',
              linkedOrderRef: 'ORD-ROW-1',
              linkedPaymentRef: 'PAY-ROW-1',
              isLegacy: false,
            ),
            ReconciliationHistorySaleRow(
              id: null,
              quantity: 1,
              unitPrice: 13000,
              paymentMethod: 'transfer',
              linkedOrderRef: 'ORD-ROW-2',
              linkedPaymentRef: 'PAY-ROW-2',
              isLegacy: true,
            ),
          ],
        ),
      ],
    );
  }
}

void main() {
  testWidgets('history detail renders summary card and grouped legacy sale rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reconciliationServiceProvider.overrideWithValue(
            _FakeHistoryDetailService(),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: const StockReconciliationHistoryDetailScreen(sessionId: 12),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Summary card is always visible at the top.
    expect(find.textContaining('ORD-TOP'), findsOneWidget);
    expect(find.textContaining('PAY-TOP'), findsOneWidget);

    // Lines are grouped under a collapsible category header. With no category
    // on the line, the fallback "Không phân loại" header is shown and starts
    // collapsed — expand it to reveal the line card.
    expect(find.text('Không phân loại'), findsOneWidget);
    await tester.tap(find.text('Không phân loại'));
    await tester.pumpAndSettle();

    // Line card starts collapsed — expand it to reveal full details and the
    // sale-rows section toggle.
    expect(find.text('Banh mi'), findsOneWidget);
    await tester.tap(find.text('Banh mi'));
    await tester.pumpAndSettle();

    // Sale rows section starts collapsed — expand it to reveal sale row titles.
    final saleRowsToggle = find.textContaining('Số dòng bán');
    await tester.tap(saleRowsToggle);
    await tester.pumpAndSettle();

    expect(find.text('1. Dòng bán'), findsOneWidget);
    expect(find.text('2. Dòng bán cũ'), findsOneWidget);
    expect(find.textContaining('ORD-ROW-1'), findsOneWidget);
    expect(find.textContaining('PAY-ROW-1'), findsOneWidget);
    expect(find.textContaining('ORD-ROW-2'), findsOneWidget);
    expect(find.textContaining('PAY-ROW-2'), findsOneWidget);
  });
}