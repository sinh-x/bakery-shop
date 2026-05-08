import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/reconciliation_service.dart';
import 'package:bakery_app/data/providers/reconciliation_provider.dart';
import 'package:bakery_app/providers/events_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeReconciliationService extends ReconciliationService {
  _FakeReconciliationService(this._draft) : super(Dio());

  final ReconciliationDraft _draft;
  int submitCalls = 0;
  ReconciliationSubmitRequest? capturedRequest;

  @override
  Future<ReconciliationDraft> getDraft() async => _draft;

  @override
  Future<ReconciliationSubmitResult> submit(
    ReconciliationSubmitRequest request,
  ) async {
    submitCalls += 1;
    capturedRequest = request;
    return ReconciliationSubmitResult(
      id: 1,
      date: '2026-05-04',
      message: 'Đã lưu đối soát thành công',
    );
  }
}

void main() {
  Future<ProviderContainer> buildContainer(_FakeReconciliationService service) async {
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        reconciliationServiceProvider.overrideWithValue(service),
      ],
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({kLoggedByKey: 'An'});
  });

  test('submit blocks when sale and waste do not match missing quantity', () async {
    final service = _FakeReconciliationService(
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
    final container = await buildContainer(service);
    addTearDown(container.dispose);

    await container.read(reconciliationProvider.notifier).loadDraft();
    container.read(reconciliationProvider.notifier).setCountedQty(1, 2);
    container.read(reconciliationProvider.notifier).setWasteQty(1, 1);
    container.read(reconciliationProvider.notifier).addSaleRow(1);
    container.read(reconciliationProvider.notifier).setSaleRowQty(1, 0, 1);
    container.read(reconciliationProvider.notifier).setSaleRowUnitPrice(1, 0, '12000');
    container.read(reconciliationProvider.notifier).setSaleRowPaymentMethod(1, 0, 'cash');

    final ok = await container.read(reconciliationProvider.notifier).submit();
    final state = container.read(reconciliationProvider);
    expect(ok, isFalse);
    expect(service.submitCalls, 0);
    expect(state.optionErrors['1:100000'], isNotNull);
  });

  test('submit blocks and marks row fields inline when row invalid', () async {
    final service = _FakeReconciliationService(
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
    final container = await buildContainer(service);
    addTearDown(container.dispose);

    await container.read(reconciliationProvider.notifier).loadDraft();
    container.read(reconciliationProvider.notifier).setCountedQty(1, 4);
    container.read(reconciliationProvider.notifier).addSaleRow(1);
    container.read(reconciliationProvider.notifier).setSaleRowQty(1, 0, 1);

    final ok = await container.read(reconciliationProvider.notifier).submit();
    final state = container.read(reconciliationProvider);
    expect(ok, isFalse);
    expect(service.submitCalls, 0);
    final rowErrors = state.saleRowErrorsByOption['1:100000']!;
    expect(rowErrors[0].unitPrice, isNotNull);
    expect(rowErrors[0].paymentMethod, isNotNull);
  });

  test('submits grouped rows and maps sale_rows payload', () async {
    final service = _FakeReconciliationService(
      ReconciliationDraft(
        date: '2026-05-04',
        products: [
          ReconciliationDraftProduct(
            productId: 1,
            name: 'Bánh kem dâu',
            category: 'banh_kem',
            expectedQty: 6,
            basePrice: 100000,
            priceChips: [],
          ),
        ],
      ),
    );
    final container = await buildContainer(service);
    addTearDown(container.dispose);

    await container.read(reconciliationProvider.notifier).loadDraft();
    container.read(reconciliationProvider.notifier).setCountedQty(1, 3);
    container.read(reconciliationProvider.notifier).addSaleRow(1);
    container.read(reconciliationProvider.notifier).setSaleRowQty(1, 0, 1);
    container.read(reconciliationProvider.notifier).setSaleRowUnitPrice(1, 0, '10000');
    container.read(reconciliationProvider.notifier).setSaleRowPaymentMethod(1, 0, 'cash');
    container.read(reconciliationProvider.notifier).addSaleRow(1);
    container.read(reconciliationProvider.notifier).setSaleRowQty(1, 1, 2);
    container.read(reconciliationProvider.notifier).setSaleRowUnitPrice(1, 1, '15000');
    container.read(reconciliationProvider.notifier).setSaleRowPaymentMethod(1, 1, 'transfer');

    final ok = await container.read(reconciliationProvider.notifier).submit();
    expect(ok, isTrue);
    expect(service.submitCalls, 1);
    final json = service.capturedRequest!.toJson();
    final line = (json['lines'] as List<dynamic>).first as Map<String, dynamic>;
    final saleRows = line['sale_rows'] as List<dynamic>;
    expect(saleRows.length, 2);
  });

  test('validates 200 sale rows client side without submit call', () async {
    final products = List.generate(
      100,
      (index) => ReconciliationDraftProduct(
        productId: index + 1,
        name: 'SP ${index + 1}',
        category: 'banh_ngot',
        expectedQty: 3,
        basePrice: 10000,
        priceChips: [],
      ),
    );
    final service = _FakeReconciliationService(
      ReconciliationDraft(date: '2026-05-04', products: products),
    );
    final container = await buildContainer(service);
    addTearDown(container.dispose);

    await container.read(reconciliationProvider.notifier).loadDraft();
    for (var i = 1; i <= 100; i++) {
      container.read(reconciliationProvider.notifier).setCountedQty(i, 1);
      container.read(reconciliationProvider.notifier).addSaleRow(i);
      container.read(reconciliationProvider.notifier).setSaleRowQty(i, 0, 1);
      container.read(reconciliationProvider.notifier).setSaleRowUnitPrice(i, 0, '10000');
      container.read(reconciliationProvider.notifier).setSaleRowPaymentMethod(i, 0, 'cash');
      container.read(reconciliationProvider.notifier).addSaleRow(i);
      container.read(reconciliationProvider.notifier).setSaleRowQty(i, 1, 1);
    }

    final ok = await container.read(reconciliationProvider.notifier).submit();
    expect(ok, isFalse);
    expect(service.submitCalls, 0);
  });
}
