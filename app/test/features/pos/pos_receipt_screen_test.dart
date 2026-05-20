import 'dart:typed_data';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/receipt_service.dart';
import 'package:bakery_app/features/pos/pos_receipt_screen.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeReceiptService extends ReceiptService {
  _FakeReceiptService() : super(Dio());

  static final Uint8List _tinyPng = Uint8List.fromList(<int>[
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82,
    0, 0, 0, 1, 0, 0, 0, 1, 8, 4, 0, 0, 0, 181, 28, 12,
    2, 0, 0, 0, 11, 73, 68, 65, 84, 120, 218, 99, 252, 255, 31,
    0, 3, 3, 2, 0, 239, 113, 149, 43, 0, 0, 0, 0, 73, 69,
    78, 68, 174, 66, 96, 130,
  ]);

  String? fetchedOrderRef;
  ReceiptType? fetchedType;
  String? printedOrderRef;
  ReceiptType? printedType;

  @override
  Future<Uint8List> fetchReceipt({
    required String orderRef,
    required ReceiptType type,
    int? itemId,
    bool photos = true,
  }) async {
    fetchedOrderRef = orderRef;
    fetchedType = type;
    return _tinyPng;
  }

  @override
  Future<void> printReceipt({
    required String orderRef,
    required ReceiptType type,
    int? itemId,
    String? printedBy,
  }) async {
    printedOrderRef = orderRef;
    printedType = type;
  }
}

Future<void> _pumpReceiptApp(
  WidgetTester tester, {
  required _FakeReceiptService receiptService,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();

  final router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/pos',
        builder: (BuildContext context, GoRouterState state) {
          return const Text('POS Home');
        },
      ),
      GoRoute(
        path: '/pos/receipt/:ref',
        builder: (BuildContext context, GoRouterState state) {
          return PosReceiptScreen(orderRef: state.pathParameters['ref']!);
        },
      ),
    ],
    initialLocation: '/pos/receipt/ORD-001',
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        receiptServiceProvider.overrideWithValue(receiptService),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('POS receipt flow after checkout finalization', () {
    testWidgets('shows print and skip actions without edit action', (
      WidgetTester tester,
    ) async {
      final fakeReceiptService = _FakeReceiptService();
      await _pumpReceiptApp(tester, receiptService: fakeReceiptService);

      expect(fakeReceiptService.fetchedOrderRef, 'ORD-001');
      expect(fakeReceiptService.fetchedType, ReceiptType.customer);
      expect(find.widgetWithText(FilledButton, 'In'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, VN.xong), findsOneWidget);
      expect(find.text(VN.editOrder), findsNothing);
    });

    testWidgets('print action uses existing receipt print service', (
      WidgetTester tester,
    ) async {
      final fakeReceiptService = _FakeReceiptService();
      await _pumpReceiptApp(tester, receiptService: fakeReceiptService);

      await tester.tap(find.widgetWithText(FilledButton, 'In'));
      await tester.pumpAndSettle();

      expect(fakeReceiptService.printedOrderRef, 'ORD-001');
      expect(fakeReceiptService.printedType, ReceiptType.customer);
    });

    testWidgets('skip returns to POS home', (WidgetTester tester) async {
      final fakeReceiptService = _FakeReceiptService();
      await _pumpReceiptApp(tester, receiptService: fakeReceiptService);

      await tester.tap(find.widgetWithText(OutlinedButton, VN.xong));
      await tester.pumpAndSettle();

      expect(find.text('POS Home'), findsOneWidget);
    });
  });
}
