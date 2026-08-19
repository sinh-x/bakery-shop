import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Selected category filter state for the blanks list screen
/// (DG-404 Phase 4.4 / FR2).
///
/// Owns the `_selectedCategory` field previously mutated via `setState`
/// inside `_BlankListScreenState`. The widget reads
/// [blankListFilterProvider] and invokes [BlankListFilterNotifier.select];
/// no `setState` is required.
class BlankListFilterNotifier extends Notifier<String> {
  @override
  String build() => '';

  /// Replace the selected category. Pass an empty string to clear the
  /// filter (the "all" chip).
  void select(String category) => state = category;
}

/// Provider for the blanks list category filter. The widget reads this
/// and calls [BlankListFilterNotifier.select]; no `setState` is required.
final blankListFilterProvider =
    NotifierProvider<BlankListFilterNotifier, String>(
        BlankListFilterNotifier.new);