import 'package:bakery_app/data/api/event_service.dart';
import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/shared/utils/date_formatting.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Interceptor that records the outgoing request body and resolves with a
/// canned response — mirrors the pattern in
/// `payment_transaction_service_test.dart`.
class _RecordingInterceptor extends Interceptor {
  String? lastPath;
  Map<String, dynamic>? lastBody;
  final Map<String, dynamic> responseJson;

  _RecordingInterceptor(this.responseJson);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    lastPath = options.path;
    lastBody = options.data is Map<String, dynamic>
        ? Map<String, dynamic>.from(options.data as Map)
        : null;
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 201,
        data: responseJson,
      ),
    );
  }
}

Map<String, dynamic> _eventJson(String timestamp) {
  return {
    'id': 1,
    'timestamp': timestamp,
    'summary': 'RT test',
    'type': 'note',
    'tags': <String>[],
    'logged_by': '',
    'source': 'app',
    'data': <String, dynamic>{},
  };
}

void main() {
  group('parseApiDateTime round-trip', () {
    test('bare timestamp round-trips through parseApiDateTime keeping local time', () {
      const localInput = '2026-06-29T12:55:02';
      final dt = parseApiDateTime(localInput);
      // The local wall-clock time must be preserved (12:55:02 local).
      expect(dt.toLocal().hour, 12);
      expect(dt.toLocal().minute, 55);
      expect(dt.toLocal().second, 2);
    });

    test('+07:00 timestamp round-trips keeping local time', () {
      const localInput = '2026-06-29T12:55:02+07:00';
      final dt = parseApiDateTime(localInput);
      expect(dt.toLocal().hour, 12);
      expect(dt.toLocal().minute, 55);
      expect(dt.toLocal().second, 2);
    });

    test('Z timestamp converts to correct local time', () {
      // UTC 05:55 -> local 12:55 in +07:00.
      final dt = parseApiDateTime('2026-06-29T05:55:00Z');
      expect(dt.toUtc().toIso8601String(), '2026-06-29T05:55:00.000Z');
      expect(dt.toLocal().hour, 12);
      expect(dt.toLocal().minute, 55);
    });

    test('configurable offset from server applies to bare timestamps', () {
      setServerTimezoneOffset('+06:00');
      try {
        final dt = parseApiDateTime('2026-06-29T12:55:02');
        // The offset is applied to the naive value: 12:55+06:00 == 06:55 UTC.
        expect(dt.toUtc().toIso8601String(), '2026-06-29T06:55:02.000Z');
      } finally {
        setServerTimezoneOffset('+07:00');
      }
    });

    test('configurable offset does not affect explicit-offset timestamps', () {
      setServerTimezoneOffset('+06:00');
      try {
        final dt = parseApiDateTime('2026-06-29T12:55:02+07:00');
        // Explicit offset wins: 12:55+07:00 == 05:55 UTC.
        expect(dt.toUtc().toIso8601String(), '2026-06-29T05:55:02.000Z');
      } finally {
        setServerTimezoneOffset('+07:00');
      }
    });

    test('full round-trip: toLocalIsoString -> parseApiDateTime preserves local time', () {
      setServerTimezoneOffset('+07:00');
      final original = DateTime(2026, 6, 29, 12, 55, 2);
      final serialized = toLocalIsoString(original);
      // Must carry +07:00, not UTC Z.
      expect(serialized.endsWith('+07:00'), isTrue,
          reason: 'toLocalIsoString must emit +07:00, not Z');
      expect(serialized.contains('Z'), isFalse,
          reason: 'toLocalIsoString must NOT emit UTC Z');

      final parsed = parseApiDateTime(serialized);
      expect(parsed.toLocal().hour, original.hour);
      expect(parsed.toLocal().minute, original.minute);
      expect(parsed.toLocal().second, original.second);
    });
  });

  group('EventService.createEvent sends +07:00 not Z', () {
    test('createEvent serializes timestamp with +07:00 offset', () async {
      final interceptor = _RecordingInterceptor(
        _eventJson('2026-06-29T12:55:02+07:00'),
      );
      final dio = Dio()..interceptors.add(interceptor);
      final service = EventService(dio);

      final timestamp = DateTime(2026, 6, 29, 12, 55, 2);
      await service.createEvent(
        summary: 'RT flutter',
        timestamp: timestamp,
      );

      expect(interceptor.lastPath, '/api/events');
      final sentTs = interceptor.lastBody?['timestamp'] as String?;
      expect(sentTs, isNotNull);
      expect(sentTs!.endsWith('+07:00'), isTrue,
          reason: 'createEvent must send +07:00 suffix, not UTC Z');
      expect(sentTs.contains('Z'), isFalse,
          reason: 'createEvent must NOT send UTC Z');
    });

    test('updateEvent serializes timestamp with +07:00 offset', () async {
      final interceptor = _RecordingInterceptor(
        _eventJson('2026-06-29T13:00:00+07:00'),
      );
      final dio = Dio()..interceptors.add(interceptor);
      final service = EventService(dio);

      final timestamp = DateTime(2026, 6, 29, 13, 0, 0);
      await service.updateEvent(1, timestamp: timestamp);

      final sentTs = interceptor.lastBody?['timestamp'] as String?;
      expect(sentTs, isNotNull);
      expect(sentTs!.endsWith('+07:00'), isTrue);
      expect(sentTs.contains('Z'), isFalse);
    });
  });

  group('BakeryEvent.fromJson round-trip', () {
    test('bare timestamp from server round-trips to correct local time', () {
      final event = BakeryEvent.fromJson(_eventJson('2026-06-29T12:55:02'));
      expect(event.timestamp.toLocal().hour, 12);
      expect(event.timestamp.toLocal().minute, 55);
    });

    test('+07:00 timestamp from server round-trips to correct local time', () {
      final event =
          BakeryEvent.fromJson(_eventJson('2026-06-29T12:55:02+07:00'));
      expect(event.timestamp.toLocal().hour, 12);
      expect(event.timestamp.toLocal().minute, 55);
    });

    test('Z timestamp from server converts to correct local time', () {
      final event = BakeryEvent.fromJson(_eventJson('2026-06-29T05:55:00Z'));
      expect(event.timestamp.toLocal().hour, 12);
      expect(event.timestamp.toLocal().minute, 55);
    });

    test('full model round-trip: create body -> server JSON -> parse', () {
      setServerTimezoneOffset('+07:00');
      final original = DateTime(2026, 6, 29, 9, 30, 0);
      final serialized = toLocalIsoString(original);
      // Simulate the server echoing the timestamp back unchanged.
      final event = BakeryEvent.fromJson(_eventJson(serialized));
      expect(event.timestamp.toLocal().hour, 9);
      expect(event.timestamp.toLocal().minute, 30);
      expect(event.timestamp.toLocal().second, 0);
    });
  });
}