import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

DateTime parseApiDateTime(String value) {
  final hasExplicitTimezone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(value);
  if (!hasExplicitTimezone) {
    if (!value.contains('T')) {
      return DateTime.parse('${value}T00:00:00+07:00');
    }
    return DateTime.parse('$value+07:00');
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
