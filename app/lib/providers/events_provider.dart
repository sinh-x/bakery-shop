import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/api_client.dart';
import '../data/api/event_service.dart';
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
  }) async {
    final service = ref.read(eventServiceProvider);
    final event = await service.createEvent(
      summary: summary,
      type: type,
      tags: tags,
      loggedBy: loggedBy,
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
  }) async {
    final service = ref.read(eventServiceProvider);
    final updated = await service.updateEvent(
      id,
      summary: summary,
      type: type,
      tags: tags,
      loggedBy: loggedBy,
    );
    state = state.whenData(
      (events) => events.map((e) => e.id == id ? updated : e).toList(),
    );
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
      () => _fetch(type: type, tag: tag, search: search, since: since, until: until),
    );
  }

  String _todayIso() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}

final eventsProvider =
    AsyncNotifierProvider<EventsNotifier, List<BakeryEvent>>(
  EventsNotifier.new,
);

// ── Order-scoped events ────────────────────────────────────────────────────────

class OrderEventsNotifier extends AsyncNotifier<List<BakeryEvent>> {
  OrderEventsNotifier(this.orderRef);

  final String orderRef;

  @override
  Future<List<BakeryEvent>> build() async {
    final service = ref.read(eventServiceProvider);
    return service.getOrderEvents(orderRef);
  }

  Future<void> addRemark({
    required String summary,
    String type = 'note',
    List<String> tags = const [],
    String loggedBy = '',
  }) async {
    final service = ref.read(eventServiceProvider);
    final orderId = int.tryParse(orderRef);
    if (orderId == null) return;
    final event = await service.createEvent(
      summary: summary,
      type: type,
      tags: tags,
      loggedBy: loggedBy,
      orderId: orderId,
    );
    state = state.whenData((events) => [event, ...events]);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }
}

final orderEventsProvider =
    AsyncNotifierProvider.family<OrderEventsNotifier, List<BakeryEvent>, String>(
  (orderRef) => OrderEventsNotifier(orderRef),
);
