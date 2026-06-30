import 'package:bakery_app/data/api/config_service.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart'
    show
        currentServerTimezoneOffset,
        kDefaultServerTimezoneOffset,
        setServerTimezoneOffset;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

class _JsonInterceptor extends Interceptor {
  final Map<String, dynamic> payload;

  _JsonInterceptor(this.payload);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: payload,
      ),
    );
  }
}

class _ErrorInterceptor extends Interceptor {
  final DioException error;

  _ErrorInterceptor(this.error);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.reject(error);
  }
}

void main() {
  group('ServerConfig.fromJson', () {
    test('parses timezone_offset from server payload', () {
      const json = <String, dynamic>{
        'timezone': 'Asia/Ho_Chi_Minh',
        'timezone_offset': '+07:00',
      };

      final config = ServerConfig.fromJson(json);

      expect(config.timezoneOffset, '+07:00');
    });

    test('uses timezone_offset only (timezone field ignored)', () {
      const json = <String, dynamic>{
        'timezone_offset': '-05:00',
      };

      final config = ServerConfig.fromJson(json);

      expect(config.timezoneOffset, '-05:00');
    });
  });

  group('ConfigService.getServerConfig', () {
    test('returns ServerConfig parsed from /api/config response', () async {
      final interceptor = _JsonInterceptor(const <String, dynamic>{
        'timezone': 'Asia/Ho_Chi_Minh',
        'timezone_offset': '+07:00',
      });
      final dio = Dio()..interceptors.add(interceptor);
      final service = ConfigService(dio);

      final config = await service.getServerConfig();

      expect(config.timezoneOffset, '+07:00');
    });

    test('sends request to /api/config', () async {
      final captured = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              captured.add(options);
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <String, dynamic>{'timezone_offset': '+07:00'},
                ),
              );
            },
          ),
        );
      final service = ConfigService(dio);

      await service.getServerConfig();

      expect(captured, hasLength(1));
      expect(captured.single.path, '/api/config');
      expect(captured.single.method, 'GET');
    });

    test('sets an explicit receiveTimeout on the request options', () async {
      final captured = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              captured.add(options);
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <String, dynamic>{'timezone_offset': '+07:00'},
                ),
              );
            },
          ),
        );
      final service = ConfigService(dio);

      await service.getServerConfig();

      expect(captured, hasLength(1));
      expect(captured.single.receiveTimeout, const Duration(seconds: 4));
    });
  });

  group('initServerTimezone', () {
    test('updates server offset when fetch succeeds', () async {
      addTearDown(() =>
          setServerTimezoneOffset(kDefaultServerTimezoneOffset));

      final dio = Dio()
        ..interceptors.add(_JsonInterceptor(const <String, dynamic>{
          'timezone_offset': '+03:00',
        }));
      final service = ConfigService(dio);

      await initServerTimezone(service);

      expect(currentServerTimezoneOffset, '+03:00');
    });

    test('keeps default offset when fetch fails', () async {
      addTearDown(() =>
          setServerTimezoneOffset(kDefaultServerTimezoneOffset));
      setServerTimezoneOffset(kDefaultServerTimezoneOffset);

      final dio = Dio()
        ..interceptors.add(_ErrorInterceptor(
          DioException(
            requestOptions: RequestOptions(path: '/api/config'),
            type: DioExceptionType.connectionTimeout,
          ),
        ));
      final service = ConfigService(dio);

      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) logs.add(message);
      };
      try {
        await initServerTimezone(service);
      } finally {
        debugPrint = original;
      }

      expect(currentServerTimezoneOffset, kDefaultServerTimezoneOffset);
      expect(logs, anyElement(contains('initServerTimezone: fetch failed')));
    });
  });
}