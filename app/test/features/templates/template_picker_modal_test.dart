import 'package:bakery_app/data/api/template_service.dart';
import 'package:bakery_app/data/models/message_template.dart';
import 'package:bakery_app/features/templates/template_context.dart';
import 'package:bakery_app/features/templates/widgets/template_picker_modal.dart';
import 'package:bakery_app/shared/labels/templates.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake [TemplateService] serving a small in-memory set of templates so the
/// modal's `templateListProvider` resolves synchronously without a backend.
class _FakeTemplateService extends TemplateService {
  _FakeTemplateService() : super(Dio());

  final List<MessageTemplate> _store = const [
    MessageTemplate(
      id: 1,
      scenario: 'ask_info',
      name: 'Mẫu hỏi thông tin',
      body: 'Dạ mình đặt bánh khi nào lấy ạ?',
      isSystem: true,
      sortOrder: 1,
      active: true,
    ),
    MessageTemplate(
      id: 2,
      scenario: 'confirm_order',
      name: 'Xác nhận đơn — Pickup',
      body: 'Dạ đơn {public_order_code} của mình ạ.',
      isSystem: true,
      sortOrder: 2,
      active: true,
    ),
    MessageTemplate(
      id: 3,
      scenario: 'confirm_order',
      name: 'Cá nhân mẫu',
      body: 'Xin chào {customer_name}',
      isSystem: false,
      createdByStaffId: 7,
      sortOrder: 3,
      active: true,
    ),
  ];

  @override
  Future<List<MessageTemplate>> listTemplates({String? scenario}) async {
    if (scenario != null) {
      return _store.where((t) => t.scenario == scenario).toList();
    }
    return List<MessageTemplate>.from(_store);
  }
}

TemplateContext _ctx({String publicOrderCode = 'DG-1'}) {
  return TemplateContext(
    customerName: 'Nguyễn Văn A',
    customerPhone: '0901234567',
    orderCode: 'REF-1',
    publicOrderCode: publicOrderCode,
    dueDate: '15/08/2026',
    dueTime: '14:00',
    totalPrice: '500.000đ',
    itemsList: '- Bánh kem',
    deliveryType: 'pickup',
    deliveryAddress: '',
    shippingFee: '0đ',
    notes: '',
    source: 'Online',
    createdBy: 'Staff',
    status: 'new',
  );
}

Future<void> _pumpModal(
  WidgetTester tester, {
  TemplateContext templateContext = const TemplateContext(
    customerName: 'Nguyễn Văn A',
    customerPhone: '0901234567',
    orderCode: 'REF-1',
    publicOrderCode: 'DG-1',
    dueDate: '15/08/2026',
    dueTime: '14:00',
    totalPrice: '500.000đ',
    itemsList: '- Bánh kem',
    deliveryType: 'pickup',
    deliveryAddress: '',
    shippingFee: '0đ',
    notes: '',
    source: 'Online',
    createdBy: 'Staff',
    status: 'new',
  ),
}) async {
  final container = ProviderContainer(
    overrides: [templateServiceProvider.overrideWithValue(_FakeTemplateService())],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => TemplatePickerModal.show(
                  ctx,
                  templateContext: templateContext,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Register a mock clipboard handler so `Clipboard.setData` does not throw
  // a MissingPluginException during widget tests.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') return null;
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
  });

  group('TemplatePickerModal (DG-375 Phase 4.3 / AC1, AC4, AC5)', () {
    testWidgets('renders modal title and templates grouped by scenario',
        (tester) async {
      await _pumpModal(tester);
      expect(find.text(TemplatesLabels.pickerTitle), findsOneWidget);
      // Scenario group headers.
      expect(find.text(TemplatesLabels.scenarioAskInfo), findsOneWidget);
      expect(find.text(TemplatesLabels.scenarioConfirmOrder), findsOneWidget);
      // Template names visible (collapsed rows).
      expect(find.text('Mẫu hỏi thông tin'), findsOneWidget);
      expect(find.text('Xác nhận đơn — Pickup'), findsOneWidget);
      expect(find.text('Cá nhân mẫu'), findsOneWidget);
    });

    testWidgets('system vs personal tag is shown on each tile', (tester) async {
      await _pumpModal(tester);
      expect(find.text(TemplatesLabels.systemTag), findsNWidgets(2));
      expect(find.text(TemplatesLabels.personalTag), findsOneWidget);
    });

    testWidgets('tapping a tile expands the preview with resolved placeholders '
        '(AC4)', (tester) async {
      await _pumpModal(tester);
      // Tap the "Xác nhận đơn — Pickup" tile to expand.
      await tester.tap(find.text('Xác nhận đơn — Pickup'));
      await tester.pumpAndSettle();
      // The preview label and resolved body appear.
      expect(find.text(TemplatesLabels.previewLabel), findsOneWidget);
      expect(find.textContaining('DG-1'), findsWidgets);
      // Copy button is present.
      expect(find.text(TemplatesLabels.copyButton), findsOneWidget);
    });

    testWidgets('tapping Copy shows confirmation snackbar (AC5)', (tester) async {
      await _pumpModal(tester);
      await tester.tap(find.text('Xác nhận đơn — Pickup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(TemplatesLabels.copyButton));
      await tester.pumpAndSettle();
      // The confirmation snackbar is shown (FR5 / AC5). The button label
      // also switches to the copied text, so the label appears at least
      // once in the button and once in the snackbar.
      expect(find.text(TemplatesLabels.copiedSnack), findsWidgets);
      // The copy button icon switches to a check mark.
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('collapsing an expanded tile hides the preview', (tester) async {
      await _pumpModal(tester);
      await tester.tap(find.text('Xác nhận đơn — Pickup'));
      await tester.pumpAndSettle();
      expect(find.text(TemplatesLabels.previewLabel), findsOneWidget);
      // Tap again to collapse.
      await tester.tap(find.text('Xác nhận đơn — Pickup'));
      await tester.pumpAndSettle();
      expect(find.text(TemplatesLabels.previewLabel), findsNothing);
    });

    testWidgets('close button dismisses the modal', (tester) async {
      await _pumpModal(tester);
      expect(find.byType(TemplatePickerModal), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(TemplatePickerModal), findsNothing);
    });

    testWidgets('empty state shows when no templates available', (tester) async {
      final container = ProviderContainer(
        overrides: [
          templateServiceProvider.overrideWithValue(_EmptyTemplateService()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: ElevatedButton(
                    onPressed: () => TemplatePickerModal.show(
                      ctx,
                      templateContext: _ctx(),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(TemplatesLabels.emptyTitle), findsOneWidget);
      expect(find.text(TemplatesLabels.emptyBody), findsOneWidget);
    });
  });
}

class _EmptyTemplateService extends TemplateService {
  _EmptyTemplateService() : super(Dio());
  @override
  Future<List<MessageTemplate>> listTemplates({String? scenario}) async =>
      const <MessageTemplate>[];
}