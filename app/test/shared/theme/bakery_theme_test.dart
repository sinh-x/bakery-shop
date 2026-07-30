import 'dart:math' as math;

import 'package:bakery_app/shared/theme/bakery_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BakeryTheme critical alert color constants', () {
    test('criticalAlertBackground is the documented dark red (#B71C1C)', () {
      const expected = Color(0xFFB71C1C);
      expect(BakeryTheme.criticalAlertBackground, expected);
      expect(BakeryTheme.criticalAlertBackground.toARGB32(), expected.toARGB32());
    });

    test('criticalAlertForeground is the documented amber (#FFC107)', () {
      const expected = Color(0xFFFFC107);
      expect(BakeryTheme.criticalAlertForeground, expected);
      expect(BakeryTheme.criticalAlertForeground.toARGB32(), expected.toARGB32());
    });

    test('contrast ratio meets WCAG AA for large text (>= 3:1)', () {
      double channelLuminance(int v) {
        final s = v / 255.0;
        return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
      }

      double luminance(Color c) {
        return 0.2126 * channelLuminance((c.r * 255.0).round().clamp(0, 255)) +
            0.7152 * channelLuminance((c.g * 255.0).round().clamp(0, 255)) +
            0.0722 * channelLuminance((c.b * 255.0).round().clamp(0, 255));
      }

      final l1 = luminance(BakeryTheme.criticalAlertForeground);
      final l2 = luminance(BakeryTheme.criticalAlertBackground);
      final ratio = (l1 + 0.05) / (l2 + 0.05);

      expect(ratio, greaterThanOrEqualTo(3.0),
          reason: 'contrast $ratio:1 must meet WCAG AA large-text threshold (3:1)');
    });
  });
}