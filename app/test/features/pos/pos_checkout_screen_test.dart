import 'package:bakery_app/features/pos/pos_checkout_screen.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractBackendDetail', () {
    test('returns null for null input', () {
      expect(extractBackendDetail(null), isNull);
    });

    test('returns null for non-map input', () {
      expect(extractBackendDetail(['detail']), isNull);
      expect(extractBackendDetail('detail'), isNull);
    });

    test('returns null when detail key is missing', () {
      expect(extractBackendDetail(<String, dynamic>{'message': 'x'}), isNull);
    });

    test('returns null when detail is not a string', () {
      expect(extractBackendDetail(<String, dynamic>{'detail': 123}), isNull);
      expect(extractBackendDetail(<String, dynamic>{'detail': true}), isNull);
    });

    test('returns null when detail is empty or whitespace', () {
      expect(extractBackendDetail(<String, dynamic>{'detail': ''}), isNull);
      expect(extractBackendDetail(<String, dynamic>{'detail': '   '}), isNull);
    });
  });

  group('resolvePosCheckoutErrorMessage', () {
    test('returns backend 422 detail when present', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/orders'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/orders'),
          statusCode: 422,
          data: {'detail': 'Sản phẩm Bánh su kem không đủ tồn kho'},
        ),
      );

      expect(
        resolvePosCheckoutErrorMessage(error),
        'Sản phẩm Bánh su kem không đủ tồn kho',
      );
    });

    test('returns vietnamese fallback when 422 detail is missing', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/orders'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/orders'),
          statusCode: 422,
          data: <String, dynamic>{},
        ),
      );

      expect(resolvePosCheckoutErrorMessage(error), VN.loiKhongXacDinhTuMayChu);
      expect(
        resolvePosCheckoutErrorMessage(error),
        isNot(contains('DioException')),
      );
    });

    test('returns VN.apiError when DioException response is null', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/orders'),
      );

      expect(resolvePosCheckoutErrorMessage(error), VN.apiError);
    });

    test('returns VN.loiMayChu for non-422 server responses', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/api/orders'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/orders'),
          statusCode: 500,
          data: <String, dynamic>{'detail': 'Internal Server Error'},
        ),
      );

      expect(resolvePosCheckoutErrorMessage(error), VN.loiMayChu);
    });

    test('returns VN.loiHeThong for non-Dio exceptions', () {
      final error = Exception('unexpected');

      expect(resolvePosCheckoutErrorMessage(error), VN.loiHeThong);
    });
  });
}
