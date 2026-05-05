import 'package:bakery_app/data/api/reconciliation_service.dart';
import 'package:bakery_app/data/providers/reconciliation_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHistoryService extends ReconciliationService {
  _FakeHistoryService() : super(Dio());

  @override
  Future<List<ReconciliationHistorySession>> getHistorySessions() async {
    return [
      ReconciliationHistorySession(
        id: 12,
        reconciliationDate: '2026-05-04',
        staffName: 'An',
        paymentMethod: 'cash',
        wasteReason: 'Bị vỡ',
        linkedOrderRef: 'POS-001',
        lineCount: 2,
        createdAt: '2026-05-04T10:00:00',
      ),
    ];
  }

  @override
  Future<ReconciliationHistoryDetail> getHistoryDetail(int sessionId) async {
    return ReconciliationHistoryDetail(
      id: sessionId,
      reconciliationDate: '2026-05-04',
      staffName: 'An',
      paymentMethod: 'cash',
      wasteReason: '',
      linkedOrderRef: 'ORD-RECON-0001',
      linkedPaymentRef: 'PTX-1',
      createdAt: '2026-05-04T10:00:00',
      lines: [
        ReconciliationHistoryLine(
          id: 1,
          productId: 101,
          productName: 'Bánh su kem',
          expectedQty: 10,
          countedQty: 7,
          saleQty: 3,
          wasteQty: 0,
          wasteReason: '',
          manualUnitPrice: null,
          linkedOrderItemId: null,
          linkedStockMovementSaleId: null,
          linkedStockMovementWasteId: null,
          saleRows: [
            ReconciliationHistorySaleRow(
              id: 11,
              quantity: 1,
              unitPrice: 12000,
              paymentMethod: 'cash',
              linkedOrderRef: 'ORD-RECON-0001',
              linkedPaymentRef: 'PTX-1',
              isLegacy: false,
            ),
            ReconciliationHistorySaleRow(
              id: null,
              quantity: 2,
              unitPrice: 15000,
              paymentMethod: 'transfer',
              linkedOrderRef: 'ORD-LEGACY-0002',
              linkedPaymentRef: 'PTX-2',
              isLegacy: true,
            ),
          ],
        ),
      ],
    );
  }
}

void main() {
  test('history list provider returns sessions', () async {
    final container = ProviderContainer(
      overrides: [
        reconciliationServiceProvider.overrideWithValue(_FakeHistoryService()),
      ],
    );
    addTearDown(container.dispose);

    final sessions = await container.read(
      reconciliationHistoryListProvider.future,
    );
    expect(sessions, hasLength(1));
    expect(sessions.first.staffName, 'An');
    expect(sessions.first.lineCount, 2);
  });

  test(
    'history detail provider returns grouped and legacy sale rows',
    () async {
      final container = ProviderContainer(
        overrides: [
          reconciliationServiceProvider.overrideWithValue(
            _FakeHistoryService(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final detail = await container.read(
        reconciliationHistoryDetailProvider(12).future,
      );
      expect(detail.lines, hasLength(1));
      expect(detail.lines.first.saleRows, hasLength(2));
      expect(
        detail.lines.first.saleRows.first.linkedOrderRef,
        'ORD-RECON-0001',
      );
      expect(detail.lines.first.saleRows.first.linkedPaymentRef, 'PTX-1');
      expect(detail.lines.first.saleRows.last.isLegacy, isTrue);
      expect(detail.lines.first.saleRows.last.unitPrice, 15000);
    },
  );
}
