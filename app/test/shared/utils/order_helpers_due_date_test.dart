import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/shared/utils/order_helpers.dart';

void main() {
  group('defaultDueDateTime (now + 1h, ceil to next 30-min slot)', () {
    test('minute :00 stays on the hour after +1h', () {
      final result = defaultDueDateTime(DateTime(2026, 7, 8, 16, 0));
      expect(result, DateTime(2026, 7, 8, 17, 0));
    });

    test('minute 1-29 rounds up to :30', () {
      final result = defaultDueDateTime(DateTime(2026, 7, 8, 16, 1));
      expect(result, DateTime(2026, 7, 8, 17, 30));
    });

    test('minute exactly :30 stays at :30 after +1h', () {
      final result = defaultDueDateTime(DateTime(2026, 7, 8, 16, 30));
      expect(result, DateTime(2026, 7, 8, 17, 30));
    });

    test('minute 31-59 rounds up to next hour :00 (hour carry)', () {
      final result = defaultDueDateTime(DateTime(2026, 7, 8, 16, 31));
      expect(result, DateTime(2026, 7, 8, 18, 0));
    });

    test('minute :59 rounds up to next hour :00', () {
      final result = defaultDueDateTime(DateTime(2026, 7, 8, 16, 59));
      expect(result, DateTime(2026, 7, 8, 18, 0));
    });

    test('day carry: 23:31 -> next day 01:00', () {
      final result = defaultDueDateTime(DateTime(2026, 7, 8, 23, 31));
      expect(result, DateTime(2026, 7, 9, 1, 0));
    });

    test('drops seconds and milliseconds', () {
      final result = defaultDueDateTime(DateTime(2026, 7, 8, 16, 1, 45, 500));
      expect(result, DateTime(2026, 7, 8, 17, 30));
    });
  });
}
