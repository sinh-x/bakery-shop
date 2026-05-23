import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/api_client.dart';
import '../data/api/event_service.dart';
import '../data/mappers/expense_event_mapper.dart';
import '../data/models/event.dart';

const kLoggedByKey = 'logged_by_name';

/// Provider for the saved staff name (who is logging events).
final loggedByProvider = NotifierProvider<LoggedByNotifier, String>(
  LoggedByNotifier.new,
);

class LoggedByNotifier extends Notifier<String> {
  @override
  String build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getString(kLoggedByKey) ?? '';
  }

  Future<void> setName(String name) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(kLoggedByKey, name);
    state = name;
  }
}

class EventsNotifier extends AsyncNotifier<List<BakeryEvent>> {
  @override
  Future<List<BakeryEvent>> build() async {
    final today = _todayIso();
    return _fetch(since: today);
  }

  Future<List<BakeryEvent>> _fetch({
    String? type,
    String? tag,
    String? search,
    String? since,
    String? until,
  }) async {
    final service = ref.read(eventServiceProvider);
    return service.listEvents(
      type: type,
      tag: tag,
      search: search,
      since: since,
      until: until,
    );
  }

  Future<void> logEvent({
    required String summary,
    String type = 'note',
    List<String> tags = const [],
    String loggedBy = '',
    Map<String, dynamic> data = const {},
  }) async {
    final service = ref.read(eventServiceProvider);
    final event = await service.createEvent(
      summary: summary,
      type: type,
      tags: tags,
      loggedBy: loggedBy,
      data: data,
      source: 'app',
    );
    // Prepend to current list immediately for snappy UX
    state = state.whenData((events) => [event, ...events]);
  }

  Future<void> updateEvent({
    required int id,
    String? summary,
    String? type,
    List<String>? tags,
    String? loggedBy,
    Map<String, dynamic>? data,
  }) async {
    final service = ref.read(eventServiceProvider);
    final updated = await service.updateEvent(
      id,
      summary: summary,
      type: type,
      tags: tags,
      loggedBy: loggedBy,
      data: data,
    );
    state = state.whenData(
      (events) => events.map((e) => e.id == id ? updated : e).toList(),
    );
  }

  Future<void> deleteEvent(int id) async {
    final service = ref.read(eventServiceProvider);
    await service.deleteEvent(id);
    state = state.whenData(
      (events) => events.where((e) => e.id != id).toList(),
    );
  }

  Future<List<BakeryEvent>> loadExpenseHistory({
    String? since,
    String? until,
    String? category,
    String? paymentMethod,
    String? staffName,
    String? searchText,
    int limit = expenseMaxHistoryLimit,
  }) async {
    final service = ref.read(eventServiceProvider);
    final safeLimit = limit.clamp(1, expenseMaxHistoryLimit);
    // MVP note: server-side filtering for expense-specific fields is not
    // available yet. We fetch up to expenseMaxHistoryLimit and filter locally,
    // which can miss older matching records when total expense events exceed
    // the capped fetch size.
    final events = await service.listEvents(
      type: expenseType,
      since: since,
      until: until,
      limit: safeLimit,
    );
    final filtered = events.where(
      (event) => ExpenseEventMapper.matchesFilters(
        event,
        category: category,
        paymentMethod: paymentMethod,
        staffName: staffName,
        searchText: searchText,
      ),
    );
    final sorted = filtered.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted;
  }

  Future<void> refresh({
    String? type,
    String? tag,
    String? search,
    String? since,
    String? until,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _fetch(
        type: type,
        tag: tag,
        search: search,
        since: since,
        until: until,
      ),
    );
  }

  String _todayIso() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}

final eventsProvider = AsyncNotifierProvider<EventsNotifier, List<BakeryEvent>>(
  EventsNotifier.new,
);
