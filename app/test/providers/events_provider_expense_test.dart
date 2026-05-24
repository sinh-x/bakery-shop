import 'package:bakery_app/data/api/event_service.dart';
import 'package:bakery_app/data/mappers/expense_event_mapper.dart';
import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/providers/events_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEventService extends EventService {
  /// Test fake contract:
  /// - Only [listEvents], [updateEvent], and [deleteEvent] are used by tests.
  /// - Any other inherited API call is out of scope for this fake.
  _FakeEventService() : super(Dio());

  bool applyRemoteFilters = true;
  String? capturedSince;
  String? capturedUntil;

  final List<BakeryEvent> _store = <BakeryEvent>[
    BakeryEvent(
      id: 1,
      timestamp: DateTime(2026, 5, 23, 9, 0),
      type: expenseType,
      summary: 'Chi phi bot',
      data: const {
        'amount_vnd': 120000,
        'category': 'Nguyên liệu',
        'payment_method': 'Tiền mặt',
        'vendor': 'NCC A',
        'note': 'Bột mì',
        'staff_name': 'Lan',
      },
    ),
    BakeryEvent(
      id: 2,
      timestamp: DateTime(2026, 5, 23, 11, 0),
      type: expenseType,
      summary: 'Chi phi van chuyen',
      data: const {
        'amount_vnd': 80000,
        'category': 'Vận chuyển',
        'payment_method': 'Chuyển khoản',
        'vendor': 'NCC B',
        'note': 'Xe giao hàng',
        'staff_name': 'Minh',
      },
    ),
  ];
  DateTime? capturedCreateTimestamp;
  DateTime? capturedUpdateTimestamp;

  @override
  Future<BakeryEvent> createEvent({
    required String summary,
    String type = 'note',
    List<String> tags = const [],
    String loggedBy = '',
    Map<String, dynamic> data = const {},
    String source = 'app',
    DateTime? timestamp,
  }) async {
    capturedCreateTimestamp = timestamp;
    final nextId =
        _store.map((e) => e.id).fold<int>(0, (a, b) => a > b ? a : b) + 1;
    final created = BakeryEvent(
      id: nextId,
      timestamp: timestamp ?? DateTime.parse('2026-05-23T12:00:00Z'),
      type: type,
      summary: summary,
      tags: tags,
      loggedBy: loggedBy,
      source: source,
      data: data,
    );
    _store.insert(0, created);
    return created;
  }

  @override
  Future<List<BakeryEvent>> listEvents({
    String? type,
    String? tag,
    String? search,
    String? since,
    String? until,
    String? loggedBy,
    String? expenseCategory,
    String? expensePaymentMethod,
    String? expenseStaffName,
    String? expenseSearch,
    int limit = 50,
  }) async {
    capturedSince = since;
    capturedUntil = until;
    var items = _store.where((item) => type == null || item.type == type);
    if (applyRemoteFilters &&
        expenseCategory != null &&
        expenseCategory.isNotEmpty) {
      items = items.where((item) => item.data['category'] == expenseCategory);
    }
    if (applyRemoteFilters &&
        expensePaymentMethod != null &&
        expensePaymentMethod.isNotEmpty) {
      items = items.where(
        (item) => item.data['payment_method'] == expensePaymentMethod,
      );
    }
    if (applyRemoteFilters &&
        expenseStaffName != null &&
        expenseStaffName.isNotEmpty) {
      final query = expenseStaffName.toLowerCase();
      items = items.where(
        (item) =>
            '${item.data['staff_name'] ?? ''}'.toLowerCase().contains(query),
      );
    }
    if (applyRemoteFilters &&
        expenseSearch != null &&
        expenseSearch.isNotEmpty) {
      final query = expenseSearch.toLowerCase();
      items = items.where((item) {
        final haystack = <String>[
          item.summary,
          '${item.data['vendor'] ?? ''}',
          '${item.data['note'] ?? ''}',
          '${item.data['staff_name'] ?? ''}',
        ].join(' ').toLowerCase();
        return haystack.contains(query);
      });
    }
    return List<BakeryEvent>.from(items.take(limit));
  }

  @override
  Future<BakeryEvent> updateEvent(
    int id, {
    String? summary,
    String? type,
    List<String>? tags,
    String? loggedBy,
    Map<String, dynamic>? data,
    DateTime? timestamp,
  }) async {
    capturedUpdateTimestamp = timestamp;
    final index = _store.indexWhere((item) => item.id == id);
    final updated = _store[index].copyWith(
      summary: summary ?? _store[index].summary,
      data: data ?? _store[index].data,
      timestamp: timestamp ?? _store[index].timestamp,
    );
    _store[index] = updated;
    return updated;
  }

  @override
  Future<void> deleteEvent(int id) async {
    _store.removeWhere((item) => item.id == id);
  }
}

void main() {
  test('loadExpenseHistory applies filters and returns newest first', () async {
    final service = _FakeEventService();
    final container = ProviderContainer(
      overrides: [eventServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(eventsProvider.notifier);
    final results = await notifier.loadExpenseHistory(
      category: 'Vận chuyển',
      paymentMethod: 'Chuyển khoản',
      staffName: 'Minh',
      searchText: 'xe',
    );

    expect(results, hasLength(1));
    expect(results.first.id, 2);
  });

  test(
    'loadExpenseHistory applies category filter locally when API ignores it',
    () async {
      final service = _FakeEventService()..applyRemoteFilters = false;
      final container = ProviderContainer(
        overrides: [eventServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(eventsProvider.notifier);
      final results = await notifier.loadExpenseHistory(category: 'Không khớp');

      expect(results, isEmpty);
    },
  );

  test(
    'loadExpenseHistory applies staff filter locally when API ignores it',
    () async {
      final service = _FakeEventService()..applyRemoteFilters = false;
      final container = ProviderContainer(
        overrides: [eventServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(eventsProvider.notifier);
      final results = await notifier.loadExpenseHistory(
        staffName: 'Không khớp',
      );

      expect(results, isEmpty);
    },
  );

  test(
    'updateEvent and deleteEvent mutate local provider state only',
    () async {
      final service = _FakeEventService();
      final container = ProviderContainer(
        overrides: [eventServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(eventsProvider.notifier);
      await container.read(eventsProvider.future);

      await notifier.updateEvent(
        id: 1,
        summary: 'Chi phi bot cap nhat',
        data: const {
          'amount_vnd': 140000,
          'category': 'Nguyên liệu',
          'payment_method': 'Tiền mặt',
          'vendor': 'NCC A',
          'note': 'Bột mì mới',
          'staff_name': 'Lan',
        },
      );

      var state = container.read(eventsProvider).requireValue;
      expect(state.first.summary, 'Chi phi bot cap nhat');

      await notifier.deleteEvent(1);
      state = container.read(eventsProvider).requireValue;
      expect(state.map((item) => item.id), isNot(contains(1)));
    },
  );

  test(
    'logEvent and updateEvent pass selected timestamp to API layer',
    () async {
      final service = _FakeEventService();
      final container = ProviderContainer(
        overrides: [eventServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(eventsProvider.notifier);
      final createdAt = DateTime(2026, 5, 23, 19, 57);
      await notifier.logEvent(
        summary: 'Chi phí mới',
        type: expenseType,
        loggedBy: 'Lan',
        data: const {
          'amount_vnd': 200000,
          'category': 'Nguyên liệu',
          'payment_method': 'Tiền mặt',
          'vendor': 'NCC A',
          'note': 'Bơ sữa',
          'staff_name': 'Lan',
        },
        timestamp: createdAt,
      );
      expect(service.capturedCreateTimestamp, createdAt);

      final updatedAt = DateTime(2026, 5, 24, 8, 15);
      await notifier.updateEvent(
        id: 1,
        summary: 'Chi phí cập nhật',
        data: const {
          'amount_vnd': 150000,
          'category': 'Nguyên liệu',
          'payment_method': 'Tiền mặt',
          'vendor': 'NCC A',
          'note': 'Bơ',
          'staff_name': 'Lan',
        },
        timestamp: updatedAt,
      );
      expect(service.capturedUpdateTimestamp, updatedAt);
    },
  );

  test(
    'loadExpenseHistory applies local since/until range in provider',
    () async {
      final service = _FakeEventService();
      final container = ProviderContainer(
        overrides: [eventServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(eventsProvider.notifier);
      final results = await notifier.loadExpenseHistory(
        since: '2026-05-23T08:30:00',
        until: '2026-05-23T09:30:00',
      );

      expect(results, hasLength(1));
      expect(results.first.id, 1);
    },
  );

  test('loadExpenseHistory does not send since/until to API query', () async {
    final service = _FakeEventService();
    final container = ProviderContainer(
      overrides: [eventServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(eventsProvider.notifier);
    await notifier.loadExpenseHistory(
      since: '2026-05-23T00:00:00',
      until: '2026-05-23T23:59:59.999',
    );

    expect(service.capturedSince, isNull);
    expect(service.capturedUntil, isNull);
  });
}
