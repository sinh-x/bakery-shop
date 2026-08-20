/// One subcategory line within a parent expense category's breakdown.
///
/// Returned by `GET /api/reports/expense-summary` (DG-386 Phase 3).
class ExpenseSubcategory {
  final String name;
  final double amount;

  const ExpenseSubcategory({
    required this.name,
    required this.amount,
  });

  factory ExpenseSubcategory.fromJson(Map<String, dynamic> json) {
    return ExpenseSubcategory(
      name: json['name'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// One parent category in the expense breakdown. `amount` is inclusive of all
/// subcategory amounts and any directly-attributed (no-subcategory) expenses.
class ExpenseCategoryBreakdown {
  final String name;
  final double amount;
  final List<ExpenseSubcategory> subcategories;

  const ExpenseCategoryBreakdown({
    required this.name,
    required this.amount,
    required this.subcategories,
  });

  factory ExpenseCategoryBreakdown.fromJson(Map<String, dynamic> json) {
    final subsRaw = json['subcategories'] as List? ?? const [];
    return ExpenseCategoryBreakdown(
      name: json['name'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      subcategories: subsRaw
          .map((s) => ExpenseSubcategory.fromJson(s as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

/// Expense-summary report returned by `GET /api/reports/expense-summary`
/// (DG-386 Phase 3).
///
/// Total expenses for a week or month period broken down by the full
/// parent/child category tree from `expense_categories`:
/// - `totalExpenses` — grand total of all expense amounts in the period.
/// - `categories` — per-parent-category breakdown, each with subcategory
///   children.
/// - `uncategorized` — expenses whose category could not be resolved.
/// - `childrenOf` — full parent→children name mapping from
///   `expense_categories` so the client can render the complete tree even
///   when a subcategory had zero expenses in the period.
class ExpenseSummary {
  final String period;
  final String startDate;
  final String endDate;
  final String date;
  final double totalExpenses;
  final List<ExpenseCategoryBreakdown> categories;
  final double uncategorized;
  final Map<String, List<String>> childrenOf;

  const ExpenseSummary({
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.date,
    required this.totalExpenses,
    required this.categories,
    required this.uncategorized,
    required this.childrenOf,
  });

  factory ExpenseSummary.fromJson(Map<String, dynamic> json) {
    final categoriesRaw = json['categories'] as List? ?? const [];
    final childrenOfRaw = json['childrenOf'] as Map? ?? const {};
    final childrenOf = <String, List<String>>{};
    childrenOfRaw.forEach((key, value) {
      if (value is List) {
        childrenOf[key.toString()] =
            value.map((e) => e.toString()).toList(growable: false);
      }
    });
    return ExpenseSummary(
      period: json['period'] as String? ?? '',
      startDate: json['startDate'] as String? ?? '',
      endDate: json['endDate'] as String? ?? '',
      date: json['date'] as String? ?? '',
      totalExpenses: (json['totalExpenses'] as num?)?.toDouble() ?? 0,
      categories: categoriesRaw
          .map((c) =>
              ExpenseCategoryBreakdown.fromJson(c as Map<String, dynamic>))
          .toList(growable: false),
      uncategorized: (json['uncategorized'] as num?)?.toDouble() ?? 0,
      childrenOf: childrenOf,
    );
  }
}