import 'package:bakery_app/shared/utils/api_error.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';

void main() {
  group('normalizeApiError', () {
    test('returns validation detail for 422', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/orders'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/orders'),
          statusCode: 422,
          data: {'detail': 'Thiếu tồn kho'},
        ),
      );

      final normalized = normalizeApiError(error);
      expect(normalized.kind, ApiErrorKind.validation);
      expect(normalized.message, 'Thiếu tồn kho');
      expect(normalized.statusCode, 422);
    });

    test('returns timeout message for connection timeout', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/orders'),
        type: DioExceptionType.connectionTimeout,
      );

      final normalized = normalizeApiError(error);
      expect(normalized.kind, ApiErrorKind.timeout);
      expect(normalized.message, SharedLabels.apiTimeout);
    });

    test('replaces raw backend diagnostics with a safe validation reason', () {
      final request = RequestOptions(path: '/api/orders/ORD/items/10');
      final error = DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 422,
          data: <String, dynamic>{
            'detail': 'SQLite exception: SQL syntax error\nTraceback',
          },
        ),
      );

      expect(normalizeApiError(error).message, SharedLabels.apiValidationError);
    });
  });

  group('action failure messaging', () {
    test(
      'covers lifecycle, validation, network, timeout, 5xx, and unknown',
      () {
        final request = RequestOptions(path: '/api/orders/ORD/items/10');
        final errors = <Object>[
          DioException(
            requestOptions: request,
            response: Response(
              requestOptions: request,
              statusCode: 422,
              data: <String, dynamic>{
                'detail': 'Không thể xóa sản phẩm đã giao',
              },
            ),
          ),
          DioException(
            requestOptions: request,
            response: Response(
              requestOptions: request,
              statusCode: 422,
              data: <String, dynamic>{'detail': 'Sản phẩm không hợp lệ'},
            ),
          ),
          DioException(
            requestOptions: request,
            type: DioExceptionType.connectionError,
          ),
          DioException(
            requestOptions: request,
            type: DioExceptionType.receiveTimeout,
          ),
          DioException(
            requestOptions: request,
            response: Response(
              requestOptions: request,
              statusCode: 500,
              data: <String, dynamic>{'detail': 'Python traceback SQL error'},
            ),
          ),
          StateError('raw Dart diagnostic'),
        ];

        for (final error in errors) {
          final message = buildApiActionFailureMessage(
            action: OrdersLabels.replaceProductFailed,
            error: error,
          );
          expect(message, contains(OrdersLabels.replaceProductFailed));
          expect(message, contains(SharedLabels.failureReasonLabel));
          expect(message, contains(SharedLabels.nextStepLabel));
          expect(message, isNot(contains('DioException')));
          expect(message, isNot(contains('StateError')));
          expect(message.toLowerCase(), isNot(contains('traceback')));
          expect(message.toLowerCase(), isNot(contains('sql error')));
        }
      },
    );

    test('refresh-only feedback keeps the successful action explicit', () {
      final message = buildApiActionFailureMessage(
        action: OrdersLabels.removeProductRefreshFailed,
        error: DioException(
          requestOptions: RequestOptions(path: '/api/orders/ORD'),
          type: DioExceptionType.connectionTimeout,
        ),
        nextStep: OrdersLabels.orderDetailRefreshRecovery,
      );

      expect(message, contains(OrdersLabels.removeProductRefreshFailed));
      expect(message, contains(SharedLabels.apiTimeout));
      expect(message, contains(OrdersLabels.orderDetailRefreshRecovery));
    });
  });

  group('order status failure messaging', () {
    test(
      'maps known backend transition detail strings to actionable recovery',
      () {
        const backendDetails = <String>[
          'Không đủ tồn kho cho sản phẩm',
          'Invalid product price bucket for order item',
          'Lý do là bắt buộc khi lùi trạng thái',
          'Chưa thanh toán đủ để hoàn thành đơn hàng — còn thiếu 12,000đ',
        ];

        for (final detail in backendDetails) {
          final action = orderStatusRecoveryActionFromDetail(detail);
          expect(
            action,
            isNot(OrdersLabels.orderStatusActionContactAdmin),
            reason: detail,
          );
        }
      },
    );

    test('maps known stock reason to recovery action', () {
      final action = orderStatusRecoveryActionFromDetail('Không đủ tồn kho');
      expect(action, OrdersLabels.orderStatusActionCheckStock);
    });

    test('maps known invalid price bucket reason to recovery action', () {
      final action = orderStatusRecoveryActionFromDetail(
        'Invalid product price bucket for order item',
      );
      expect(action, OrdersLabels.orderStatusActionCheckPriceBucket);
    });

    test('maps missing backward transition reason to recovery action', () {
      final action = orderStatusRecoveryActionFromDetail(
        'Thiếu lý do khi quay lại trạng thái trước',
      );
      expect(action, OrdersLabels.orderStatusActionAddBackwardReason);
    });

    test('maps incomplete payment reason to recovery action', () {
      final action = orderStatusRecoveryActionFromDetail(
        'Đơn hàng chưa thanh toán đủ',
      );
      expect(action, OrdersLabels.orderStatusActionCompletePayment);
    });

    test('builds message with order ref and status code', () {
      final message = buildOrderStatusFailureMessage(
        reason: 'Không đủ tồn kho',
        action: OrdersLabels.orderStatusActionCheckStock,
        orderRef: 'ORD-260508-010',
        statusCode: 422,
      );
      expect(message, contains('ORD-260508-010'));
      expect(message, contains('422'));
      expect(message, contains(OrdersLabels.orderStatusRecoveryLabel));
    });
  });
}
