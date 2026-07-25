import 'package:bakery_app/data/api/blank_service.dart';
import 'package:bakery_app/data/models/blank.dart';
import 'package:bakery_app/features/blanks/blank_stock_screen.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBlankService extends BlankService {
  _FakeBlankService({
    List<BlankStockSummary> stock = const [],
    this.throwOnGetStock = false,
  })  : _stock = List<BlankStockSummary>.from(stock),
        super(Dio());

  final List<BlankStockSummary> _stock;
  final bool throwOnGetStock;

  int productionCallCount = 0;
  int usageCallCount = 0;
  double? lastProductionQty;
  double? lastUsageQty;

  @override
  Future<List<BlankStockSummary>> getStock() async {
    if (throwOnGetStock) throw Exception('network error');
    return List<BlankStockSummary>.from(_stock);
  }

  @override
  Future<BlankStockEntry> recordStock(
    int blankId,
    double quantity,
    String type, {
    String producedDate = '',
    String? expiryDate,
  }) async {
    if (type == 'production') {
      productionCallCount++;
      lastProductionQty = quantity;
      final i = _stock.indexWhere((s) => s.blankId == blankId);
      if (i >= 0) {
        _stock[i] = _stock[i].copyWith(stock: _stock[i].stock + quantity);
      }
    } else {
      usageCallCount++;
      lastUsageQty = quantity;
      final i = _stock.indexWhere((s) => s.blankId == blankId);
      if (i >= 0) {
        _stock[i] = _stock[i].copyWith(stock: _stock[i].stock - quantity);
      }
    }
    return BlankStockEntry(id: 1, blankId: blankId, quantity: quantity, type: type);
  }
}

const _stock = [
  BlankStockSummary(blankId: 1, name: 'Phôi kem', category: 'kem', unit: 'kg', stock: 12.0),
  BlankStockSummary(blankId: 2, name: 'Phôi cốt', category: 'cot', unit: 'cái', stock: 0.0),
];

Future<void> _pump(
  WidgetTester tester,
  BlankService service,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [blankServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(home: BlankStockScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows loading indicator before data', (tester) async {
    final service = _FakeBlankService(stock: _stock);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [blankServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: BlankStockScreen()),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('shows error state with retry when stock load fails',
      (tester) async {
    await _pump(tester, _FakeBlankService(stock: _stock, throwOnGetStock: true));
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.text(VN.apiError), findsOneWidget);
  });

  testWidgets('shows empty state when no blanks have stock', (tester) async {
    await _pump(tester, _FakeBlankService(stock: const []));
    expect(find.text(BlanksLabels.emptyBlanks), findsOneWidget);
  });

  testWidgets('displays stock rows grouped by category with names and stock',
      (tester) async {
    await _pump(tester, _FakeBlankService(stock: _stock));
    expect(find.text('Phôi kem'), findsOneWidget);
    expect(find.text('Phôi cốt'), findsOneWidget);
    // Category headers (sorted: cot, kem).
    expect(find.text('cot'), findsOneWidget);
    expect(find.text('kem'), findsOneWidget);
  });

  testWidgets('production button opens the stock action sheet', (tester) async {
    await _pump(tester, _FakeBlankService(stock: _stock));
    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.pumpAndSettle();
    expect(find.text(BlanksLabels.actionStockIn), findsOneWidget);
    expect(find.byType(TextFormField), findsWidgets);
  });

  testWidgets('usage button opens the stock action sheet', (tester) async {
    await _pump(tester, _FakeBlankService(stock: _stock));
    await tester.tap(find.byIcon(Icons.remove_circle).first);
    await tester.pumpAndSettle();
    expect(find.text(BlanksLabels.actionStockOut), findsOneWidget);
  });

  testWidgets('production sheet submits and records production', (tester) async {
    final service = _FakeBlankService(stock: _stock);
    await _pump(tester, service);
    await tester.tap(find.byIcon(Icons.add_circle).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '5');
    await tester.tap(find.widgetWithText(FilledButton, BlanksLabels.actionSave));
    await tester.pumpAndSettle();
    expect(service.productionCallCount, 1);
    expect(service.lastProductionQty, 5.0);
  });

  testWidgets('usage sheet submits and records usage', (tester) async {
    final service = _FakeBlankService(stock: _stock);
    await _pump(tester, service);
    await tester.tap(find.byIcon(Icons.remove_circle).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '3');
    await tester.tap(find.widgetWithText(FilledButton, BlanksLabels.actionSave));
    await tester.pumpAndSettle();
    expect(service.usageCallCount, 1);
    expect(service.lastUsageQty, 3.0);
  });

  testWidgets('refresh button reloads the stock overview', (tester) async {
    final service = _FakeBlankService(stock: _stock);
    await _pump(tester, service);
    final refreshBtn = find.byTooltip(BlanksLabels.actionSave).first;
    await tester.tap(refreshBtn);
    await tester.pumpAndSettle();
    expect(find.text('Phôi kem'), findsOneWidget);
  });
}