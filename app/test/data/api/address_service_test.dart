import 'package:bakery_app/data/api/address_service.dart';
import 'package:bakery_app/data/models/address.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures the outgoing request and returns a canned response body.
class _CaptureInterceptor extends Interceptor {
  String? method;
  String? path;
  Map<String, dynamic>? queryParameters;
  Object? responseBody;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    method = options.method;
    path = options.path;
    queryParameters = options.queryParameters;
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: responseBody ?? const <Map<String, dynamic>>[],
      ),
    );
  }
}

void main() {
  test('missingLinks calls GET /api/addresses/missing-links with no limit (F2)',
      () async {
    final interceptor = _CaptureInterceptor();
    interceptor.responseBody = <Map<String, dynamic>>[
      {'deliveryAddress': '12 Nguyễn Huệ, Q1', 'orderCount': 5},
      {'deliveryAddress': '45 Lê Lợi', 'orderCount': 2},
    ];
    final dio = Dio()..interceptors.add(interceptor);
    final service = AddressService(dio);

    final items = await service.missingLinks();

    expect(interceptor.method, 'GET');
    expect(interceptor.path, '/api/addresses/missing-links');
    expect(interceptor.queryParameters, isNot(contains('limit')));
    expect(items, hasLength(2));
    expect(items.first.deliveryAddress, '12 Nguyễn Huệ, Q1');
    expect(items.first.orderCount, 5);
    expect(items.last.deliveryAddress, '45 Lê Lợi');
    expect(items.last.orderCount, 2);
  });

  test('missingLinks forwards limit query parameter when supplied', () async {
    final interceptor = _CaptureInterceptor();
    interceptor.responseBody = const <Map<String, dynamic>>[];
    final dio = Dio()..interceptors.add(interceptor);
    final service = AddressService(dio);

    await service.missingLinks(limit: 50);

    expect(interceptor.queryParameters, containsPair('limit', 50));
  });

  test('missingLinks returns empty list when backend responds with []', () async {
    final interceptor = _CaptureInterceptor();
    interceptor.responseBody = const <Map<String, dynamic>>[];
    final dio = Dio()..interceptors.add(interceptor);
    final service = AddressService(dio);

    final items = await service.missingLinks();

    expect(items, isEmpty);
  });

  test('missingLinks deserializes MissingLinkItem fields (F1)', () async {
    final interceptor = _CaptureInterceptor();
    interceptor.responseBody = <Map<String, dynamic>>[
      {'deliveryAddress': 'Đường Thần Kê', 'orderCount': 11},
    ];
    final dio = Dio()..interceptors.add(interceptor);
    final service = AddressService(dio);

    final items = await service.missingLinks();

    expect(items.single, isA<MissingLinkItem>());
    expect(items.single.deliveryAddress, 'Đường Thần Kê');
    expect(items.single.orderCount, 11);
  });
}