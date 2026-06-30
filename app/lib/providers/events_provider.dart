import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/api_client.dart';
import '../data/api/event_service.dart';
import '../data/mappers/expense_event_mapper.dart';
import '../data/models/event.dart';
import '../shared/utils/date_formatting.dart';

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
    DateTime? timestamp,
    int? orderId,
  }) async {
    final service = ref.read(eventServiceProvider);
    final event = await service.createEvent(
      summary: summary,
      type: type,
      tags: tags,
      loggedBy: loggedBy,
      data: data,
      source: 'app',
      timestamp: timestamp,
      orderId: orderId,
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
    DateTime? timestamp,
  }) async {
    final service = ref.read(eventServiceProvider);
    final updated = await service.updateEvent(
      id,
      summary: summary,
      type: type,
      tags: tags,
      loggedBy: loggedBy,
      data: data,
      timestamp: timestamp,
    );
    state = state.whenData(
      (events) => events.map((e) => e.id == id ? updated : e).toList(),
    );
  }

  Future<void> deleteEvent(int id, {String deletedBy = ''}) async {
    final service = ref.read(eventServiceProvider);
    await service.deleteEvent(id, deletedBy: deletedBy);
    state = state.whenData(
      (events) => events.where((e) => e.id != id).toList(),
    );
  }

  Future<List<BakeryEvent>> loadExpenseHistory({
    String? since,
    String? until,
    String? category,
    String? paymentMethod,
    String? paymentSource,
    String? staffName,
    String? paidByName,
    String? loggedBy,
    String? searchText,
    int limit = expenseMaxHistoryLimit,
  }) async {
    final service = ref.read(eventServiceProvider);
    final safeLimit = limit.clamp(1, expenseMaxHistoryLimit);
    final events = await service.listEvents(
      type: expenseType,
      expenseCategory: category,
      expensePaymentMethod: paymentMethod,
      expensePaymentSource: paymentSource,
      loggedBy: loggedBy ?? staffName,
      expensePaidByName: paidByName,
      expenseSearch: searchText,
      limit: safeLimit,
    );
    final sinceLocal = _parseLocalDateTimeOrNull(since);
    final untilLocal = _parseLocalDateTimeOrNull(until);

    final filtered = events.where(
      (event) =>
          ExpenseEventMapper.matchesFilters(
            event,
            category: category,
            paymentMethod: paymentMethod,
            paymentSource: paymentSource,
            staffName: staffName,
            paidByName: paidByName,
            loggedBy: loggedBy,
            searchText: searchText,
          ) &&
          _matchesLocalDateRange(
            event.timestamp,
            since: sinceLocal,
            until: untilLocal,
          ),
    );
    final sorted = filtered.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted;
  }

  bool _matchesLocalDateRange(
    DateTime timestamp, {
    DateTime? since,
    DateTime? until,
  }) {
    final local = timestamp.toLocal();
    if (since != null && local.isBefore(since)) {
      return false;
    }
    if (until != null && local.isAfter(until)) {
      return false;
    }
    return true;
  }

  DateTime? _parseLocalDateTimeOrNull(String? iso) =>
      parseApiDateTime(iso)?.toLocal();

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

  String _todayIso() => formatApiDate(DateTime.now());
}

final eventsProvider = AsyncNotifierProvider<EventsNotifier, List<BakeryEvent>>(
  EventsNotifier.new,
);
