/// Format a [double] for display: integers without a trailing `.0`,
/// non-integers as their raw string. Shared across the blanks feature
/// (and other features) to avoid per-screen duplication of this helper.
String formatDouble(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}

/// Format a [double] with at most one decimal place: integers render
/// without a trailing `.0`, non-integers round to 1 decimal. Shared helper
/// extracted from blank_detail_screen.dart (DG-294 Mn-1) to replace
/// duplicate `toStringAsFixed(v.truncateToDouble() == v ? 0 : 1)` calls.
String formatDecimal(double v) {
  return v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);
}