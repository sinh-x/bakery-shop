import 'package:bakery_app/data/api/event_service.dart';
import 'package:bakery_app/data/mappers/expense_event_mapper.dart';
import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/providers/events_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEventService extends EventService {
  _FakeEventService() : super(Dio());

  final List<BakeryEvent> _store = <BakeryEvent>[
    BakeryEvent(
      id: 1,
      timestamp: DateTime.parse('2026-05-23T09:00:00Z'),
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
      timestamp: DateTime.parse('2026-05-23T11:00:00Z'),
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

  @override
  Future<List<BakeryEvent>> listEvents({
    String? type,
    String? tag,
    String? search,
    String? since,
    String? until,
    String? loggedBy,
    int limit = 50,
  }) async {
    return List<BakeryEvent>.from(
      _store.where((item) => type == null || item.type == type).take(limit),
    );
  }

  @override
  Future<BakeryEvent> updateEvent(
    int id, {
    String? summary,
    String? type,
    List<String>? tags,
    String? loggedBy,
    Map<String, dynamic>? data,
  }) async {
    final index = _store.indexWhere((item) => item.id == id);
    final updated = _store[index].copyWith(
      summary: summary ?? _store[index].summary,
      data: data ?? _store[index].data,
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
}
