import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/template_service.dart';
import 'package:bakery_app/data/models/message_template.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Captures the last request body and method for a given path prefix.
class _RecordingInterceptor extends Interceptor {
  _RecordingInterceptor(this._responses);

  /// Maps a method+path regex to a canned response. Keys look like
  /// ``GET /api/templates`` or ``POST /api/templates``.
  final Map<String, Map<String, dynamic>> _responses;
  String? lastMethod;
  String? lastPath;
  Map<String, dynamic>? lastBody;
  Map<String, dynamic>? lastQuery;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    lastMethod = options.method;
    lastPath = options.path;
    final data = options.data;
    lastBody = data is Map<String, dynamic> ? data : null;
    lastQuery = Map<String, dynamic>.from(options.queryParameters);

    final key = '${options.method} ${options.path}';
    if (_responses.containsKey(key)) {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: _responses[key],
        ),
      );
      return;
    }

    // 204 No Content for DELETE.
    if (options.method == 'DELETE' &&
        RegExp(r'^/api/templates/\d+$').hasMatch(options.path)) {
      handler.resolve(
        Response(requestOptions: options, statusCode: 204),
      );
      return;
    }

    // 200 with empty body for list calls returning arrays.
    if (options.method == 'GET' && options.path == '/api/templates') {
      handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: <Map<String, dynamic>>[],
        ),
      );
      return;
    }

    handler.next(options);
  }
}

Map<String, dynamic> _templateJson({
  int id = 1,
  String scenario = 'ask_info',
  String name = 'Hỏi thông tin đặt bánh',
  String body = 'Dạ mình đặt bánh khi nào lấy ạ?',
  bool isSystem = true,
  int? createdByStaffId,
  int sortOrder = 1,
  bool active = true,
}) {
  return MessageTemplate(
    id: id,
    scenario: scenario,
    name: name,
    body: body,
    isSystem: isSystem,
    createdByStaffId: createdByStaffId,
    sortOrder: sortOrder,
    active: active,
  ).toJson();
}

void main() {
  group('TemplateService (DG-375 Phase 2)', () {
    test('listTemplates GETs /api/templates and parses response', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.interceptors.add(_RecordingInterceptor({}));
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final service = container.read(templateServiceProvider);
      final result = await service.listTemplates();

      expect(result, isEmpty);
    });

    test('listTemplates sends scenario query when provided', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final interceptor = _RecordingInterceptor({});
      dio.interceptors.add(interceptor);
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final service = container.read(templateServiceProvider);
      await service.listTemplates(scenario: 'confirm_order');

      expect(interceptor.lastMethod, 'GET');
      expect(interceptor.lastPath, '/api/templates');
      expect(interceptor.lastQuery?['scenario'], 'confirm_order');
    });

    test('listTemplates omits scenario query when not provided', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final interceptor = _RecordingInterceptor({});
      dio.interceptors.add(interceptor);
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final service = container.read(templateServiceProvider);
      await service.listTemplates();

      expect(interceptor.lastQuery?['scenario'], isNull);
    });

    test('createTemplate POSTs payload with all fields', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final interceptor = _RecordingInterceptor({
        'POST /api/templates': _templateJson(id: 10, name: 'New template'),
      });
      dio.interceptors.add(interceptor);
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final service = container.read(templateServiceProvider);
      final created = await service.createTemplate(
        scenario: 'ask_info',
        name: 'New template',
        body: 'Body text',
        isSystem: true,
        sortOrder: 5,
        active: true,
      );

      expect(interceptor.lastMethod, 'POST');
      expect(interceptor.lastPath, '/api/templates');
      expect(interceptor.lastBody?['scenario'], 'ask_info');
      expect(interceptor.lastBody?['name'], 'New template');
      expect(interceptor.lastBody?['body'], 'Body text');
      expect(interceptor.lastBody?['is_system'], isTrue);
      expect(interceptor.lastBody?['sort_order'], 5);
      expect(interceptor.lastBody?['active'], isTrue);
      expect(created.id, 10);
      expect(created.name, 'New template');
    });

    test('updateTemplate PATCHes only provided fields', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final interceptor = _RecordingInterceptor({
        'PATCH /api/templates/3': _templateJson(id: 3, name: 'Updated'),
      });
      dio.interceptors.add(interceptor);
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final service = container.read(templateServiceProvider);
      final updated = await service.updateTemplate(
        3,
        name: 'Updated',
        active: false,
      );

      expect(interceptor.lastMethod, 'PATCH');
      expect(interceptor.lastPath, '/api/templates/3');
      expect(interceptor.lastBody?['name'], 'Updated');
      expect(interceptor.lastBody?['active'], isFalse);
      expect(interceptor.lastBody?.containsKey('body'), isFalse);
      expect(interceptor.lastBody?.containsKey('scenario'), isFalse);
      expect(updated.id, 3);
    });

    test('deleteTemplate DELETEs /api/templates/{id}', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      final interceptor = _RecordingInterceptor({});
      dio.interceptors.add(interceptor);
      final container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      final service = container.read(templateServiceProvider);
      await service.deleteTemplate(7);

      expect(interceptor.lastMethod, 'DELETE');
      expect(interceptor.lastPath, '/api/templates/7');
    });
  });

  group('allowedTemplateScenarios', () {
    test('contains the six allowed scenario slugs', () {
      expect(allowedTemplateScenarios, contains('ask_info'));
      expect(allowedTemplateScenarios, contains('confirm_order'));
      expect(allowedTemplateScenarios, contains('final_message'));
      expect(allowedTemplateScenarios, contains('follow_up'));
      expect(allowedTemplateScenarios, contains('status_update'));
      expect(allowedTemplateScenarios, contains('payment_request'));
      expect(allowedTemplateScenarios.length, 6);
    });
  });
}