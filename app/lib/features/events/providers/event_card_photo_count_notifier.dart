import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for the event-card photo count badge (DG-404 Phase 4.2 / FR2).
///
/// Owns the loaded count, the loaded flag, and the last-fetched event
/// id (de-dupe guard) previously held as `setState` fields inside
/// `_EventCardPhotoCountState`.
class EventCardPhotoCountState {
  const EventCardPhotoCountState({
    this.count = 0,
    this.loaded = false,
    this.lastFetchedEventId,
  });

  final int count;
  final bool loaded;
  final int? lastFetchedEventId;

  EventCardPhotoCountState copyWith({
    int? count,
    bool? loaded,
    int? lastFetchedEventId,
  }) {
    return EventCardPhotoCountState(
      count: count ?? this.count,
      loaded: loaded ?? this.loaded,
      lastFetchedEventId: lastFetchedEventId ?? this.lastFetchedEventId,
    );
  }
}

/// `Notifier` that owns the photo-count badge state for a single event
/// (DG-404 Phase 4.2 / FR2). Keyed by the event id via a family
/// provider so each card in the list maintains its own state.
/// Following the codebase convention for `NotifierProvider.family`
/// (arg as constructor param, see `ExpenseHistoryPhotoNotifier`).
class EventCardPhotoCountNotifier
    extends Notifier<EventCardPhotoCountState> {
  final int eventId;

  EventCardPhotoCountNotifier(this.eventId);

  @override
  EventCardPhotoCountState build() => const EventCardPhotoCountState();

  void setCount(int count) => state = state.copyWith(
        count: count,
        loaded: true,
        lastFetchedEventId: eventId,
      );

  void markLoaded() => state = state.copyWith(loaded: true);
}

/// Family provider for the photo-count badge state, keyed by event id.
final eventCardPhotoCountProvider =
    NotifierProvider.family<EventCardPhotoCountNotifier,
        EventCardPhotoCountState, int>(EventCardPhotoCountNotifier.new);