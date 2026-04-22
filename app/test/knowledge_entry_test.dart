import 'package:flutter_test/flutter_test.dart';
import 'package:bakery_app/data/models/knowledge_entry.dart';

void main() {
  group('KnowledgeEntry.fromJson', () {
    test('parses backend snake_case payload', () {
      final json = {
        'id': 1,
        'title': 'Công thức bánh',
        'content': 'Bột + đường + trứng',
        'type': 'recipe',
        'tags': <String>['bánh ngọt', 'test'],
        'logged_by': 'sinh',
        'source': 'app',
        'created_at': '2026-04-22T09:00:00',
        'updated_at': '2026-04-22T09:30:00',
        'pinned': true,
        'pinned_at': '2026-04-22T10:00:00',
        'photos': <dynamic>[],
      };

      final entry = KnowledgeEntry.fromJson(json);

      expect(entry.createdAt, isA<DateTime>());
      expect(entry.updatedAt, isA<DateTime>());
      expect(entry.id, 1);
      expect(entry.title, 'Công thức bánh');
      expect(entry.pinned, true);
      expect(entry.pinnedAt, isA<DateTime>());
    });

    test('handles null pinned_at', () {
      final json = {
        'id': 2,
        'title': 'Ghi chú đơn giản',
        'content': '',
        'type': 'note',
        'tags': <String>[],
        'logged_by': '',
        'source': 'app',
        'created_at': '2026-04-22T08:00:00',
        'updated_at': '2026-04-22T08:00:00',
        'pinned': false,
        'pinned_at': null,
        'photos': <dynamic>[],
      };

      final entry = KnowledgeEntry.fromJson(json);

      expect(entry.id, 2);
      expect(entry.pinned, false);
      expect(entry.pinnedAt, isNull);
    });

    test('handles empty photos array', () {
      final json = {
        'id': 3,
        'title': 'Test',
        'content': '',
        'type': 'note',
        'tags': <String>[],
        'logged_by': '',
        'source': 'app',
        'created_at': '2026-04-22T08:00:00',
        'updated_at': '2026-04-22T08:00:00',
        'pinned': false,
        'pinned_at': null,
        'photos': <dynamic>[],
      };

      final entry = KnowledgeEntry.fromJson(json);
      expect(entry.photos, isEmpty);
    });
  });
}