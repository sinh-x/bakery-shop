import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/category_service.dart';
import 'package:bakery_app/data/api/stock_service.dart';
import 'package:bakery_app/data/models/category.dart';
import 'package:bakery_app/features/stock/stock_screen.dart';
import 'package:bakery_app/features/stock/widgets/stock_action_sheet.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:bakery_app/shared/utils/product_photo_url.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeStockService extends StockService {
  _FakeStockService(this._items) : super(Dio());

  final List<StockOverviewItem> _items;

  @override
  Future<List<StockOverviewItem>> getStockOverview() async => _items;
}

class _FakeCategoryService extends CategoryService {
  _FakeCategoryService(this._categories) : super(Dio());

  final List<Category> _categories;

  @override
  Future<List<Category>> listCategories({bool includeInactive = false}) async {
    return _categories;
  }
}

/// Fake [StockService] that records [restock] calls without hitting the
/// network. Used by DG-266 Phase 4 chip-tap tests to verify pre-selected
/// price propagation and dismiss-without-submit behavior.
class _RecordingStockService extends StockService {
  _RecordingStockService(this._items) : super(Dio());

  final List<StockOverviewItem> _items;
  final List<Map<String, Object?>> restockCalls = [];
  int overviewCallCount = 0;

  @override
  Future<List<StockOverviewItem>> getStockOverview() async {
    overviewCallCount++;
    return _items;
  }

  @override
  Future<void> restock(
    int productId,
    int quantity, {
    String note = '',
    int? normalizedPrice,
  }) async {
    restockCalls.add({
      'productId': productId,
      'quantity': quantity,
      'note': note,
      'normalizedPrice': normalizedPrice,
    });
  }
}

void main() {
  test('builds cache-busted stock product photo URL', () {
    expect(
      productPhotoUrl('http://localhost:8000', 9, cacheBuster: '11'),
      'http://localhost:8000/api/products/9/photo?v=11',
    );
  });

  GoRouter buildRouter() {
    return GoRouter(
      routes: [
        GoRoute(
          path: '/stock',
          builder: (context, state) => const StockScreen(),
        ),
      ],
      initialLocation: '/stock',
    );
  }

  testWidgets('groups by category with collapsed sections by default', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final stockService = _FakeStockService([
      StockOverviewItem(
        productId: 1,
        productName: 'Bánh dâu',
        category: 'banh_kem',
        quantity: 5,
        basePrice: 100000,
        perChip: const [],
      ),
      StockOverviewItem(
        productId: 2,
        productName: 'Nến số',
        category: 'phu_kien',
        quantity: 2,
        basePrice: 5000,
        perChip: const [],
      ),
    ]);
    final categoryService = _FakeCategoryService(const [
      Category(
        id: 1,
        slug: 'phu_kien',
        name: 'Phụ kiện',
        codePrefix: 'PK',
        active: 1,
        position: 1,
      ),
      Category(
        id: 2,
        slug: 'banh_kem',
        name: 'Bánh kem',
        codePrefix: 'BK',
        active: 1,
        position: 2,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          stockServiceProvider.overrideWithValue(stockService),
          categoryServiceProvider.overrideWithValue(categoryService),
        ],
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Phụ kiện'), findsOneWidget);
    expect(find.text('Bánh kem'), findsOneWidget);
    expect(find.text('Nến số'), findsNothing);
    expect(find.text('Bánh dâu'), findsNothing);

    await tester.tap(find.text('Phụ kiện'));
    await tester.pumpAndSettle();
    expect(find.text('Nến số'), findsOneWidget);
    expect(find.text(VN.nhapHang), findsOneWidget);
    expect(find.text(VN.haoHut), findsOneWidget);
    expect(find.text(VN.dieuChinh), findsOneWidget);
    expect(find.byIcon(Icons.add), findsWidgets);
    expect(find.byIcon(Icons.remove), findsWidgets);
    expect(find.byIcon(Icons.edit), findsWidgets);
  });

  // DG-200 Phase 5 — AC-10: negative stock display
  testWidgets('displays negative stock with minus sign and Âm N label', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final stockService = _FakeStockService([
      StockOverviewItem(
        productId: 10,
        productName: 'Bánh âm',
        category: 'banh_kem',
        quantity: -5,
        basePrice: 100000,
        perChip: [
          StockOverviewOption(
            normalizedPrice: 100000,
            quantity: -5,
            chipLabels: ['Giá gốc'],
            chipLabel: 'Giá gốc',
          ),
        ],
      ),
    ]);
    final categoryService = _FakeCategoryService(const [
      Category(
        id: 2,
        slug: 'banh_kem',
        name: 'Bánh kem',
        codePrefix: 'BK',
        active: 1,
        position: 2,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          stockServiceProvider.overrideWithValue(stockService),
          categoryServiceProvider.overrideWithValue(categoryService),
        ],
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bánh kem'));
    await tester.pumpAndSettle();

    // Quantity text shows the negative number (minus sign).
    expect(find.text('-5'), findsOneWidget);
    // Negative-aware VN label "Âm 5".
    expect(find.text(VN.negativeStockLabel(-5)), findsOneWidget);
    // Per-chip line reflects the negative net position.
    expect(find.textContaining('Giá gốc (100000): -5'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // DG-266 Phase 4 — chip tap behavior tests
  // ---------------------------------------------------------------------------

  group('DG-266 price chip tap', () {
    /// Shared helper: builds the StockScreen with a single product that has
    /// two per-chip price options, expands its category section so the card
    /// is visible, and returns the recording stock service for assertions.
    Future<_RecordingStockService> pumpMultiChipScreen(
      WidgetTester tester, {
      required String categorySlug,
      required String categoryName,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final stockService = _RecordingStockService([
        StockOverviewItem(
          productId: 7,
          productName: 'Bánh mì lạp',
          category: categorySlug,
          quantity: 4,
          basePrice: 20000,
          perChip: [
            StockOverviewOption(
              normalizedPrice: 20000,
              quantity: 2,
              chipLabels: ['Bình thường'],
              chipLabel: 'Bình thường',
            ),
            StockOverviewOption(
              normalizedPrice: 35000,
              quantity: 2,
              chipLabels: ['Khuyến mãi'],
              chipLabel: 'Khuyến mãi',
            ),
          ],
        ),
      ]);
      final categoryService = _FakeCategoryService([
        Category(
          id: 1,
          slug: categorySlug,
          name: categoryName,
          codePrefix: 'BK',
          active: 1,
          position: 1,
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            stockServiceProvider.overrideWithValue(stockService),
            categoryServiceProvider.overrideWithValue(categoryService),
          ],
          child: MaterialApp.router(routerConfig: buildRouter()),
        ),
      );
      await tester.pumpAndSettle();

      // Expand the collapsed category section so the card renders.
      await tester.tap(find.text(categoryName));
      await tester.pumpAndSettle();

      return stockService;
    }

    testWidgets('AC1: tapping a price chip opens restock sheet with that '
        'price pre-selected and quantity field auto-focused', (tester) async {
      final stockService = await pumpMultiChipScreen(
        tester,
        categorySlug: 'banh_kem',
        categoryName: 'Bánh kem',
      );

      // The 35.000đ chip ("Khuyến mãi") has an add_circle_outline affordance
      // icon. Verify a trailing + icon is rendered for each chip (AC4).
      expect(
        find.byIcon(Icons.add_circle_outline),
        findsNWidgets(2),
      );

      // Tap the chip text to open the restock action sheet. The chip text
      // format is "$displayLabel ($normalizedPrice): $quantity".
      await tester.tap(find.textContaining('Khuyến mãi (35000): 2'));
      await tester.pumpAndSettle();

      // Restock sheet (StockActionSheet) is now presented.
      expect(find.byType(StockActionSheet), findsOneWidget);
      // Price dropdown present (perChip is non-empty).
      expect(find.text(VN.tuyChonGia), findsOneWidget);

      // The tapped price (35000) should be the selected dropdown value. The
      // DropdownMenuItem child text is "$displayLabel - $priceText ($qty)".
      // For 35000 the formatted price text is "35,000đ". Verify the
      // pre-selected dropdown item is visible.
      expect(find.textContaining('Khuyến mãi - 35,000đ (2)'), findsOneWidget);

      // Quantity field is auto-focused: the TextFormField with VN.soLuong
      // label is rendered and has autofocus: true. Verify the field exists.
      expect(find.text(VN.soLuong), findsOneWidget);

      // No restock call yet — sheet is open but not submitted.
      expect(stockService.restockCalls, isEmpty);
    });

    testWidgets('AC2: submitting the chip-tap-opened restock sheet restocks at '
        'the pre-selected price and refreshes the overview', (tester) async {
      final stockService = await pumpMultiChipScreen(
        tester,
        categorySlug: 'banh_kem',
        categoryName: 'Bánh kem',
      );
      final initialOverviewCalls = stockService.overviewCallCount;

      // Tap the 20000-chip ("Bình thường").
      await tester.tap(find.textContaining('Bình thường (20000): 2'));
      await tester.pumpAndSettle();

      // Enter a quantity into the focused quantity field.
      await tester.enterText(find.byType(TextFormField).first, '3');
      await tester.pumpAndSettle();

      // Submit via the FilledButton inside the action sheet (it shows
      // VN.xacNhanNhapHang == "Nhập hàng", which is ambiguous on the screen
      // because the restock button uses the same label — so target the
      // button inside the sheet).
      final submitButton = find.descendant(
        of: find.byType(StockActionSheet),
        matching: find.byType(FilledButton),
      );
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Verify restock API was called with the tapped price pre-selected.
      expect(stockService.restockCalls, hasLength(1));
      expect(stockService.restockCalls.single['productId'], 7);
      expect(stockService.restockCalls.single['quantity'], 3);
      expect(stockService.restockCalls.single['normalizedPrice'], 20000);

      // Verify the overview was refreshed (onDone callback fired).
      expect(
        stockService.overviewCallCount,
        greaterThan(initialOverviewCalls),
      );
    });

    testWidgets('AC3: no-chip product retains button-only restock flow '
        'unchanged', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final stockService = _RecordingStockService([
        StockOverviewItem(
          productId: 9,
          productName: 'Bánh phu kien',
          category: 'phu_kien',
          quantity: 6,
          basePrice: 5000,
          perChip: const [],
        ),
      ]);
      final categoryService = _FakeCategoryService(const [
        Category(
          id: 1,
          slug: 'phu_kien',
          name: 'Phụ kiện',
          codePrefix: 'PK',
          active: 1,
          position: 1,
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            stockServiceProvider.overrideWithValue(stockService),
            categoryServiceProvider.overrideWithValue(categoryService),
          ],
          child: MaterialApp.router(routerConfig: buildRouter()),
        ),
      );
      await tester.pumpAndSettle();

      // Expand the category section.
      await tester.tap(find.text('Phụ kiện'));
      await tester.pumpAndSettle();

      // No per-chip tags -> no chip affordance icons rendered.
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);

      // Find the restock button on the card. The card's restock button is a
      // FilledButton.tonalIcon with an Icons.add leading icon; it shares its
      // label "Nhập hàng" with the sheet's submit button, so disambiguate by
      // targeting the tonal Icon-laden button on the card (not inside the
      // sheet). Before the sheet opens, the only FilledButton.tonalIcon with
      // Icons.add on screen is the card's restock button.
      final restockButton = find.ancestor(
        of: find.byIcon(Icons.add),
        matching: find.byType(FilledButton),
      );
      await tester.tap(restockButton);
      await tester.pumpAndSettle();

      // Restock sheet opened via button — no pre-selected price.
      expect(find.byType(StockActionSheet), findsOneWidget);

      // Quantity field still auto-focuses. Enter a value into the first
      // TextFormField within the sheet.
      await tester.enterText(
        find.descendant(
          of: find.byType(StockActionSheet),
          matching: find.byType(TextFormField),
        ).first,
        '2',
      );
      await tester.pumpAndSettle();

      // Submit via the FilledButton inside the sheet.
      await tester.tap(
        find.descendant(
          of: find.byType(StockActionSheet),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();

      expect(stockService.restockCalls, hasLength(1));
      expect(stockService.restockCalls.single['productId'], 9);
      expect(stockService.restockCalls.single['quantity'], 2);
      expect(stockService.restockCalls.single['normalizedPrice'], isNull);
    });

    testWidgets('AC4: each price chip shows InkWell ripple + trailing + icon',
        (tester) async {
      await pumpMultiChipScreen(
        tester,
        categorySlug: 'banh_kem',
        categoryName: 'Bánh kem',
      );

      // Two chips -> two trailing + icons (AC4).
      expect(find.byIcon(Icons.add_circle_outline), findsNWidgets(2));

      // Each tappable chip is wrapped in an InkWell (ripple visual feedback).
      // Verify the card contains at least two InkWell widgets corresponding to
      // the two chips. (Other InkWells may exist in the widget tree; the chip
      // InkWells are distinguishable by being ancestors of the chip text.)
      final chip1InkWell = tester.widgetList<InkWell>(
        find.ancestor(
          of: find.textContaining('Bình thường (20000): 2'),
          matching: find.byType(InkWell),
        ),
      );
      final chip2InkWell = tester.widgetList<InkWell>(
        find.ancestor(
          of: find.textContaining('Khuyến mãi (35000): 2'),
          matching: find.byType(InkWell),
        ),
      );
      expect(chip1InkWell, isNotEmpty);
      expect(chip2InkWell, isNotEmpty);
    });

    testWidgets('AC5: dismissing the chip-tap-opened restock sheet without '
        'submitting does not change stock', (tester) async {
      final stockService = await pumpMultiChipScreen(
        tester,
        categorySlug: 'banh_kem',
        categoryName: 'Bánh kem',
      );
      final initialOverviewCalls = stockService.overviewCallCount;

      // Open the sheet via chip tap.
      await tester.tap(find.textContaining('Bình thường (20000): 2'));
      await tester.pumpAndSettle();
      expect(find.byType(StockActionSheet), findsOneWidget);

      // Dismiss via the Cancel TextButton inside the sheet (no submit).
      await tester.tap(
        find.descendant(
          of: find.byType(StockActionSheet),
          matching: find.byType(TextButton),
        ),
      );
      await tester.pumpAndSettle();

      // No restock call was made.
      expect(stockService.restockCalls, isEmpty);
      // Overview was not refreshed (onDone not fired).
      expect(stockService.overviewCallCount, initialOverviewCalls);
      // Sheet is gone.
      expect(find.byType(StockActionSheet), findsNothing);
    });
  });
}
