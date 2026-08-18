import 'package:bakery_app/data/api/blank_service.dart';
import 'package:bakery_app/data/models/blank.dart';
import 'package:bakery_app/features/blanks/blank_demand_screen.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bakery_app/shared/labels/shared.dart';

class _FakeBlankService extends BlankService {
  _FakeBlankService({
    List<BlankDemand> demand = const [],
    this.throwOnGetDemand = false,
  })  : _demand = List<BlankDemand>.from(demand),
        super(Dio());

  final List<BlankDemand> _demand;
  final bool throwOnGetDemand;

  int getDemandCallCount = 0;

  @override
  Future<List<BlankDemand>> getDemand() async {
    getDemandCallCount++;
    if (throwOnGetDemand) throw Exception('network error');
    return List<BlankDemand>.from(_demand);
  }
}

const _demand = [
  BlankDemand(
    blankId: 1,
    name: 'Phôi kem',
    category: 'kem',
    unit: 'kg',
    demand: 10.0,
    stock: 12.0,
    shortage: 0.0,
  ),
  BlankDemand(
    blankId: 2,
    name: 'Phôi cốt',
    category: 'cot',
    unit: 'cái',
    demand: 8.0,
    stock: 3.0,
    shortage: 5.0,
  ),
];

Future<void> _pump(
  WidgetTester tester,
  BlankService service,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [blankServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(home: BlankDemandScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows loading indicator before data', (tester) async {
    final service = _FakeBlankService(demand: _demand);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [blankServiceProvider.overrideWithValue(service)],
        child: const MaterialApp(home: BlankDemandScreen()),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('shows error state with retry when demand load fails',
      (tester) async {
    await _pump(
        tester, _FakeBlankService(demand: _demand, throwOnGetDemand: true));
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.text(SharedLabels.apiError), findsOneWidget);
    expect(find.text(SharedLabels.retry), findsOneWidget);
  });

  testWidgets('shows empty state when no demand rows', (tester) async {
    await _pump(tester, _FakeBlankService(demand: const []));
    expect(find.text(BlanksLabels.emptyData), findsOneWidget);
  });

  testWidgets('displays demand rows grouped by category with shortage highlight',
      (tester) async {
    await _pump(tester, _FakeBlankService(demand: _demand));
    expect(find.text('Phôi kem'), findsOneWidget);
    expect(find.text('Phôi cốt'), findsOneWidget);
    // Category headers (sorted: cot, kem).
    expect(find.text('cot'), findsOneWidget);
    expect(find.text('kem'), findsOneWidget);

    // Shortage row (Phôi cốt) is bold and shows a warning icon.
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    // No-shortage row (Phôi kem) shows a check icon.
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    // Shortage value chip text appears (5).
    expect(find.textContaining('5'), findsWidgets);
  });

  testWidgets('refresh button reloads the demand overview', (tester) async {
    final service = _FakeBlankService(demand: _demand);
    await _pump(tester, service);
    final refreshBtn = find.byTooltip(BlanksLabels.actionSave).first;
    await tester.tap(refreshBtn);
    await tester.pumpAndSettle();
    expect(find.text('Phôi kem'), findsOneWidget);
    expect(service.getDemandCallCount, greaterThanOrEqualTo(2));
  });
}