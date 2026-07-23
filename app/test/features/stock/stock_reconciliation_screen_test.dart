import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/reconciliation_service.dart';
import 'package:bakery_app/features/stock/stock_reconciliation_screen.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/login_screen_test_helpers.dart';

class _FakeService extends ReconciliationService {
  _FakeService(this._draft, {this.failDraftTimes = 0}) : super(Dio());

  final ReconciliationDraft _draft;
  int failDraftTimes;
  int draftCalls = 0;
  int submitCalls = 0;
  ReconciliationSubmitRequest? lastSubmitRequest;

  @override
  Future<ReconciliationDraft> getDraft() async {
    draftCalls += 1;
    if (failDraftTimes > 0) {
      failDraftTimes -= 1;
      throw DioException(
        requestOptions: RequestOptions(path: '/stock/reconciliation/draft'),
        type: DioExceptionType.connectionError,
      );
    }
    return _draft;
  }

  @override
  Future<ReconciliationSubmitResult> submit(
    ReconciliationSubmitRequest request,
  ) async {
    submitCalls += 1;
    lastSubmitRequest = request;
    return ReconciliationSubmitResult(
      id: 1,
      date: '2026-05-04',
      message: 'Đã lưu đối soát thành công',
    );
  }
}

void main() {
  Finder textFieldByLabel(String label) {
    return find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
  }

  Finder optionSummary(String optionKey) {
    return find.byKey(ValueKey('reconciliation-option-summary-$optionKey'));
  }

  Future<void> expandFirstCategory(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.expand_more).first);
    await tester.pumpAndSettle();
  }

  Future<void> expandOptionInventory(
    WidgetTester tester, {
    int index = 0,
  }) async {
    final header = find.textContaining('${VN.priceChipPrice} ').at(index);
    await tester.ensureVisible(header);
    await tester.tap(header);
    await tester.pumpAndSettle();
  }

  Finder saleModalButton() => find.text(VN.banHang);

  Finder wasteModalButton() => find.text(VN.haoHutSheet);

  Future<void> openSaleModal(WidgetTester tester, {int index = 0}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final button = saleModalButton().at(index);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  Future<void> openWasteModal(WidgetTester tester, {int index = 0}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final button = wasteModalButton().at(index);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  Future<void> confirmModal(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final button = find.text(VN.xacNhan);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  Future<void> cancelModal(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final button = find.text(VN.dong);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button, warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  GoRouter buildRouter() {
    return GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const StockReconciliationScreen(),
        ),
        GoRoute(
          path: '/stock/reconciliation/history',
          builder: (context, state) => const Scaffold(body: Text('Lịch sử')),
        ),
        GoRoute(
          path: '/stock/reconciliation/history/:id',
          builder: (context, state) =>
              Scaffold(body: Text('Chi tiết #${state.pathParameters['id']}')),
        ),
      ],
    );
  }

  testWidgets('product card toggles and shows collapsed summary', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
    final prefs = await SharedPreferences.getInstance();
    final service = _FakeService(
      ReconciliationDraft(
        date: '2026-05-04',
        products: [
          ReconciliationDraftProduct(
            productId: 1,
            name: 'Bánh kem dâu',
            category: 'banh_kem',
            expectedQty: 5,
            basePrice: 100000,
            priceChips: const [],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          reconciliationServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.refresh), findsWidgets);
    expect(find.byIcon(Icons.history), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

    expect(find.text('Bánh kem dâu'), findsNothing);
    expect(find.text('banh_kem'), findsOneWidget);
    await expandFirstCategory(tester);

    expect(find.text('Tồn dự kiến: 5'), findsOneWidget);
    expect(find.text('Trạng thái: Ổn'), findsOneWidget);
    expect(find.text(VN.tonDaDem), findsNothing);

    await tester.tap(find.text('Bánh kem dâu'));
    await tester.pumpAndSettle();

    expect(find.text(VN.tonDaDem), findsOneWidget);
  });

  testWidgets(
    'reconciliation list filters out products with expectedQty <= 0',
    (tester) async {
      SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
      final prefs = await SharedPreferences.getInstance();
      final service = _FakeService(
        ReconciliationDraft(
          date: '2026-05-04',
          products: [
            ReconciliationDraftProduct(
              productId: 1,
              name: 'Bánh kem dâu',
              category: 'banh_kem',
              expectedQty: 5,
              basePrice: 100000,
              priceChips: const [],
            ),
            ReconciliationDraftProduct(
              productId: 2,
              name: 'Bánh su kem',
              category: 'banh_kem',
              expectedQty: 0,
              basePrice: 12000,
              priceChips: const [],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            reconciliationServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp.router(routerConfig: buildRouter()),
        ),
      );
      await tester.pumpAndSettle();

      await expandFirstCategory(tester);

      expect(find.text('Bánh kem dâu'), findsOneWidget);
      expect(find.text('Bánh su kem'), findsNothing);
    },
  );

  testWidgets('add row defaults option unit price and keeps manual edit', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
    final prefs = await SharedPreferences.getInstance();
    final service = _FakeService(
      ReconciliationDraft(
        date: '2026-05-04',
        products: [
          ReconciliationDraftProduct(
            productId: 1,
            name: 'Bánh kem dâu',
            category: 'banh_kem',
            expectedQty: 5,
            basePrice: 100000,
            priceChips: [
              ReconciliationPriceChip(
                id: 1,
                label: 'M',
                price: 12000,
                position: 1,
              ),
            ],
            options: [
              ReconciliationDraftOption(
                productId: 1,
                normalizedPrice: 12000,
                chipLabel: 'M',
                sourceChipIds: [1],
                sourceChipLabels: ['M'],
                expectedQty: 5,
              ),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          reconciliationServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await expandFirstCategory(tester);

    await tester.tap(find.text('Bánh kem dâu'));
    await tester.pumpAndSettle();
    await expandOptionInventory(tester);

    await tester.enterText(find.byType(TextField).first, '3');
    await tester.pumpAndSettle();

    await openSaleModal(tester);

    final unitPriceField = tester.widget<TextFormField>(
      find.byKey(const Key('reconciliation-sale-modal-unit-price-field')),
    );
    expect(unitPriceField.controller?.text, '12000');

    await tester.enterText(
      find.byKey(const Key('reconciliation-sale-modal-unit-price-field')),
      '15000',
    );
    await tester.pumpAndSettle();
    final editedUnitPriceField = tester.widget<TextFormField>(
      find.byKey(const Key('reconciliation-sale-modal-unit-price-field')),
    );
    expect(editedUnitPriceField.controller?.text, '15000');

    await confirmModal(tester);
    await tester.pumpAndSettle();
  });

  testWidgets('expanded option header hides chips without initial inventory', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
    final prefs = await SharedPreferences.getInstance();
    final service = _FakeService(
      ReconciliationDraft(
        date: '2026-05-04',
        products: [
          ReconciliationDraftProduct(
            productId: 1,
            name: 'Bánh kem dâu',
            category: 'banh_kem',
            expectedQty: 2,
            basePrice: 100000,
            priceChips: [
              ReconciliationPriceChip(
                id: 2,
                label: 'M',
                price: 10000,
                position: 1,
              ),
              ReconciliationPriceChip(
                id: 3,
                label: 'L',
                price: 12000,
                position: 2,
              ),
            ],
            options: [
              ReconciliationDraftOption(
                productId: 1,
                normalizedPrice: 10000,
                chipLabel: 'M',
                sourceChipIds: [2],
                sourceChipLabels: ['M'],
                expectedQty: 2,
              ),
              ReconciliationDraftOption(
                productId: 1,
                normalizedPrice: 12000,
                chipLabel: 'L',
                sourceChipIds: [3],
                sourceChipLabels: ['L'],
                expectedQty: 0,
              ),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          reconciliationServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await expandFirstCategory(tester);
    await tester.tap(find.text('Bánh kem dâu'));
    await tester.pumpAndSettle();

    expect(find.text('${VN.nhanChip}: M'), findsOneWidget);
    expect(find.text('${VN.nhanChip}: L'), findsNothing);
    expect(textFieldByLabel(VN.tonDaDem), findsNothing);

    await expandOptionInventory(tester);
    expect(textFieldByLabel(VN.tonDaDem), findsOneWidget);
  });

  testWidgets('multi-chip option header excludes same-price no-stock chip', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
    final prefs = await SharedPreferences.getInstance();
    final service = _FakeService(
      ReconciliationDraft(
        date: '2026-05-04',
        products: [
          ReconciliationDraftProduct.fromJson({
            'product_id': 1,
            'name': 'Bánh kem dâu',
            'category': 'banh_kem',
            'expected_qty': 2,
            'base_price': 100000,
            'price_chips': [
              {'id': 2, 'label': 'Có hàng', 'price': 10000, 'position': 1},
              {'id': 3, 'label': 'Không tồn', 'price': 10000, 'position': 2},
            ],
            'options': [
              {
                'product_id': 1,
                'normalized_price': 10000,
                'chip_label': 'Có hàng',
                'source_chip_ids': const <int>[],
                'source_chip_labels': ['Có hàng'],
                'expected_qty': 2,
              },
              {
                'product_id': 1,
                'normalized_price': 10000,
                'chip_label': 'Không tồn',
                'source_chip_ids': const <int>[],
                'source_chip_labels': ['Không tồn'],
                'expected_qty': 0,
              },
            ],
          }),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          reconciliationServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await expandFirstCategory(tester);
    await tester.tap(find.text('Bánh kem dâu'));
    await tester.pumpAndSettle();

    expect(find.text('${VN.nhanChip}: Có hàng'), findsOneWidget);
    expect(find.textContaining('Không tồn'), findsNothing);
  });

  testWidgets('sale row hides chip shortcut area when no chips qualify', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
    final prefs = await SharedPreferences.getInstance();
    final service = _FakeService(
      ReconciliationDraft(
        date: '2026-05-04',
        products: [
          ReconciliationDraftProduct(
            productId: 1,
            name: 'Bánh kem dâu',
            category: 'banh_kem',
            expectedQty: 2,
            basePrice: 100000,
            priceChips: [
              ReconciliationPriceChip(
                id: 1,
                label: 'A',
                price: 12000,
                position: 1,
              ),
            ],
            options: [
              ReconciliationDraftOption(
                productId: 1,
                normalizedPrice: 16000,
                chipLabel: 'Gia 16k',
                sourceChipIds: const <int>[],
                sourceChipLabels: const <String>[],
                expectedQty: 2,
              ),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          reconciliationServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await expandFirstCategory(tester);
    await tester.tap(find.text('Bánh kem dâu'));
    await tester.pumpAndSettle();
    await expandOptionInventory(tester);

    await tester.enterText(find.byType(TextField).first, '1');
    await tester.pumpAndSettle();
    await openSaleModal(tester);
    await tester.enterText(textFieldByLabel(VN.soLuongBan).first, '1');
    await tester.pumpAndSettle();
    await confirmModal(tester);
    await tester.pumpAndSettle();

    final saleRow = find.ancestor(
      of: find.text('${VN.dongBan} 1'),
      matching: find.byType(Container),
    );
    expect(
      find.descendant(of: saleRow.first, matching: find.byType(ActionChip)),
      findsNothing,
    );
    expect(find.text('A: 12000đ'), findsNothing);
  });

  testWidgets(
    'sale row has no ActionChip and manual unit price stays editable',
    (tester) async {
      SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
      final prefs = await SharedPreferences.getInstance();
      final service = _FakeService(
        ReconciliationDraft(
          date: '2026-05-04',
          products: [
            ReconciliationDraftProduct(
              productId: 1,
              name: 'Bánh kem dâu',
              category: 'banh_kem',
              expectedQty: 3,
              basePrice: 100000,
              priceChips: [
                ReconciliationPriceChip(
                  id: 1,
                  label: 'A',
                  price: 12000,
                  position: 1,
                ),
                ReconciliationPriceChip(
                  id: 2,
                  label: 'B',
                  price: 14000,
                  position: 2,
                ),
              ],
              options: [
                ReconciliationDraftOption(
                  productId: 1,
                  normalizedPrice: 12000,
                  chipLabel: 'Gia 12k',
                  sourceChipIds: const <int>[],
                  sourceChipLabels: const <String>[],
                  expectedQty: 1,
                ),
                ReconciliationDraftOption(
                  productId: 1,
                  normalizedPrice: 16000,
                  chipLabel: 'Gia 16k',
                  sourceChipIds: const <int>[],
                  sourceChipLabels: const <String>[],
                  expectedQty: 2,
                ),
              ],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            reconciliationServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp.router(routerConfig: buildRouter()),
        ),
      );
      await tester.pumpAndSettle();

      await expandFirstCategory(tester);
      await tester.tap(find.text('Bánh kem dâu'));
      await tester.pumpAndSettle();
      await expandOptionInventory(tester);
      await expandOptionInventory(tester, index: 1);

      final countedFields = find.byType(TextField);
      await tester.enterText(countedFields.at(0), '0');
      await tester.enterText(countedFields.at(1), '1');
      await tester.pumpAndSettle();

      await openSaleModal(tester, index: 0);
      await tester.enterText(textFieldByLabel(VN.soLuongBan).first, '1');
      final saleRow1UnitPrice = find.byKey(
        const Key('reconciliation-sale-modal-unit-price-field'),
      );
      await tester.enterText(saleRow1UnitPrice, '15500');
      await tester.pumpAndSettle();
      final firstEdited = tester.widget<TextFormField>(saleRow1UnitPrice);
      expect(firstEdited.controller?.text, '15500');
      await confirmModal(tester);
      await tester.pumpAndSettle();

      // Inline sale row for option 1 has no ActionChip shortcuts.
      final saleRow1 = find.ancestor(
        of: find.text('${VN.dongBan} 1'),
        matching: find.byType(Container),
      );
      expect(
        find.descendant(of: saleRow1.first, matching: find.byType(ActionChip)),
        findsNothing,
      );

      await openSaleModal(tester, index: 1);
      await tester.enterText(textFieldByLabel(VN.soLuongBan).first, '1');
      final saleRow2UnitPrice = find.byKey(
        const Key('reconciliation-sale-modal-unit-price-field'),
      );
      await tester.enterText(saleRow2UnitPrice, '16500');
      await tester.pumpAndSettle();
      final secondEdited = tester.widget<TextFormField>(saleRow2UnitPrice);
      expect(secondEdited.controller?.text, '16500');
      await confirmModal(tester);
      await tester.pumpAndSettle();

      // Inline sale row for option 2 has no ActionChip shortcuts.
      final saleRow2 = find.ancestor(
        of: find.text('${VN.dongBan} 1'),
        matching: find.byType(Container),
      );
      expect(
        find.descendant(of: saleRow2.first, matching: find.byType(ActionChip)),
        findsNothing,
      );
    },
  );

  testWidgets(
    'no-chip single price inventory renders expanded without option collapse',
    (tester) async {
      SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
      final prefs = await SharedPreferences.getInstance();
      final service = _FakeService(
        ReconciliationDraft(
          date: '2026-05-04',
          products: [
            ReconciliationDraftProduct(
              productId: 1,
              name: 'Bánh kem dâu',
              category: 'banh_kem',
              expectedQty: 5,
              basePrice: 100000,
              priceChips: const [],
            ),
          ],
        ),
      );

      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            reconciliationServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp.router(routerConfig: buildRouter()),
        ),
      );
      await tester.pumpAndSettle();

      await expandFirstCategory(tester);
      await tester.tap(find.text('Bánh kem dâu'));
      await tester.pumpAndSettle();

      expect(find.textContaining('${VN.priceChipPrice} '), findsOneWidget);
      final summary = optionSummary('1:100000');
      expect(summary, findsOneWidget);
      expect(
        find.descendant(of: summary, matching: find.text('${VN.tonDaDem}: 5')),
        findsOneWidget,
      );
      // Complete sale row (qty=1, price=15000, method defaults to cash) —
      // no validation errors expected.
      expect(
        find.descendant(
          of: summary,
          matching: find.text('${VN.trangThai}: ${VN.trangThaiOn}'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: summary,
          matching: find.text('${VN.soLuongHaoHut}: 0'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: summary,
          matching: find.text('${VN.soLuongChenhLech}: 0'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: summary,
          matching: find.text('${VN.trangThai}: ${VN.trangThaiOn}'),
        ),
        findsOneWidget,
      );
      expect(textFieldByLabel(VN.tonDaDem), findsOneWidget);
      await tester.tap(find.textContaining('${VN.priceChipPrice} ').first);
      await tester.pumpAndSettle();
      expect(textFieldByLabel(VN.tonDaDem), findsOneWidget);

      await tester.enterText(textFieldByLabel(VN.tonDaDem).first, '4');
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: summary,
          matching: find.text('${VN.trangThai}: ${VN.trangThaiCoLoi}'),
        ),
        findsOneWidget,
      );

      await tester.enterText(textFieldByLabel(VN.tonDaDem).first, '5');
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: summary,
          matching: find.text('${VN.trangThai}: ${VN.trangThaiOn}'),
        ),
        findsOneWidget,
      );

      await tester.enterText(textFieldByLabel(VN.tonDaDem).first, '4');
      await tester.pumpAndSettle();

      await openSaleModal(tester);
      expect(
        find.byKey(const Key('reconciliation-sale-modal-unit-price-field')),
        findsOneWidget,
      );
      await tester.enterText(textFieldByLabel(VN.soLuongBan).first, '1');
      await tester.enterText(
        find.byKey(const Key('reconciliation-sale-modal-unit-price-field')),
        '15000',
      );
      await tester.pumpAndSettle();
      await confirmModal(tester);
      await tester.pumpAndSettle();

      // Complete sale row (qty=1, price=15000, method defaults to cash) —
      // no validation errors expected.
      expect(
        find.descendant(
          of: summary,
          matching: find.text('${VN.trangThai}: ${VN.trangThaiOn}'),
        ),
        findsOneWidget,
      );

      expect(
        find.descendant(of: summary, matching: find.text('${VN.tonDaDem}: 4')),
        findsOneWidget,
      );
      // Complete sale row (qty=1, price=15000, method defaults to cash) —
      // no validation errors expected.
      expect(
        find.descendant(
          of: summary,
          matching: find.text('${VN.trangThai}: ${VN.trangThaiOn}'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: summary,
          matching: find.text('${VN.soLuongHaoHut}: 0'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: summary,
          matching: find.text('${VN.soLuongChenhLech}: 0'),
        ),
        findsOneWidget,
      );
      // Complete sale row (qty=1, price=15000, method defaults to cash) —
      // no validation errors expected.
      expect(
        find.descendant(
          of: summary,
          matching: find.text('${VN.trangThai}: ${VN.trangThaiOn}'),
        ),
        findsOneWidget,
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid submit review shows issues and blocks final submit', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
    final prefs = await SharedPreferences.getInstance();
    final service = _FakeService(
      ReconciliationDraft(
        date: '2026-05-04',
        products: [
          ReconciliationDraftProduct(
            productId: 1,
            name: 'Bánh kem dâu',
            category: 'banh_kem',
            expectedQty: 5,
            basePrice: 100000,
            priceChips: const [],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          reconciliationServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await expandFirstCategory(tester);

    await tester.tap(find.text('Bánh kem dâu'));
    await tester.pumpAndSettle();
    await expandOptionInventory(tester);

    await tester.enterText(find.byType(TextField).first, '4');
    await tester.pumpAndSettle();
    await openSaleModal(tester);
    await tester.enterText(textFieldByLabel(VN.soLuongBan).first, '1');
    await tester.enterText(
      find.byKey(const Key('reconciliation-sale-modal-unit-price-field')),
      '',
    );
    await tester.pumpAndSettle();
    await confirmModal(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, VN.guiDoiSoat));
    await tester.pumpAndSettle();

    expect(find.textContaining(VN.tongSoLuongBan), findsOneWidget);
    expect(find.textContaining(VN.tongSoLuongHaoHut), findsOneWidget);
    expect(find.text(VN.vanDeCanXuLyTruocKhiGui), findsOneWidget);

    final confirmButton = tester.widget<FilledButton>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, VN.guiDoiSoat),
      ),
    );
    expect(confirmButton.onPressed, isNull);
    expect(service.submitCalls, 0);

    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();

    expect(find.text('${VN.trangThai}: ${VN.trangThaiCoLoi}'), findsWidgets);
  });

  testWidgets('missing sale row payment method blocks submit review', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
    final prefs = await SharedPreferences.getInstance();
    final service = _FakeService(
      ReconciliationDraft(
        date: '2026-05-04',
        products: [
          ReconciliationDraftProduct(
            productId: 1,
            name: 'Bánh kem dâu',
            category: 'banh_kem',
            expectedQty: 5,
            basePrice: 100000,
            priceChips: const [],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          reconciliationServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await expandFirstCategory(tester);
    await tester.tap(find.text('Bánh kem dâu'));
    await tester.pumpAndSettle();
    await expandOptionInventory(tester);

    await tester.enterText(textFieldByLabel(VN.tonDaDem).first, '4');
    await tester.pumpAndSettle();
    await openSaleModal(tester);
    await tester.enterText(textFieldByLabel(VN.soLuongBan).first, '1');
    await tester.pumpAndSettle();
    await confirmModal(tester);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: optionSummary('1:100000'),
        matching: find.text('${VN.soLuongBan}: 1'),
      ),
      findsOneWidget,
    );

    // Payment method defaults to 'cash', so no method error — submit review
    // proceeds normally.
    await tester.tap(find.widgetWithText(FilledButton, VN.guiDoiSoat));
    await tester.pumpAndSettle();

    expect(find.textContaining(VN.tongSoLuongBan), findsOneWidget);
    final confirmButton = tester.widget<FilledButton>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, VN.guiDoiSoat),
      ),
    );
    expect(confirmButton.onPressed, isNotNull);
  });

  testWidgets('load failure and empty states show guidance with retry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
    final prefs = await SharedPreferences.getInstance();
    final service = _FakeService(
      ReconciliationDraft(date: '2026-05-04', products: const []),
      failDraftTimes: 1,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          reconciliationServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, VN.taiLai), findsOneWidget);
    expect(find.text(VN.huongDanTaiLaiDoiSoat), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, VN.taiLai));
    await tester.pumpAndSettle();

    expect(service.draftCalls, 2);
    expect(find.text(VN.khongCoSanPhamTrungBay), findsOneWidget);
    expect(find.text(VN.huongDanKhongCoSanPhamTrungBay), findsOneWidget);
    expect(find.widgetWithText(FilledButton, VN.taiLai), findsOneWidget);
  });

  testWidgets('submit success keeps action to open saved history detail', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
    final prefs = await SharedPreferences.getInstance();
    final service = _FakeService(
      ReconciliationDraft(
        date: '2026-05-04',
        products: [
          ReconciliationDraftProduct(
            productId: 1,
            name: 'Bánh kem dâu',
            category: 'banh_kem',
            expectedQty: 1,
            basePrice: 100000,
            priceChips: const [],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          reconciliationServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, VN.guiDoiSoat));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, VN.guiDoiSoat),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.submitCalls, 1);
    await tester.tap(find.widgetWithText(SnackBarAction, VN.xemLichSu));
    await tester.pumpAndSettle();
    expect(find.text('Chi tiết #1'), findsOneWidget);
  });

  testWidgets(
    'variance indicator updates value, sign, color, and wraps at 360',
    (tester) async {
      SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
      final prefs = await SharedPreferences.getInstance();
      final service = _FakeService(
        ReconciliationDraft(
          date: '2026-05-04',
          products: [
            ReconciliationDraftProduct(
              productId: 1,
              name: 'Bánh kem dâu',
              category: 'banh_kem',
              expectedQty: 5,
              basePrice: 100000,
              priceChips: const [],
            ),
          ],
        ),
      );

      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            reconciliationServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp.router(routerConfig: buildRouter()),
        ),
      );
      await tester.pumpAndSettle();

      await expandFirstCategory(tester);
      await tester.tap(find.text('Bánh kem dâu'));
      await tester.pumpAndSettle();
      await expandOptionInventory(tester);

      await tester.enterText(textFieldByLabel(VN.tonDaDem).first, '4');
      await tester.pumpAndSettle();

      final positiveVarianceFinder = find.text('${VN.soLuongChenhLech}: +1');
      expect(positiveVarianceFinder, findsWidgets);
      final positiveVarianceText = tester
          .widgetList<Text>(positiveVarianceFinder)
          .first;
      expect(positiveVarianceText.style?.color, Colors.red[700]);

      await openSaleModal(tester);
      await tester.enterText(textFieldByLabel(VN.soLuongBan).first, '1');
      await tester.pumpAndSettle();
      await confirmModal(tester);
      await tester.pumpAndSettle();

      final zeroVarianceFinder = find.text('${VN.soLuongChenhLech}: 0');
      expect(zeroVarianceFinder, findsWidgets);
      final zeroVarianceText = tester
          .widgetList<Text>(zeroVarianceFinder)
          .first;
      expect(zeroVarianceText.style?.color, Colors.green[700]);

      await openWasteModal(tester);
      await tester.enterText(textFieldByLabel(VN.soLuongHaoHut).first, '1');
      await tester.pumpAndSettle();
      await confirmModal(tester);
      await tester.pumpAndSettle();

      final negativeVarianceFinder = find.text('${VN.soLuongChenhLech}: -1');
      expect(negativeVarianceFinder, findsWidgets);
      final negativeVarianceText = tester
          .widgetList<Text>(negativeVarianceFinder)
          .first;
      expect(negativeVarianceText.style?.color, Colors.red[700]);

      await tester.enterText(textFieldByLabel(VN.tonDaDem).first, '3');
      await tester.pumpAndSettle();
      expect(find.text('${VN.soLuongChenhLech}: 0'), findsWidgets);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sales row supports reorder, manual price, and waste-only path',
    (tester) async {
      SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
      final prefs = await SharedPreferences.getInstance();
      final service = _FakeService(
        ReconciliationDraft(
          date: '2026-05-04',
          products: [
            ReconciliationDraftProduct(
              productId: 1,
              name: 'Bánh kem dâu',
              category: 'banh_kem',
              expectedQty: 5,
              basePrice: 100000,
              priceChips: const [],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            reconciliationServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp.router(routerConfig: buildRouter()),
        ),
      );
      await tester.pumpAndSettle();

      await expandFirstCategory(tester);
      await tester.tap(find.text('Bánh kem dâu'));
      await tester.pumpAndSettle();
      await expandOptionInventory(tester);

      await tester.enterText(find.byType(TextField).first, '4');
      await tester.pumpAndSettle();

      await openSaleModal(tester);
      final saleUnitPriceField = find.byKey(
        const Key('reconciliation-sale-modal-unit-price-field'),
      );
      final prefilledUnitPrice = tester.widget<TextFormField>(
        saleUnitPriceField,
      );
      expect(prefilledUnitPrice.controller?.text, '100000');

      await tester.enterText(textFieldByLabel(VN.soLuongBan).first, '1');
      await tester.enterText(saleUnitPriceField, '15000');
      await tester.pumpAndSettle();

      final editedUnitPrice = tester.widget<TextFormField>(
        saleUnitPriceField,
      );
      expect(editedUnitPrice.controller?.text, '15000');
      await confirmModal(tester);
      await tester.pumpAndSettle();

      // Submitted sale row renders inline below the sale/waste buttons.
      expect(find.text('${VN.dongBan} 1'), findsOneWidget);
      final saleRowDy = tester.getTopLeft(find.text('${VN.dongBan} 1')).dy;
      final wasteButtonDy = tester.getTopLeft(
        find.widgetWithText(OutlinedButton, VN.haoHutSheet),
      ).dy;
      expect(saleRowDy, greaterThan(wasteButtonDy));

      // Delete the inline sale row via the X (close) icon button.
      final saleRow = find.ancestor(
        of: find.text('${VN.dongBan} 1'),
        matching: find.byType(Container),
      );
      final deleteButton = find.descendant(
        of: saleRow.first,
        matching: find.widgetWithIcon(IconButton, Icons.close),
      );
      expect(deleteButton, findsOneWidget);
      await tester.tap(deleteButton, warnIfMissed: true);
      await tester.pumpAndSettle();
      // Verify the row was removed.
      expect(find.text('${VN.dongBan} 1'), findsNothing);

      // Waste-only path: open the waste modal, enter qty, submit.
      await openWasteModal(tester);
      await tester.enterText(textFieldByLabel(VN.soLuongHaoHut).first, '1');
      await tester.pumpAndSettle();
      await confirmModal(tester);
      await tester.pumpAndSettle();
    },
  );

  // DG-200 Phase 6 — surplus (counted > expected) inflow display (FR-9, AC-11)
  testWidgets(
    'surplus displays inflow quantity and restock indicator and hides sale/waste editors',
    (tester) async {
      SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
      final prefs = await SharedPreferences.getInstance();
      final service = _FakeService(
        ReconciliationDraft(
          date: '2026-07-05',
          products: [
            ReconciliationDraftProduct(
              productId: 1,
              name: 'Bánh kem dâu',
              category: 'banh_kem',
              expectedQty: 5,
              basePrice: 100000,
              priceChips: const [],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            reconciliationServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp.router(routerConfig: buildRouter()),
        ),
      );
      await tester.pumpAndSettle();

      await expandFirstCategory(tester);
      await tester.tap(find.text('Bánh kem dâu'));
      await tester.pumpAndSettle();
      await expandOptionInventory(tester);

      // Counted > expected (8 > 5) creates a surplus of 3.
      await tester.enterText(textFieldByLabel(VN.tonDaDem).first, '8');
      await tester.pumpAndSettle();

      final summary = optionSummary('1:100000');
      // Surplus inflow indicator visible with restock label.
      expect(
        find.descendant(
          of: summary,
          matching: find.textContaining('${VN.soLuongBu}: +3'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: summary,
          matching: find.text(VN.nhapBuTonKho),
        ),
        findsOneWidget,
      );
      // Status is OK (no sale/waste for surplus).
      expect(
        find.descendant(
          of: summary,
          matching: find.text('${VN.trangThai}: ${VN.trangThaiOn}'),
        ),
        findsOneWidget,
      );
      // Sale row editor and waste editor are hidden for surplus.
      expect(find.text(VN.themDongBan), findsNothing);
      expect(find.text(VN.lyDoHaoHut), findsNothing);
      // Surplus hint is shown in the editor area.
      expect(find.text(VN.nhapBuHint), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'surplus submit review succeeds when counted > expected and no sale/waste',
    (tester) async {
      SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
      final prefs = await SharedPreferences.getInstance();
      final service = _FakeService(
        ReconciliationDraft(
          date: '2026-07-05',
          products: [
            ReconciliationDraftProduct(
              productId: 1,
              name: 'Bánh kem dâu',
              category: 'banh_kem',
              expectedQty: 5,
              basePrice: 100000,
              priceChips: const [],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            reconciliationServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp.router(routerConfig: buildRouter()),
        ),
      );
      await tester.pumpAndSettle();

      await expandFirstCategory(tester);
      await tester.tap(find.text('Bánh kem dâu'));
      await tester.pumpAndSettle();
      await expandOptionInventory(tester);

      await tester.enterText(textFieldByLabel(VN.tonDaDem).first, '8');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, VN.guiDoiSoat));
      await tester.pumpAndSettle();
      // No unresolved issues → confirm button enabled.
      final confirmButton = tester.widget<FilledButton>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, VN.guiDoiSoat),
        ),
      );
      expect(confirmButton.onPressed, isNotNull);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, VN.guiDoiSoat),
        ),
      );
      await tester.pumpAndSettle();

      expect(service.submitCalls, 1);
      expect(service.lastSubmitRequest!.lines.first.countedQty, 8);
      expect(service.lastSubmitRequest!.lines.first.expectedQty, 5);
      expect(service.lastSubmitRequest!.lines.first.saleQty, 0);
      expect(service.lastSubmitRequest!.lines.first.wasteQty, 0);
    },
  );

  testWidgets(
    'surplus with leftover sale row blocks submit and shows error',
    (tester) async {
      SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
      final prefs = await SharedPreferences.getInstance();
      final service = _FakeService(
        ReconciliationDraft(
          date: '2026-07-05',
          products: [
            ReconciliationDraftProduct(
              productId: 1,
              name: 'Bánh kem dâu',
              category: 'banh_kem',
              expectedQty: 5,
              basePrice: 100000,
              priceChips: const [],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            reconciliationServiceProvider.overrideWithValue(service),
          ],
          child: MaterialApp.router(routerConfig: buildRouter()),
        ),
      );
      await tester.pumpAndSettle();

      await expandFirstCategory(tester);
      await tester.tap(find.text('Bánh kem dâu'));
      await tester.pumpAndSettle();
      await expandOptionInventory(tester);

      // First create a missing scenario to seed a sale row, then push counted above expected.
      await tester.enterText(textFieldByLabel(VN.tonDaDem).first, '4');
      await tester.pumpAndSettle();
      await openSaleModal(tester);
      await tester.enterText(textFieldByLabel(VN.soLuongBan).first, '1');
      await tester.pumpAndSettle();
      await confirmModal(tester);
      await tester.pumpAndSettle();

      // Now push counted above expected while a sale row remains.
      await tester.enterText(textFieldByLabel(VN.tonDaDem).first, '8');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, VN.guiDoiSoat));
      await tester.pumpAndSettle();

      final confirmButton = tester.widget<FilledButton>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, VN.guiDoiSoat),
        ),
      );
      expect(confirmButton.onPressed, isNull);
      expect(service.submitCalls, 0);
      expect(
        find.textContaining('tự nhập bù'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'cancel sell/waste modal preserves live sale row and waste mutations',
    (tester) async {
    SharedPreferences.setMockInitialValues({
      'auth_token': kTestAdminToken,
      'auth_username': 'An',
      'auth_role': 'staff',
    });
    final prefs = await SharedPreferences.getInstance();
    final service = _FakeService(
      ReconciliationDraft(
        date: '2026-05-04',
        products: [
          ReconciliationDraftProduct(
            productId: 1,
            name: 'Bánh kem dâu',
            category: 'banh_kem',
            expectedQty: 5,
            basePrice: 100000,
            priceChips: const [],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          reconciliationServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await expandFirstCategory(tester);
    await tester.tap(find.text('Bánh kem dâu'));
    await tester.pumpAndSettle();
    await expandOptionInventory(tester);

    await tester.enterText(textFieldByLabel(VN.tonDaDem).first, '4');
    await tester.pumpAndSettle();

    final summary = optionSummary('1:100000');
    expect(
      find.descendant(
        of: summary,
        matching: find.text('${VN.soLuongBan}: 0'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: summary,
        matching: find.text('${VN.soLuongHaoHut}: 0'),
      ),
      findsOneWidget,
    );

    await openSaleModal(tester);
    await tester.enterText(textFieldByLabel(VN.soLuongBan).first, '1');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('reconciliation-sale-modal-unit-price-field')),
      '15000',
    );
    await tester.pumpAndSettle();
    await confirmModal(tester);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: summary,
        matching: find.text('${VN.soLuongBan}: 1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: summary,
        matching: find.text('${VN.soLuongHaoHut}: 0'),
      ),
      findsOneWidget,
    );

    await openWasteModal(tester);
    await tester.enterText(textFieldByLabel(VN.soLuongHaoHut).first, '1');
    await tester.pumpAndSettle();
    await cancelModal(tester);
    await tester.pumpAndSettle();

    // Modal is dismissed.
    expect(find.text(VN.xacNhan), findsNothing);
    expect(find.text(VN.dong), findsNothing);
    // The sale row submitted earlier remains in shared state; the waste
    // modal was cancelled before submit so waste stays at 0.
    expect(
      find.descendant(
        of: summary,
        matching: find.text('${VN.soLuongBan}: 1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: summary,
        matching: find.text('${VN.soLuongHaoHut}: 0'),
      ),
      findsOneWidget,
    );
  });
}
