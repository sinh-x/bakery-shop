import 'package:intl/intl.dart';

/// Parses an API timestamp string (Z-suffixed UTC, +07:00 offset, or bare
/// ISO-8601) into a [DateTime]. The returned [DateTime] retains the original
/// timezone information; callers should use `.toLocal()` (or the
/// `formatDisplay*` helpers below) when presenting it to the user.
///
/// `DateTime.parse` natively handles `Z`-suffixed, offset-suffixed, and bare
/// ISO-8601 strings, so this is backward-compatible with legacy bare
/// timestamps. Returns `null` when [value] is empty or cannot be parsed.
DateTime? parseApiDateTime(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

/// Parses a non-null API timestamp string into a [DateTime]. Use this for
/// required timestamp fields. Throws [FormatException] when [value] cannot be
/// parsed — matching the previous `DateTime.parse` behavior for required
/// fields.
DateTime parseApiDateTimeRequired(String value) {
  return DateTime.parse(value);
}

/// Formats a [DateTime] for full display in the device's local timezone as
/// `dd/MM/yyyy HH:mm`. Returns an empty string when [dateTime] is null.
String formatDisplay(DateTime? dateTime) {
  if (dateTime == null) return '';
  return DateFormat('dd/MM/yyyy HH:mm').format(dateTime.toLocal());
}

/// Formats a [DateTime] for date-only display in the device's local timezone
/// as `dd/MM/yyyy`. Returns an empty string when [dateTime] is null.
String formatDisplayDate(DateTime? dateTime) {
  if (dateTime == null) return '';
  return DateFormat('dd/MM/yyyy').format(dateTime.toLocal());
}

/// Formats a [DateTime] for time-only display in the device's local timezone
/// as `HH:mm`. Returns an empty string when [dateTime] is null.
String formatDisplayTime(DateTime? dateTime) {
  if (dateTime == null) return '';
  return DateFormat('HH:mm').format(dateTime.toLocal());
}

/// Formats a [DateTime] for short display in the device's local timezone as
/// `dd/MM HH:mm`. Returns an empty string when [dateTime] is null.
String formatDisplayShort(DateTime? dateTime) {
  if (dateTime == null) return '';
  return DateFormat('dd/MM HH:mm').format(dateTime.toLocal());
}

/// Formats a [DateTime] as a date-only API string `yyyy-MM-dd`. Use this for
/// date-only columns (`due_date`, `checklist_date`, `reconciliation_date`)
/// which are NOT UTC timestamps and must not receive a `Z` suffix.
String formatApiDate(DateTime dateTime) {
  return DateFormat('yyyy-MM-dd').format(dateTime);
}

/// Parses a date-only API string (`yyyy-MM-dd`) into a [DateTime]. Returns
/// `null` when [value] is empty or cannot be parsed.
DateTime? parseApiDate(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

/// Formats a [TimeOfDay]-equivalent hour/minute pair as `HH:mm`.
String formatHourMinute(int hour, int minute) {
  return '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';
}