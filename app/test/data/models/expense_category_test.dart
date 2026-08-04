import 'package:bakery_app/data/models/expense_category.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExpenseCategory (DG-302 Phase 3)', () {
    test('fromJson parses parent with children', () {
      final json = <String, dynamic>{
        'id': 1,
        'name': 'Nguyên liệu',
        'account_code': '5100',
        'parent_id': null,
        'children': [
          {
            'id': 9,
            'name': 'Trứng',
            'account_code': '5110',
            'parent_id': 1,
          },
          {
            'id': 10,
            'name': 'Kem',
            'account_code': '5120',
            'parent_id': 1,
          },
        ],
      };

      final cat = ExpenseCategory.fromJson(json);

      expect(cat.id, 1);
      expect(cat.name, 'Nguyên liệu');
      expect(cat.accountCode, '5100');
      expect(cat.parentId, isNull);
      expect(cat.hasChildren, isTrue);
      expect(cat.isSubcategory, isFalse);
      expect(cat.children.length, 2);
      expect(cat.children.first.name, 'Trứng');
      expect(cat.children.first.isSubcategory, isTrue);
      expect(cat.children.first.hasChildren, isFalse);
    });

    test('fromJson tolerates missing children array', () {
      final cat = ExpenseCategory.fromJson(<String, dynamic>{
        'id': 3,
        'name': 'Vận chuyển',
        'account_code': '5300',
        'parent_id': null,
      });
      expect(cat.children, isEmpty);
      expect(cat.hasChildren, isFalse);
    });

    test('toJson round-trips the tree', () {
      const cat = ExpenseCategory(
        id: 2,
        name: 'Bao bì',
        accountCode: '5200',
        parentId: null,
        children: [
          ExpenseCategory(
            id: 12,
            name: 'Hộp & đế',
            accountCode: '5210',
            parentId: 2,
          ),
        ],
      );
      final json = cat.toJson();
      expect(json['name'], 'Bao bì');
      expect((json['children'] as List).length, 1);
    });
  });

  group('ExpenseCategoryTree extension', () {
    const tree = <ExpenseCategory>[
      ExpenseCategory(
        id: 1,
        name: 'Nguyên liệu',
        accountCode: '5100',
        children: [
          ExpenseCategory(id: 9, name: 'Trứng', accountCode: '5110', parentId: 1),
          ExpenseCategory(id: 10, name: 'Kem', accountCode: '5120', parentId: 1),
        ],
      ),
      ExpenseCategory(id: 2, name: 'Bao bì', accountCode: '5200'),
    ];

    test('parentNames lists parents in order', () {
      expect(tree.parentNames, ['Nguyên liệu', 'Bao bì']);
    });

    test('subcategoriesOf returns children for a parent', () {
      expect(tree.subcategoriesOf('Nguyên liệu').length, 2);
      expect(tree.subcategoriesOf('Bao bì'), isEmpty);
      expect(tree.subcategoriesOf('Khác'), isEmpty);
    });

    test('allSubcategoryNames flattens children', () {
      expect(tree.allSubcategoryNames, ['Trứng', 'Kem']);
    });

    test('parentNameOfSubcategory resolves parent', () {
      expect(tree.parentNameOfSubcategory('Trứng'), 'Nguyên liệu');
      expect(tree.parentNameOfSubcategory('Nguyên liệu'), isNull);
    });
  });
}