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
    'buildSubmitLines emits one line per chip when base price + two chips '
    'collide at the same price (DG-413 CQ-1 regression)',
    () {
      // Backend payload: a base-price option (price_chip_id=null) plus two
      // distinct chip options (price_chip_id=11 and 12) all at the same
      // normalized price 130000. The merge layer must NOT collapse the two
      // chips into one (which would null out priceChipId and collide with
      // the base bucket on submit).
      final product = ReconciliationDraftProduct.fromJson({
        'product_id': 83,
        'name': 'Bánh kem',
        'category': 'banh_kem',
        'expected_qty': 10,
        'base_price': 130000,
        'price_chips': [
          {'id': 11, 'label': 'chip 130a', 'price': 130000, 'position': 1},
          {'id': 12, 'label': 'chip 130b', 'price': 130000, 'position': 2},
        ],
        'options': [
          {
            'product_id': 83,
            'normalized_price': 130000,
            'chip_label': 'Gia goc',
            'source_chip_ids': <int>[],
            'source_chip_labels': <String>['Gia goc'],
            'expected_qty': 4,
          },
          {
            'product_id': 83,
            'normalized_price': 130000,
            'price_chip_id': 11,
            'chip_label': 'chip 130a',
            'source_chip_ids': [11],
            'source_chip_labels': ['chip 130a'],
            'expected_qty': 3,
          },
          {
            'product_id': 83,
            'normalized_price': 130000,
            'price_chip_id': 12,
            'chip_label': 'chip 130b',
            'source_chip_ids': [12],
            'source_chip_labels': ['chip 130b'],
            'expected_qty': 3,
          },
        ],
      });

      // Three distinct options must survive the merge: base + chipA + chipB.
      expect(product.options.length, 3);
      final base = product.options.firstWhere(
        (o) => o.keyDiscriminator == 'base',
      );
      final chipA = product.options.firstWhere(
        (o) => o.keyDiscriminator == 'c11',
      );
      final chipB = product.options.firstWhere(
        (o) => o.keyDiscriminator == 'c12',
      );
      expect(base.priceChipId, isNull);
      expect(chipA.priceChipId, 11);
      expect(chipB.priceChipId, 12);

      // buildSubmitLines must emit three lines with distinct price_chip_id
      // values (null for base, 11 for chipA, 12 for chipB) — not a single
      // null-chip line that would collide with the base bucket.
      final state = ReconciliationState(
        draft: ReconciliationDraft(
          date: '2026-05-04',
          products: [product],
        ),
        countedQtyByOption: const <String, int>{
          '83:130000#base': 4,
          '83:130000#c11': 2,
          '83:130000#c12': 3,
        },
        wasteQtyByOption: const <String, int>{},
        wasteReasonByOption: const <String, String>{},
        saleRowsByOption: const <String, List<ReconciliationSaleRowInput>>{},
      );

      final lines = buildSubmitLines(state);
      expect(lines.length, 3);
      final chipIds = lines.map((line) => line.priceChipId).toSet();
      expect(chipIds, <int?>{null, 11, 12});
      expect(lines.where((l) => l.priceChipId == null).length, 1);
      expect(lines.where((l) => l.priceChipId == 11).length, 1);
      expect(lines.where((l) => l.priceChipId == 12).length, 1);
    },
  );

  test(
    'normalizeReconciliationOptionKey throws on ambiguous product id '
    '(DG-413 CQ-2 regression)',
    () {
      final state = ReconciliationState(
        countedQtyByOption: const <String, int>{
          '83:130000#base': 4,
          '83:130000#c11': 2,
          '83:130000#c12': 3,
        },
        wasteQtyByOption: const <String, int>{},
        wasteReasonByOption: const <String, String>{},
        saleRowsByOption: const <String, List<ReconciliationSaleRowInput>>{},
      );

      // Two keys share the '83:' prefix — int input is ambiguous and must
      // fail loudly instead of fabricating '83:0'.
      expect(
        () => normalizeReconciliationOptionKey(83, state),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'normalizeReconciliationOptionKey throws on unknown product id '
    '(DG-413 CQ-2 regression)',
    () {
      final state = ReconciliationState(
        countedQtyByOption: const <String, int>{'1:12000': 2},
        wasteQtyByOption: const <String, int>{},
        wasteReasonByOption: const <String, String>{},
        saleRowsByOption: const <String, List<ReconciliationSaleRowInput>>{},
      );

      // No key matches the '99:' prefix — must throw instead of returning
      // the fabricated '99:0' dangling key.
      expect(
        () => normalizeReconciliationOptionKey(99, state),
        throwsA(isA<StateError>()),
      );
    },
  );

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

  // DG-413 Phase 2 — Regression tests for base-price == chip-price collision.
  group('DG-413 base-price == chip-price collision', () {
    // FR1 / AC1: When a trưng bày product's base price equals a price chip
    // price, the reconciliation draft renders base-price stock and chip-price
    // stock as two separate lines (not merged). This is the regression guard
    // for the Phase 1 merge fix in `mergeOptionsByNormalizedPrice`.
    test(
      'FR1/AC1: base-price and chip-price at the same price render as two separate lines',
      () {
        // Construct raw options that mirror the backend draft payload for a
        // trưng bày product whose base price (130.000đ) equals a price chip.
        // The backend sends `price_chip_id` for chip options (see
        // `reconciliations.py` _load_display_products), so the chip option
        // carries `price_chip_id: 11` here. The merge function must keep
        // base and chip separate so the per-chip expected_qty comparison in
        // the backend 409 guard still matches.
        const productId = 83;
        const price = 130000;
        const baseExpected = 5;
        const chipId = 11;
        const chipExpected = 3;

        final merged = mergeOptionsByNormalizedPrice([
          ReconciliationDraftOption(
            productId: productId,
            normalizedPrice: price,
            priceChipId: null,
            chipLabel: 'Gia goc',
            sourceChipIds: const <int>[],
            sourceChipLabels: const <String>['Gia goc'],
            expectedQty: baseExpected,
          ),
          ReconciliationDraftOption(
            productId: productId,
            normalizedPrice: price,
            priceChipId: chipId,
            chipLabel: 'chip 130',
            sourceChipIds: const <int>[chipId],
            sourceChipLabels: const <String>['chip 130'],
            expectedQty: chipExpected,
          ),
        ]);

        expect(merged.length, 2);
        final base = merged.first;
        final chip = merged.last;
        expect(base.normalizedPrice, price);
        expect(base.expectedQty, baseExpected);
        expect(base.priceChipId, isNull);
        expect(base.sourceChipIds, isEmpty);
        expect(base.keyDiscriminator, 'base');
        expect(chip.normalizedPrice, price);
        expect(chip.expectedQty, chipExpected);
        expect(chip.priceChipId, chipId);
        expect(chip.sourceChipIds, [chipId]);
        expect(chip.keyDiscriminator, 'c$chipId');

        // The two options must produce distinct state-map keys so the
        // reconciliation state never collapses base and chip counts into
        // the same entry (FR2 regression guard).
        final baseKey = reconciliationOptionKey(
          base.productId,
          base.normalizedPrice,
          discriminator: base.keyDiscriminator,
        );
        final chipKey = reconciliationOptionKey(
          chip.productId,
          chip.normalizedPrice,
          discriminator: chip.keyDiscriminator,
        );
        expect(baseKey, '83:130000#base');
        expect(chipKey, '83:130000#c11');
        expect(baseKey, isNot(equals(chipKey)));
      },
    );

    // FR1 / AC1 (state integration): loadDraft builds two distinct state-map
    // entries for base-price and chip-price at the same price, so counted
    // quantities and submit lines stay per-chip and match the backend's
    // (product_id, price_chip_id) key.
    test(
      'FR1/AC1: loadDraft keeps separate state keys for base-price and chip-price collision',
      () async {
        const productId = 83;
        const price = 130000;
        const baseExpected = 5;
        const chipId = 11;
        const chipExpected = 3;

        // Construct the draft via `fromJson` so `mergeOptionsByNormalizedPrice`
        // runs (the real path the backend payload takes) and stamps the
        // discriminators onto the colliding base + chip options.
        final service = _FakeReconciliationService(
          ReconciliationDraft.fromJson({
            'date': '2026-05-04',
            'products': [
              {
                'product_id': productId,
                'name': 'Bánh kem trưng bày',
                'category': 'banh_kem',
                'expected_qty': baseExpected + chipExpected,
                'base_price': price,
                'price_chips': [
                  {'id': chipId, 'label': 'chip 130', 'price': price, 'position': 0},
                ],
                'options': [
                  {
                    'product_id': productId,
                    'normalized_price': price,
                    'price_chip_id': null,
                    'chip_label': 'Gia goc',
                    'source_chip_ids': <int>[],
                    'source_chip_labels': <String>['Gia goc'],
                    'expected_qty': baseExpected,
                  },
                  {
                    'product_id': productId,
                    'normalized_price': price,
                    'price_chip_id': chipId,
                    'chip_label': 'chip 130',
                    'source_chip_ids': [chipId],
                    'source_chip_labels': ['chip 130'],
                    'expected_qty': chipExpected,
                  },
                ],
              },
            ],
          }),
        );
        final container = await buildContainer(service);
        addTearDown(container.dispose);

        await container.read(reconciliationProvider.notifier).loadDraft();
        final state = container.read(reconciliationProvider);

        // Two distinct state-map entries exist for the same product+price.
        final keys = state.countedQtyByOption.keys
            .where((key) => key.startsWith('$productId:$price'))
            .toList();
        expect(keys.length, 2);
        expect(keys.toSet(), {'$productId:$price#base', '$productId:$price#c$chipId'});

        // Each option retains its own expected_qty (NOT summed into one).
        expect(state.countedQtyByOption['$productId:$price#base'], baseExpected);
        expect(state.countedQtyByOption['$productId:$price#c$chipId'], chipExpected);
      },
    );

    // FR1 / AC1 (submit payload): buildSubmitLines emits two separate lines
    // for the collision — one for the base-price option (price_chip_id=null)
    // and one for the chip option (price_chip_id=11). Each line carries its
    // own expected_qty so the backend 409 guard matches both backend keys.
    test(
      'FR1/AC1: buildSubmitLines emits separate base and chip lines for collision',
      () {
        const productId = 83;
        const price = 130000;
        const baseExpected = 5;
        const chipId = 11;
        const chipExpected = 3;

        final state = ReconciliationState(
          draft: ReconciliationDraft(
            date: '2026-05-04',
            products: [
              ReconciliationDraftProduct(
                productId: productId,
                name: 'Bánh kem trưng bày',
                category: 'banh_kem',
                expectedQty: baseExpected + chipExpected,
                basePrice: price.toDouble(),
                priceChips: const <ReconciliationPriceChip>[],
                options: [
                  ReconciliationDraftOption(
                    productId: productId,
                    normalizedPrice: price,
                    priceChipId: null,
                    chipLabel: 'Gia goc',
                    sourceChipIds: const <int>[],
                    sourceChipLabels: const <String>['Gia goc'],
                    expectedQty: baseExpected,
                    keyDiscriminator: 'base',
                  ),
                  ReconciliationDraftOption(
                    productId: productId,
                    normalizedPrice: price,
                    priceChipId: chipId,
                    chipLabel: 'chip 130',
                    sourceChipIds: const <int>[chipId],
                    sourceChipLabels: const <String>['chip 130'],
                    expectedQty: chipExpected,
                    keyDiscriminator: 'c$chipId',
                  ),
                ],
              ),
            ],
          ),
          countedQtyByOption: const <String, int>{
            '$productId:$price#base': baseExpected,
            '$productId:$price#c$chipId': chipExpected,
          },
          wasteQtyByOption: const <String, int>{
            '$productId:$price#base': 0,
            '$productId:$price#c$chipId': 0,
          },
          wasteReasonByOption: const <String, String>{
            '$productId:$price#base': '',
            '$productId:$price#c$chipId': '',
          },
          saleRowsByOption:
              const <String, List<ReconciliationSaleRowInput>>{},
        );

        final lines = buildSubmitLines(state);
        expect(lines.length, 2);

        final baseLine = lines.firstWhere(
          (line) => line.priceChipId == null,
        );
        final chipLine = lines.firstWhere(
          (line) => line.priceChipId == chipId,
        );

        // The base line keeps the base expected_qty (chip_id=null backend key).
        expect(baseLine.productId, productId);
        expect(baseLine.normalizedPrice, price);
        expect(baseLine.expectedQty, baseExpected);
        expect(baseLine.countedQty, baseExpected);

        // The chip line carries the single resolved chip id and its own
        // expected_qty, matching the backend's (product_id, chip_id) key.
        expect(chipLine.productId, productId);
        expect(chipLine.normalizedPrice, price);
        expect(chipLine.expectedQty, chipExpected);
        expect(chipLine.countedQty, chipExpected);
      },
    );

    // FR3 / AC3: For products with distinct chip prices, existing merge
    // behavior is preserved — distinct chip prices do not collapse, and the
    // merge function does NOT inject discriminators for the non-collision
    // case. This guards against the Phase 1 change accidentally altering the
    // distinct-price flow.
    test(
      'FR3/AC3: distinct chip prices stay as separate options (no regression)',
      () {
        const productId = 10;
        const chipAId = 11;
        const chipBId = 12;
        const priceA = 130000;
        const priceB = 150000;

        final merged = mergeOptionsByNormalizedPrice([
          ReconciliationDraftOption(
            productId: productId,
            normalizedPrice: priceA,
            priceChipId: chipAId,
            chipLabel: 'chip 130',
            sourceChipIds: const <int>[chipAId],
            sourceChipLabels: const <String>['chip 130'],
            expectedQty: 5,
          ),
          ReconciliationDraftOption(
            productId: productId,
            normalizedPrice: priceB,
            priceChipId: chipBId,
            chipLabel: 'chip 150',
            sourceChipIds: const <int>[chipBId],
            sourceChipLabels: const <String>['chip 150'],
            expectedQty: 3,
          ),
        ]);

        // Distinct prices stay as two options — no merging across prices.
        expect(merged.length, 2);
        // No discriminator is injected for the non-collision case, so option
        // keys stay backward-compatible (`productId:price`).
        expect(merged.every((option) => option.keyDiscriminator == null), isTrue);
        expect(merged.first.normalizedPrice, priceA);
        expect(merged.last.normalizedPrice, priceB);
      },
    );

    // FR3 / AC3 (chip+chip at the same price still merge): the existing
    // behavior of merging multiple chip options that share a normalized
    // price (no base option involved) is preserved.
    test(
      'FR3/AC3: two chip options at the same price still merge (no regression)',
      () {
        const productId = 10;
        const price = 130000;
        const chipAId = 11;
        const chipBId = 12;

        final merged = mergeOptionsByNormalizedPrice([
          ReconciliationDraftOption(
            productId: productId,
            normalizedPrice: price,
            priceChipId: chipAId,
            chipLabel: 'chip 130',
            sourceChipIds: const <int>[chipAId],
            sourceChipLabels: const <String>['chip 130'],
            expectedQty: 5,
          ),
          ReconciliationDraftOption(
            productId: productId,
            normalizedPrice: price,
            priceChipId: chipBId,
            chipLabel: 'chip 130b',
            sourceChipIds: const <int>[chipBId],
            sourceChipLabels: const <String>['chip 130b'],
            expectedQty: 3,
          ),
        ]);

        // Two chip options at the same price still collapse into one option
        // (existing distinct-chip-at-same-price merge behavior unchanged).
        expect(merged.length, 1);
        final option = merged.single;
        expect(option.normalizedPrice, price);
        expect(option.expectedQty, 8);
        expect(option.sourceChipIds, [chipAId, chipBId]);
        // No discriminator for chip+chip merge (no base involved).
        expect(option.keyDiscriminator, isNull);
      },
    );
  });
}
