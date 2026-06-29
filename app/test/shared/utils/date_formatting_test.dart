import 'package:bakery_app/shared/utils/date_formatting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseApiDateTime', () {
    test('naive timestamp treated as GMT+7', () {
      final dt = parseApiDateTime('2026-05-23T10:00:00');
      expect(dt.toUtc().toIso8601String(), '2026-05-23T03:00:00.000Z');
      expect(dt.toLocal().hour, 10);
      expect(dt.toLocal().minute, 0);
    });

    test('Z suffix parsed as UTC', () {
      final dt = parseApiDateTime('2026-05-23T10:00:00Z');
      expect(dt.toUtc().toIso8601String(), '2026-05-23T10:00:00.000Z');
    });

    test('+00:00 offset treated as UTC', () {
      final dt = parseApiDateTime('2026-05-23T10:00:00+00:00');
      expect(dt.toUtc().toIso8601String(), '2026-05-23T10:00:00.000Z');
    });

    test('+07:00 offset preserved', () {
      final dt = parseApiDateTime('2026-05-23T10:00:00+07:00');
      expect(dt.toUtc().toIso8601String(), '2026-05-23T03:00:00.000Z');
    });

    test('-05:00 offset preserved', () {
      final dt = parseApiDateTime('2026-05-23T10:00:00-05:00');
      expect(dt.toUtc().toIso8601String(), '2026-05-23T15:00:00.000Z');
    });

    test('naive timestamp with sub-seconds', () {
      final dt = parseApiDateTime('2026-12-31T23:59:59.123456');
      expect(dt.toUtc().toIso8601String(), '2026-12-31T16:59:59.123456Z');
    });

    test('naive timestamp at midnight', () {
      final dt = parseApiDateTime('2026-06-28T00:00:00');
      expect(dt.toUtc().toIso8601String(), '2026-06-27T17:00:00.000Z');
    });

    test('DST boundary - US Eastern spring forward (2026-03-08T02:30:00-05:00)', () {
      final dt = parseApiDateTime('2026-03-08T02:30:00-05:00');
      expect(dt.toUtc().toIso8601String(), '2026-03-08T07:30:00.000Z');
    });

    test('DST boundary - US Eastern fall back (2026-11-01T01:30:00-05:00)', () {
      final dt = parseApiDateTime('2026-11-01T01:30:00-05:00');
      expect(dt.toUtc().toIso8601String(), '2026-11-01T06:30:00.000Z');
    });

    test('handles date-only string (no time component)', () {
      final dt = parseApiDateTime('2026-05-23');
      expect(dt.toUtc().toIso8601String(), '2026-05-22T17:00:00.000Z');
    });
  });

  group('setServerTimezoneOffset', () {
    test('default offset is +07:00', () {
      expect(currentServerTimezoneOffset, '+07:00');
    });

    test('naive timestamp uses configured offset', () {
      setServerTimezoneOffset('+06:00');
      final dt = parseApiDateTime('2026-05-23T10:00:00');
      expect(dt.toUtc().toIso8601String(), '2026-05-23T04:00:00.000Z');
      // restore default
      setServerTimezoneOffset('+07:00');
    });

    test('explicit offset timestamps are unaffected by config', () {
      setServerTimezoneOffset('+06:00');
      final dt = parseApiDateTime('2026-05-23T10:00:00+07:00');
      expect(dt.toUtc().toIso8601String(), '2026-05-23T03:00:00.000Z');
      setServerTimezoneOffset('+07:00');
    });

    test('empty offset is ignored', () {
      setServerTimezoneOffset('+06:00');
      setServerTimezoneOffset('');
      expect(currentServerTimezoneOffset, '+06:00');
      setServerTimezoneOffset('+07:00');
    });
  });

  group('toLocalIsoString', () {
    test('emits local time with configured offset', () {
      setServerTimezoneOffset('+07:00');
      // Local 10:00 in a +07:00 device -> 10:00:00+07:00
      final local = DateTime(2026, 5, 23, 10, 0);
      expect(toLocalIsoString(local), '2026-05-23T10:00:00+07:00');
    });

    test('UTC input converts to device local then appends offset', () {
      setServerTimezoneOffset('+07:00');
      final utc = DateTime.utc(2026, 5, 23, 3, 0);
      // UTC 03:00 -> device local depends on TZ; just verify offset suffix
      expect(toLocalIsoString(utc).endsWith('+07:00'), isTrue);
      setServerTimezoneOffset('+07:00');
    });
  });

  group('formatDisplay', () {
    test('default pattern dd/MM/yyyy HH:mm', () {
      final dt = DateTime(2026, 5, 23, 14, 30);
      expect(formatDisplay(dt), '23/05/2026 14:30');
    });

    test('custom pattern yyyy-MM-dd HH:mm:ss', () {
      final dt = DateTime(2026, 5, 23, 14, 30, 45);
      expect(formatDisplay(dt, pattern: 'yyyy-MM-dd HH:mm:ss'), '2026-05-23 14:30:45');
    });

    test('applies toLocal to UTC datetime', () {
      final utcDt = DateTime.utc(2026, 5, 23, 10, 0);
      final localDt = utcDt.toLocal();
      expect(formatDisplay(utcDt), formatDisplay(localDt));
    });

    test('pads single-digit values', () {
      final dt = DateTime(2026, 1, 5, 3, 7);
      expect(formatDisplay(dt), '05/01/2026 03:07');
    });
  });

  group('formatDisplayDate', () {
    test('returns dd/MM/yyyy', () {
      final dt = DateTime(2026, 5, 23, 14, 30);
      expect(formatDisplayDate(dt), '23/05/2026');
    });

    test('pads single-digit day and month', () {
      final dt = DateTime(2026, 1, 5);
      expect(formatDisplayDate(dt), '05/01/2026');
    });

    test('applies toLocal to UTC datetime', () {
      final utcDt = DateTime.utc(2026, 5, 23, 10, 0);
      final localDt = utcDt.toLocal();
      expect(formatDisplayDate(utcDt), formatDisplayDate(localDt));
    });
  });

  group('formatDisplayTime', () {
    test('returns HH:mm', () {
      final dt = DateTime(2026, 5, 23, 14, 30);
      expect(formatDisplayTime(dt), '14:30');
    });

    test('pads single-digit values', () {
      final dt = DateTime(2026, 5, 23, 3, 7);
      expect(formatDisplayTime(dt), '03:07');
    });

    test('applies toLocal to UTC datetime', () {
      final utcDt = DateTime.utc(2026, 5, 23, 10, 0);
      final localDt = utcDt.toLocal();
      expect(formatDisplayTime(utcDt), formatDisplayTime(localDt));
    });
  });

  group('formatDisplayShort', () {
    test('returns dd/MM HH:mm', () {
      final dt = DateTime(2026, 5, 23, 14, 30);
      expect(formatDisplayShort(dt), '23/05 14:30');
    });

    test('pads single-digit values', () {
      final dt = DateTime(2026, 1, 5, 3, 7);
      expect(formatDisplayShort(dt), '05/01 03:07');
    });

    test('applies toLocal to UTC datetime', () {
      final utcDt = DateTime.utc(2026, 5, 23, 10, 0);
      final localDt = utcDt.toLocal();
      expect(formatDisplayShort(utcDt), formatDisplayShort(localDt));
    });
  });
}
