/// Format a [double] for display: integers without a trailing `.0`,
/// non-integers as their raw string. Shared across the blanks feature
/// (and other features) to avoid per-screen duplication of this helper.
String formatDouble(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}