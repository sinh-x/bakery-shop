// DG-322 / CQ-7 — direct unit tests for the extracted `OrderSubmissionMixin`
// pure helper `buildOrderItemsPayload`. The mixin is constrained on
// `ConsumerState<W>`, so the fixture below builds a minimal host widget whose
// state mixes in the mixin and exposes the helper under test. Only the pure
// payload builder is exercised here — the full submission spine
// (`submitOrder`, `uploadPendingPhotosDefault`) touches `ref`, services, and
// navigation, so it is covered by the existing `pos_checkout_screen_test.dart`
// and `order_creation_orchestrator_test.dart` integration suites.
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/features/orders/widgets/order_creation_orchestrator.dart';
import 'package:bakery_app/features/orders/providers/order_draft_contexts.dart';
import 'package:bakery_app/providers/form_draft_session_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/data/models/order_draft.dart';
import 'package:bakery_app/data/models/product.dart';
import 'package:bakery_app/features/orders/widgets/order_creation_config.dart';
import 'package:bakery_app/features/orders/widgets/order_submission_mixin.dart';
import 'package:bakery_app/features/orders/widgets/order_wizard.dart';
import 'package:bakery_app/providers/order/order_create_state_provider.dart';

class _SubmissionHost extends ConsumerStatefulWidget {
  const _SubmissionHost({required this.state});
  final _HostStateState state;
  @override
  // ignore: no_logic_in_create_state
  ConsumerState<_SubmissionHost> createState() => state;
}

class _HostStateState extends ConsumerState<_SubmissionHost>
    with OrderSubmissionMixin<_SubmissionHost> {
  _HostStateState(this._state);
  final OrderCreateState _state;

  @override
  OrderCreationConfig get config => throw UnimplementedError();

  @override
  NotifierProvider<OrderCreateStateNotifier, OrderCreateState> get provider =>
      throw UnimplementedError();

  OrderCreateState get testState => _state;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  for (final flow in ['create', 'pos']) {
    for (final type in ['bus', 'door']) {
      for (final link in ['https://maps.example/selected', null]) {
        testWidgets(
          'DG-438 $flow/$type submission ${link == null ? 'null' : 'linked'} payload and retry',
          (tester) async {
            final requests = <Map<String, dynamic>>[];
            final dio = Dio()
              ..interceptors.add(
                InterceptorsWrapper(
                  onRequest: (options, handler) {
                    if (options.method == 'POST') {
                      requests.add(
                        Map<String, dynamic>.from(options.data as Map),
                      );
                      if (requests.length == 1) {
                        handler.reject(DioException(requestOptions: options));
                        return;
                      }
                    }
                    handler.resolve(
                      Response(
                        requestOptions: options,
                        statusCode: 200,
                        data: {
                          ...requests.last,
                          'id': '1',
                          'orderRef': 'SAVED',
                          'customerName': 'Test',
                          'items': <Object>[],
                          'totalPrice': 10000,
                          'createdAt': '2026-10-11T00:00:00Z',
                          'updatedAt': '2026-10-11T00:00:00Z',
                        },
                      ),
                    );
                  },
                ),
              );
            final container = ProviderContainer(
              overrides: [
                orderServiceProvider.overrideWithValue(OrderService(dio)),
              ],
            );
            addTearDown(container.dispose);
            final provider = flow == 'pos'
                ? posOrderStateProvider
                : orderCreateStateProvider;
            final notifier = container.read(provider.notifier);
            notifier.updateItems([
              DraftOrderItem(
                product: const Product(id: 1, name: 'Test', basePrice: 10000),
              ),
            ]);
            notifier.updateWizardData(
              OrderWizardData(
                customerName: 'Test',
                deliveryType: type,
                deliveryAddress: '12 Exact',
              ),
            );
            notifier.updateGpsFields(
              googleMapsUrl: link,
              clearGoogleMapsUrl: link == null,
              clearLatitude: true,
              clearLongitude: true,
            );
            final context = flow == 'pos'
                ? OrderDraftContexts.posCheckout
                : OrderDraftContexts.createOrder;
            final other = OrderDraftContexts.editOrder('OTHER');
            container.read(formDraftSessionProvider.notifier)
              ..retainDraft(context, container.read(provider))
              ..retainDraft(other, 'unrelated');
            final key = GlobalKey<OrderCreationOrchestratorState>();
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: container,
                child: MaterialApp(
                  home: Scaffold(
                    body: OrderCreationOrchestrator(
                      key: key,
                      config: OrderCreationConfig(
                        orderStateProvider: provider,
                        posMode: flow == 'pos',
                        enableDraft: false,
                        enableCartSync: false,
                        enableSwipeNavigation: false,
                        enableOrderListRefresh: false,
                        stage1Builder: (_, _) => const SizedBox.shrink(),
                        stage2Builder: (_, _) => const SizedBox.shrink(),
                        stage3Builder: (_, _) => const SizedBox.shrink(),
                        stage4Builder: (_, _) => const SizedBox.shrink(),
                        stageContainerBuilder: (_, stages, stage) =>
                            stages[stage - 1],
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              await tester.runAsync(() => key.currentState!.submitOrder()),
              isFalse,
            );
            await tester.pumpAndSettle();
            expect(container.read(provider).googleMapsUrl, link);
            expect(container.read(formDraftSessionProvider), contains(context));
            expect(key.currentState!.isSubmitting, isFalse);
            expect(
              await tester.runAsync(() => key.currentState!.submitOrder()),
              isTrue,
            );
            await tester.pumpAndSettle();
            expect(requests, hasLength(2));
            for (final request in requests) {
              expect(request['deliveryType'], type);
              expect(request['deliveryAddress'], '12 Exact');
              expect(request['googleMapsUrl'], link);
              expect(request['latitude'], isNull);
              expect(request['longitude'], isNull);
            }
            final readback = (await tester.runAsync(
              () => container.read(orderServiceProvider).getOrder('SAVED'),
            ))!;
            expect(readback.deliveryAddress, '12 Exact');
            expect(readback.googleMapsUrl, link);
            expect(readback.latitude, isNull);
            expect(readback.longitude, isNull);
            expect(
              container.read(formDraftSessionProvider),
              isNot(contains(context)),
            );
            expect(container.read(formDraftSessionProvider), contains(other));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  group('OrderSubmissionMixin.buildOrderItemsPayload (DG-322 / CQ-7)', () {
    Widget buildHost(OrderCreateState state) {
      final hostState = _HostStateState(state);
      return ProviderScope(
        child: MaterialApp(home: _SubmissionHost(state: hostState)),
      );
    }

    testWidgets('maps a plain catalog item with default attributes', (
      tester,
    ) async {
      const product = Product(id: 42, name: 'Bánh mì', basePrice: 15000);
      final state = OrderCreateState(
        items: [DraftOrderItem(product: product, quantity: 2)],
        wizardData: const OrderWizardData(),
      );

      await tester.pumpWidget(buildHost(state));
      await tester.pump();

      final hostState = tester.state<_HostStateState>(
        find.byType(_SubmissionHost),
      );
      final payload = hostState.buildOrderItemsPayload(hostState.testState);

      expect(payload, hasLength(1));
      final item = payload.single;
      expect(item['productId'], '42');
      expect(item['productName'], 'Bánh mì');
      expect(item['quantity'], 2);
      expect(item['unitPrice'], 15000);
      expect(item['isBirthday'], isFalse);
      expect(item['isExtra'], isFalse);
      expect(item['isGift'], isFalse);
      expect(item['attributes'], isA<Map<String, dynamic>>());
    });

    testWidgets(
      'FR3: includes assignedPrice when the trưng bày markup item has one',
      (tester) async {
        const product = Product(
          id: 7,
          name: 'Trưng bày set',
          basePrice: 100000,
          attributes: {'trung_bay': 'true'},
        );
        final state = OrderCreateState(
          items: [
            DraftOrderItem(
              product: product,
              quantity: 1,
              assignedPrice: 120000,
            ),
          ],
          wizardData: const OrderWizardData(),
        );

        await tester.pumpWidget(buildHost(state));
        await tester.pump();

        final hostState = tester.state<_HostStateState>(
          find.byType(_SubmissionHost),
        );
        final payload = hostState.buildOrderItemsPayload(hostState.testState);

        expect(payload.single['assignedPrice'], 120000);
      },
    );

    testWidgets('omits assignedPrice when it is null', (tester) async {
      const product = Product(id: 3, name: 'Croissant', basePrice: 20000);
      final state = OrderCreateState(
        items: [DraftOrderItem(product: product)],
        wizardData: const OrderWizardData(),
      );

      await tester.pumpWidget(buildHost(state));
      await tester.pump();

      final hostState = tester.state<_HostStateState>(
        find.byType(_SubmissionHost),
      );
      final payload = hostState.buildOrderItemsPayload(hostState.testState);

      expect(payload.single.containsKey('assignedPrice'), isFalse);
    });

    testWidgets('attaches age when isBirthday and age parses to int', (
      tester,
    ) async {
      const product = Product(id: 9, name: 'Birthday cake', basePrice: 250000);
      final state = OrderCreateState(
        items: [DraftOrderItem(product: product, isBirthday: true, age: ' 5 ')],
        wizardData: const OrderWizardData(),
      );

      await tester.pumpWidget(buildHost(state));
      await tester.pump();

      final hostState = tester.state<_HostStateState>(
        find.byType(_SubmissionHost),
      );
      final payload = hostState.buildOrderItemsPayload(hostState.testState);

      expect(payload.single['isBirthday'], isTrue);
      expect(payload.single['age'], 5);
    });

    testWidgets('omits age when isBirthday but age is non-numeric', (
      tester,
    ) async {
      const product = Product(id: 9, name: 'Birthday cake', basePrice: 250000);
      final state = OrderCreateState(
        items: [DraftOrderItem(product: product, isBirthday: true, age: 'abc')],
        wizardData: const OrderWizardData(),
      );

      await tester.pumpWidget(buildHost(state));
      await tester.pump();

      final hostState = tester.state<_HostStateState>(
        find.byType(_SubmissionHost),
      );
      final payload = hostState.buildOrderItemsPayload(hostState.testState);

      expect(payload.single['isBirthday'], isTrue);
      expect(payload.single.containsKey('age'), isFalse);
    });

    testWidgets('returns an empty list for an empty cart', (tester) async {
      const state = OrderCreateState(items: [], wizardData: OrderWizardData());

      await tester.pumpWidget(buildHost(state));
      await tester.pump();

      final hostState = tester.state<_HostStateState>(
        find.byType(_SubmissionHost),
      );
      final payload = hostState.buildOrderItemsPayload(hostState.testState);

      expect(payload, isEmpty);
    });

    testWidgets('preserves priceChipId when set', (tester) async {
      const product = Product(id: 11, name: 'Chip cake', basePrice: 50000);
      final state = OrderCreateState(
        items: [DraftOrderItem(product: product, priceChipId: 77)],
        wizardData: const OrderWizardData(),
      );

      await tester.pumpWidget(buildHost(state));
      await tester.pump();

      final hostState = tester.state<_HostStateState>(
        find.byType(_SubmissionHost),
      );
      final payload = hostState.buildOrderItemsPayload(hostState.testState);

      expect(payload.single['priceChipId'], 77);
    });
  });
}
