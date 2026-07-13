import 'package:bakery_app/data/api/config_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TagUsage.fromJson', () {
    test('parses integer product_ids without throwing (BUG-1 regression guard)',
        () {
      final json = <String, dynamic>{
        'key': 'khach-le',
        'count': 2,
        'product_ids': [10, 20],
      };

      final usage = TagUsage.fromJson(json);

      expect(usage.count, 2);
      expect(usage.productIds, ['10', '20']);
    });

    test('parses empty product_ids list', () {
      final json = <String, dynamic>{
        'key': 'hoa-hong',
        'count': 0,
        'product_ids': <dynamic>[],
      };

      final usage = TagUsage.fromJson(json);

      expect(usage.count, 0);
      expect(usage.productIds, isEmpty);
    });

    test('parses string product_ids for forward compatibility', () {
      final json = <String, dynamic>{
        'key': 'sinh-nhat',
        'count': 1,
        'product_ids': ['p1'],
      };

      final usage = TagUsage.fromJson(json);

      expect(usage.count, 1);
      expect(usage.productIds, ['p1']);
    });
  });
}
