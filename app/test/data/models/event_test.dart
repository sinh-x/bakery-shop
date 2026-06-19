import 'package:bakery_app/data/models/event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses timestamp without timezone as UTC+7 instant', () {
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

    expect(event.timestamp.toUtc().toIso8601String(), '2026-05-23T03:00:00.000Z');
    expect(event.timestamp.toLocal().hour, 10);
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
