import '../models/event.dart';

const expenseType = 'expense';
const expenseMaxHistoryLimit = 500;

/// Debt payment method value — must match backend
/// ``schema.EXPENSE_DEBT_PAYMENT_METHOD`` ("Nợ").
const expenseDebtPaymentMethod = 'Nợ';

/// Debt status derived from the ``settlements`` array stored in the expense
/// data JSON. Matches the backend ``debt_status`` values.
enum ExpenseDebtStatus { none, unpaid, partial, paid }

class ExpenseEventData {
  const ExpenseEventData({
    required this.amountVnd,
    required this.category,
    required this.paymentMethod,
    this.paymentSource = 'Shop tiền mặt',
    required this.vendor,
    required this.note,
    this.loggedBy = '',
    this.paidByName = '',
    this.reimbursed = false,
    this.creditorName = '',
    this.settlementAmounts = const <int>[],
  });

  final int amountVnd;
  final String category;
  final String paymentMethod;
  final String paymentSource;
  final String vendor;
  final String note;
  final String loggedBy;
  final String paidByName;
  final bool reimbursed;

  /// Creditor name for debt expenses. Equals [vendor] when
  /// [paymentMethod] is [expenseDebtPaymentMethod]; empty otherwise.
  final String creditorName;

  /// Settlement amounts recorded against this debt expense, in VND.
  /// Empty for non-debt expenses or unpaid debts.
  final List<int> settlementAmounts;

  /// Total amount settled so far (sum of [settlementAmounts]).
  int get settledAmount =>
      settlementAmounts.fold<int>(0, (sum, v) => sum + v);

  /// Remaining debt balance. Zero for non-debt or fully settled expenses.
  int get remainingAmount {
    if (!isDebt) return 0;
    final remaining = amountVnd - settledAmount;
    return remaining < 0 ? 0 : remaining;
  }

  /// Whether this expense is a debt (payment_method == "Nợ").
  bool get isDebt => paymentMethod == expenseDebtPaymentMethod;

  /// Derived debt status for display. Returns [ExpenseDebtStatus.none] for
  /// non-debt expenses.
  ExpenseDebtStatus get debtStatus {
    if (!isDebt) return ExpenseDebtStatus.none;
    final settled = settledAmount;
    if (settled <= 0) return ExpenseDebtStatus.unpaid;
    if (settled >= amountVnd) return ExpenseDebtStatus.paid;
    return ExpenseDebtStatus.partial;
  }
}

class ExpenseEventMapper {
  static Map<String, dynamic> toDataMap(ExpenseEventData input) {
    // FR2 / NFR3: for debt expenses the backend ignores payment_source; we
    // persist an empty string so the data shape stays stable and the form
    // does not surface a misleading source on round-trip.
    final paymentSource =
        input.paymentMethod == expenseDebtPaymentMethod ? '' : input.paymentSource;
    return <String, dynamic>{
      'amount_vnd': input.amountVnd,
      'category': input.category,
      'payment_method': input.paymentMethod,
      'payment_source': paymentSource,
      'vendor': input.vendor,
      'note': input.note,
      'paid_by_name': input.paidByName,
      'reimbursed': input.reimbursed,
    };
  }

  static ExpenseEventData? fromEvent(BakeryEvent event) {
    if (event.type != expenseType) {
      return null;
    }
    final data = event.data;
    final amount = data['amount_vnd'];
    final amountVnd = amount is int ? amount : int.tryParse('$amount');
    if (amountVnd == null || amountVnd <= 0) {
      return null;
    }
    final paymentMethod = '${data['payment_method'] ?? ''}';
    final vendor = '${data['vendor'] ?? ''}';
    final isDebt = paymentMethod == expenseDebtPaymentMethod;
    final settlements = _parseSettlementAmounts(data['settlements']);
    return ExpenseEventData(
      amountVnd: amountVnd,
      category: '${data['category'] ?? ''}',
      paymentMethod: paymentMethod,
      paymentSource: '${data['payment_source'] ?? 'Shop tiền mặt'}',
      vendor: vendor,
      note: '${data['note'] ?? ''}',
      loggedBy: event.loggedBy,
      paidByName: _nonEmpty(data['paid_by_name']) ?? event.loggedBy,
      reimbursed: data['reimbursed'] == true,
      creditorName: isDebt ? vendor : '',
      settlementAmounts: settlements,
    );
  }

  static List<int> _parseSettlementAmounts(dynamic raw) {
    if (raw is! List) return const <int>[];
    final amounts = <int>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final value = entry['amount'];
      final parsed = value is int ? value : int.tryParse('$value');
      if (parsed != null && parsed > 0) {
        amounts.add(parsed);
      }
    }
    return amounts;
  }

  static String? _nonEmpty(dynamic value) {
    if (value == null) return null;
    final s = '$value';
    return s.isNotEmpty ? s : null;
  }

  static bool matchesFilters(
    BakeryEvent event, {
    String? category,
    String? paymentMethod,
    String? paymentSource,
    String? staffName,
    String? paidByName,
    String? loggedBy,
    String? searchText,
  }) {
    final expense = fromEvent(event);
    if (expense == null) {
      return false;
    }
    if (category != null && category.isNotEmpty && expense.category != category) {
      return false;
    }
    if (paymentMethod != null &&
        paymentMethod.isNotEmpty &&
        expense.paymentMethod != paymentMethod) {
      return false;
    }
    if (paymentSource != null &&
        paymentSource.isNotEmpty &&
        expense.paymentSource != paymentSource) {
      return false;
    }
    final logFilter = loggedBy ?? staffName;
    if (logFilter != null && logFilter.isNotEmpty && event.loggedBy != logFilter) {
      return false;
    }
    if (paidByName != null && paidByName.isNotEmpty && expense.paidByName != paidByName) {
      return false;
    }
    if (searchText == null || searchText.trim().isEmpty) {
      return true;
    }
    final query = searchText.trim().toLowerCase();
    final haystack = <String>[
      event.summary,
      expense.vendor,
      expense.note,
      event.loggedBy,
      expense.paidByName,
      expense.category,
      expense.paymentMethod,
      expense.paymentSource,
      '${expense.amountVnd}',
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }
}
