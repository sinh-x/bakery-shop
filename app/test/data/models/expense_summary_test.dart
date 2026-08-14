import 'package:bakery_app/data/models/expense_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExpenseSummary (DG-386 Phase 5)', () {
    test('fromJson parses full category tree + uncategorized + childrenOf', () {
      final json = <String, dynamic>{
        'period': 'week',
        'startDate': '2026-08-11',
        'endDate': '2026-08-17',
        'date': '2026-08-13',
        'totalExpenses': 800000,
        'categories': [
          <String, dynamic>{
            'name': 'Nguyên liệu',
            'amount': 500000,
            'subcategories': [
              <String, dynamic>{'name': 'Trứng', 'amount': 200000},
              <String, dynamic>{'name': 'Kem', 'amount': 300000},
            ],
          },
          <String, dynamic>{
            'name': 'Nhân công',
            'amount': 300000,
            'subcategories': const [],
          },
        ],
        'uncategorized': 50000,
        'childrenOf': <String, dynamic>{
          'Nguyên liệu': ['Trứng', 'Kem'],
          'Nhân công': const [],
        },
      };

      final summary = ExpenseSummary.fromJson(json);

      expect(summary.period, 'week');
      expect(summary.startDate, '2026-08-11');
      expect(summary.endDate, '2026-08-17');
      expect(summary.date, '2026-08-13');
      expect(summary.totalExpenses, 800000);
      expect(summary.categories.length, 2);
      expect(summary.categories.first.name, 'Nguyên liệu');
      expect(summary.categories.first.amount, 500000);
      expect(summary.categories.first.subcategories.length, 2);
      expect(summary.categories.first.subcategories.first.name, 'Trứng');
      expect(summary.categories.first.subcategories.first.amount, 200000);
      expect(summary.categories.last.name, 'Nhân công');
      expect(summary.categories.last.subcategories, isEmpty);
      expect(summary.uncategorized, 50000);
      expect(summary.childrenOf['Nguyên liệu'], ['Trứng', 'Kem']);
      expect(summary.childrenOf['Nhân công'], isEmpty);
    });

    test('fromJson handles empty/missing fields with defaults', () {
      final summary = ExpenseSummary.fromJson(const {});
      expect(summary.period, '');
      expect(summary.totalExpenses, 0);
      expect(summary.categories, isEmpty);
      expect(summary.uncategorized, 0);
      expect(summary.childrenOf, isEmpty);
    });

    test('ExpenseSubcategory + ExpenseCategoryBreakdown null-safe parsing', () {
      final cat = ExpenseCategoryBreakdown.fromJson(const {'name': 'Khác'});
      expect(cat.name, 'Khác');
      expect(cat.amount, 0);
      expect(cat.subcategories, isEmpty);

      final sub = ExpenseSubcategory.fromJson(const {});
      expect(sub.name, '');
      expect(sub.amount, 0);
    });
  });
}