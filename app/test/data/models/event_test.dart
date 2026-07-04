import 'package:bakery_app/data/models/event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses bare timestamp without timezone (timezone-agnostic)', () {
    final event = BakeryEvent.fromJson({
      'id': 1,
      'timestamp': '2026-05-23T10:00:00',
      'summary': 'Chi phi',
      'type': 'expense',
      'tags': <String>[],
      'logged_by': '',
      'source': 'app',
      'data': <String, dynamic>{},
    });

    // Bare timestamps carry no timezone info (DateTime.parse treats them as
    // local time); validate the parsed components match the input rather than
    // asserting a specific UTC offset.
    expect(event.timestamp.year, 2026);
    expect(event.timestamp.month, 5);
    expect(event.timestamp.day, 23);
    expect(event.timestamp.hour, 10);
    expect(event.timestamp.minute, 0);
  });

  test('keeps explicit timezone timestamps unchanged', () {
    final event = BakeryEvent.fromJson({
      'id': 2,
      'timestamp': '2026-05-23T10:00:00+07:00',
      'summary': 'Chi phi',
      'type': 'expense',
      'tags': <String>[],
      'logged_by': '',
      'source': 'app',
      'data': <String, dynamic>{},
    });

    expect(event.timestamp.toUtc().toIso8601String(), '2026-05-23T03:00:00.000Z');
  });
}
