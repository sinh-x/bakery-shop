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
    return ReconciliationSubmitResult(
      id: 1,
      date: '2026-05-04',
      message: 'Đã lưu đối soát thành công',
    );
  }
}

void main() {
  Finder _unitPriceFieldFinder() => find.byType(TextFormField).first;

  GoRouter _buildRouter() {
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

  testWidgets('product card toggles and shows collapsed summary', (tester) async {
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
        child: MaterialApp.router(routerConfig: _buildRouter()),
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

  testWidgets('add row defaults option unit price and keeps manual edit', (tester) async {
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          reconciliationServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: _buildRouter()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bánh kem dâu'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '3');
    await tester.pumpAndSettle();
    await tester.tap(find.text(VN.themDongBan));
    await tester.pumpAndSettle();

    final unitPriceField = tester.widget<TextFormField>(_unitPriceFieldFinder());
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          reconciliationServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: _buildRouter()),
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
        child: MaterialApp.router(routerConfig: _buildRouter()),
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

    await tester.tap(find.widgetWithText(FilledButton, VN.guiDoiSoat));
    await tester.pumpAndSettle();

    expect(find.textContaining(VN.tongSoLuongBan), findsOneWidget);
    expect(find.textContaining(VN.tongSoLuongHaoHut), findsOneWidget);
    expect(find.text(VN.vanDeCanXuLyTruocKhiGui), findsOneWidget);
    expect(find.textContaining('Đơn giá phải lớn hơn 0'), findsWidgets);

    final confirmButton = tester.widget<FilledButton>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, VN.guiDoiSoat),
      ),
    );
    expect(confirmButton.onPressed, isNull);
    expect(service.submitCalls, 0);

    await tester.tap(find.byType(InkWell).first);
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
        child: MaterialApp.router(routerConfig: _buildRouter()),
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
        child: MaterialApp.router(routerConfig: _buildRouter()),
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
}
