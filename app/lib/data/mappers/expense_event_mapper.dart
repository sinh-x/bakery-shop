import '../models/event.dart';

const expenseType = 'expense';
const expenseMaxHistoryLimit = 500;

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
}

class ExpenseEventMapper {
  static Map<String, dynamic> toDataMap(ExpenseEventData input) {
    return <String, dynamic>{
      'amount_vnd': input.amountVnd,
      'category': input.category,
      'payment_method': input.paymentMethod,
      'payment_source': input.paymentSource,
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
    return ExpenseEventData(
      amountVnd: amountVnd,
      category: '${data['category'] ?? ''}',
      paymentMethod: '${data['payment_method'] ?? ''}',
      paymentSource: '${data['payment_source'] ?? 'Shop tiền mặt'}',
      vendor: '${data['vendor'] ?? ''}',
      note: '${data['note'] ?? ''}',
      loggedBy: event.loggedBy,
      paidByName: _nonEmpty(data['paid_by_name']) ?? event.loggedBy,
      reimbursed: data['reimbursed'] == true,
    );
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
    if (staffName != null && staffName.isNotEmpty && event.loggedBy != staffName) {
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
