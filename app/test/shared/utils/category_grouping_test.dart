import 'package:bakery_app/data/models/category.dart';
import 'package:bakery_app/shared/utils/category_grouping.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestProduct {
  const _TestProduct(this.name, this.category);

  final String name;
  final String category;
}

void main() {
  group('groupItemsByCategory', () {
    test('orders by category position then category and item name', () {
      final categories = [
        const Category(
          id: 1,
          slug: 'banh_kem',
          name: 'Banh kem',
          codePrefix: 'BKM',
          active: 1,
          position: 2,
        ),
        const Category(
          id: 2,
          slug: 'phu_kien',
          name: 'Phu kien',
          codePrefix: 'PKI',
          active: 1,
          position: 1,
        ),
      ];

      final items = [
        const _TestProduct('Kem dau', 'banh_kem'),
        const _TestProduct('No', 'phu_kien'),
        const _TestProduct('Hop', 'phu_kien'),
      ];

      final grouped = groupItemsByCategory<_TestProduct>(
        items: items,
        categories: categories,
        categoryKeyOf: (item) => item.category,
        itemLabelOf: (item) => item.name,
      );

      expect(grouped.map((section) => section.categoryKey), [
        'phu_kien',
        'banh_kem',
      ]);
      expect(grouped.first.items.map((item) => item.name), ['Hop', 'No']);
    });

    test('filters sections but preserves grouped headers', () {
      final sections = [
        const GroupedCategorySection<_TestProduct>(
          categoryKey: 'banh_kem',
          categoryName: 'Banh kem',
          categoryPosition: 1,
          items: [
            _TestProduct('Kem dau', 'banh_kem'),
            _TestProduct('Kem socola', 'banh_kem'),
          ],
        ),
        const GroupedCategorySection<_TestProduct>(
          categoryKey: 'phu_kien',
          categoryName: 'Phu kien',
          categoryPosition: 2,
          items: [_TestProduct('No', 'phu_kien')],
        ),
      ];

      final filtered = filterGroupedSections<_TestProduct>(
        sections: sections,
        matches: (item) => item.name.toLowerCase().contains('kem'),
      );

      expect(filtered.length, 1);
      expect(filtered.first.categoryName, 'Banh kem');
      expect(filtered.first.items.length, 2);
    });
  });
}
