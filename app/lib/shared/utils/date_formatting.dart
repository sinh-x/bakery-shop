import 'package:intl/intl.dart';

/// Server timezone configuration fetched from `GET /api/config` at startup
/// (DG-202 FR7/AC6). The Flutter client uses the server's timezone offset —
/// rather than the device's local timezone — for display conversion, keeping
/// timestamps consistent with the server's configured timezone.
///
/// `ServerTimezone.offsetMinutes` is the server timezone's UTC offset in
/// minutes (e.g., 420 for +07:00). It defaults to the device's local offset
/// (via `DateTime.now().timeZoneOffset`) so display helpers keep working
/// before `initServerTimezone()` runs or if the API is unreachable.
class ServerTimezone {
  static int offsetMinutes = DateTime.now().timeZoneOffset.inMinutes;

  static void configure(String timezoneName, int offsetMinutesValue) {
    ServerTimezone.timezoneName = timezoneName;
    offsetMinutes = offsetMinutesValue;
  }

  static String timezoneName = DateTime.now().timeZoneName;

  /// Returns a UTC [DateTime] shifted by the server timezone offset, producing
  /// a wall-clock [DateTime] in the server's local time (no UTC label).
  static DateTime toServerLocal(DateTime dateTime) {
    final utc = dateTime.toUtc();
    return utc.add(Duration(minutes: offsetMinutes));
  }
}

/// Parses an API timestamp string (Z-suffixed UTC, +07:00 offset, or bare
/// ISO-8601) into a [DateTime]. The returned [DateTime] retains the original
/// timezone information; callers should use the `formatDisplay*` helpers below
/// (which apply the server timezone offset) when presenting it to the user.
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

/// Formats a [DateTime] for full display in the server's timezone as
/// `dd/MM/yyyy HH:mm`. Returns an empty string when [dateTime] is null.
String formatDisplay(DateTime? dateTime) {
  if (dateTime == null) return '';
  return DateFormat('dd/MM/yyyy HH:mm').format(ServerTimezone.toServerLocal(dateTime));
}

/// Formats a [DateTime] for date-only display in the server's timezone
/// as `dd/MM/yyyy`. Returns an empty string when [dateTime] is null.
String formatDisplayDate(DateTime? dateTime) {
  if (dateTime == null) return '';
  return DateFormat('dd/MM/yyyy').format(ServerTimezone.toServerLocal(dateTime));
}

/// Formats a [DateTime] for time-only display in the server's timezone
/// as `HH:mm`. Returns an empty string when [dateTime] is null.
String formatDisplayTime(DateTime? dateTime) {
  if (dateTime == null) return '';
  return DateFormat('HH:mm').format(ServerTimezone.toServerLocal(dateTime));
}

/// Formats a [DateTime] for short display in the server's timezone as
/// `dd/MM HH:mm`. Returns an empty string when [dateTime] is null.
String formatDisplayShort(DateTime? dateTime) {
  if (dateTime == null) return '';
  return DateFormat('dd/MM HH:mm').format(ServerTimezone.toServerLocal(dateTime));
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