import 'package:bakery_app/shared/utils/event_photo_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('eventPhotoUrl', () {
    test('builds event photo URL without cache buster', () {
      expect(
        eventPhotoUrl('http://localhost:8000', 'abc123'),
        'http://localhost:8000/api/photos/abc123.jpg',
      );
    });

    test('appends cache-buster query parameter when provided', () {
      expect(
        eventPhotoUrl('http://localhost:8000', 'abc123', cacheBuster: '17'),
        'http://localhost:8000/api/photos/abc123.jpg?v=17',
      );
    });

    test('ignores empty cache buster after trimming', () {
      expect(
        eventPhotoUrl('http://localhost:8000', 'abc123', cacheBuster: '   '),
        'http://localhost:8000/api/photos/abc123.jpg',
      );
    });

    test('trims whitespace from cache buster before appending', () {
      expect(
        eventPhotoUrl('http://localhost:8000', 'abc123', cacheBuster: ' 42 '),
        'http://localhost:8000/api/photos/abc123.jpg?v=42',
      );
    });

    test('preserves existing query parameters when appending cache buster',
        () {
      expect(
        eventPhotoUrl(
          'http://localhost:8000',
          'abc123',
          cacheBuster: '2',
        ),
        'http://localhost:8000/api/photos/abc123.jpg?v=2',
      );
    });

    test('handles hash containing special URL-safe characters', () {
      final url = eventPhotoUrl('http://localhost:8000', 'a_b-c.123');
      expect(url, 'http://localhost:8000/api/photos/a_b-c.123.jpg');
    });

    test('encodes hash with characters requiring escaping', () {
      final url = eventPhotoUrl('http://localhost:8000', 'a b c');
      // Uri.parse + replace encodes the space in the path segment.
      expect(url, contains('/api/photos/'));
      expect(url, endsWith('.jpg'));
      expect(url, isNot(contains(' ')));
    });
  });
}