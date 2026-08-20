import 'package:bakery_app/data/api/template_service.dart';
import 'package:bakery_app/data/models/message_template.dart';
import 'package:bakery_app/features/templates/widgets/template_editor_screen.dart';
import 'package:bakery_app/shared/labels/templates.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTemplateService extends TemplateService {
  _FakeTemplateService(this._store) : super(Dio());

  final List<MessageTemplate> _store;
  int _nextId = 100;

  @override
  Future<List<MessageTemplate>> listTemplates({String? scenario}) async =>
      List<MessageTemplate>.from(_store);

  @override
  Future<MessageTemplate> createTemplate({
    required String scenario,
    required String name,
    required String body,
    bool isSystem = false,
    int sortOrder = 0,
    bool active = true,
  }) async {
    final created = MessageTemplate(
      id: _nextId++,
      scenario: scenario,
      name: name,
      body: body,
      isSystem: isSystem,
      sortOrder: sortOrder,
      active: active,
    );
    _store.add(created);
    return created;
  }

  @override
  Future<MessageTemplate> updateTemplate(
    int id, {
    String? scenario,
    String? name,
    String? body,
    bool? isSystem,
    int? sortOrder,
    bool? active,
  }) async {
    final idx = _store.indexWhere((t) => t.id == id);
    final current = _store[idx];
    final updated = MessageTemplate(
      id: id,
      scenario: scenario ?? current.scenario,
      name: name ?? current.name,
      body: body ?? current.body,
      isSystem: isSystem ?? current.isSystem,
      createdByStaffId: current.createdByStaffId,
      sortOrder: sortOrder ?? current.sortOrder,
      active: active ?? current.active,
      createdAt: current.createdAt,
    );
    _store[idx] = updated;
    return updated;
  }
}

Future<ProviderContainer> _pumpEditor(
  WidgetTester tester, {
  MessageTemplate? template,
  bool isAdmin = false,
  bool initialIsSystem = false,
}) async {
  final store = <MessageTemplate>[];
  if (template != null) store.add(template);
  final fake = _FakeTemplateService(store);
  final container = ProviderContainer(
    overrides: [templateServiceProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: TemplateEditorScreen(
          template: template,
          initialIsSystem: initialIsSystem,
          isAdmin: isAdmin,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('TemplateEditorScreen (DG-375 Phase 4 / FR8 / AC8)', () {
    testWidgets('create mode shows create title and empty fields',
        (tester) async {
      await _pumpEditor(tester, isAdmin: false);
      expect(find.text(TemplatesLabels.editorCreateTitle), findsOneWidget);
      expect(find.text(TemplatesLabels.editorNameLabel), findsOneWidget);
      expect(find.text(TemplatesLabels.editorBodyLabel), findsOneWidget);
      expect(find.text(TemplatesLabels.editorScenarioLabel), findsOneWidget);
    });

    testWidgets('edit mode shows edit title and pre-filled fields',
        (tester) async {
      const template = MessageTemplate(
        id: 5,
        scenario: 'ask_info',
        name: 'Mẫu cũ',
        body: 'Dạ mình đặt bánh?',
        isSystem: false,
        createdByStaffId: 7,
        sortOrder: 1,
        active: true,
      );
      await _pumpEditor(tester, template: template, isAdmin: false);
      expect(find.text(TemplatesLabels.editorEditTitle), findsOneWidget);
      expect(find.text('Mẫu cũ'), findsOneWidget);
      expect(find.text('Dạ mình đặt bánh?'), findsOneWidget);
    });

    testWidgets('insert order field helper opens and inserts placeholder at '
        'cursor (FR8 / AC8)', (tester) async {
      await _pumpEditor(tester, isAdmin: false);
      // Tap the "insert field" button to open the helper sheet.
      await tester.tap(find.text(TemplatesLabels.editorInsertFieldButton));
      await tester.pumpAndSettle();
      expect(find.text(TemplatesLabels.editorInsertFieldTitle), findsOneWidget);
      // The placeholder list shows the available placeholders.
      expect(find.text('{customer_name}'), findsOneWidget);
      expect(find.text('{order_code}'), findsOneWidget);
      // Tap a placeholder to insert it.
      await tester.tap(find.text('{customer_name}'));
      await tester.pumpAndSettle();
      // The body field now contains the inserted placeholder. Find the
      // multi-line TextField (the body field is the only one with maxLines != 1).
      final multilineFields = tester.widgetList<TextField>(find.byType(TextField));
      final bodyCtrl = multilineFields
          .firstWhere((f) => f.maxLines != 1)
          .controller!;
      expect(bodyCtrl.text, contains('{customer_name}'));
    });

    testWidgets('admin sees the system-template toggle (FR6)', (tester) async {
      await _pumpEditor(tester, isAdmin: true);
      expect(find.text(TemplatesLabels.editorIsSystemLabel), findsOneWidget);
    });

    testWidgets('non-admin does NOT see the system-template toggle (FR7)',
        (tester) async {
      await _pumpEditor(tester, isAdmin: false);
      expect(find.text(TemplatesLabels.editorIsSystemLabel), findsNothing);
    });

    testWidgets('save with empty name shows validation error', (tester) async {
      await _pumpEditor(tester, isAdmin: false);
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await tester.pumpAndSettle();
      expect(find.text(TemplatesLabels.editorNameRequired), findsOneWidget);
    });

    testWidgets('save with empty body shows validation error', (tester) async {
      await _pumpEditor(tester, isAdmin: false);
      // Enter a name but leave body empty.
      await tester.enterText(
        find.widgetWithText(TextFormField, '').first,
        'Mẫu mới',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await tester.pumpAndSettle();
      expect(find.text(TemplatesLabels.editorBodyRequired), findsOneWidget);
    });

    testWidgets('valid create persists template and pops the screen',
        (tester) async {
      await _pumpEditor(tester, isAdmin: false);
      // Name field is the first TextFormField.
      await tester.enterText(find.byType(TextFormField).at(0), 'Mẫu chào');
      // Body field is the multi-line one.
      final bodyField = tester.widgetList<TextField>(find.byType(TextField))
          .firstWhere((f) => f.maxLines != 1);
      await tester.enterText(find.byWidget(bodyField), 'Xin chào {customer_name}');
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await tester.pumpAndSettle();
      // Pops back — the editor screen is no longer present.
      expect(find.byType(TemplateEditorScreen), findsNothing);
    });
  });
}