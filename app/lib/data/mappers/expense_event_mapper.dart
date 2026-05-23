import '../models/event.dart';

const expenseType = 'expense';
const expenseMaxHistoryLimit = 500;

class ExpenseEventData {
  const ExpenseEventData({
    required this.amountVnd,
    required this.category,
    required this.paymentMethod,
    required this.vendor,
    required this.note,
    required this.staffName,
  });

  final int amountVnd;
  final String category;
  final String paymentMethod;
  final String vendor;
  final String note;
  final String staffName;
}

class ExpenseEventMapper {
  static Map<String, dynamic> toDataMap(ExpenseEventData input) {
    return <String, dynamic>{
      'amount_vnd': input.amountVnd,
      'category': input.category,
      'payment_method': input.paymentMethod,
      'vendor': input.vendor,
      'note': input.note,
      'staff_name': input.staffName,
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
      vendor: '${data['vendor'] ?? ''}',
      note: '${data['note'] ?? ''}',
      staffName: '${data['staff_name'] ?? ''}',
    );
  }

  static bool matchesFilters(
    BakeryEvent event, {
    String? category,
    String? paymentMethod,
    String? staffName,
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
    if (staffName != null && staffName.isNotEmpty && expense.staffName != staffName) {
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
      expense.staffName,
      expense.category,
      expense.paymentMethod,
      '${expense.amountVnd}',
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }
}
