import 'package:bakery_app/data/models/cashflow_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CashflowSummary (DG-386 Phase 5)', () {
    test('fromJson parses full operating cashflow payload', () {
      final json = <String, dynamic>{
        'period': 'month',
        'startDate': '2026-08-01',
        'endDate': '2026-08-31',
        'date': '2026-08-13',
        'operatingInflow': 1200000,
        'operatingOutflow': 600000,
        'netOperatingCashFlow': 600000,
        'customers': <String, dynamic>{
          'inflow': 1200000,
          'outflow': 0,
          'perAccount': [
            <String, dynamic>{
              'code': '1101',
              'inflow': 800000,
              'outflow': 0,
              'net': 800000,
            },
            <String, dynamic>{
              'code': '1200',
              'inflow': 400000,
              'outflow': 0,
              'net': 400000,
            },
          ],
        },
        'suppliers': <String, dynamic>{
          'inflow': 0,
          'outflow': 600000,
          'perAccount': [
            <String, dynamic>{
              'code': '1101',
              'inflow': 0,
              'outflow': 400000,
              'net': -400000,
            },
          ],
        },
        'supplierCategories': [
          <String, dynamic>{
            'name': 'Nguyên liệu',
            'amount': 400000,
            'subcategories': [
              <String, dynamic>{'name': 'Trứng', 'amount': 250000},
              <String, dynamic>{'name': 'Bơ', 'amount': 150000},
            ],
          },
        ],
        'uncategorizedSupplier': 200000,
        'childrenOf': <String, dynamic>{
          'Nguyên liệu': ['Trứng', 'Bơ'],
        },
      };

      final summary = CashflowSummary.fromJson(json);

      expect(summary.period, 'month');
      expect(summary.startDate, '2026-08-01');
      expect(summary.endDate, '2026-08-31');
      expect(summary.date, '2026-08-13');
      expect(summary.operatingInflow, 1200000);
      expect(summary.operatingOutflow, 600000);
      expect(summary.netOperatingCashFlow, 600000);
      expect(summary.customers.inflow, 1200000);
      expect(summary.customers.outflow, 0);
      expect(summary.customers.perAccount.length, 2);
      expect(summary.customers.perAccount.first.code, '1101');
      expect(summary.customers.perAccount.first.inflow, 800000);
      expect(summary.customers.perAccount.first.outflow, 0);
      expect(summary.customers.perAccount.first.net, 800000);
      expect(summary.suppliers.outflow, 600000);
      expect(summary.suppliers.perAccount.first.net, -400000);
      expect(summary.supplierCategories.length, 1);
      expect(summary.supplierCategories.first.name, 'Nguyên liệu');
      expect(summary.supplierCategories.first.amount, 400000);
      expect(summary.supplierCategories.first.subcategories.length, 2);
      expect(summary.supplierCategories.first.subcategories.first.name, 'Trứng');
      expect(summary.supplierCategories.first.subcategories.first.amount,
          250000);
      expect(summary.uncategorizedSupplier, 200000);
      expect(summary.childrenOf['Nguyên liệu'], ['Trứng', 'Bơ']);
    });

    test('fromJson handles empty/missing fields with defaults', () {
      final summary = CashflowSummary.fromJson(const {});
      expect(summary.period, '');
      expect(summary.operatingInflow, 0);
      expect(summary.operatingOutflow, 0);
      expect(summary.netOperatingCashFlow, 0);
      expect(summary.customers.inflow, 0);
      expect(summary.customers.outflow, 0);
      expect(summary.customers.perAccount, isEmpty);
      expect(summary.suppliers.perAccount, isEmpty);
      expect(summary.supplierCategories, isEmpty);
      expect(summary.uncategorizedSupplier, 0);
      expect(summary.childrenOf, isEmpty);
    });

    test('nested model fromJson null-safety', () {
      final movement = CashflowAccountMovement.fromJson(const {'code': 'A'});
      expect(movement.code, 'A');
      expect(movement.inflow, 0);
      expect(movement.outflow, 0);
      expect(movement.net, 0);

      final section = CashflowSection.fromJson(const {});
      expect(section.inflow, 0);
      expect(section.outflow, 0);
      expect(section.perAccount, isEmpty);

      final sub = CashflowSubcategory.fromJson(const {'name': 'X'});
      expect(sub.name, 'X');
      expect(sub.amount, 0);

      final cat = CashflowSupplierCategory.fromJson(const {});
      expect(cat.name, '');
      expect(cat.amount, 0);
      expect(cat.subcategories, isEmpty);
    });
  });
}