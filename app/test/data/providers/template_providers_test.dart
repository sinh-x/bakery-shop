import 'package:bakery_app/data/api/template_service.dart';
import 'package:bakery_app/data/models/message_template.dart';
import 'package:bakery_app/data/providers/template_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTemplateService extends TemplateService {
  _FakeTemplateService() : super(Dio());

  final List<MessageTemplate> _store = <MessageTemplate>[];
  int _nextId = 100;
  bool failNextList = false;

  @override
  Future<List<MessageTemplate>> listTemplates({String? scenario}) async {
    if (failNextList) {
      failNextList = false;
      throw DioException(
        requestOptions: RequestOptions(path: '/api/templates'),
        type: DioExceptionType.connectionError,
      );
    }
    if (scenario != null) {
      return _store.where((t) => t.scenario == scenario).toList();
    }
    return List<MessageTemplate>.from(_store);
  }

  @override
  Future<MessageTemplate> createTemplate({
    required String scenario,
    required String name,
    required String body,
    bool isSystem = false,
    int sortOrder = 0,
    bool active = true,
  }) async {
    final created = MessageTemplate(
      id: _nextId++,
      scenario: scenario,
      name: name,
      body: body,
      isSystem: isSystem,
      sortOrder: sortOrder,
      active: active,
    );
    _store.add(created);
    return created;
  }

  @override
  Future<MessageTemplate> updateTemplate(
    int id, {
    String? scenario,
    String? name,
    String? body,
    bool? isSystem,
    int? sortOrder,
    bool? active,
  }) async {
    final idx = _store.indexWhere((t) => t.id == id);
    if (idx == -1) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/templates/$id'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/templates/$id'),
          statusCode: 404,
        ),
      );
    }
    final updated = _store[idx].copyWith(
      scenario: scenario ?? _store[idx].scenario,
      name: name ?? _store[idx].name,
      body: body ?? _store[idx].body,
      isSystem: isSystem ?? _store[idx].isSystem,
      sortOrder: sortOrder ?? _store[idx].sortOrder,
      active: active ?? _store[idx].active,
    );
    _store[idx] = updated;
    return updated;
  }

  @override
  Future<void> deleteTemplate(int id) async {
    _store.removeWhere((t) => t.id == id);
  }
}

void main() {
  group('TemplateListNotifier (DG-375 Phase 2)', () {
    test('build returns fetched templates from backend', () async {
      final fake = _FakeTemplateService();
      final container = ProviderContainer(
        overrides: [templateServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      await fake.createTemplate(
        scenario: 'ask_info',
        name: 'Hỏi',
        body: 'Body',
      );
      final templates = await container.read(templateListProvider.future);

      expect(templates, hasLength(1));
      expect(templates.first.name, 'Hỏi');
    });

    test('build falls back to defaultTemplatesFallback when backend fails',
        () async {
      final fake = _FakeTemplateService();
      fake.failNextList = true;
      final container = ProviderContainer(
        overrides: [templateServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      final templates = await container.read(templateListProvider.future);

      expect(templates, hasLength(8));
      expect(templates.first.scenario, 'ask_info');
      expect(templates.any((t) => t.name == 'Yêu cầu thanh toán'), isTrue);
      expect(templates.every((t) => t.isSystem), isTrue);
    });

    test('refresh falls back to bundled defaults on error', () async {
      final fake = _FakeTemplateService();
      final container = ProviderContainer(
        overrides: [templateServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      // Seed the list with one backend template.
      await container.read(templateListProvider.future);
      final notifier = container.read(templateListProvider.notifier);
      await fake.createTemplate(
        scenario: 'ask_info',
        name: 'Hỏi',
        body: 'Body',
      );
      await notifier.refresh();
      expect(container.read(templateListProvider).value, hasLength(1));

      // Trigger an error on refresh -> should fall back to bundled defaults.
      fake.failNextList = true;
      await notifier.refresh();

      final value = container.read(templateListProvider).value;
      expect(value, hasLength(8));
      expect(value!.every((t) => t.isSystem), isTrue);
    });

    test('createTemplate appends new template to list state', () async {
      final fake = _FakeTemplateService();
      final container = ProviderContainer(
        overrides: [templateServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(templateListProvider.notifier);
      await container.read(templateListProvider.future);

      final created = await notifier.createTemplate(
        scenario: 'follow_up',
        name: 'Cảm ơn',
        body: 'Cảm ơn mình ạ!',
        isSystem: false,
        sortOrder: 0,
      );

      expect(created.id, greaterThan(0));
      final templates = container.read(templateListProvider).value;
      expect(templates, hasLength(1));
      expect(templates!.last.name, 'Cảm ơn');
    });

    test('updateTemplate replaces the matching entry in list state', () async {
      final fake = _FakeTemplateService();
      final container = ProviderContainer(
        overrides: [templateServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(templateListProvider.notifier);
      await container.read(templateListProvider.future);

      final created = await notifier.createTemplate(
        scenario: 'ask_info',
        name: 'Old',
        body: 'Old body',
      );

      final updated = await notifier.updateTemplate(
        created.id,
        name: 'New',
        body: 'New body',
      );

      expect(updated.name, 'New');
      final templates = container.read(templateListProvider).value;
      expect(templates, hasLength(1));
      expect(templates!.first.name, 'New');
      expect(templates.first.body, 'New body');
    });

    test('deleteTemplate removes the entry from list state', () async {
      final fake = _FakeTemplateService();
      final container = ProviderContainer(
        overrides: [templateServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(templateListProvider.notifier);
      await container.read(templateListProvider.future);

      final created = await notifier.createTemplate(
        scenario: 'ask_info',
        name: 'To delete',
        body: 'Body',
      );
      expect(container.read(templateListProvider).value, hasLength(1));

      await notifier.deleteTemplate(created.id);

      final templates = container.read(templateListProvider).value;
      expect(templates, isEmpty);
    });
  });

  group('defaultTemplatesFallback', () {
    test('contains exactly 8 default templates across 6 scenarios', () {
      expect(defaultTemplatesFallback, hasLength(8));

      final scenarios = defaultTemplatesFallback.map((t) => t.scenario).toSet();
      expect(scenarios, contains('ask_info'));
      expect(scenarios, contains('confirm_order'));
      expect(scenarios, contains('final_message'));
      expect(scenarios, contains('follow_up'));
      expect(scenarios, contains('status_update'));
      expect(scenarios, contains('payment_request'));
      expect(scenarios.length, 6);
    });

    test('all bundled defaults are system templates with negative ids', () {
      for (final t in defaultTemplatesFallback) {
        expect(t.isSystem, isTrue, reason: '${t.name} should be system');
        expect(t.active, isTrue, reason: '${t.name} should be active');
        expect(t.id, lessThan(0), reason: '${t.name} should have a sentinel id');
      }
    });

    test('confirm_order scenario contains 3 templates (pickup/delivery/bus)',
        () {
      final confirmOrder =
          defaultTemplatesFallback.where((t) => t.scenario == 'confirm_order');
      expect(confirmOrder, hasLength(3));
      expect(
        confirmOrder.map((t) => t.name),
        containsAll([
          'Xác nhận đơn — Pickup',
          'Xác nhận đơn — Delivery',
          'Xác nhận đơn — Gửi xe buýt',
        ]),
      );
    });

    test('parity with backend SEED_MESSAGE_TEMPLATES (CQ-DupSeed)', () {
      // Mirrors `SEED_MESSAGE_TEMPLATES` in
      // `src/baker/db/schema/_constants.py` (scenario, name, body, sort_order).
      // The Flutter fallback must match the backend seed on scenario + name +
      // sortOrder so the offline fallback (NFR3) shows the same templates as
      // a freshly migrated backend (FR9 / AC9).
      const backendSeed = <(String, String, int)>[
        ('ask_info', 'Hỏi thông tin đặt bánh', 1),
        ('confirm_order', 'Xác nhận đơn — Pickup', 2),
        ('confirm_order', 'Xác nhận đơn — Delivery', 3),
        ('confirm_order', 'Xác nhận đơn — Gửi xe buýt', 4),
        ('final_message', 'Bánh đã sẵn sàng', 5),
        ('follow_up', 'Cảm ơn khách hàng', 6),
        ('status_update', 'Cập nhật trạng thái đơn', 7),
        ('payment_request', 'Yêu cầu thanh toán', 8),
      ];

      expect(defaultTemplatesFallback, hasLength(backendSeed.length));
      for (var i = 0; i < backendSeed.length; i++) {
        final fallback = defaultTemplatesFallback[i];
        final (scenario, name, sortOrder) = backendSeed[i];
        expect(fallback.scenario, scenario,
            reason: 'scenario mismatch at index $i');
        expect(fallback.name, name, reason: 'name mismatch at index $i');
        expect(fallback.sortOrder, sortOrder,
            reason: 'sortOrder mismatch at index $i');
      }
    });

    test('template bodies preserve placeholder syntax (FR4)', () {
      final bodyWithPlaceholders = defaultTemplatesFallback
          .where((t) => t.scenario == 'confirm_order')
          .first
          .body;
      expect(bodyWithPlaceholders, contains('{public_order_code}'));
      expect(bodyWithPlaceholders, contains('{items_list}'));
      expect(bodyWithPlaceholders, contains('{total_price}'));
      expect(bodyWithPlaceholders, contains('{due_date}'));
      expect(bodyWithPlaceholders, contains('{due_time}'));

      final statusUpdate = defaultTemplatesFallback.firstWhere(
        (t) => t.scenario == 'status_update',
      );
      expect(
        statusUpdate.body,
        contains('{status, select: confirmed: đã xác nhận'),
      );
      expect(
        statusUpdate.body,
        contains('{delivery_type, select:'),
      );

      final paymentRequest = defaultTemplatesFallback.firstWhere(
        (t) => t.scenario == 'payment_request',
      );
      expect(paymentRequest.body, contains('{notes, if: Đã ghi chú: {notes}}'));
    });
  });
}