import 'package:bakery_app/shared/build_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shortBuildFingerprint', () {
    test('returns full value when length is at most seven', () {
      expect(shortBuildFingerprint('abc1234'), 'abc1234');
      expect(shortBuildFingerprint('abc'), 'abc');
    });

    test('returns first seven characters when value is longer', () {
      expect(shortBuildFingerprint('abcdefghi'), 'abcdefg');
    });
  });
}
