import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/data/models/blank.dart';
import 'package:bakery_app/data/models/work_item.dart';
import 'package:bakery_app/data/providers/blanks_provider.dart';
import 'package:bakery_app/features/orders/widgets/cake_detail_blank_section.dart';
import 'package:bakery_app/shared/labels/blanks.dart';

const _orderRef = 'TEST-ORDER-1';
const _itemId = '5';

const _blanks = [
  Blank(id: 1, name: 'Phôi cốt'),
  Blank(id: 2, name: 'Phôi kem'),
  Blank(id: 3, name: 'Phôi nhân'),
];

class _FakeBlanksNotifier extends BlanksNotifier {
  final List<Blank> _blanks;
  _FakeBlanksNotifier(this._blanks);

  @override
  Future<List<Blank>> build() async => _blanks;
}

WorkItem _item(List<BlankAssignment> blanks) => WorkItem(
      id: _itemId,
      orderId: '1',
      productName: 'Bánh sinh nhật',
      blanks: blanks,
    );

const _assignment1 = BlankAssignment(
  id: 10,
  blankId: 1,
  blankName: 'Phôi cốt',
  quantity: 2.0,
  notes: 'Đặc biệt',
);

const _assignment2 = BlankAssignment(
  id: 11,
  blankId: 2,
  blankName: 'Phôi kem',
  quantity: 1.0,
  notes: '',
);

Future<void> _pumpSection(
  WidgetTester tester, {
  required WorkItem item,
  required bool editing,
  required Future<BlankAssignment> Function(String, {required int blankId, double quantity, String notes}) onAddBlank,
  required Future<BlankAssignment> Function(String, int, {double? quantity, String? notes}) onUpdateBlank,
  required Future<void> Function(String, int) onDeleteBlank,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        blanksProvider.overrideWith(() => _FakeBlanksNotifier(_blanks)),
        blankByIdProvider.overrideWith((ref, id) async =>
            Blank(id: id, name: 'Phôi #$id')),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CakeDetailBlankSection(
              orderRef: _orderRef,
              item: item,
              editing: editing,
              onAddBlank: onAddBlank,
              onUpdateBlank: onUpdateBlank,
              onDeleteBlank: onDeleteBlank,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CakeDetailBlankSection', () {
    testWidgets('read mode: shows assigned blanks with name, qty, notes',
        (tester) async {
      final item = _item(const [_assignment1, _assignment2]);
      await _pumpSection(
        tester,
        item: item,
        editing: false,
        onAddBlank: (_, {required blankId, quantity = 1.0, notes = ''}) async =>
            _assignment1,
        onUpdateBlank: (_, __, {quantity, notes}) async => _assignment1,
        onDeleteBlank: (_, __) async {},
      );

      expect(find.text(BlanksLabels.sectionBlanks), findsOneWidget);
      // Add button is visible in read mode too (DG-294 Phase 5.6-c2 / Mn-6).
      expect(find.text(BlanksLabels.actionAddCakeBlank), findsOneWidget);
      // Line items with names.
      expect(find.text('Phôi cốt'), findsOneWidget);
      expect(find.text('Phôi kem'), findsOneWidget);
      // Quantity + notes for assignment1.
      expect(find.text('${BlanksLabels.fieldBlankQuantity}: 2'), findsOneWidget);
      expect(
        find.text('${BlanksLabels.fieldBlankNotes}: Đặc biệt'),
        findsOneWidget,
      );
      // Edit/delete icons are visible in read mode too (DG-294 Phase 5.6-c2).
      expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2));
      expect(find.byIcon(Icons.close), findsNWidgets(2));
    });

    testWidgets('read mode: shows empty hint when no blanks', (tester) async {
      await _pumpSection(
        tester,
        item: _item(const []),
        editing: false,
        onAddBlank: (_, {required blankId, quantity = 1.0, notes = ''}) async =>
            _assignment1,
        onUpdateBlank: (_, __, {quantity, notes}) async => _assignment1,
        onDeleteBlank: (_, __) async {},
      );

      expect(find.text(BlanksLabels.emptyBlanksAssigned), findsOneWidget);
    });

    testWidgets('AC2: edit mode shows "Thêm phôi bánh" button and edit/delete icons',
        (tester) async {
      final item = _item(const [_assignment1]);
      await _pumpSection(
        tester,
        item: item,
        editing: true,
        onAddBlank: (_, {required blankId, quantity = 1.0, notes = ''}) async =>
            _assignment1,
        onUpdateBlank: (_, __, {quantity, notes}) async => _assignment1,
        onDeleteBlank: (_, __) async {},
      );

      expect(find.text(BlanksLabels.actionAddCakeBlank), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('tapping "Thêm phôi bánh" opens the add blank modal',
        (tester) async {
      final item = _item(const []);
      await _pumpSection(
        tester,
        item: item,
        editing: true,
        onAddBlank: (_, {required blankId, quantity = 1.0, notes = ''}) async =>
            _assignment1,
        onUpdateBlank: (_, __, {quantity, notes}) async => _assignment1,
        onDeleteBlank: (_, __) async {},
      );

      await tester.tap(find.text(BlanksLabels.actionAddCakeBlank));
      await tester.pumpAndSettle();

      // Add blank modal opened: blank selection dropdown now visible.
      expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    });

    testWidgets('AC3: tapping edit icon opens modal prefilled with assignment',
        (tester) async {
      final item = _item(const [_assignment1]);
      await _pumpSection(
        tester,
        item: item,
        editing: true,
        onAddBlank: (_, {required blankId, quantity = 1.0, notes = ''}) async =>
            _assignment1,
        onUpdateBlank: (_, __, {quantity, notes}) async => _assignment1,
        onDeleteBlank: (_, __) async {},
      );

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(find.text(BlanksLabels.editBlankTitle), findsOneWidget);
      // Prefilled quantity.
      final qtyField = tester.widget<TextField>(
        find.byType(TextField).at(0),
      );
      expect(qtyField.controller!.text, '2');
    });

    testWidgets('AC4: tapping delete icon opens confirmation dialog',
        (tester) async {
      final item = _item(const [_assignment1]);
      var deleteCalled = false;
      await _pumpSection(
        tester,
        item: item,
        editing: true,
        onAddBlank: (_, {required blankId, quantity = 1.0, notes = ''}) async =>
            _assignment1,
        onUpdateBlank: (_, __, {quantity, notes}) async => _assignment1,
        onDeleteBlank: (_, __) async {
          deleteCalled = true;
        },
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text(BlanksLabels.messageBlankDeleteConfirm), findsOneWidget);
      expect(find.text(BlanksLabels.actionDelete), findsNWidgets(2));
      // Not deleted yet.
      expect(deleteCalled, isFalse);

      // Confirm deletion.
      await tester.tap(find.text(BlanksLabels.actionDelete).last);
      await tester.pumpAndSettle();

      expect(deleteCalled, isTrue);
    });

    testWidgets('delete dialog cancel does not call onDeleteBlank',
        (tester) async {
      final item = _item(const [_assignment1]);
      var deleteCalled = false;
      await _pumpSection(
        tester,
        item: item,
        editing: true,
        onAddBlank: (_, {required blankId, quantity = 1.0, notes = ''}) async =>
            _assignment1,
        onUpdateBlank: (_, __, {quantity, notes}) async => _assignment1,
        onDeleteBlank: (_, __) async {
          deleteCalled = true;
        },
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Cancel the dialog.
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();

      expect(deleteCalled, isFalse);
      // Line item still present.
      expect(find.text('Phôi cốt'), findsOneWidget);
    });
  });
}
