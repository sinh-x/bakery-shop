/// Per-cash-account inflow/outflow pair for one cashflow sub-section.
///
/// Returned by `GET /api/reports/cashflow-summary` (DG-386 Phase 4).
class CashflowAccountMovement {
  final String code;
  final double inflow;
  final double outflow;
  final double net;

  const CashflowAccountMovement({
    required this.code,
    required this.inflow,
    required this.outflow,
    required this.net,
  });

  factory CashflowAccountMovement.fromJson(Map<String, dynamic> json) {
    return CashflowAccountMovement(
      code: json['code'] as String? ?? '',
      inflow: (json['inflow'] as num?)?.toDouble() ?? 0,
      outflow: (json['outflow'] as num?)?.toDouble() ?? 0,
      net: (json['net'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// One operating-activity sub-section (customers or suppliers) in the
/// cashflow summary.
class CashflowSection {
  final double inflow;
  final double outflow;
  final List<CashflowAccountMovement> perAccount;

  const CashflowSection({
    required this.inflow,
    required this.outflow,
    required this.perAccount,
  });

  factory CashflowSection.fromJson(Map<String, dynamic> json) {
    final perAccountRaw = json['perAccount'] as List? ?? const [];
    return CashflowSection(
      inflow: (json['inflow'] as num?)?.toDouble() ?? 0,
      outflow: (json['outflow'] as num?)?.toDouble() ?? 0,
      perAccount: perAccountRaw
          .map((a) =>
              CashflowAccountMovement.fromJson(a as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

/// One subcategory line within a supplier category's cashflow breakdown.
class CashflowSubcategory {
  final String name;
  final double amount;

  const CashflowSubcategory({
    required this.name,
    required this.amount,
  });

  factory CashflowSubcategory.fromJson(Map<String, dynamic> json) {
    return CashflowSubcategory(
      name: json['name'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// One parent category in the supplier-outflow breakdown. `amount` is
/// inclusive of all subcategory amounts.
class CashflowSupplierCategory {
  final String name;
  final double amount;
  final List<CashflowSubcategory> subcategories;

  const CashflowSupplierCategory({
    required this.name,
    required this.amount,
    required this.subcategories,
  });

  factory CashflowSupplierCategory.fromJson(Map<String, dynamic> json) {
    final subsRaw = json['subcategories'] as List? ?? const [];
    return CashflowSupplierCategory(
      name: json['name'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      subcategories: subsRaw
          .map((s) => CashflowSubcategory.fromJson(s as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

/// Cashflow-summary report returned by `GET /api/reports/cashflow-summary`
/// (DG-386 Phase 4).
///
/// Operating-activity cash-flow summary for a week or month, computed from
/// journal entries on the bakery's cash accounts without requiring an active
/// cash drawer. Mirrors the operating-activities section of
/// `baker report cashflow`:
/// - `operatingInflow` — total operating cash inflow (customers).
/// - `operatingOutflow` — total operating cash outflow (suppliers +
///   employees, including `order_shipping_release`).
/// - `netOperatingCashFlow` — inflow minus outflow.
/// - `customers` — customer sub-section (`payment_transaction`).
/// - `suppliers` — supplier sub-section (expense + expense_settlement +
///   order_shipping_release).
/// - `supplierCategories` — category/subcategory breakdown of cash paid to
///   suppliers (expense + expense_settlement only).
/// - `uncategorizedSupplier` — supplier outflow whose category could not be
///   resolved.
/// - `childrenOf` — full parent→children mapping from `expense_categories`
///   for complete tree rendering.
class CashflowSummary {
  final String period;
  final String startDate;
  final String endDate;
  final String date;
  final double operatingInflow;
  final double operatingOutflow;
  final double netOperatingCashFlow;
  final CashflowSection customers;
  final CashflowSection suppliers;
  final List<CashflowSupplierCategory> supplierCategories;
  final double uncategorizedSupplier;
  final Map<String, List<String>> childrenOf;

  const CashflowSummary({
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.date,
    required this.operatingInflow,
    required this.operatingOutflow,
    required this.netOperatingCashFlow,
    required this.customers,
    required this.suppliers,
    required this.supplierCategories,
    required this.uncategorizedSupplier,
    required this.childrenOf,
  });

  factory CashflowSummary.fromJson(Map<String, dynamic> json) {
    final supplierCatsRaw = json['supplierCategories'] as List? ?? const [];
    final childrenOfRaw = json['childrenOf'] as Map? ?? const {};
    final childrenOf = <String, List<String>>{};
    childrenOfRaw.forEach((key, value) {
      if (value is List) {
        childrenOf[key.toString()] =
            value.map((e) => e.toString()).toList(growable: false);
      }
    });
    return CashflowSummary(
      period: json['period'] as String? ?? '',
      startDate: json['startDate'] as String? ?? '',
      endDate: json['endDate'] as String? ?? '',
      date: json['date'] as String? ?? '',
      operatingInflow: (json['operatingInflow'] as num?)?.toDouble() ?? 0,
      operatingOutflow: (json['operatingOutflow'] as num?)?.toDouble() ?? 0,
      netOperatingCashFlow:
          (json['netOperatingCashFlow'] as num?)?.toDouble() ?? 0,
      customers: CashflowSection.fromJson(
          json['customers'] as Map<String, dynamic>? ?? const {}),
      suppliers: CashflowSection.fromJson(
          json['suppliers'] as Map<String, dynamic>? ?? const {}),
      supplierCategories: supplierCatsRaw
          .map((c) =>
              CashflowSupplierCategory.fromJson(c as Map<String, dynamic>))
          .toList(growable: false),
      uncategorizedSupplier:
          (json['uncategorizedSupplier'] as num?)?.toDouble() ?? 0,
      childrenOf: childrenOf,
    );
  }
}