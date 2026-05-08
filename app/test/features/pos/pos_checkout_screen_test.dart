import 'package:bakery_app/features/pos/pos_checkout_screen.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
  });
}
