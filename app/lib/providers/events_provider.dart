import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/event_service.dart';
import '../data/mappers/expense_event_mapper.dart';
import '../data/models/event.dart';
import '../features/auth/auth_provider.dart';
import '../shared/utils/date_formatting.dart';

const kLoggedByKey = 'logged_by_name';

/// Provider for the staff member logging events (FR17).
///
/// Previously this was a free-text field the user typed in the Settings
/// screen. As of DG-029 Phase 6 it derives from the authenticated identity
/// in the JWT token: when the user is logged in, `loggedByProvider` returns
/// the JWT `sub` claim (the username). When unauthenticated it returns an
/// empty string — preserving the pre-auth behavior so the app still functions
/// during the `AUTH_REQUIRED=false` grace period (NFR6).
///
/// The old `setName` API is retained as a no-op so existing call sites
/// (`ref.read(loggedByProvider.notifier).setName(...)`) compile without
/// changes; the value is now read-only and sourced from [authProvider].
final loggedByProvider = NotifierProvider<LoggedByNotifier, String>(
  LoggedByNotifier.new,
);

class LoggedByNotifier extends Notifier<String> {
  @override
  String build() {
    final auth = ref.watch(authProvider);
    return auth.username ?? '';
  }

  /// Deprecated no-op (FR17). The logger identity is now sourced from the
  /// authenticated JWT and cannot be set manually. Retained for source
  /// compatibility with existing call sites.
  Future<void> setName(String name) async {}
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
    String? debtStatus,
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
      expenseDebtStatus: debtStatus,
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
    final local = ServerTimezone.toServerLocal(timestamp);
    if (since != null && local.isBefore(since)) {
      return false;
    }
    if (until != null && local.isAfter(until)) {
      return false;
    }
    return true;
  }

  DateTime? _parseLocalDateTimeOrNull(String? iso) =>
      parseApiDateTime(iso) == null
          ? null
          : ServerTimezone.toServerLocal(parseApiDateTime(iso)!);

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

/// Provider that returns distinct, non-empty vendor names from recent
/// expense events. Used by the expense form for creditor/vendor
/// autocomplete (DG-212 Phase 3 — FR2).
final expenseVendorSuggestionsProvider =
    FutureProvider<List<String>>((ref) async {
  final service = ref.read(eventServiceProvider);
  final events = await service.listEvents(type: expenseType, limit: 500);
  final names = events
      .map(ExpenseEventMapper.fromEvent)
      .whereType<ExpenseEventData>()
      .map((e) => e.vendor.trim())
      .where((name) => name.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return names;
});

/// Notifier that loads outstanding debts grouped by creditor (DG-212 Phase
/// 4 — FR5). Wraps [EventService.listDebts] and exposes the raw decoded
/// response so the debts list screen can render grouped creditors.
class DebtsNotifier extends AsyncNotifier<Map<String, dynamic>> {
  @override
  Future<Map<String, dynamic>> build() async => const <String, dynamic>{
        'creditors': <Map<String, dynamic>>[],
        'total_owed': 0.0,
        'count': 0,
      };

  /// Reload debts with optional filters. Returns the parsed response.
  Future<Map<String, dynamic>> reload({
    String? creditor,
    String? since,
    String? until,
    String? status,
  }) async {
    final service = ref.read(eventServiceProvider);
    final data = await service.listDebts(
      creditor: creditor,
      since: since,
      until: until,
      status: status,
    );
    state = AsyncData(data);
    return data;
  }
}

final debtsProvider =
    AsyncNotifierProvider<DebtsNotifier, Map<String, dynamic>>(
  DebtsNotifier.new,
);
