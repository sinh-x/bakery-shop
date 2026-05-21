import 'package:bakery_app/shared/utils/api_error.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

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
      expect(normalized.message, VN.apiTimeout);
    });
  });

  group('order status failure messaging', () {
    test('maps known backend transition detail strings to actionable recovery', () {
      const backendDetails = <String>[
        'Không đủ tồn kho cho sản phẩm',
        'Invalid product price bucket for order item',
        'Lý do là bắt buộc khi lùi trạng thái',
        'Chưa thanh toán đủ để hoàn thành đơn hàng — còn thiếu 12,000đ',
      ];

      for (final detail in backendDetails) {
        final action = orderStatusRecoveryActionFromDetail(detail);
        expect(action, isNot(VN.orderStatusActionContactAdmin), reason: detail);
      }
    });

    test('maps known stock reason to recovery action', () {
      final action = orderStatusRecoveryActionFromDetail('Không đủ tồn kho');
      expect(action, VN.orderStatusActionCheckStock);
    });

    test('maps known invalid price bucket reason to recovery action', () {
      final action = orderStatusRecoveryActionFromDetail(
        'Invalid product price bucket for order item',
      );
      expect(action, VN.orderStatusActionCheckPriceBucket);
    });

    test('maps missing backward transition reason to recovery action', () {
      final action = orderStatusRecoveryActionFromDetail(
        'Thiếu lý do khi quay lại trạng thái trước',
      );
      expect(action, VN.orderStatusActionAddBackwardReason);
    });

    test('maps incomplete payment reason to recovery action', () {
      final action = orderStatusRecoveryActionFromDetail(
        'Đơn hàng chưa thanh toán đủ',
      );
      expect(action, VN.orderStatusActionCompletePayment);
    });

    test('builds message with order ref and status code', () {
      final message = buildOrderStatusFailureMessage(
        reason: 'Không đủ tồn kho',
        action: VN.orderStatusActionCheckStock,
        orderRef: 'ORD-260508-010',
        statusCode: 422,
      );
      expect(message, contains('ORD-260508-010'));
      expect(message, contains('422'));
      expect(message, contains(VN.orderStatusRecoveryLabel));
    });
  });
}
