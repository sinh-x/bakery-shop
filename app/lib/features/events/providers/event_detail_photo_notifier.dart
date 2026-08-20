import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/event_photo.dart';

/// State for the event-detail photo section (DG-404 Phase 4.2 / FR2).
///
/// Owns the loaded photos list, loading flag, and transient error string
/// previously held as `setState` fields inside
/// `_EventDetailScreenState`.
class EventDetailPhotoState {
  const EventDetailPhotoState({
    this.photos = const <EventPhoto>[],
    this.loading = true,
    this.error,
  });

  final List<EventPhoto> photos;
  final bool loading;
  final String? error;

  EventDetailPhotoState copyWith({
    List<EventPhoto>? photos,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return EventDetailPhotoState(
      photos: photos ?? this.photos,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// `Notifier` that owns the event-detail photo state (DG-404 Phase 4.2 /
/// FR2). The widget reads [eventDetailPhotoProvider] and invokes
/// mutators; no `setState` is required.
class EventDetailPhotoNotifier extends Notifier<EventDetailPhotoState> {
  @override
  EventDetailPhotoState build() => const EventDetailPhotoState();

  void setPhotos(List<EventPhoto> photos) => state = state.copyWith(
        photos: photos,
        loading: false,
        clearError: true,
      );

  void setError(String message) => state = state.copyWith(
        error: message,
        loading: false,
      );
}

/// Provider for the event-detail photo state.
final eventDetailPhotoProvider =
    NotifierProvider<EventDetailPhotoNotifier, EventDetailPhotoState>(
  EventDetailPhotoNotifier.new,
);