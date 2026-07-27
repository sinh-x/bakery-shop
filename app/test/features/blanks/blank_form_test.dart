import 'package:bakery_app/data/api/blank_service.dart';
import 'package:bakery_app/data/models/blank.dart';
import 'package:bakery_app/features/blanks/widgets/blank_form.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBlankService extends BlankService {
  _FakeBlankService([List<Blank> initial = const []])
      : _blanks = List<Blank>.from(initial),
        super(Dio());

  final List<Blank> _blanks;
  int createCalls = 0;
  int updateCalls = 0;
  String? lastCreateName;
  String? lastUpdateName;

  @override
  Future<List<Blank>> listBlanks({String? category}) async =>
      List<Blank>.from(_blanks);

  @override
  Future<Blank> createBlank({
    required String name,
    String category = '',
    String unit = '',
    String notes = '',
  }) async {
    createCalls++;
    lastCreateName = name;
    final created = Blank(
      id: _blanks.length + 1,
      name: name,
      category: category,
      unit: unit,
      notes: notes,
    );
    _blanks.add(created);
    return created;
  }

  @override
  Future<Blank> updateBlank(
    int id, {
    String? name,
    String? category,
    String? unit,
    String? notes,
  }) async {
    updateCalls++;
    lastUpdateName = name;
    final i = _blanks.indexWhere((b) => b.id == id);
    final cur = _blanks[i];
    final updated = Blank(
      id: cur.id,
      name: name ?? cur.name,
      category: category ?? cur.category,
      unit: unit ?? cur.unit,
      notes: notes ?? cur.notes,
    );
    _blanks[i] = updated;
    return updated;
  }
}

Future<void> _pumpForm(
  WidgetTester tester,
  BlankService service, {
  Blank? blank,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [blankServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        home: Scaffold(
          body: ElevatedButton(
            onPressed: () => showBlankForm(
              tester.element(find.byType(ElevatedButton)),
              blank: blank,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('create form: empty name shows validation error', (tester) async {
    final service = _FakeBlankService();
    await _pumpForm(tester, service);

    await tester.tap(find.text(BlanksLabels.actionSave));
    await tester.pumpAndSettle();
    // Validator returns the field-name label as the error text.
    expect(find.text(BlanksLabels.fieldName), findsWidgets);
    expect(service.createCalls, 0);
  });

  testWidgets('create form: valid input creates a blank', (tester) async {
    final service = _FakeBlankService();
    await _pumpForm(tester, service);

    await tester.enterText(
      find.widgetWithText(TextFormField, BlanksLabels.fieldName),
      'Phôi dâu',
    );
    // Category is now a server-managed dropdown. With no categoriesProvider
    // override in this test, the form falls back to the hardcoded
    // categoryMap fallback; open the dropdown and pick the first item.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${VN.emojiBanhMi} ${VN.catBanhMi}').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, BlanksLabels.fieldUnit),
      'kg',
    );
    await tester.tap(find.text(BlanksLabels.actionSave));
    await tester.pumpAndSettle();

    expect(service.createCalls, 1);
    expect(service.lastCreateName, 'Phôi dâu');
  });

  testWidgets('edit form: prefills existing blank fields', (tester) async {
    final service = _FakeBlankService();
    await _pumpForm(
      tester,
      service,
      blank: const Blank(
        id: 5,
        name: 'Phôi sẵn',
        category: 'cot',
        unit: 'cai',
        notes: 'note',
      ),
    );
    expect(find.text('Phôi sẵn'), findsOneWidget);
    // 'cot' is not a server Category slug, so the dropdown shows the hint
    // instead of the stored value; the original value is preserved on save.
    expect(find.text(BlanksLabels.fieldCategoryHint), findsWidgets);
    expect(find.text('cai'), findsOneWidget);
  });

  testWidgets('edit form: submit calls updateBlank', (tester) async {
    final service = _FakeBlankService();
    await _pumpForm(
      tester,
      service,
      blank: const Blank(id: 5, name: 'Phôi sẵn', category: 'cot', unit: 'cai'),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, BlanksLabels.fieldName),
      'Phôi mới',
    );
    await tester.tap(find.text(BlanksLabels.actionSave));
    await tester.pumpAndSettle();

    expect(service.updateCalls, 1);
    expect(service.lastUpdateName, 'Phôi mới');
  });

  testWidgets('cancel button dismisses without saving', (tester) async {
    final service = _FakeBlankService();
    await _pumpForm(tester, service);

    await tester.tap(find.text(BlanksLabels.actionCancel));
    await tester.pumpAndSettle();
    expect(service.createCalls, 0);
    // Bottom sheet closed: form title no longer on screen.
    expect(find.text(BlanksLabels.screenCreate), findsNothing);
  });
}