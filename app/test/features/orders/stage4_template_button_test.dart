import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/models/order_draft.dart';
import 'package:bakery_app/data/models/order_photo.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/orders/widgets/order_wizard.dart';
import 'package:bakery_app/features/orders/widgets/stage4_review_screen.dart';
import 'package:bakery_app/features/orders/widgets/order_edit/edit_stage4_review.dart';
import 'package:bakery_app/providers/order/order_create_state_provider.dart';
import 'package:bakery_app/shared/labels/templates.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Integration tests for the template-picker review-stage button on the
/// order create wizard's Stage 4 and the order edit wizard's Stage 4
/// (DG-375 Phase 4.3 / FR2, FR3 / AC2, AC3).
///
/// The edit Stage 4 embeds an `OrderPhotoSection` which fetches photos via
/// Dio. To avoid a pending-timer failure we override `orderServiceProvider`
/// with a [FakeOrderService] whose `listOrderPhotos` resolves synchronously.

class FakeOrderService extends OrderService {
  FakeOrderService() : super(Dio(BaseOptions(baseUrl: 'http://test')));

  @override
  Future<List<OrderPhoto>> listOrderPhotos(String orderRef) async =>
      const <OrderPhoto>[];
}

Future<ProviderContainer> _container({bool withOrderService = false}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (withOrderService)
        orderServiceProvider.overrideWithValue(FakeOrderService()),
    ],
  );
}

void main() {
  group('Stage4ReviewScreen template button (AC2)', () {
    testWidgets('renders the "Mẫu tin nhắn" button when onOpenTemplates is '
        'provided', (tester) async {
      var tapped = false;
      final container = await _container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Stage4ReviewScreen(
                onBack: () {},
                onSubmit: () {},
                orderStateProvider: orderCreateStateProvider,
                onOpenTemplates: () => tapped = true,
              ),
            ),
          ),
        ),
      );
      expect(find.text(TemplatesLabels.reviewStageButton), findsOneWidget);
      await tester.tap(find.text(TemplatesLabels.reviewStageButton));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('does not render the template button when onOpenTemplates is '
        'null (backward compat)', (tester) async {
      final container = await _container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Stage4ReviewScreen(
                onBack: () {},
                onSubmit: () {},
                orderStateProvider: orderCreateStateProvider,
              ),
            ),
          ),
        ),
      );
      expect(find.text(TemplatesLabels.reviewStageButton), findsNothing);
    });
  });

  group('EditStage4Review template button (AC3)', () {
    testWidgets('renders the "Mẫu tin nhắn" button when onOpenTemplates is '
        'provided', (tester) async {
      var tapped = false;
      final container = await _container(withOrderService: true);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: EditStage4Review(
                orderRef: 'ORD-1',
                wizardSnapshot: const OrderWizardData(),
                summaryItems: [
                  DraftOrderItem(
                    product: const Product(
                      id: 1,
                      name: 'Bánh',
                      category: 'banh_kem',
                      basePrice: 100000,
                    ),
                    quantity: 1,
                  ),
                ],
                dueDate: DateTime(2026, 8, 15),
                dueTime: const TimeOfDay(hour: 14, minute: 0),
                onSave: () {},
                onBack: () {},
                isProcessing: false,
                onOpenTemplates: () => tapped = true,
              ),
            ),
          ),
        ),
      );
      // Pump a few frames to let the photo section's async load settle
      // without pumpAndSettle (Dio may leave a pending timer).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(TemplatesLabels.reviewStageButton), findsOneWidget);
      await tester.tap(find.text(TemplatesLabels.reviewStageButton));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('does not render the template button when onOpenTemplates is '
        'null (backward compat)', (tester) async {
      final container = await _container(withOrderService: true);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: EditStage4Review(
                orderRef: 'ORD-1',
                wizardSnapshot: const OrderWizardData(),
                summaryItems: const [],
                dueDate: null,
                dueTime: null,
                onSave: () {},
                onBack: () {},
                isProcessing: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(TemplatesLabels.reviewStageButton), findsNothing);
    });
  });
}