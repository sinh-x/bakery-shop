import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/reconciliation_service.dart';
import 'package:bakery_app/features/stock/stock_reconciliation_screen.dart';
import 'package:bakery_app/providers/events_provider.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  Finder unitPriceFieldFinder() =>
      find.byKey(const Key('reconciliation-unit-price-field')).first;

  Future<void> expandFirstCategory(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.expand_more).first);
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
    SharedPreferences.setMockInitialValues({kLoggedByKey: 'An'});
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
    expect(find.text('Tồn đã đếm'), findsNothing);

    await tester.tap(find.text('Bánh kem dâu'));
    await tester.pumpAndSettle();

    expect(find.text('Tồn đã đếm'), findsOneWidget);
  });

  testWidgets('reconciliation list filters out products with expectedQty <= 0', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({kLoggedByKey: 'An'});
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
  });

  testWidgets('add row defaults option unit price and keeps manual edit', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({kLoggedByKey: 'An'});
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

    await tester.enterText(find.byType(TextField).first, '3');
    await tester.pumpAndSettle();
    await tester.tap(find.text(VN.themDongBan));
    await tester.pumpAndSettle();

    final unitPriceField = tester.widget<TextFormField>(unitPriceFieldFinder());
    expect(unitPriceField.controller?.text, '12000');

    await tester.enterText(unitPriceFieldFinder(), '15000');
    await tester.pumpAndSettle();
    final editedUnitPriceField = tester.widget<TextFormField>(
      unitPriceFieldFinder(),
    );
    expect(editedUnitPriceField.controller?.text, '15000');

    final firstSaleRow = find.ancestor(
      of: find.text('${VN.dongBan} 1'),
      matching: find.byType(Container),
    );
    await tester.tap(
      find.descendant(
        of: firstSaleRow.first,
        matching: find.byIcon(Icons.delete_outline),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('${VN.dongBan} 1'), findsOneWidget);
  });

  testWidgets('expanded option header hides chips without initial inventory', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({kLoggedByKey: 'An'});
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
  });

  testWidgets('sale row hides chip shortcut area when no chips qualify', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({kLoggedByKey: 'An'});
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

    await tester.enterText(find.byType(TextField).first, '1');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, VN.themDongBan));
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
      SharedPreferences.setMockInitialValues({kLoggedByKey: 'An'});
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

      final countedFields = find.byType(TextField);
      await tester.enterText(countedFields.at(0), '0');
      await tester.enterText(countedFields.at(1), '1');
      await tester.pumpAndSettle();

      expect(find.text('${VN.dongBan} 1'), findsNWidgets(2));

      final saleRow1 = find.ancestor(
        of: find.text('${VN.dongBan} 1').first,
        matching: find.byType(Container),
      );
      expect(
        find.descendant(of: saleRow1.first, matching: find.byType(ActionChip)),
        findsNothing,
      );
      final saleRow2 = find.ancestor(
        of: find.text('${VN.dongBan} 1').last,
        matching: find.byType(Container),
      );
      expect(
        find.descendant(of: saleRow2.first, matching: find.byType(ActionChip)),
        findsNothing,
      );

      final unitPriceFields = find.byKey(const Key('reconciliation-unit-price-field'));
      expect(unitPriceFields, findsNWidgets(2));

      await tester.enterText(unitPriceFields.at(0), '15500');
      await tester.enterText(unitPriceFields.at(1), '16600');
      await tester.pumpAndSettle();

      final firstEdited = tester.widget<TextFormField>(unitPriceFields.at(0));
      final secondEdited = tester.widget<TextFormField>(unitPriceFields.at(1));
      expect(firstEdited.controller?.text, '15500');
      expect(secondEdited.controller?.text, '16600');
    },
  );

  testWidgets('invalid submit review shows issues and blocks final submit', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({kLoggedByKey: 'An'});
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

    await tester.enterText(find.byType(TextField).first, '4');
    await tester.pumpAndSettle();
    await tester.tap(find.text(VN.themDongBan));
    await tester.pumpAndSettle();
    final saleRow = find.ancestor(
      of: find.text('${VN.dongBan} 1'),
      matching: find.byType(Container),
    );
    await tester.enterText(
      find.descendant(
        of: saleRow.first,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.controller != null &&
              widget.controller!.text == '0',
        ),
      ),
      '1',
    );
    await tester.enterText(unitPriceFieldFinder(), '');
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

    await tester.tap(find.byType(InkWell).first, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Trạng thái: Có lỗi'), findsOneWidget);
  });

  testWidgets('load failure and empty states show guidance with retry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({kLoggedByKey: 'An'});
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
    SharedPreferences.setMockInitialValues({kLoggedByKey: 'An'});
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

  testWidgets('auto sales row supports reorder, manual price, and waste-only path', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({kLoggedByKey: 'An'});
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

    await tester.enterText(find.byType(TextField).first, '4');
    await tester.pumpAndSettle();

    expect(find.text('${VN.dongBan} 1'), findsOneWidget);
    final prefilledUnitPrice = tester.widget<TextFormField>(
      unitPriceFieldFinder(),
    );
    expect(prefilledUnitPrice.controller?.text, '100000');

    final saleRowDy = tester.getTopLeft(find.text('${VN.dongBan} 1')).dy;
    final wasteLabelDy = tester.getTopLeft(find.text(VN.soLuongHaoHut).last).dy;
    expect(saleRowDy, lessThan(wasteLabelDy));

    final saleRow = find.ancestor(
      of: find.text('${VN.dongBan} 1'),
      matching: find.byType(Container),
    );
    await tester.enterText(
      find.descendant(
        of: saleRow.first,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.controller != null &&
              widget.controller!.text == '0',
        ),
      ),
      '1',
    );
    await tester.enterText(unitPriceFieldFinder(), '15000');
    await tester.pumpAndSettle();

    final editedUnitPrice = tester.widget<TextFormField>(unitPriceFieldFinder());
    expect(editedUnitPrice.controller?.text, '15000');

    await tester.tap(
      find.descendant(
        of: saleRow.first,
        matching: find.byIcon(Icons.delete_outline),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('${VN.dongBan} 1'), findsNothing);
    expect(find.text(VN.soLuongHaoHut), findsWidgets);

    final wasteField = find.byType(TextField).last;
    await tester.enterText(wasteField, '1');
    await tester.pumpAndSettle();
  });
}
