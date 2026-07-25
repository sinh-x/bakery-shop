import 'package:bakery_app/data/api/blank_service.dart';
import 'package:bakery_app/data/models/blank.dart';
import 'package:bakery_app/data/models/work_item.dart';
import 'package:bakery_app/features/blanks/blank_detail_screen.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeBlankService extends BlankService {
  _FakeBlankService(
    this._blanks, {
    this.throwOnList = false,
    this.stock = const [],
    this.demand = const [],
    this.blankProducts,
  }) : super(Dio());

  List<Blank> _blanks;
  final bool throwOnList;
  final List<BlankStockSummary> stock;
  final List<BlankDemand> demand;
  final BlankProducts? blankProducts;
  int deleteCallCount = 0;

  @override
  Future<List<Blank>> listBlanks({String? category}) async {
    if (throwOnList) throw Exception('network error');
    return List<Blank>.from(_blanks);
  }

  @override
  Future<void> deleteBlank(int id) async {
    deleteCallCount++;
    _blanks = _blanks.where((b) => b.id != id).toList();
  }

  @override
  Future<Blank> updateBlank(
    int id, {
    String? name,
    String? category,
    String? unit,
    String? notes,
  }) async {
    final i = _blanks.indexWhere((b) => b.id == id);
    final cur = _blanks[i];
    final updated = Blank(
      id: cur.id,
      name: name ?? cur.name,
      category: category ?? cur.category,
      unit: unit ?? cur.unit,
      notes: notes ?? cur.notes,
      createdAt: cur.createdAt,
      updatedAt: cur.updatedAt,
    );
    _blanks[i] = updated;
    return updated;
  }

  @override
  Future<List<BlankStockSummary>> getStock() async => stock;

  @override
  Future<List<BlankDemand>> getDemand() async => demand;

  @override
  Future<BlankProducts> getBlankProducts(int id) async {
    return blankProducts ?? BlankProducts(blankId: id, bomProducts: const [], workItems: const []);
  }
}

GoRouter _router() => GoRouter(
      routes: [
        GoRoute(
          path: '/blanks/:id',
          builder: (_, state) =>
              BlankDetailScreen(blankId: int.parse(state.pathParameters['id']!)),
        ),
        GoRoute(
          path: '/orders/:id',
          builder: (_, _) => const Scaffold(body: Center(child: Text('order-detail'))),
        ),
        GoRoute(
          path: '/products/:id/edit',
          builder: (_, _) => const Scaffold(body: Center(child: Text('product-edit'))),
        ),
      ],
      initialLocation: '/blanks/1',
    );

Future<void> _pump(
  WidgetTester tester,
  BlankService service,
  String initialLocation,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [blankServiceProvider.overrideWithValue(service)],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle();
}

const _blank = Blank(
  id: 1,
  name: 'Phôi kem',
  category: 'kem',
  unit: 'kg',
  notes: 'Ghi chú mẫu',
);

void main() {
  testWidgets('shows loading indicator before data', (tester) async {
    final service = _FakeBlankService(const [_blank]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [blankServiceProvider.overrideWithValue(service)],
        child: MaterialApp.router(routerConfig: _router()),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('shows error state when load fails', (tester) async {
    await _pump(
      tester,
      _FakeBlankService(const [], throwOnList: true),
      '/blanks/1',
    );
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });

  testWidgets('displays blank fields', (tester) async {
    await _pump(tester, _FakeBlankService(const [_blank]), '/blanks/1');
    expect(find.text('Phôi kem'), findsOneWidget);
    expect(find.text('kem'), findsOneWidget);
    expect(find.text('kg'), findsOneWidget);
    expect(find.text('Ghi chú mẫu'), findsOneWidget);
  });

  testWidgets('delete confirmation dialog appears and cancels', (tester) async {
    final service = _FakeBlankService(const [_blank]);
    await _pump(tester, service, '/blanks/1');

    await tester.scrollUntilVisible(
      find.text(BlanksLabels.actionDelete),
      200,
    );
    await tester.tap(find.text(BlanksLabels.actionDelete));
    await tester.pumpAndSettle();
    expect(find.text(BlanksLabels.messageDeleteConfirm), findsOneWidget);

    await tester.tap(find.text(BlanksLabels.actionCancel));
    await tester.pumpAndSettle();
    expect(service.deleteCallCount, 0);
  });

  testWidgets('delete confirmation dialog confirms and calls delete',
      (tester) async {
    final service = _FakeBlankService(const [_blank]);
    await _pump(tester, service, '/blanks/1');

    await tester.scrollUntilVisible(
      find.text(BlanksLabels.actionDelete),
      200,
    );
    await tester.tap(find.text(BlanksLabels.actionDelete));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, BlanksLabels.actionDelete),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.deleteCallCount, 1);
  });

  testWidgets('edit button opens blank form in edit mode', (tester) async {
    await _pump(tester, _FakeBlankService(const [_blank]), '/blanks/1');
    final editFinder = find.widgetWithText(FilledButton, BlanksLabels.actionEdit);
    await tester.scrollUntilVisible(editFinder, 200);
    await tester.pumpAndSettle();
    await tester.tap(editFinder, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text(BlanksLabels.actionSave), findsOneWidget);
  });

  // --- DG-293 Phase 4: stock, demand, linked products sections ---

  testWidgets('displays stock summary section with current stock', (tester) async {
    await _pump(
      tester,
      _FakeBlankService(
        const [_blank],
        stock: const [
          BlankStockSummary(blankId: 1, name: 'Phôi kem', category: 'kem', unit: 'kg', stock: 12),
        ],
      ),
      '/blanks/1',
    );
    expect(find.text(BlanksLabels.sectionStock), findsOneWidget);
    expect(find.text('12 kg'), findsOneWidget);
  });

  testWidgets('stock section shows empty state when blank has no stock row',
      (tester) async {
    await _pump(
      tester,
      _FakeBlankService(const [_blank], stock: const []),
      '/blanks/1',
    );
    expect(find.text(BlanksLabels.sectionStock), findsOneWidget);
    expect(find.text(BlanksLabels.emptyData), findsWidgets);
  });

  testWidgets('displays demand summary section with demand, stock and shortage',
      (tester) async {
    await _pump(
      tester,
      _FakeBlankService(
        const [_blank],
        demand: const [
          BlankDemand(blankId: 1, name: 'Phôi kem', category: 'kem', unit: 'kg', demand: 5, stock: 2, shortage: 3),
        ],
      ),
      '/blanks/1',
    );
    expect(find.text(BlanksLabels.sectionDemand), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    // shortage > 0 is emphasized in red.
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('demand section shows empty state when blank has no demand row',
      (tester) async {
    await _pump(
      tester,
      _FakeBlankService(const [_blank], demand: const []),
      '/blanks/1',
    );
    expect(find.text(BlanksLabels.sectionDemand), findsOneWidget);
  });

  testWidgets('linked products section shows empty state when no links exist',
      (tester) async {
    await _pump(tester, _FakeBlankService(const [_blank]), '/blanks/1');
    expect(find.text(BlanksLabels.sectionLinkedProducts), findsOneWidget);
    expect(find.text(BlanksLabels.linkedEmpty), findsOneWidget);
  });

  testWidgets('linked products section lists BOM products and work items',
      (tester) async {
    const products = BlankProducts(
      blankId: 1,
      bomProducts: [
        BlankBomProduct(bomId: 10, productId: 7, productName: 'Bánh kem A', productCategory: 'kem', quantity: 2),
      ],
      workItems: [
        WorkItem(id: '100', orderId: '5', productId: '7', productName: 'Bánh kem A', quantity: 3),
      ],
    );
    await _pump(
      tester,
      _FakeBlankService(const [_blank], blankProducts: products),
      '/blanks/1',
    );
    expect(find.text(BlanksLabels.linkedBomProducts), findsOneWidget);
    expect(find.text(BlanksLabels.linkedWorkItems), findsOneWidget);
    expect(find.text('Bánh kem A'), findsNWidgets(2));
  });

  testWidgets('tapping a work item row navigates to the order detail',
      (tester) async {
    const products = BlankProducts(
      blankId: 1,
      bomProducts: [],
      workItems: [
        WorkItem(id: '100', orderId: '5', productId: '7', productName: 'Bánh kem A', quantity: 3),
      ],
    );
    await _pump(
      tester,
      _FakeBlankService(const [_blank], blankProducts: products),
      '/blanks/1',
    );
    await tester.tap(find.text('Bánh kem A'));
    await tester.pumpAndSettle();
    expect(find.text('order-detail'), findsOneWidget);
  });
}