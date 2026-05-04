import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/reconciliation_service.dart';
import 'package:bakery_app/data/providers/reconciliation_provider.dart';
import 'package:bakery_app/providers/events_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _FakeReconciliationService extends ReconciliationService {
  _FakeReconciliationService(this._draft) : super(Dio());

  final ReconciliationDraft _draft;
  int submitCalls = 0;

  @override
  Future<ReconciliationDraft> getDraft() async => _draft;

  @override
  Future<ReconciliationSubmitResult> submit(
    ReconciliationSubmitRequest request,
  ) async {
    submitCalls += 1;
    return ReconciliationSubmitResult(
      id: 1,
      date: '2026-05-04',
      message: 'Đã lưu đối soát thành công',
    );
  }
}

void main() {
  test('submit blocks when sale exists without payment method', () async {
    SharedPreferences.setMockInitialValues({kLoggedByKey: 'An'});
    final prefs = await SharedPreferences.getInstance();

    final fakeService = _FakeReconciliationService(
      ReconciliationDraft(
        date: '2026-05-04',
        products: [
          ReconciliationDraftProduct(
            productId: 1,
            name: 'Bánh kem dâu',
            category: 'banh_kem',
            expectedQty: 5,
            basePrice: 100000,
            priceChips: [],
          ),
        ],
      ),
    );

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        reconciliationServiceProvider.overrideWithValue(fakeService),
      ],
    );
    addTearDown(container.dispose);

    await container.read(reconciliationProvider.notifier).loadDraft();
    container.read(reconciliationProvider.notifier).setCountedQty(1, 4);
    container.read(reconciliationProvider.notifier).setSaleQty(1, 1);
    container.read(reconciliationProvider.notifier).setWasteQty(1, 0);
    container
        .read(reconciliationProvider.notifier)
        .setManualUnitPrice(1, '12000');

    final success = await container
        .read(reconciliationProvider.notifier)
        .submit();
    final state = container.read(reconciliationProvider);

    expect(success, isFalse);
    expect(fakeService.submitCalls, 0);
    expect(state.errorMessage, 'Vui lòng chọn phương thức thanh toán');
  });
}
