/// Layout constants for the day/week calendar grid columns (DG-306 Phase 2
/// / DG-329 Phase 4).
///
/// Extracted from `delivery_week_calendar_components.dart` (CQ-1, DG-329
/// Phase 5.6-c1 review remediation) so the grid layout values can be shared
/// by `WeekDayColumn`, `WeekHourLabelColumn`, and `currentTimeGridOffset`
/// without a circular import between the components file and the
/// `time_grid_helpers.dart` file. This is an implementation-detail of the
/// day/week calendar grids and is not intended for reuse outside the
/// calendar.
class WeekDayLayoutConstants {
  const WeekDayLayoutConstants._();

  /// Header row height (weekday name + date label).
  static const double headerHeight = 44.0;

  /// One hour-row height in the time grid (6:00–21:00, 16 slots).
  static const double hourRowHeight = 64.0;

  /// Unscheduled ("Chưa có giờ") row height at the top of each day column.
  static const double unscheduledRowHeight = 72.0;
}