import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/reconciliation_service.dart';
import 'package:bakery_app/data/providers/reconciliation_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/login_screen_test_helpers.dart';

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
  Future<ProviderContainer> buildContainer(
    _FakeReconciliationService service,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        reconciliationServiceProvider.overrideWithValue(service),
      ],
    );
  }

  setUp(() {
    // Seed an authenticated session so `loggedByProvider` (which now derives
    // from the JWT `sub` claim per FR17) returns 'An' as it did when it was
    // a free-text SharedPreferences field.
    SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
  });

  test(
    'submit blocks when sale and waste do not match missing quantity',
    () async {
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
      container.read(reconciliationProvider.notifier).setSaleRowQty(1, 0, 1);
      container
          .read(reconciliationProvider.notifier)
          .setSaleRowUnitPrice(1, 0, 12000);
      container
          .read(reconciliationProvider.notifier)
          .setSaleRowPaymentMethod(1, 0, 'cash');

      final ok = await container.read(reconciliationProvider.notifier).submit();
      final state = container.read(reconciliationProvider);
      expect(ok, isFalse);
      expect(service.submitCalls, 0);
      expect(state.optionErrors['1:100000'], isNotNull);
    },
  );

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
    container
        .read(reconciliationProvider.notifier)
        .setSaleRowUnitPrice(1, 0, 10000);
    container
        .read(reconciliationProvider.notifier)
        .setSaleRowPaymentMethod(1, 0, 'cash');
    container.read(reconciliationProvider.notifier).addSaleRow(1);
    container.read(reconciliationProvider.notifier).setSaleRowQty(1, 1, 2);
    container
        .read(reconciliationProvider.notifier)
        .setSaleRowUnitPrice(1, 1, 15000);
    container
        .read(reconciliationProvider.notifier)
        .setSaleRowPaymentMethod(1, 1, 'transfer');

    final ok = await container.read(reconciliationProvider.notifier).submit();
    expect(ok, isTrue);
    expect(service.submitCalls, 1);
    final json = service.capturedRequest!.toJson();
    final line = (json['lines'] as List<dynamic>).first as Map<String, dynamic>;
    final saleRows = line['sale_rows'] as List<dynamic>;
    expect(saleRows.length, 2);
  });

  test(
    'FR17/AC14: submit derives staffName from loggedByProvider (authenticated username)',
    () async {
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
    container
        .read(reconciliationProvider.notifier)
        .setSaleRowUnitPrice(1, 0, 13000);
      container
          .read(reconciliationProvider.notifier)
          .setSaleRowUnitPrice(1, 0, 15000);
      container
          .read(reconciliationProvider.notifier)
          .setSaleRowPaymentMethod(1, 0, 'cash');

      final ok = await container.read(reconciliationProvider.notifier).submit();
      expect(ok, isTrue);
      expect(service.submitCalls, 1);
      // FR17: staffName is sourced from loggedByProvider, which derives from
      // the authenticated JWT `sub` claim (seeded as 'An' in setUp).
      expect(service.capturedRequest!.staffName, 'An');
    },
  );

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
      container.read(reconciliationProvider.notifier).setSaleRowQty(i, 0, 1);
      container
          .read(reconciliationProvider.notifier)
          .setSaleRowUnitPrice(i, 0, 10000);
      container
          .read(reconciliationProvider.notifier)
          .setSaleRowPaymentMethod(i, 0, 'cash');
      container.read(reconciliationProvider.notifier).addSaleRow(i);
      container.read(reconciliationProvider.notifier).setSaleRowQty(i, 1, 1);
    }

    final ok = await container.read(reconciliationProvider.notifier).submit();
    expect(ok, isFalse);
    expect(service.submitCalls, 0);
  });

  test(
    'setCountedQty does not auto-create sale rows',
    () async {
      final service = _FakeReconciliationService(
        ReconciliationDraft(
          date: '2026-05-04',
          products: [
            ReconciliationDraftProduct(
              productId: 1,
              name: 'Banh su kem',
              category: 'banh_ngot',
              expectedQty: 5,
              basePrice: 100000,
              priceChips: [],
              options: [
                ReconciliationDraftOption(
                  productId: 1,
                  normalizedPrice: 13000,
                  chipLabel: 'L',
                  sourceChipIds: <int>[],
                  sourceChipLabels: <String>[],
                  expectedQty: 5,
                ),
              ],
            ),
          ],
        ),
      );
      final container = await buildContainer(service);
      addTearDown(container.dispose);

      await container.read(reconciliationProvider.notifier).loadDraft();
      container
          .read(reconciliationProvider.notifier)
          .setCountedQty('1:13000', 4);

      final state = container.read(reconciliationProvider);
      final rows = state.saleRowsByOption['1:13000']!;
      expect(rows, isEmpty);
    },
  );

  test(
    'setCountedQty does not create sale rows for any option',
    () async {
      final service = _FakeReconciliationService(
        ReconciliationDraft(
          date: '2026-05-04',
          products: [
            ReconciliationDraftProduct(
              productId: 1,
              name: 'Banh su kem',
              category: 'banh_ngot',
              expectedQty: 8,
              basePrice: 100000,
              priceChips: [],
              options: [
                ReconciliationDraftOption(
                  productId: 1,
                  normalizedPrice: 12000,
                  chipLabel: 'S',
                  sourceChipIds: <int>[],
                  sourceChipLabels: <String>[],
                  expectedQty: 3,
                ),
                ReconciliationDraftOption(
                  productId: 1,
                  normalizedPrice: 18000,
                  chipLabel: 'L',
                  sourceChipIds: <int>[],
                  sourceChipLabels: <String>[],
                  expectedQty: 5,
                ),
              ],
            ),
          ],
        ),
      );
      final container = await buildContainer(service);
      addTearDown(container.dispose);

      await container.read(reconciliationProvider.notifier).loadDraft();
      container
          .read(reconciliationProvider.notifier)
          .setCountedQty('1:12000', 2);
      container
          .read(reconciliationProvider.notifier)
          .setCountedQty('1:18000', 4);
      container
          .read(reconciliationProvider.notifier)
          .setCountedQty('1:12000', 1);

      final state = container.read(reconciliationProvider);
      final rows12000 = state.saleRowsByOption['1:12000']!;
      final rows18000 = state.saleRowsByOption['1:18000']!;
      expect(rows12000, isEmpty);
      expect(rows18000, isEmpty);
    },
  );

  test(
    'no sale row created when countedQty returns to expectedQty',
    () async {
      final service = _FakeReconciliationService(
        ReconciliationDraft(
          date: '2026-05-04',
          products: [
            ReconciliationDraftProduct(
              productId: 1,
              name: 'Banh su kem',
              category: 'banh_ngot',
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
      container.read(reconciliationProvider.notifier).setCountedQty(1, 5);

      final state = container.read(reconciliationProvider);
      final rows = state.saleRowsByOption['1:100000']!;
      expect(rows, isEmpty);
    },
  );

  test(
    'normalizeReconciliationOptionKey resolves unique key from product id',
    () {
      final state = ReconciliationState(
        countedQtyByOption: const <String, int>{'1:12000': 2, '2:15000': 1},
        wasteQtyByOption: const <String, int>{},
        wasteReasonByOption: const <String, String>{},
        saleRowsByOption: const <String, List<ReconciliationSaleRowInput>>{},
      );

      expect(normalizeReconciliationOptionKey(1, state), '1:12000');
      expect(normalizeReconciliationOptionKey('2:15000', state), '2:15000');
    },
  );

  test('buildSubmitLines groups active sale rows by option key', () {
    final state = ReconciliationState(
      draft: ReconciliationDraft(
        date: '2026-05-04',
        products: [
          ReconciliationDraftProduct(
            productId: 1,
            name: 'Bánh',
            category: 'banh_ngot',
            expectedQty: 5,
            basePrice: 100000,
            priceChips: const <ReconciliationPriceChip>[],
            options: [
              ReconciliationDraftOption(
                productId: 1,
                normalizedPrice: 100000,
                chipLabel: 'Gia goc',
                sourceChipIds: const <int>[],
                sourceChipLabels: const <String>[],
                expectedQty: 5,
              ),
              ReconciliationDraftOption(
                productId: 1,
                normalizedPrice: 130000,
                priceChipId: 15,
                chipLabel: '130',
                sourceChipIds: const <int>[15],
                sourceChipLabels: const <String>['130'],
                expectedQty: 0,
              ),
            ],
          ),
        ],
      ),
      countedQtyByOption: const <String, int>{'1:100000': 3},
      wasteQtyByOption: const <String, int>{'1:100000': 0},
      wasteReasonByOption: const <String, String>{'1:100000': ''},
      saleRowsByOption: {
        '1:100000': <ReconciliationSaleRowInput>[
          ReconciliationSaleRowInput(
            quantity: 1,
            unitPrice: 10000,
            paymentMethod: 'cash',
          ),
          ReconciliationSaleRowInput(
            quantity: 0,
            unitPrice: 12000,
            paymentMethod: 'transfer',
          ),
        ],
      },
    );

    final lines = buildSubmitLines(state);
    expect(lines.length, 1);
    expect(lines.first.priceChipId, isNull);
    expect(lines.first.saleRows.length, 1);
    expect(lines.first.saleRows.first.paymentMethod, 'cash');
  });

  test(
    'buildSubmitLines includes stocked chip id and skips zero-stock options',
    () {
      final state = ReconciliationState(
        draft: ReconciliationDraft(
          date: '2026-05-04',
          products: [
            ReconciliationDraftProduct(
              productId: 83,
              name: 'Bánh kem trưng bày',
              category: 'banh_kem',
              expectedQty: 6,
              basePrice: 130000,
              priceChips: const <ReconciliationPriceChip>[],
              options: [
                ReconciliationDraftOption(
                  productId: 83,
                  normalizedPrice: 130000,
                  priceChipId: 15,
                  chipLabel: '130',
                  sourceChipIds: const <int>[15],
                  sourceChipLabels: const <String>['130'],
                  expectedQty: 0,
                ),
                ReconciliationDraftOption(
                  productId: 83,
                  normalizedPrice: 200000,
                  priceChipId: 19,
                  chipLabel: '200',
                  sourceChipIds: const <int>[19],
                  sourceChipLabels: const <String>['200'],
                  expectedQty: 6,
                ),
              ],
            ),
          ],
        ),
        countedQtyByOption: const <String, int>{'83:130000': 0, '83:200000': 6},
        wasteQtyByOption: const <String, int>{'83:130000': 0, '83:200000': 0},
        wasteReasonByOption: const <String, String>{
          '83:130000': '',
          '83:200000': '',
        },
        saleRowsByOption: const <String, List<ReconciliationSaleRowInput>>{},
      );

      final lines = buildSubmitLines(state);
      expect(lines.length, 1);
      expect(lines.single.normalizedPrice, 200000);
      expect(lines.single.priceChipId, 19);
    },
  );
}
