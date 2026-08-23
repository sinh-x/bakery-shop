import 'package:bakery_app/data/api/blank_service.dart';
import 'package:bakery_app/data/models/blank.dart';
import 'package:bakery_app/features/blanks/bom_mapping_screen.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bakery_app/shared/labels/shared.dart';

class _FakeBlankService extends BlankService {
  _FakeBlankService({
    List<Blank> blanks = const [],
    List<ProductBlankBom> bom = const [],
    this.throwOnListBom = false,
  }) : _blanks = List<Blank>.from(blanks),
       _bom = List<ProductBlankBom>.from(bom),
       super(Dio());

  final List<Blank> _blanks;
  final List<ProductBlankBom> _bom;
  final bool throwOnListBom;

  int createCallCount = 0;
  int updateCallCount = 0;
  int deleteCallCount = 0;

  @override
  Future<List<Blank>> listBlanks({String? category}) async {
    return List<Blank>.from(_blanks);
  }

  @override
  Future<List<ProductBlankBom>> listBom(int chipId) async {
    if (throwOnListBom) throw Exception('network error');
    return List<ProductBlankBom>.from(_bom);
  }

  @override
  Future<ProductBlankBom> createBom(
    int chipId,
    int blankId,
    double quantity,
  ) async {
    createCallCount++;
    final created = ProductBlankBom(
      id: 900 + createCallCount,
      priceChipId: chipId,
      blankId: blankId,
      quantity: quantity,
    );
    _bom.add(created);
    return created;
  }

  @override
  Future<ProductBlankBom> updateBom(
    int chipId,
    int bomId,
    double quantity,
  ) async {
    updateCallCount++;
    final i = _bom.indexWhere((b) => b.id == bomId);
    final cur = _bom[i];
    final updated = cur.copyWith(quantity: quantity);
    _bom[i] = updated;
    return updated;
  }

  @override
  Future<void> deleteBom(int chipId, int bomId) async {
    deleteCallCount++;
    _bom.removeWhere((b) => b.id == bomId);
  }
}

const _blanks = [
  Blank(id: 1, name: 'Phôi kem', category: 'kem', unit: 'kg'),
  Blank(id: 2, name: 'Phôi cốt', category: 'cot', unit: 'cái'),
];

const _boms = [
  ProductBlankBom(id: 10, priceChipId: 5, blankId: 1, quantity: 2.0),
  ProductBlankBom(id: 11, priceChipId: 5, blankId: 2, quantity: 1.5),
];

Future<void> _pump(WidgetTester tester, BlankService service) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [blankServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(home: BomMappingScreen(priceChipId: 5)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows loading indicator before data', (tester) async {
    final service = _FakeBlankService(blanks: _blanks, bom: _boms);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [blankServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: BomMappingScreen(priceChipId: 5)),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('shows error state when BOM load fails', (tester) async {
    await _pump(
      tester,
      _FakeBlankService(blanks: _blanks, bom: _boms, throwOnListBom: true),
    );
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.text(SharedLabels.apiError), findsOneWidget);
  });

  testWidgets('shows empty state when no BOM mappings exist', (tester) async {
    await _pump(tester, _FakeBlankService(blanks: _blanks, bom: const []));
    expect(find.text(BlanksLabels.emptyBom), findsOneWidget);
  });

  testWidgets('displays BOM mappings with blank name and quantity', (
    tester,
  ) async {
    await _pump(tester, _FakeBlankService(blanks: _blanks, bom: _boms));
    expect(find.text('Phôi kem'), findsOneWidget);
    expect(find.text('2 kg'), findsOneWidget);
    expect(find.text('Phôi cốt'), findsOneWidget);
    expect(find.text('1.5 cái'), findsOneWidget);
  });

  testWidgets('FAB opens the add BOM sheet', (tester) async {
    await _pump(tester, _FakeBlankService(blanks: _blanks, bom: _boms));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text(BlanksLabels.actionAddBom), findsWidgets);
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
  });

  testWidgets('null BOM selection does not submit a create request', (
    tester,
  ) async {
    final service = _FakeBlankService(blanks: _blanks, bom: const []);
    await _pump(tester, service);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pump();

    expect(service.createCallCount, 0);
    expect(find.text(BlanksLabels.messageBomSelectBlank), findsOneWidget);
  });

  testWidgets('delete confirmation dialog appears and cancels', (tester) async {
    final service = _FakeBlankService(blanks: _blanks, bom: _boms);
    await _pump(tester, service);
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    expect(find.text(BlanksLabels.messageDeleteConfirm), findsOneWidget);
    await tester.tap(find.text(BlanksLabels.actionCancel));
    await tester.pumpAndSettle();
    expect(service.deleteCallCount, 0);
  });

  testWidgets('delete confirmation dialog confirms and calls delete', (
    tester,
  ) async {
    final service = _FakeBlankService(blanks: _blanks, bom: _boms);
    await _pump(tester, service);
    await tester.tap(find.byIcon(Icons.delete_outline).first);
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

  testWidgets('edit quantity updates the BOM mapping', (tester) async {
    final service = _FakeBlankService(blanks: _blanks, bom: _boms);
    await _pump(tester, service);
    await tester.tap(find.byIcon(Icons.edit).first);
    await tester.pumpAndSettle();
    final qtyField = find.byType(TextField);
    await tester.enterText(qtyField, '3');
    await tester.tap(find.byIcon(Icons.check).first);
    await tester.pumpAndSettle();
    expect(service.updateCallCount, 1);
  });
}
