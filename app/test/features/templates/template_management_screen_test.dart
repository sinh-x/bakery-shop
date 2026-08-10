import 'package:bakery_app/data/api/template_service.dart';
import 'package:bakery_app/data/models/message_template.dart';
import 'package:bakery_app/features/templates/template_management_screen.dart';
import 'package:bakery_app/features/templates/widgets/template_management_tile.dart';
import 'package:bakery_app/shared/labels/templates.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake [TemplateService] with an in-memory store so the management screen's
/// `templateListProvider` resolves synchronously without a backend.
class _FakeTemplateService extends TemplateService {
  _FakeTemplateService(this._store) : super(Dio());

  final List<MessageTemplate> _store;
  int _nextId = 100;

  @override
  Future<List<MessageTemplate>> listTemplates({String? scenario}) async {
    if (scenario != null) {
      return _store.where((t) => t.scenario == scenario).toList();
    }
    return List<MessageTemplate>.from(_store);
  }

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
  Future<void> deleteTemplate(int id) async {
    _store.removeWhere((t) => t.id == id);
  }
}

List<MessageTemplate> _seedStore() => [
      const MessageTemplate(
        id: 1,
        scenario: 'ask_info',
        name: 'Mẫu hỏi hệ thống',
        body: 'Dạ mình đặt bánh khi nào lấy ạ?',
        isSystem: true,
        sortOrder: 1,
        active: true,
      ),
      const MessageTemplate(
        id: 2,
        scenario: 'confirm_order',
        name: 'Mẫu cá nhân A',
        body: 'Xin chào {customer_name}',
        isSystem: false,
        createdByStaffId: 7,
        sortOrder: 2,
        active: true,
      ),
    ];

Future<ProviderContainer> _pumpManagement(
  WidgetTester tester, {
  required bool isAdmin,
  List<MessageTemplate>? seed,
}) async {
  final store = seed != null ? List<MessageTemplate>.from(seed) : <MessageTemplate>[];
  final fake = _FakeTemplateService(store);
  final container = ProviderContainer(
    overrides: [templateServiceProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: TemplateManagementScreen(isAdmin: isAdmin),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('TemplateManagementScreen (DG-375 Phase 4 / FR6, FR7 / AC6, AC7)', () {
    testWidgets('renders title and system/personal tabs', (tester) async {
      await _pumpManagement(tester, isAdmin: true, seed: _seedStore());
      expect(find.text(TemplatesLabels.managementTitle), findsOneWidget);
      expect(find.text(TemplatesLabels.managementSystemTab), findsOneWidget);
      expect(find.text(TemplatesLabels.managementPersonalTab), findsOneWidget);
    });

    testWidgets('system tab lists only system templates grouped by scenario',
        (tester) async {
      await _pumpManagement(tester, isAdmin: true, seed: _seedStore());
      // System scenario header + system template name appear.
      expect(find.text(TemplatesLabels.scenarioAskInfo), findsOneWidget);
      expect(find.text('Mẫu hỏi hệ thống'), findsOneWidget);
      // Personal template should NOT appear on system tab.
      expect(find.text('Mẫu cá nhân A'), findsNothing);
    });

    testWidgets('personal tab lists only personal templates', (tester) async {
      await _pumpManagement(tester, isAdmin: true, seed: _seedStore());
      await tester.tap(find.text(TemplatesLabels.managementPersonalTab));
      await tester.pumpAndSettle();
      expect(find.text('Mẫu cá nhân A'), findsOneWidget);
      expect(find.text('Mẫu hỏi hệ thống'), findsNothing);
    });

    testWidgets('admin sees edit and delete actions on system tab (FR6/AC6)',
        (tester) async {
      await _pumpManagement(tester, isAdmin: true, seed: _seedStore());
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets(
        'non-admin does NOT see edit/delete actions on system tab '
        '(personal tab still editable — FR7)', (tester) async {
      await _pumpManagement(tester, isAdmin: false, seed: _seedStore());
      // System tab: no edit/delete affordances.
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      // Switch to personal tab: edit/delete reappear.
      await tester.tap(find.text(TemplatesLabels.managementPersonalTab));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('delete confirmation dialog appears and cancels (FR6/FR7)',
        (tester) async {
      await _pumpManagement(tester, isAdmin: true, seed: _seedStore());
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text(TemplatesLabels.managementDeleteConfirmTitle),
          findsOneWidget);
      // The body has the template name substituted in place of {name}.
      expect(find.textContaining('Mẫu hỏi hệ thống'), findsWidgets);
      // Cancel the dialog via the "Hủy" TextButton.
      await tester.tap(find.widgetWithText(TextButton, 'Hủy'));
      await tester.pumpAndSettle();
      // Template still present after cancel.
      expect(find.text('Mẫu hỏi hệ thống'), findsOneWidget);
    });

    testWidgets('delete confirmation deletes the template when confirmed',
        (tester) async {
      await _pumpManagement(tester, isAdmin: true, seed: _seedStore());
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      // Confirm delete (action button is the FilledButton in the dialog).
      await tester.tap(find
          .widgetWithText(FilledButton, TemplatesLabels.managementDeleteConfirmAction));
      await tester.pumpAndSettle();
      // Row removed.
      expect(find.text('Mẫu hỏi hệ thống'), findsNothing);
    });

    testWidgets('FAB is present for adding templates (FR6/FR7)', (tester) async {
      await _pumpManagement(tester, isAdmin: true, seed: _seedStore());
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('empty state shows when a tab has no templates', (tester) async {
      await _pumpManagement(tester, isAdmin: true, seed: _seedStore());
      // Personal tab has 1 template; system tab has 1. Switch to personal then
      // delete the single personal template to reach empty state.
      await tester.tap(find.text(TemplatesLabels.managementPersonalTab));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(
          FilledButton, TemplatesLabels.managementDeleteConfirmAction));
      await tester.pumpAndSettle();
      expect(find.text(TemplatesLabels.managementEmpty), findsOneWidget);
    });

    testWidgets('TemplateManagementTile renders name and body preview',
        (tester) async {
      await _pumpManagement(tester, isAdmin: true, seed: _seedStore());
      expect(find.byType(TemplateManagementTile), findsOneWidget);
      expect(find.textContaining('Dạ mình đặt bánh'), findsOneWidget);
    });
  });
}