import 'package:bakery_app/data/api/catalog_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _CaptureInterceptor extends Interceptor {
  String? method;
  String? path;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    method = options.method;
    path = options.path;
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: const <String, dynamic>{},
      ),
    );
  }
}

void main() {
  test('promoteCatalogPhoto calls backend promote endpoint', () async {
    final interceptor = _CaptureInterceptor();
    final dio = Dio()..interceptors.add(interceptor);
    final service = CatalogService(dio);

    await service.promoteCatalogPhoto(12, 34);

    expect(interceptor.method, 'POST');
    expect(interceptor.path, '/api/products/12/catalog/34/promote');
  });
}
