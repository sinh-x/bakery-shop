import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Timezone offset applied to naive (offset-less) API timestamps.
///
/// Defaults to `+07:00` (Asia/Ho_Chi_Minh) and is updated at startup from the
/// server's `GET /api/config` endpoint via [setServerTimezoneOffset].
String _serverTimezoneOffset = '+07:00';

/// Update the timezone offset used to interpret naive API timestamps.
///
/// Called once the Flutter app fetches the server config at startup. Must match
/// the format `+HH:MM` / `-HH:MM`.
void setServerTimezoneOffset(String offset) {
  final trimmed = offset.trim();
  if (trimmed.isEmpty) return;
  _serverTimezoneOffset = trimmed;
}

/// The timezone offset currently applied to naive API timestamps.
String get currentServerTimezoneOffset => _serverTimezoneOffset;

DateTime parseApiDateTime(String value) {
  final hasExplicitTimezone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(value);
  if (!hasExplicitTimezone) {
    if (!value.contains('T')) {
      return DateTime.parse('${value}T00:00:00$_serverTimezoneOffset');
    }
    return DateTime.parse('$value$_serverTimezoneOffset');
  }
  return DateTime.parse(value);
}

String formatDisplay(DateTime dt, {String? pattern}) {
  final local = dt.toLocal();
  return DateFormat(pattern ?? 'dd/MM/yyyy HH:mm').format(local);
}

String formatDisplayDate(DateTime dt) {
  final local = dt.toLocal();
  return DateFormat('dd/MM/yyyy').format(local);
}

String formatDisplayTime(DateTime dt) {
  final local = dt.toLocal();
  return DateFormat('HH:mm').format(local);
}

String formatDisplayShort(DateTime dt) {
  final local = dt.toLocal();
  return DateFormat('dd/MM HH:mm').format(local);
}

String formatDisplayTimeOfDay(TimeOfDay tod) {
  return DateFormat('HH:mm').format(DateTime(0, 1, 1, tod.hour, tod.minute));
}

/// Serialize a [DateTime] as local time with the configured server timezone
/// offset (e.g. `2026-06-29T14:30:00+07:00`).
///
/// Use this instead of [DateTime.toIso8601String] when sending timestamps to the
/// API, since `toIso8601String()` emits UTC `Z` for aware values and a bare
/// string for naive values.
String toLocalIsoString(DateTime dt) {
  final local = dt.toLocal();
  return DateFormat('yyyy-MM-ddTHH:mm:ss').format(local) +
      _serverTimezoneOffset;
}
