import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/features/today_sales/widgets/period_tab_body.dart';

void main() {
  group('shiftPeriodAnchor', () {
    test('week shift adds ±7 days', () {
      final anchor = DateTime(2026, 8, 13);
      expect(
        shiftPeriodAnchor(anchor, isWeek: true, direction: 1),
        DateTime(2026, 8, 20),
      );
      expect(
        shiftPeriodAnchor(anchor, isWeek: true, direction: -1),
        DateTime(2026, 8, 6),
      );
    });

    test('month shift keeps same day when target month is long enough', () {
      final anchor = DateTime(2026, 1, 15);
      expect(
        shiftPeriodAnchor(anchor, isWeek: false, direction: 1),
        DateTime(2026, 2, 15),
      );
    });

    test('month shift clamps 31st anchor to target month last day (Mn-3 regression)', () {
      // Jan 31 + 1 month → Feb 28 (2026 is not a leap year), not Mar 3.
      final jan31 = DateTime(2026, 1, 31);
      final feb = shiftPeriodAnchor(jan31, isWeek: false, direction: 1);
      expect(feb, DateTime(2026, 2, 28));
      expect(feb.month, 2, reason: 'must land in February, not March');

      // Mar 31 + 1 month → Apr 30.
      final mar31 = DateTime(2026, 3, 31);
      final apr = shiftPeriodAnchor(mar31, isWeek: false, direction: 1);
      expect(apr, DateTime(2026, 4, 30));
      expect(apr.month, 4, reason: 'must land in April, not May');

      // May 31 + 1 month → Jun 30.
      final may31 = DateTime(2026, 5, 31);
      final jun = shiftPeriodAnchor(may31, isWeek: false, direction: 1);
      expect(jun, DateTime(2026, 6, 30));
      expect(jun.month, 6, reason: 'must land in June, not July');

      // Aug 31 + 1 month → Sep 30.
      final aug31 = DateTime(2026, 8, 31);
      final sep = shiftPeriodAnchor(aug31, isWeek: false, direction: 1);
      expect(sep, DateTime(2026, 9, 30));
      expect(sep.month, 9, reason: 'must land in September, not October');
    });

    test('month shift clamps backward navigation too', () {
      // Mar 31 − 1 month → Feb 28.
      final mar31 = DateTime(2026, 3, 31);
      final feb = shiftPeriodAnchor(mar31, isWeek: false, direction: -1);
      expect(feb, DateTime(2026, 2, 28));
      expect(feb.month, 2);
    });

    test('month shift wraps across year boundaries', () {
      // Dec 31 + 1 month → Jan 31 of next year.
      final dec31 = DateTime(2026, 12, 31);
      final jan = shiftPeriodAnchor(dec31, isWeek: false, direction: 1);
      expect(jan, DateTime(2027, 1, 31));

      // Jan 31 − 1 month → Dec 31 of previous year.
      final jan31 = DateTime(2026, 1, 31);
      final dec = shiftPeriodAnchor(jan31, isWeek: false, direction: -1);
      expect(dec, DateTime(2025, 12, 31));
    });

    test('leap year: Jan 31 + 1 month → Feb 29', () {
      final jan31 = DateTime(2024, 1, 31);
      final feb = shiftPeriodAnchor(jan31, isWeek: false, direction: 1);
      expect(feb, DateTime(2024, 2, 29));
      expect(feb.month, 2);
    });
  });
}