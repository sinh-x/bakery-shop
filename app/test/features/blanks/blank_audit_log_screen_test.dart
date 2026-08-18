import 'package:bakery_app/data/api/blank_service.dart';
import 'package:bakery_app/data/models/blank.dart';
import 'package:bakery_app/features/blanks/blank_audit_log_screen.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

class _FakeBlankService extends BlankService {
  _FakeBlankService({
    List<BlankStockLog> log = const [],
    this.throwOnListLog = false,
  })  : _log = List<BlankStockLog>.from(log),
        super(Dio());

  final List<BlankStockLog> _log;
  final bool throwOnListLog;

  @override
  Future<List<BlankStockLog>> listStockLog(int blankId) async {
    if (throwOnListLog) throw Exception('network error');
    return List<BlankStockLog>.from(_log);
  }
}

const _entries = [
  BlankStockLog(
    id: 1,
    blankId: 2,
    quantityChange: 10.0,
    type: 'production',
    producedDate: '2026-07-24',
    expiryDate: '2026-07-31',
    createdAt: '2026-07-24T10:00:00Z',
  ),
  BlankStockLog(
    id: 2,
    blankId: 2,
    quantityChange: -4.0,
    type: 'usage',
    producedDate: null,
    expiryDate: null,
    createdAt: '2026-07-24T12:00:00Z',
  ),
];

Future<void> _pump(
  WidgetTester tester,
  BlankService service, {
  int blankId = 2,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [blankServiceProvider.overrideWithValue(service)],
      child: MaterialApp(home: BlankAuditLogScreen(blankId: blankId)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows loading indicator before data', (tester) async {
    final service = _FakeBlankService(log: _entries);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [blankServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: BlankAuditLogScreen(blankId: 2)),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('shows error state with retry when audit log load fails',
      (tester) async {
    await _pump(tester, _FakeBlankService(log: _entries, throwOnListLog: true));
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.text(VN.apiError), findsOneWidget);
  });

  testWidgets('shows empty state when no audit log entries exist',
      (tester) async {
    await _pump(tester, _FakeBlankService(log: const []));
    expect(find.text(BlanksLabels.emptyHistory), findsOneWidget);
  });

  testWidgets('displays audit log entries with type and quantity change',
      (tester) async {
    await _pump(tester, _FakeBlankService(log: _entries));
    // Production entry: +10 (Sản xuất).
    expect(find.text('+10 (Sản xuất)'), findsOneWidget);
    // Usage entry: -4 (Sử dụng).
    expect(find.text('-4 (Sử dụng)'), findsOneWidget);
    // Produced date chip for the production entry.
    expect(find.textContaining('2026-07-24'), findsWidgets);
  });

  testWidgets('refresh button reloads the audit log', (tester) async {
    final service = _FakeBlankService(log: _entries);
    await _pump(tester, service);
    final refreshBtn = find.byTooltip(BlanksLabels.actionSave).first;
    await tester.tap(refreshBtn);
    await tester.pumpAndSettle();
    expect(find.text('+10 (Sản xuất)'), findsOneWidget);
  });
}