import 'package:bakery_app/data/api/order_service.dart';
import 'package:bakery_app/data/api/work_item_service.dart';
import 'package:bakery_app/data/providers/order/order_detail_notifier.dart';
import 'package:bakery_app/data/providers/order/order_work_item_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _WorkItemMutationInterceptor extends Interceptor {
  bool failDetailRefresh = false;
  int detailRequestCount = 0;

  Map<String, dynamic> get _item => <String, dynamic>{
    'id': '10',
    'orderId': 'ORD-STATE',
    'productId': 'P-OLD',
    'productName': 'Bánh cũ',
    'quantity': 2,
    'unitPrice': 250000.0,
    'status': 'pending',
    'attributes': <String, dynamic>{'old_enum': 'old_value'},
  };

  Map<String, dynamic> get _order => <String, dynamic>{
    'id': 'order-state',
    'orderRef': 'ORD-STATE',
    'publicOrderCode': '',
    'customerName': 'Test',
    'customerPhone': '',
    'deliveryPhone': '',
    'customerId': null,
    'items': <Map<String, dynamic>>[],
    'totalPrice': 0.0,
    'status': 'new',
    'deliveryType': 'pickup',
    'deliveryAddress': '',
    'shippingFee': 0.0,
    'notes': '',
    'source': '',
    'packingChecklist': <Map<String, dynamic>>[],
    'createdAt': '2026-08-29T00:00:00Z',
    'updatedAt': '2026-08-29T00:00:00Z',
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/api/orders/ORD-STATE/items' &&
        options.method == 'GET') {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: <Map<String, dynamic>>[_item],
        ),
      );
      return;
    }
    if (options.path == '/api/orders/ORD-STATE/items/10' &&
        options.method == 'PATCH') {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: <String, dynamic>{
            ..._item,
            'productId': 'P-NEW',
            'productName': 'Bánh mới',
            'attributes': <String, dynamic>{'workflow_key': 'preserved'},
          },
        ),
      );
      return;
    }
    if (options.path == '/api/orders/ORD-STATE/items/10' &&
        options.method == 'DELETE') {
      handler.resolve(Response<void>(requestOptions: options, statusCode: 204));
      return;
    }
    if (options.path == '/api/orders/ORD-STATE' && options.method == 'GET') {
      detailRequestCount += 1;
      if (failDetailRefresh) {
        handler.reject(
          DioException(
            requestOptions: options,
            response: Response<void>(requestOptions: options, statusCode: 500),
          ),
        );
      } else {
        handler.resolve(
          Response(requestOptions: options, statusCode: 200, data: _order),
        );
      }
      return;
    }
    handler.reject(DioException(requestOptions: options));
  }
}

ProviderContainer _buildContainer(_WorkItemMutationInterceptor interceptor) {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
    ..interceptors.add(interceptor);
  final container = ProviderContainer(
    overrides: [
      workItemServiceProvider.overrideWithValue(WorkItemService(dio)),
      orderServiceProvider.overrideWithValue(OrderService(dio)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _seedState(
  ProviderContainer container,
  _WorkItemMutationInterceptor interceptor,
) async {
  await container.read(orderWorkItemsProvider('ORD-STATE').future);
  await container.read(orderDetailProvider('ORD-STATE').future);
  interceptor.failDetailRefresh = true;
}

void main() {
  group('OrderWorkItemsNotifier mutation reconciliation', () {
    test(
      'AC8 replacement keeps server result and stale detail when refresh fails, then retries',
      () async {
        final interceptor = _WorkItemMutationInterceptor();
        final container = _buildContainer(interceptor);
        await _seedState(container, interceptor);

        final notifier = container.read(
          orderWorkItemsProvider('ORD-STATE').notifier,
        );
        final outcome = await notifier.replaceProduct(
          '10',
          productId: 'P-NEW',
          productName: 'Bánh mới',
        );

        expect(outcome.refreshFailed, isTrue);
        expect(outcome.updatedItem?.productName, 'Bánh mới');
        final visibleItem = container
            .read(orderWorkItemsProvider('ORD-STATE'))
            .requireValue
            .single;
        expect(visibleItem.productName, 'Bánh mới');
        expect(visibleItem.attributes, <String, dynamic>{
          'workflow_key': 'preserved',
        });
        expect(
          container.read(orderDetailProvider('ORD-STATE')).hasError,
          isFalse,
          reason: 'a refresh-only failure must retain rendered order detail',
        );

        interceptor.failDetailRefresh = false;
        expect(await notifier.retryOrderDetailRefresh(), isNull);
        expect(interceptor.detailRequestCount, 3);
      },
    );

    test('AC8 removal remains absent when detail refresh fails', () async {
      final interceptor = _WorkItemMutationInterceptor();
      final container = _buildContainer(interceptor);
      await _seedState(container, interceptor);

      final outcome = await container
          .read(orderWorkItemsProvider('ORD-STATE').notifier)
          .removeWithOutcome('10');

      expect(outcome.refreshFailed, isTrue);
      expect(
        container.read(orderWorkItemsProvider('ORD-STATE')).requireValue,
        isEmpty,
      );
      expect(
        container.read(orderDetailProvider('ORD-STATE')).hasError,
        isFalse,
      );
    });
  });
}
