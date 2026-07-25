import 'dart:async';

import 'package:bakery_app/data/models/blank.dart';
import 'package:bakery_app/data/providers/blanks_provider.dart';
import 'package:bakery_app/features/orders/order_edit/widgets/work_item_blank_dropdown.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBlanksNotifier extends BlanksNotifier {
  final List<Blank> _blanks;
  _FakeBlanksNotifier(this._blanks);

  @override
  Future<List<Blank>> build() async => _blanks;
}

class _LoadingBlanksNotifier extends BlanksNotifier {
  final Completer<List<Blank>> _completer = Completer<List<Blank>>();

  @override
  Future<List<Blank>> build() async => _completer.future;
}

Future<void> _pumpDropdown(
  WidgetTester tester, {
  required List<Blank> blanks,
  required int? blankId,
  required ValueChanged<int?> onChanged,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        blanksProvider.overrideWith(() => _FakeBlanksNotifier(blanks)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WorkItemBlankDropdown(
              blankId: blankId,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _blanks = [
  Blank(id: 1, name: 'Phôi cốt'),
  Blank(id: 2, name: 'Phôi kem'),
  Blank(id: 3, name: 'Phôi nhân'),
];

void main() {
  group('WorkItemBlankDropdown', () {
    testWidgets('AC2: renders dropdown with all blanks + none entry', (
      tester,
    ) async {
      await _pumpDropdown(
        tester,
        blanks: _blanks,
        blankId: null,
        onChanged: (_) {},
      );

      expect(find.byType(WorkItemBlankDropdown), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<int?>), findsOneWidget);

      // Tap to open the dropdown menu.
      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();

      // The "not assigned" entry appears both as the selected display value
      // (blankId is null) and as a menu item once the dropdown is open.
      expect(find.text(BlanksLabels.notAssigned), findsNWidgets(2));
      for (final b in _blanks) {
        expect(find.text(b.name), findsOneWidget);
      }
    });

    testWidgets('shows current blank as selected value', (tester) async {
      await _pumpDropdown(
        tester,
        blanks: _blanks,
        blankId: 2,
        onChanged: (_) {},
      );

      final field = tester.widget<DropdownButtonFormField<int?>>(
        find.byType(DropdownButtonFormField<int?>),
      );
      expect(field.initialValue, 2);
    });

    testWidgets('falls back to null when blankId not in blanks list', (
      tester,
    ) async {
      await _pumpDropdown(
        tester,
        blanks: _blanks,
        blankId: 999,
        onChanged: (_) {},
      );

      final field = tester.widget<DropdownButtonFormField<int?>>(
        find.byType(DropdownButtonFormField<int?>),
      );
      expect(field.initialValue, isNull);
    });

    testWidgets('onChanged fires with selected blank id', (tester) async {
      int? captured;
      await _pumpDropdown(
        tester,
        blanks: _blanks,
        blankId: null,
        onChanged: (v) => captured = v,
      );

      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Phôi kem').last);
      await tester.pumpAndSettle();

      expect(captured, 2);
    });

    testWidgets('onChanged fires with null when clearing', (tester) async {
      int? captured = -1; // sentinel so we can detect a null write
      await _pumpDropdown(
        tester,
        blanks: _blanks,
        blankId: 3,
        onChanged: (v) => captured = v,
      );

      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(BlanksLabels.notAssigned).last);
      await tester.pumpAndSettle();

      expect(captured, isNull);
    });

    testWidgets('renders nothing when blanks list is empty', (tester) async {
      await _pumpDropdown(
        tester,
        blanks: const [],
        blankId: null,
        onChanged: (_) {},
      );

      expect(find.byType(DropdownButtonFormField<int?>), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('shows nothing while blanks are loading', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            blanksProvider.overrideWith(_LoadingBlanksNotifier.new),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: WorkItemBlankDropdown(
                blankId: null,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<int?>), findsNothing);
    });
  });
}