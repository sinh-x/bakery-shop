import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Expansion state for a single checklist history day card
/// (DG-404 Phase 4.7).
///
/// Owns the per-card `_expanded` toggle previously held as a `setState`
/// field inside `_DayCardState`. Keyed by the day's date string via a
/// family provider so each card in the list maintains its own expansion
/// state.
class DayCardState {
  const DayCardState({this.expanded = true});

  final bool expanded;

  DayCardState copyWith({bool? expanded}) {
    return DayCardState(expanded: expanded ?? this.expanded);
  }
}

/// `Notifier` that owns the expansion toggle for a single checklist
/// history day card (DG-404 Phase 4.7). Keyed by the day's date string
/// via a family provider.
class DayCardNotifier extends Notifier<DayCardState> {
  final String dayKey;

  DayCardNotifier(this.dayKey);

  @override
  DayCardState build() => const DayCardState(expanded: true);

  void toggle() => state = state.copyWith(expanded: !state.expanded);

  void setExpanded(bool value) =>
      state = state.copyWith(expanded: value);
}

/// Family provider for the day-card expansion state, keyed by the day's
/// date string.
final dayCardProvider = NotifierProvider.family<DayCardNotifier,
    DayCardState, String>(DayCardNotifier.new);