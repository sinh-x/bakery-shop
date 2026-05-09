import 'package:bakery_app/shared/utils/api_error.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
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
}
