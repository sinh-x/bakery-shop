import 'package:flutter/material.dart';

import 'package:bakery_app/shared/labels/orders.dart';

/// Available date filter options for the order list (DG-193 Phase 1).
///
/// The four options form an exclusive single-select set. [all] clears the
/// date filter and shows every order; the other three restrict the list to
/// orders whose `dueDate` matches today, tomorrow, or both.
enum DateFilterOption {
  today,
  tomorrow,
  todayTomorrow,
  all,
}

/// A horizontal row of [FilterChip]s offering quick date filtering for the
/// order list (DG-193 Phase 1 — FR1).
///
/// The widget is a pure presentational component: it receives the currently
/// selected [DateFilterOption] and a [onChanged] callback, leaving filtering
/// logic to the owning screen. This keeps the 879-line `order_list_screen`
/// from growing further (NFR1) and matches the existing status-filter chip
/// pattern.
///
/// Labels:
/// - today     → `VN.filterToday` ("Hôm nay")
/// - tomorrow  → `OrdersLabels.dateFilterTomorrow` ("Ngày mai")
/// - today+tom → `OrdersLabels.dateFilterTodayTomorrow` ("Nay + Mai")
/// - all       → `VN.filterAll` ("Tất cả")
class DateFilterChips extends StatelessWidget {
  const DateFilterChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  /// Currently selected option. The selection is exclusive — exactly one
  /// option is selected at a time.
  final DateFilterOption selected;

  /// Called when the user taps a chip. The owning screen updates its filter
  /// state and re-runs the filtering pipeline.
  final ValueChanged<DateFilterOption> onChanged;

  static const _options = [
    DateFilterOption.today,
    DateFilterOption.tomorrow,
    DateFilterOption.todayTomorrow,
    DateFilterOption.all,
  ];

  String _label(DateFilterOption option) {
    switch (option) {
      case DateFilterOption.today:
        return VN.filterToday;
      case DateFilterOption.tomorrow:
        return OrdersLabels.dateFilterTomorrow;
      case DateFilterOption.todayTomorrow:
        return OrdersLabels.dateFilterTodayTomorrow;
      case DateFilterOption.all:
        return VN.filterAll;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: _options.map((option) {
          final isSelected = selected == option;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(_label(option)),
              selected: isSelected,
              selectedColor: theme.colorScheme.primary.withAlpha(30),
              onSelected: (_) => onChanged(option),
            ),
          );
        }).toList(),
      ),
    );
  }
}