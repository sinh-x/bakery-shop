import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/event_photo.dart';

/// State for the expense-history photo strip (DG-404 Phase 4.1 / FR2).
///
/// Owns the loaded photos list, the loading flag, and the last-fetched
/// event id (de-dupe guard) previously held as `setState` fields inside
/// `_ExpenseHistoryPhotoStripState`.
class ExpenseHistoryPhotoState {
  const ExpenseHistoryPhotoState({
    this.photos = const <EventPhoto>[],
    this.loading = true,
    this.lastFetchedEventId,
  });

  final List<EventPhoto> photos;
  final bool loading;
  final int? lastFetchedEventId;

  ExpenseHistoryPhotoState copyWith({
    List<EventPhoto>? photos,
    bool? loading,
    int? lastFetchedEventId,
  }) {
    return ExpenseHistoryPhotoState(
      photos: photos ?? this.photos,
      loading: loading ?? this.loading,
      lastFetchedEventId: lastFetchedEventId ?? this.lastFetchedEventId,
    );
  }
}

/// `Notifier` that owns the photo-strip state for a single event
/// (DG-404 Phase 4.1 / FR2). Keyed by the event id via a family
/// provider so each card in the list maintains its own strip state.
/// Following the codebase convention for `NotifierProvider.family`
/// (arg as constructor param, see `BlankStockLogNotifier`).
class ExpenseHistoryPhotoNotifier extends Notifier<ExpenseHistoryPhotoState> {
  final int eventId;

  ExpenseHistoryPhotoNotifier(this.eventId);

  @override
  ExpenseHistoryPhotoState build() => const ExpenseHistoryPhotoState();

  void setPhotos(List<EventPhoto> photos) => state = state.copyWith(
        photos: photos,
        loading: false,
        lastFetchedEventId: eventId,
      );

  void setLoading(bool value) => state = state.copyWith(loading: value);
}

/// Family provider for the photo-strip state, keyed by event id.
final expenseHistoryPhotoProvider =
    NotifierProvider.family<ExpenseHistoryPhotoNotifier,
        ExpenseHistoryPhotoState, int>(ExpenseHistoryPhotoNotifier.new);