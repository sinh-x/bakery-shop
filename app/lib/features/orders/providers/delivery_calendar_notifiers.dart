import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/delivery_helpers.dart';

/// Day-calendar navigation state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_date` and `_didInitialScroll` fields previously mutated via
/// `setState` inside `_DeliveryDayCalendarViewState`. The widget reads
/// [deliveryDayCalendarProvider] and invokes the notifier's [shift]/[goToday]
/// methods; no `setState` is required.
class DeliveryDayCalendarState {
  const DeliveryDayCalendarState({
    required this.date,
    this.didInitialScroll = false,
  });

  final DateTime date;
  final bool didInitialScroll;

  DeliveryDayCalendarState copyWith({
    DateTime? date,
    bool? didInitialScroll,
  }) =>
      DeliveryDayCalendarState(
        date: date ?? this.date,
        didInitialScroll: didInitialScroll ?? this.didInitialScroll,
      );
}

class DeliveryDayCalendarNotifier extends Notifier<DeliveryDayCalendarState> {
  DateTime? _initialDate;

  /// Seed the initial focus date (defaults to today when null). Called once
  /// from the widget's `initState` before any mutation. Updates the state so
  /// the seeded value is visible on the first build.
  void seedInitialDate(DateTime? initialDate) {
    _initialDate = initialDate;
    final effective = initialDate ?? DateTime.now();
    if (state.date != effective || state.didInitialScroll) {
      state = DeliveryDayCalendarState(date: effective);
    }
  }

  @override
  DeliveryDayCalendarState build() {
    final initial = _initialDate;
    return DeliveryDayCalendarState(date: initial ?? DateTime.now());
  }

  void shift(int days) => state = state.copyWith(
        date: state.date.add(Duration(days: days)),
      );

  void goToday() => state = DeliveryDayCalendarState(date: DateTime.now());

  /// Mark the initial scroll-to-current-time as performed so it does not
  /// re-run on every rebuild.
  void markInitialScrollDone() =>
      state = state.copyWith(didInitialScroll: true);
}

final deliveryDayCalendarProvider =
    NotifierProvider<DeliveryDayCalendarNotifier, DeliveryDayCalendarState>(
        DeliveryDayCalendarNotifier.new);

/// Week-calendar navigation state (DG-404 Phase 4.6 / FR2).
///
/// Owns the `_weekStart` field previously mutated via `setState` inside
/// `_DeliveryWeekCalendarViewState`. The widget reads
/// [deliveryWeekCalendarProvider] and invokes the notifier's [shift]/[goToday]
/// methods; no `setState` is required.
class DeliveryWeekCalendarNotifier extends Notifier<DateTime> {
  DateTime? _initialWeekStart;

  /// Seed the initial week-start (a Monday). Called once from the widget's
  /// `initState` before any mutation. Updates the state so the seeded value
  /// is visible on the first build.
  void seedInitialWeekStart(DateTime? initialWeekStart) {
    _initialWeekStart = initialWeekStart;
    final effective = initialWeekStart ?? startOfWeek(DateTime.now());
    if (state != effective) {
      state = effective;
    }
  }

  @override
  DateTime build() {
    final initial = _initialWeekStart;
    return initial ?? startOfWeek(DateTime.now());
  }

  void shift(int weeks) => state = state.add(Duration(days: 7 * weeks));

  void goToday() => state = startOfWeek(DateTime.now());
}

final deliveryWeekCalendarProvider =
    NotifierProvider<DeliveryWeekCalendarNotifier, DateTime>(
        DeliveryWeekCalendarNotifier.new);