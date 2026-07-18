import 'package:bakery_app/shared/utils/phone_formatter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatPhone', () {
    test('formats 9 digits as xxx-xxx-xxx', () {
      expect(formatPhone('090123456'), '090-123-456');
    });

    test('formats 10 digits as xxxx-xxx-xxx', () {
      expect(formatPhone('0901234567'), '0901-234-567');
    });

    test('formats 11 digits as xxxx-xxx-xxxx (matches PhoneInputFormatter)', () {
      expect(formatPhone('09012345678'), '0901-234-5678');
    });

    test('formats 12+ digits: first 10 as xxxx-xxx-xxxx, rest raw', () {
      expect(formatPhone('090123456789'), '0901-234-56789');
      expect(formatPhone('090123456789012'), '0901-234-56789012');
    });

    test('ignores non-digit characters when formatting', () {
      expect(formatPhone('0901-234-567'), '0901-234-567');
      expect(formatPhone(' 0901 234 5678 '), '0901-234-5678');
    });

    test('returns input as-is for lengths other than 9/10+', () {
      expect(formatPhone('090'), '090');
      expect(formatPhone('09012345'), '09012345');
      expect(formatPhone(''), '');
    });
  });

  group('PhoneInputFormatter parity', () {
    final formatter = PhoneInputFormatter();

    TextEditingValue format(String text) {
      return formatter.formatEditUpdate(
        const TextEditingValue(),
        TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)),
      );
    }

    test('11-digit typed value matches formatPhone', () {
      final typed = format('09012345678').text;
      expect(typed, formatPhone('09012345678'));
    });

    test('12-digit typed value matches formatPhone', () {
      final typed = format('090123456789').text;
      expect(typed, formatPhone('090123456789'));
    });

    test('10-digit typed value matches formatPhone', () {
      final typed = format('0901234567').text;
      expect(typed, formatPhone('0901234567'));
    });
  });
}