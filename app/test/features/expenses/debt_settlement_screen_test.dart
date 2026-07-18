import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/features/expenses/debt_settlement_screen.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/login_screen_test_helpers.dart';

BakeryEvent _debtEvent({
  required int id,
  required int amount,
  List<Map<String, dynamic>> settlements = const [],
  String vendor = 'Nhà cung cấp A',
}) {
  return BakeryEvent(
    id: id,
    timestamp: DateTime.parse('2026-07-06T10:00:00Z'),
    type: 'expense',
    summary: 'Chi phi nợ',
    loggedBy: 'Lan',
    data: {
      'amount_vnd': amount,
      'category': 'Nguyên liệu',
      'payment_method': 'Nợ',
      'payment_source': '',
      'vendor': vendor,
      'note': '',
      'paid_by_name': '',
      'reimbursed': false,
      'settlements': settlements,
    },
  );
}

void main() {
  testWidgets(
    'settlement screen loads debt and shows summary with remaining balance',
    (tester) async {
      final event = _debtEvent(
        id: 7,
        amount: 500000,
        settlements: [
          {'id': 1, 'amount': 200000},
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DebtSettlementScreen(
            eventId: 7,
            loadEvent: (id, ref) async => event,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Total debt 500000, settled 200000, remaining 300000.
      expect(find.textContaining(VN.debtSettlementCreditor), findsOneWidget);
      expect(
        find.text('${VN.debtSettlementTotalDebt}: ${formatVND(500000)}'),
        findsOneWidget,
      );
      expect(
        find.text('${VN.debtSettlementSettledSoFar}: ${formatVND(200000)}'),
        findsOneWidget,
      );
      expect(
        find.text('${VN.debtSettlementRemainingLabel}: ${formatVND(300000)}'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'submitting a valid settlement calls submitSettlement with correct fields',
    (tester) async {
      final event = _debtEvent(id: 7, amount: 500000);
      Map<String, dynamic>? captured;

      SharedPreferences.setMockInitialValues({
        'auth_token': kTestAdminToken,
        'auth_username': 'Lan',
        'auth_role': 'staff',
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            home: DebtSettlementScreen(
              eventId: 7,
              loadEvent: (id, ref) async => event,
              submitSettlement: ({
                required eventId,
                required amount,
                required paymentMethod,
                required paymentSource,
                required note,
                required settledBy,
              }) async {
                captured = {
                  'eventId': eventId,
                  'amount': amount,
                  'paymentMethod': paymentMethod,
                  'paymentSource': paymentSource,
                  'note': note,
                  'settledBy': settledBy,
                };
                return {'status': 'partial', 'remaining': 200000};
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter amount 300000.
      await tester.enterText(
        find.byType(TextFormField).first,
        '300000',
      );

      // Tap submit.
      await tester.tap(find.text(VN.debtSettlementSaveAction));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!['eventId'], 7);
      expect(captured!['amount'], 300000);
      expect(captured!['paymentMethod'], VN.methodCash);
      expect(captured!['paymentSource'], VN.paymentSourceShopCash);
      // settledBy is sourced from loggedByProvider (saved staff name).
      expect(captured!['settledBy'], 'Lan');
    },
  );

  testWidgets(
    'amount exceeding remaining shows validation error and blocks submit',
    (tester) async {
      final event = _debtEvent(
        id: 7,
        amount: 500000,
        settlements: [
          {'id': 1, 'amount': 200000},
        ],
      );
      bool submitted = false;

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            home: DebtSettlementScreen(
              eventId: 7,
              loadEvent: (id, ref) async => event,
              submitSettlement: ({
                required eventId,
                required amount,
                required paymentMethod,
                required paymentSource,
                required note,
                required settledBy,
              }) async {
                submitted = true;
                return {'status': 'paid'};
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Remaining is 300000. Enter 400000 — should fail validation.
      await tester.enterText(find.byType(TextFormField).first, '400000');
      await tester.tap(find.text(VN.debtSettlementSaveAction));
      await tester.pumpAndSettle();

      expect(find.text(VN.debtSettlementAmountExceedsRemaining), findsOneWidget);
      expect(submitted, isFalse);
    },
  );

  testWidgets(
    'empty amount shows required validation error',
    (tester) async {
      final event = _debtEvent(id: 7, amount: 500000);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            home: DebtSettlementScreen(
              eventId: 7,
              loadEvent: (id, ref) async => event,
              submitSettlement: ({
                required eventId,
                required amount,
                required paymentMethod,
                required paymentSource,
                required note,
                required settledBy,
              }) async => {'status': 'paid'},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(VN.debtSettlementSaveAction));
      await tester.pumpAndSettle();

      expect(find.text(VN.debtSettlementAmountRequired), findsOneWidget);
    },
  );

  testWidgets(
    'shows error card when loadEvent throws',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: DebtSettlementScreen(
              eventId: 99,
              loadEvent: (id, ref) async => throw Exception('not found'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(VN.debtSettlementFailure), findsOneWidget);
    },
  );
}
