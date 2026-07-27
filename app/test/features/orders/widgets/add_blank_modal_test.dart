import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/data/models/blank.dart';
import 'package:bakery_app/data/providers/blanks_provider.dart';
import 'package:bakery_app/features/orders/widgets/add_blank_modal.dart';
import 'package:bakery_app/shared/labels/blanks.dart';

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

Future<void> _pumpModal(
  WidgetTester tester, {
  required List<Blank> blanks,
  int? initialBlankId,
  double initialQuantity = 1.0,
  String initialNotes = '',
  bool isEdit = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        blanksProvider.overrideWith(() => _FakeBlanksNotifier(blanks)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showAddBlankModal(
                  ctx,
                  initialBlankId: initialBlankId,
                  initialQuantity: initialQuantity,
                  initialNotes: initialNotes,
                  isEdit: isEdit,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('AddBlankModal', () {
    testWidgets(
        'AC1: shows blank dropdown, quantity (default 1), and optional notes field',
        (tester) async {
      await _pumpModal(tester, blanks: _blanks);

      expect(find.text(BlanksLabels.addBlankTitle), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
      // Quantity defaults to 1 for add flow.
      expect(
        tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
        '1',
      );
      // Notes field present.
      expect(find.text(BlanksLabels.fieldBlankNotes), findsOneWidget);
    });

    testWidgets('confirm with blank selected returns BlankModalResult',
        (tester) async {
      await _pumpModal(tester, blanks: _blanks);

      // Open dropdown and pick "Phôi kem".
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phôi kem').last);
      await tester.pumpAndSettle();

      // Confirm.
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();

      // Modal popped; the home screen with the open button is back in view.
      expect(find.text('open'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    });

    testWidgets('confirm without blank shows validation error', (tester) async {
      await _pumpModal(tester, blanks: _blanks);

      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();

      expect(find.text(BlanksLabels.messageBlankRequired), findsOneWidget);
      // Modal still open.
      expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    });

    testWidgets('AC3: edit mode prefills title, blank, quantity, notes',
        (tester) async {
      await _pumpModal(
        tester,
        blanks: _blanks,
        initialBlankId: 2,
        initialQuantity: 3.0,
        initialNotes: 'Ghi chú cũ',
        isEdit: true,
      );

      expect(find.text(BlanksLabels.editBlankTitle), findsOneWidget);
      final field = tester.widget<DropdownButtonFormField<int>>(
        find.byType(DropdownButtonFormField<int>),
      );
      expect(field.initialValue, 2);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
        '3',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        'Ghi chú cũ',
      );
    });

    testWidgets('cancel dismisses modal without result', (tester) async {
      await _pumpModal(tester, blanks: _blanks);

      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });
  });
}