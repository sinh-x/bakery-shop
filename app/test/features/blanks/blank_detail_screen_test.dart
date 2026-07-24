import 'package:bakery_app/data/api/blank_service.dart';
import 'package:bakery_app/data/models/blank.dart';
import 'package:bakery_app/features/blanks/blank_detail_screen.dart';
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
  int deleteCallCount = 0;

  @override
  Future<List<Blank>> listBlanks({String? category}) async {
    if (throwOnList) throw Exception('network error');
    return List<Blank>.from(_blanks);
  }

  @override
  Future<void> deleteBlank(int id) async {
    deleteCallCount++;
    _blanks = _blanks.where((b) => b.id != id).toList();
  }

  @override
  Future<Blank> updateBlank(
    int id, {
    String? name,
    String? category,
    String? unit,
    String? notes,
  }) async {
    final i = _blanks.indexWhere((b) => b.id == id);
    final cur = _blanks[i];
    final updated = Blank(
      id: cur.id,
      name: name ?? cur.name,
      category: category ?? cur.category,
      unit: unit ?? cur.unit,
      notes: notes ?? cur.notes,
      createdAt: cur.createdAt,
      updatedAt: cur.updatedAt,
    );
    _blanks[i] = updated;
    return updated;
  }
}

GoRouter _router() => GoRouter(
      routes: [
        GoRoute(
          path: '/blanks/:id',
          builder: (_, state) =>
              BlankDetailScreen(blankId: int.parse(state.pathParameters['id']!)),
        ),
      ],
      initialLocation: '/blanks/1',
    );

Future<void> _pump(
  WidgetTester tester,
  BlankService service,
  String initialLocation,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [blankServiceProvider.overrideWithValue(service)],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/blanks/:id',
              builder: (_, state) => BlankDetailScreen(
                blankId: int.parse(state.pathParameters['id']!),
              ),
            ),
          ],
          initialLocation: initialLocation,
        ),
      ),
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
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('shows error state when load fails', (tester) async {
    await _pump(
      tester,
      _FakeBlankService(const [], throwOnList: true),
      '/blanks/1',
    );
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });

  testWidgets('displays blank fields', (tester) async {
    await _pump(
      tester,
      _FakeBlankService(const [
        Blank(
          id: 1,
          name: 'Phôi kem',
          category: 'kem',
          unit: 'kg',
          notes: 'Ghi chú mẫu',
        ),
      ]),
      '/blanks/1',
    );
    expect(find.text('Phôi kem'), findsOneWidget);
    expect(find.text('kem'), findsOneWidget);
    expect(find.text('kg'), findsOneWidget);
    expect(find.text('Ghi chú mẫu'), findsOneWidget);
  });

  testWidgets('delete confirmation dialog appears and cancels', (tester) async {
    final service = _FakeBlankService(const [
      Blank(id: 1, name: 'Phôi kem', category: 'kem', unit: 'kg'),
    ]);
    await _pump(tester, service, '/blanks/1');

    await tester.tap(find.text(BlanksLabels.actionDelete));
    await tester.pumpAndSettle();
    expect(find.text(BlanksLabels.messageDeleteConfirm), findsOneWidget);

    await tester.tap(find.text(BlanksLabels.actionCancel));
    await tester.pumpAndSettle();
    expect(service.deleteCallCount, 0);
  });

  testWidgets('delete confirmation dialog confirms and calls delete',
      (tester) async {
    final service = _FakeBlankService(const [
      Blank(id: 1, name: 'Phôi kem', category: 'kem', unit: 'kg'),
    ]);
    await _pump(tester, service, '/blanks/1');

    await tester.tap(find.text(BlanksLabels.actionDelete));
    await tester.pumpAndSettle();
    // Confirm via the dialog's delete button (the second one in the dialog).
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, BlanksLabels.actionDelete),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.deleteCallCount, 1);
  });

  testWidgets('edit button opens blank form in edit mode', (tester) async {
    await _pump(
      tester,
      _FakeBlankService(const [
        Blank(id: 1, name: 'Phôi kem', category: 'kem', unit: 'kg'),
      ]),
      '/blanks/1',
    );
    await tester.tap(find.text(BlanksLabels.actionEdit));
    await tester.pumpAndSettle();
    expect(find.text(BlanksLabels.actionEdit), findsWidgets);
    expect(find.text(BlanksLabels.actionSave), findsOneWidget);
  });
}