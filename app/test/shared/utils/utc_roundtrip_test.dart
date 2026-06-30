// UTC timestamp round-trip tests (DG-202 Phase 6 / AC8).
//
// Verifies the "store UTC, display local" contract on the Flutter side:
//
// 1. A local wall-clock instant (e.g. 12:00 +07:00) is converted to UTC
//    (05:00Z) and serialized via `DateTime.toIso8601String()` (the same
//    call EventService uses when building the request body).
// 2. The server stores the UTC Z-suffixed value and returns it.
// 3. `parseApiDateTime` parses the returned Z-suffixed string into a
//    `DateTime` retaining UTC timezone info.
// 4. Applying the configured server timezone offset (via
//    `ServerTimezone.toServerLocal`) reproduces the original local
//    wall-clock time.
//
// Also covers:
// - `parseApiDateTime` handles Z-suffixed, offset-suffixed, and bare
//   ISO-8601 strings (backward compatibility — NFR4).
// - Model round-trip: a model serialized to JSON and parsed back preserves
//   the original local wall-clock time (AC8).
// - Date-only columns (`dueDate`, `checklistDate`) carry no `Z` suffix and
//   are not timezone-converted (FR8 / AC9).

import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/data/models/order.dart';
import 'package:bakery_app/data/models/order_item.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Server timezone is Asia/Ho_Chi_Minh (+07:00 = 420 minutes). Configure
  // ServerTimezone deterministically so display conversion does not depend
  // on the test host's local timezone.
  setUp(() {
    ServerTimezone.configure('Asia/Ho_Chi_Minh', 420);
  });

  group('parseApiDateTime', () {
    test('parses Z-suffixed UTC timestamp', () {
      final dt = parseApiDateTime('2026-06-30T05:00:00Z');
      expect(dt, isNotNull);
      expect(dt!.toUtc().toIso8601String(), '2026-06-30T05:00:00.000Z');
    });

    test('parses offset-suffixed timestamp', () {
      final dt = parseApiDateTime('2026-06-30T12:00:00+07:00');
      expect(dt, isNotNull);
      expect(dt!.toUtc().toIso8601String(), '2026-06-30T05:00:00.000Z');
    });

    test('parses bare ISO-8601 timestamp (backward compatible — NFR4)', () {
      final dt = parseApiDateTime('2026-06-30T05:00:00');
      expect(dt, isNotNull);
      // Bare timestamps carry no timezone info (DateTime.parse treats them as
      // local time); the key backward-compat guarantee is that they still
      // parse without error so legacy server responses keep working.
      expect(dt!.year, 2026);
      expect(dt.month, 6);
      expect(dt.day, 30);
      expect(dt.hour, 5);
    });

    test('returns null for empty/null input', () {
      expect(parseApiDateTime(null), isNull);
      expect(parseApiDateTime(''), isNull);
    });
  });

  group('UTC round-trip: local -> toIso8601String -> parseApiDateTime -> local', () {
    test('local 12:00 (+07:00) round-trips through UTC Z back to 12:00', () {
      // Original local wall-clock instant (12:30 +07:00).
      const localHour = 12;
      const localMinute = 30;
      final localWithOffset =
          DateTime.parse('2026-06-30T12:30:00+07:00');
      final utc = localWithOffset.toUtc();
      // Serialized form sent to the API (UTC Z-suffixed).
      final wire = utc.toIso8601String();
      expect(wire, '2026-06-30T05:30:00.000Z');

      // Server stores and returns the same UTC Z-suffixed value.
      final parsed = parseApiDateTime(wire)!;
      expect(parsed.toUtc().toIso8601String(), '2026-06-30T05:30:00.000Z');

      // Display conversion applies the server timezone offset (+07:00).
      final displayed = ServerTimezone.toServerLocal(parsed);
      expect(displayed.hour, localHour);
      expect(displayed.minute, localMinute);
    });

    test('formatDisplay renders server-local time from UTC Z input', () {
      final dt = parseApiDateTime('2026-06-30T05:00:00Z')!;
      // 05:00Z + 7h = 12:00 local.
      expect(formatDisplayTime(dt), '12:00');
      expect(formatDisplay(dt), '30/06/2026 12:00');
    });
  });

  group('BakeryEvent model round-trip', () {
    test('create body -> server JSON -> parse preserves local wall-clock', () {
      // The client builds the request timestamp from a UTC DateTime.
      final utcTimestamp =
          DateTime.parse('2026-06-30T05:30:00Z'); // 12:30 (+07:00)
      final wire = utcTimestamp.toIso8601String();
      expect(wire, '2026-06-30T05:30:00.000Z');

      // Server responds with the stored timestamp (Z-suffixed UTC).
      final serverJson = <String, dynamic>{
        'id': 1,
        'timestamp': wire,
        'summary': 'Round-trip event',
        'type': 'note',
        'tags': <String>[],
        'logged_by': '',
        'source': 'app',
        'data': <String, dynamic>{},
      };
      final event = BakeryEvent.fromJson(serverJson);

      // Parsed timestamp is the same UTC instant.
      expect(event.timestamp.toUtc().toIso8601String(), wire);

      // Display conversion reproduces the original local wall-clock time.
      final displayed = ServerTimezone.toServerLocal(event.timestamp);
      expect(displayed.hour, 12);
      expect(displayed.minute, 30);

      // Serializing back to JSON emits a clean UTC Z-suffixed string (no
      // fractional seconds) via the shared `timestampToJson` helper, matching
      // Python `now_utc()` output (DG-202 review-auto cycle 1 CQ-2).
      final reSerialized = event.toJson();
      expect(reSerialized['timestamp'], '2026-06-30T05:30:00Z');
    });

    test('parses Z-suffixed server timestamp', () {
      final event = BakeryEvent.fromJson({
        'id': 2,
        'timestamp': '2026-05-23T03:00:00.000Z',
        'summary': 'Z-suffix event',
        'type': 'expense',
        'tags': <String>[],
        'logged_by': '',
        'source': 'app',
        'data': <String, dynamic>{},
      });
      expect(event.timestamp.toUtc().toIso8601String(),
          '2026-05-23T03:00:00.000Z');
      // +07:00 -> 10:00 local.
      expect(ServerTimezone.toServerLocal(event.timestamp).hour, 10);
    });
  });

  group('Order model round-trip — date-only columns unchanged (FR8 / AC9)', () {
    test('dueDate and dueTime carry no Z suffix', () {
      final order = Order(
        id: '1',
        orderRef: 'ORD-1',
        customerName: 'Khách',
        items: <OrderItem>[],
        totalPrice: 0,
        dueDate: '2026-03-20',
        dueTime: '14:00',
        createdAt: DateTime.parse('2026-03-20T01:21:51Z'),
        updatedAt: DateTime.parse('2026-03-20T01:21:51Z'),
      );
      final json = order.toJson();
      // Date-only and time-only columns are plain strings with no Z suffix.
      expect(json['dueDate'], '2026-03-20');
      expect(json['dueDate'].toString().contains('Z'), isFalse);
      expect(json['dueTime'], '14:00');
      expect(json['dueTime'].toString().contains('Z'), isFalse);
      // Timestamp columns ARE UTC Z-suffixed.
      expect(json['createdAt'].toString().endsWith('Z'), isTrue);
    });

    test('parses Z-suffixed createdAt/updatedAt as DateTime', () {
      final order = Order.fromJson({
        'id': '1',
        'orderRef': 'ORD-1',
        'customerName': 'Khách',
        'items': <dynamic>[],
        'totalPrice': 0,
        'dueDate': '2026-03-20',
        'dueTime': '14:00',
        'createdAt': '2026-03-20T01:21:51Z',
        'updatedAt': '2026-03-20T01:21:51Z',
      });
      expect(order.createdAt, isA<DateTime>());
      expect(order.updatedAt, isA<DateTime>());
      expect(order.createdAt.toUtc().toIso8601String(),
          '2026-03-20T01:21:51.000Z');
      // Date-only column stays a plain string.
      expect(order.dueDate, '2026-03-20');
      expect(order.dueDate!.contains('Z'), isFalse);
    });
  });

  group('formatApiDate — date-only helper carries no Z (FR8)', () {
    test('produces yyyy-MM-dd with no timezone suffix', () {
      final date = DateTime(2026, 3, 25);
      expect(formatApiDate(date), '2026-03-25');
      expect(formatApiDate(date).contains('Z'), isFalse);
    });

    test('parseApiDate parses a bare yyyy-MM-dd string', () {
      final dt = parseApiDate('2026-03-25');
      expect(dt, isNotNull);
      // Date-only parse yields midnight local (no timezone info).
      expect(dt!.year, 2026);
      expect(dt.month, 3);
      expect(dt.day, 25);
    });
  });
}