import 'package:bakery_app/data/api/template_service.dart';
import 'package:bakery_app/data/models/message_template.dart';
import 'package:bakery_app/features/templates/template_management_screen.dart';
import 'package:bakery_app/features/templates/template_context.dart';
import 'package:bakery_app/features/templates/widgets/template_picker_modal.dart';
import 'package:bakery_app/shared/labels/templates.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTemplateService extends TemplateService {
  _FakeTemplateService() : super(Dio());

  @override
  Future<List<MessageTemplate>> listTemplates({String? scenario}) async =>
      const [
        MessageTemplate(
          id: 1,
          scenario: 'ask_info',
          name: 'Mẫu hỏi',
          body: 'Dạ mình đặt bánh?',
          isSystem: true,
          sortOrder: 1,
          active: true,
        ),
      ];
}

const _ctx = TemplateContext(
  customerName: 'Nguyễn Văn A',
  customerPhone: '0901',
  orderCode: 'REF-1',
  publicOrderCode: 'DG-1',
  dueDate: '15/08/2026',
  dueTime: '14:00',
  totalPrice: '500.000đ',
  itemsList: '- Bánh',
  deliveryType: 'pickup',
  deliveryAddress: '',
  shippingFee: '0đ',
  notes: '',
  source: 'Online',
  createdBy: 'Staff',
  status: 'new',
);

void main() {
  group('Template picker modal — Manage Templates footer (DG-375 Phase 4 / '
      'FR10)', () {
    testWidgets('picker modal shows a "Manage Templates" footer button',
        (tester) async {
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
                    onPressed: () =>
                        TemplatePickerModal.show(ctx, templateContext: _ctx),
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
      expect(find.text(TemplatesLabels.manageTemplatesButton), findsOneWidget);
    });

    testWidgets('tapping Manage Templates pushes the management screen '
        '(FR10)', (tester) async {
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
                    onPressed: () =>
                        TemplatePickerModal.show(ctx, templateContext: _ctx),
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
      await tester.tap(find.text(TemplatesLabels.manageTemplatesButton));
      await tester.pumpAndSettle();
      // The management screen is now rendered.
      expect(find.byType(TemplateManagementScreen), findsOneWidget);
      expect(find.text(TemplatesLabels.managementTitle), findsOneWidget);
    });

    testWidgets('onManage callback is invoked when provided', (tester) async {
      var invoked = false;
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
                      templateContext: _ctx,
                      onManage: () => invoked = true,
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
      await tester.tap(find.text(TemplatesLabels.manageTemplatesButton));
      await tester.pumpAndSettle();
      expect(invoked, isTrue);
    });
  });
}