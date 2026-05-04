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
}
