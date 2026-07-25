import 'package:bakery_app/data/api/blank_service.dart';
import 'package:bakery_app/data/models/blank.dart';
import 'package:bakery_app/features/blanks/blank_list_screen.dart';
import 'package:bakery_app/shared/labels/blanks.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeBlankService extends BlankService {
  _FakeBlankService(this._blanks, {this.throwOnList = false}) : super(Dio());

  List<Blank> _blanks;
  final bool throwOnList;

  @override
  Future<List<Blank>> listBlanks({String? category}) async {
    if (throwOnList) throw Exception('network error');
    if (category == null || category.isEmpty) return List<Blank>.from(_blanks);
    return _blanks.where((b) => b.category == category).toList();
  }

  @override
  Future<Blank> createBlank({
    required String name,
    String category = '',
    String unit = '',
    String notes = '',
  }) async {
    final created = Blank(
      id: _blanks.length + 1,
      name: name,
      category: category,
      unit: unit,
      notes: notes,
    );
    _blanks = [..._blanks, created];
    return created;
  }
}

GoRouter _router() => GoRouter(
      routes: [
        GoRoute(
          path: '/blanks',
          builder: (_, _) => const BlankListScreen(),
        ),
        GoRoute(
          path: '/blanks/:id',
          builder: (_, state) =>
              SizedBox(child: Text('detail-${state.pathParameters['id']}')),
        ),
      ],
      initialLocation: '/blanks',
    );

Future<void> _pump(
  WidgetTester tester,
  BlankService service,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [blankServiceProvider.overrideWithValue(service)],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows loading indicator before data', (tester) async {
    final service = _FakeBlankService(const [
      Blank(id: 1, name: 'Phôi kem', category: 'kem', unit: 'kg'),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [blankServiceProvider.overrideWithValue(service)],
        child: MaterialApp.router(routerConfig: _router()),
      ),
    );
    // Before settling: loading.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('shows empty state when no blanks', (tester) async {
    await _pump(tester, _FakeBlankService(const []));
    expect(find.text(BlanksLabels.emptyBlanks), findsOneWidget);
  });

  testWidgets('shows error state with retry', (tester) async {
    await _pump(tester, _FakeBlankService(const [], throwOnList: true));
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.text(BlanksLabels.actionCancel), findsNothing);
  });

  testWidgets('renders blank list with category filter', (tester) async {
    await _pump(
      tester,
      _FakeBlankService(const [
        Blank(id: 1, name: 'Phôi kem', category: 'kem', unit: 'kg'),
        Blank(id: 2, name: 'Phôi cốt', category: 'cot', unit: 'cai'),
      ]),
    );
    expect(find.text('Phôi kem'), findsOneWidget);
    expect(find.text('Phôi cốt'), findsOneWidget);
    // Category filter bar shows "all" plus each category chip.
    expect(
      find.descendant(
        of: find.byType(FilterChip),
        matching: find.text(BlanksLabels.categoryFilterAll),
      ),
      findsOneWidget,
    );
  });

  testWidgets('FAB opens create form', (tester) async {
    await _pump(
      tester,
      _FakeBlankService(const [
        Blank(id: 1, name: 'Phôi kem', category: 'kem', unit: 'kg'),
      ]),
    );
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text(BlanksLabels.screenCreate), findsOneWidget);
    expect(find.text(BlanksLabels.actionSave), findsOneWidget);
  });

  testWidgets('category filter narrows the list', (tester) async {
    await _pump(
      tester,
      _FakeBlankService(const [
        Blank(id: 1, name: 'Phôi kem', category: 'kem', unit: 'kg'),
        Blank(id: 2, name: 'Phôi cốt', category: 'cot', unit: 'cai'),
      ]),
    );
    // Tap the "cot" filter chip.
    final cotChip = find.descendant(
      of: find.byType(FilterChip),
      matching: find.text('cot'),
    );
    await tester.ensureVisible(cotChip);
    await tester.tap(cotChip);
    await tester.pumpAndSettle();
    expect(find.text('Phôi cốt'), findsOneWidget);
    expect(find.text('Phôi kem'), findsNothing);
  });
}