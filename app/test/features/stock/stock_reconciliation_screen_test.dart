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
  _FakeService(this._draft) : super(Dio());

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
  Finder _unitPriceFieldFinder() {
    return find.byType(TextFormField).first;
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

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const StockReconciliationScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          reconciliationServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tồn dự kiến: 5'), findsOneWidget);
    expect(find.text('Trạng thái: Ổn'), findsOneWidget);
    expect(find.text('Tồn đã đếm'), findsNothing);

    await tester.tap(find.text('Bánh kem dâu'));
    await tester.pumpAndSettle();

    expect(find.text('Tồn đã đếm'), findsOneWidget);
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
          ),
        ],
      ),
    );

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const StockReconciliationScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          reconciliationServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bánh kem dâu'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '3');
    await tester.pumpAndSettle();
    await tester.tap(find.text(VN.themDongBan));
    await tester.pumpAndSettle();

    final unitPriceField = tester.widget<TextFormField>(
      _unitPriceFieldFinder(),
    );
    expect(unitPriceField.controller?.text, '100000');

    await tester.enterText(_unitPriceFieldFinder(), '15000');
    await tester.pumpAndSettle();
    final editedUnitPriceField = tester.widget<TextFormField>(
      _unitPriceFieldFinder(),
    );
    expect(editedUnitPriceField.controller?.text, '15000');

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('${VN.dongBan} 1'), findsNothing);
  });

  testWidgets('price chip fills only tapped row price', (tester) async {
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
          ),
        ],
      ),
    );

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const StockReconciliationScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          reconciliationServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bánh kem dâu'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '3');
    await tester.pumpAndSettle();
    await tester.tap(find.text(VN.themDongBan));
    await tester.tap(find.text(VN.themDongBan));
    await tester.pumpAndSettle();

    final chip = tester.widget<ActionChip>(find.byType(ActionChip).first);
    chip.onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('12000'), findsOneWidget);
  });

  testWidgets('invalid sale row keeps inline errors and collapsed error status', (
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

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const StockReconciliationScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          reconciliationServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

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
      find.descendant(of: saleRow.first, matching: find.byType(TextField)).first,
      '1',
    );
    await tester.enterText(_unitPriceFieldFinder(), '');
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, VN.guiDoiSoat),
      ),
    );
    await tester.pumpAndSettle();

    expect(service.submitCalls, 0);
    expect(find.text('Đơn giá phải lớn hơn 0'), findsOneWidget);
    expect(find.text('Chọn phương thức'), findsOneWidget);

    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();
    expect(find.text('Trạng thái: Có lỗi'), findsOneWidget);

    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();
    expect(find.text('Đơn giá phải lớn hơn 0'), findsOneWidget);
    expect(find.text('Chọn phương thức'), findsOneWidget);
  });
}
