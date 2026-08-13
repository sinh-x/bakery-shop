import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bakery_app/data/api/report_service.dart';
import 'package:bakery_app/data/models/cashflow_summary.dart';
import 'package:bakery_app/data/models/expense_summary.dart';
import 'package:bakery_app/data/models/period_summary.dart';
import 'package:bakery_app/data/models/product_breakdown.dart';
import 'package:bakery_app/providers/dashboard/period_summary_providers.dart';

/// Fake [ReportService] recording each endpoint call and returning canned
/// payloads. Mirrors the pattern in
/// `dashboard_metrics_provider_test.dart`.
class _FakeReportService extends ReportService {
  _FakeReportService() : super(Dio());

  int getPeriodSummaryCalls = 0;
  int getProductBreakdownCalls = 0;
  int getExpenseSummaryCalls = 0;
  int getCashflowSummaryCalls = 0;

  PeriodSummary? summary;
  ProductBreakdown? productBreakdown;
  ExpenseSummary? expenseSummary;
  CashflowSummary? cashflowSummary;

  @override
  Future<PeriodSummary> getPeriodSummary({
    required String period,
    String? date,
  }) async {
    getPeriodSummaryCalls++;
    return summary ??
        PeriodSummary(
          period: period,
          startDate: '2026-08-11',
          endDate: '2026-08-17',
          date: date ?? '',
          revenue: 0,
          orderCount: 0,
          cashTotal: 0,
          bankTransferTotal: 0,
          cashInTotal: 0,
          cashOutTotal: 0,
          orders: const [],
        );
  }

  @override
  Future<ProductBreakdown> getProductBreakdown({
    required String period,
    String? date,
  }) async {
    getProductBreakdownCalls++;
    return productBreakdown ??
        ProductBreakdown(
          period: period,
          startDate: '2026-08-11',
          endDate: '2026-08-17',
          date: date ?? '',
          totalRevenue: 0,
          products: const [],
          others: const ProductBreakdownRow(
              name: 'Khác', quantity: 0, revenue: 0, percentage: 0),
        );
  }

  @override
  Future<ExpenseSummary> getExpenseSummary({
    required String period,
    String? date,
  }) async {
    getExpenseSummaryCalls++;
    return expenseSummary ??
        ExpenseSummary(
          period: period,
          startDate: '2026-08-11',
          endDate: '2026-08-17',
          date: date ?? '',
          totalExpenses: 0,
          categories: const [],
          uncategorized: 0,
          childrenOf: const {},
        );
  }

  @override
  Future<CashflowSummary> getCashflowSummary({
    required String period,
    String? date,
  }) async {
    getCashflowSummaryCalls++;
    return cashflowSummary ??
        CashflowSummary(
          period: period,
          startDate: '2026-08-11',
          endDate: '2026-08-17',
          date: date ?? '',
          operatingInflow: 0,
          operatingOutflow: 0,
          netOperatingCashFlow: 0,
          customers: const CashflowSection(
              inflow: 0, outflow: 0, perAccount: []),
          suppliers: const CashflowSection(
              inflow: 0, outflow: 0, perAccount: []),
          supplierCategories: const [],
          uncategorizedSupplier: 0,
          childrenOf: const {},
        );
  }
}

void main() {
  group('PeriodQuery', () {
    test('value equality keys the family correctly', () {
      const a = PeriodQuery(period: 'week', date: '2026-08-13');
      const b = PeriodQuery(period: 'week', date: '2026-08-13');
      const c = PeriodQuery(period: 'month', date: '2026-08-13');
      expect(a == b, isTrue);
      expect(a == c, isFalse);
      expect(a.hashCode, b.hashCode);
    });

    test('toString includes period + date', () {
      const q = PeriodQuery(period: 'week', date: '2026-08-13');
      expect(q.toString(), 'PeriodQuery(week, 2026-08-13)');
    });
  });

  group('periodReportDataProvider (NFR3 parallel fetch)', () {
    test('fires all four endpoints exactly once for one query', () async {
      final reports = _FakeReportService()
        ..summary = const PeriodSummary(
          period: 'week',
          startDate: '2026-08-11',
          endDate: '2026-08-17',
          date: '2026-08-13',
          revenue: 1000000,
          orderCount: 12,
          cashTotal: 500000,
          bankTransferTotal: 500000,
          cashInTotal: 0,
          cashOutTotal: 0,
          orders: [],
        )
        ..productBreakdown = const ProductBreakdown(
          period: 'week',
          startDate: '2026-08-11',
          endDate: '2026-08-17',
          date: '2026-08-13',
          totalRevenue: 1000000,
          products: [
            ProductBreakdownRow(
                name: 'Bánh kem',
                quantity: 5,
                revenue: 500000,
                percentage: 50.0),
          ],
          others: ProductBreakdownRow(
              name: 'Khác', quantity: 1, revenue: 500000, percentage: 50.0),
        )
        ..expenseSummary = const ExpenseSummary(
          period: 'week',
          startDate: '2026-08-11',
          endDate: '2026-08-17',
          date: '2026-08-13',
          totalExpenses: 300000,
          categories: [
            ExpenseCategoryBreakdown(
                name: 'Nguyên liệu',
                amount: 300000,
                subcategories: []),
          ],
          uncategorized: 0,
          childrenOf: {},
        )
        ..cashflowSummary = const CashflowSummary(
          period: 'week',
          startDate: '2026-08-11',
          endDate: '2026-08-17',
          date: '2026-08-13',
          operatingInflow: 800000,
          operatingOutflow: 300000,
          netOperatingCashFlow: 500000,
          customers:
              CashflowSection(inflow: 800000, outflow: 0, perAccount: []),
          suppliers:
              CashflowSection(inflow: 0, outflow: 300000, perAccount: []),
          supplierCategories: [],
          uncategorizedSupplier: 0,
          childrenOf: {},
        );

      final container = ProviderContainer(overrides: [
        reportServiceProvider.overrideWithValue(reports),
      ]);
      addTearDown(container.dispose);

      const query = PeriodQuery(period: 'week', date: '2026-08-13');
      final result = await container.read(periodReportDataProvider(query).future);

      // All four endpoints fire exactly once each (NFR3 — parallel).
      expect(reports.getPeriodSummaryCalls, 1);
      expect(reports.getProductBreakdownCalls, 1);
      expect(reports.getExpenseSummaryCalls, 1);
      expect(reports.getCashflowSummaryCalls, 1);

      // Aggregated result surfaces each sub-report's data.
      expect(result.summary.revenue, 1000000);
      expect(result.summary.orderCount, 12);
      expect(result.productBreakdown.totalRevenue, 1000000);
      expect(result.productBreakdown.products.first.name, 'Bánh kem');
      expect(result.expenseSummary.totalExpenses, 300000);
      expect(result.cashflowSummary.netOperatingCashFlow, 500000);
    });

    test('different queries resolve independently', () async {
      final reports = _FakeReportService();

      final container = ProviderContainer(overrides: [
        reportServiceProvider.overrideWithValue(reports),
      ]);
      addTearDown(container.dispose);

      const weekQuery = PeriodQuery(period: 'week', date: '2026-08-13');
      const monthQuery = PeriodQuery(period: 'month', date: '2026-08-13');

      await container.read(periodReportDataProvider(weekQuery).future);
      await container.read(periodReportDataProvider(monthQuery).future);

      // Each query triggers its own fetch of each endpoint.
      expect(reports.getPeriodSummaryCalls, 2);
      expect(reports.getProductBreakdownCalls, 2);
      expect(reports.getExpenseSummaryCalls, 2);
      expect(reports.getCashflowSummaryCalls, 2);
    });
  });

  group('individual family providers', () {
    test('periodSummaryProvider returns the API summary', () async {
      final reports = _FakeReportService()
        ..summary = const PeriodSummary(
          period: 'week',
          startDate: '2026-08-11',
          endDate: '2026-08-17',
          date: '2026-08-13',
          revenue: 777,
          orderCount: 3,
          cashTotal: 0,
          bankTransferTotal: 0,
          cashInTotal: 0,
          cashOutTotal: 0,
          orders: [],
        );

      final container = ProviderContainer(overrides: [
        reportServiceProvider.overrideWithValue(reports),
      ]);
      addTearDown(container.dispose);

      const query = PeriodQuery(period: 'week', date: '2026-08-13');
      final summary = await container.read(periodSummaryProvider(query).future);

      expect(summary.revenue, 777);
      expect(summary.orderCount, 3);
      expect(reports.getPeriodSummaryCalls, 1);
      expect(reports.getProductBreakdownCalls, 0);
    });
  });
}