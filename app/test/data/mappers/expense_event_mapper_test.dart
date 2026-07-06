import 'package:bakery_app/data/mappers/expense_event_mapper.dart';
import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:flutter_test/flutter_test.dart';

BakeryEvent _expenseEvent({
  required int id,
  required int amount,
  String paymentMethod = 'Tiền mặt',
  String vendor = '',
  String paymentSource = 'Shop tiền mặt',
  List<Map<String, dynamic>> settlements = const [],
}) {
  return BakeryEvent(
    id: id,
    timestamp: DateTime.parse('2026-07-06T10:00:00Z'),
    type: expenseType,
    summary: 'Chi phí test',
    loggedBy: 'Lan',
    data: <String, dynamic>{
      'amount_vnd': amount,
      'category': 'Nguyên liệu',
      'payment_method': paymentMethod,
      'payment_source': paymentSource,
      'vendor': vendor,
      'note': '',
      'paid_by_name': 'Lan',
      'reimbursed': false,
      'settlements': settlements,
    },
  );
}

void main() {
  group('ExpenseEventMapper debt fields', () {
    test('fromEvent maps creditorName from vendor for debt expenses', () {
      final event = _expenseEvent(
        id: 1,
        amount: 500000,
        paymentMethod: VN.methodDebt,
        vendor: 'Nhà cung cấp A',
      );
      final data = ExpenseEventMapper.fromEvent(event)!;

      expect(data.isDebt, isTrue);
      expect(data.creditorName, 'Nhà cung cấp A');
      expect(data.paymentMethod, VN.methodDebt);
    });

    test('fromEvent leaves creditorName empty for non-debt expenses', () {
      final event = _expenseEvent(
        id: 2,
        amount: 120000,
        paymentMethod: VN.methodCash,
        vendor: 'NCC A',
      );
      final data = ExpenseEventMapper.fromEvent(event)!;

      expect(data.isDebt, isFalse);
      expect(data.creditorName, '');
    });

    test('fromEvent parses settlementAmounts from settlements array', () {
      final event = _expenseEvent(
        id: 3,
        amount: 500000,
        paymentMethod: VN.methodDebt,
        vendor: 'NCC A',
        settlements: [
          {'id': 1, 'amount': 200000},
          {'id': 2, 'amount': 100000},
        ],
      );
      final data = ExpenseEventMapper.fromEvent(event)!;

      expect(data.settlementAmounts, [200000, 100000]);
      expect(data.settledAmount, 300000);
      expect(data.remainingAmount, 200000);
    });

    test('debtStatus is unpaid when no settlements exist', () {
      final event = _expenseEvent(
        id: 4,
        amount: 500000,
        paymentMethod: VN.methodDebt,
        vendor: 'NCC A',
      );
      final data = ExpenseEventMapper.fromEvent(event)!;

      expect(data.debtStatus, ExpenseDebtStatus.unpaid);
    });

    test('debtStatus is partial when settled less than amount', () {
      final event = _expenseEvent(
        id: 5,
        amount: 500000,
        paymentMethod: VN.methodDebt,
        vendor: 'NCC A',
        settlements: [
          {'amount': 300000},
        ],
      );
      final data = ExpenseEventMapper.fromEvent(event)!;

      expect(data.debtStatus, ExpenseDebtStatus.partial);
    });

    test('debtStatus is paid when settled equals amount', () {
      final event = _expenseEvent(
        id: 6,
        amount: 500000,
        paymentMethod: VN.methodDebt,
        vendor: 'NCC A',
        settlements: [
          {'amount': 500000},
        ],
      );
      final data = ExpenseEventMapper.fromEvent(event)!;

      expect(data.debtStatus, ExpenseDebtStatus.paid);
      expect(data.remainingAmount, 0);
    });

    test('debtStatus is none for non-debt expenses', () {
      final event = _expenseEvent(
        id: 7,
        amount: 120000,
        paymentMethod: VN.methodCash,
      );
      final data = ExpenseEventMapper.fromEvent(event)!;

      expect(data.debtStatus, ExpenseDebtStatus.none);
      expect(data.remainingAmount, 0);
    });
  });

  group('ExpenseEventMapper toDataMap debt handling', () {
    test('toDataMap clears payment_source for debt expenses', () {
      const payload = ExpenseEventData(
        amountVnd: 500000,
        category: 'Nguyên liệu',
        paymentMethod: 'Nợ',
        paymentSource: 'Shop tiền mặt',
        vendor: 'NCC A',
        note: '',
        loggedBy: 'Lan',
        paidByName: 'Lan',
      );

      final map = ExpenseEventMapper.toDataMap(payload);

      expect(map['payment_method'], 'Nợ');
      expect(map['payment_source'], '');
      expect(map['vendor'], 'NCC A');
    });

    test('toDataMap preserves payment_source for non-debt expenses', () {
      const payload = ExpenseEventData(
        amountVnd: 120000,
        category: 'Nguyên liệu',
        paymentMethod: 'Tiền mặt',
        paymentSource: 'Shop tiền mặt',
        vendor: '',
        note: '',
        loggedBy: 'Lan',
        paidByName: 'Lan',
      );

      final map = ExpenseEventMapper.toDataMap(payload);

      expect(map['payment_source'], 'Shop tiền mặt');
    });
  });
}