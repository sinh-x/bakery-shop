import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/features/events/event_detail_screen.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

BakeryEvent _event({
  int id = 1,
  String type = 'note',
  String summary = 'Chi tiết sự kiện',
  List<String> tags = const [],
  String loggedBy = '',
  String staffName = '',
}) {
  return BakeryEvent(
    id: id,
    timestamp: DateTime(2026, 7, 15, 8, 30),
    type: type,
    summary: summary,
    tags: tags,
    loggedBy: loggedBy,
    staffName: staffName,
    source: 'app',
    data: const {},
  );
}

GoRouter _router(BakeryEvent event) => GoRouter(
      routes: [
        GoRoute(
          path: '/events/:id',
          builder: (_, _) => EventDetailScreen(event: event),
        ),
        GoRoute(
          path: '/events/:id/edit',
          builder: (_, state) =>
              SizedBox(child: Text('edit-${state.pathParameters['id']}')),
        ),
      ],
      initialLocation: '/events/${event.id}',
    );

Future<void> _pump(WidgetTester tester, BakeryEvent event) async {
  await tester.pumpWidget(
    MaterialApp.router(routerConfig: _router(event)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders type label as app bar title', (tester) async {
    await _pump(tester, _event(type: 'equipment'));
    expect(find.text(VN.typeEquipment), findsNWidgets(2)); // AppBar + body
  });

  testWidgets('renders event summary', (tester) async {
    await _pump(tester, _event(summary: 'Hỏng lò nướng'));
    expect(find.text('Hỏng lò nướng'), findsOneWidget);
  });

  testWidgets('renders summary label', (tester) async {
    await _pump(tester, _event());
    expect(find.text(VN.eventSummary), findsOneWidget);
  });

  testWidgets('renders tag chips for tagged events', (tester) async {
    await _pump(tester, _event(tags: const ['incident', 'maintenance']));
    expect(find.text('incident'), findsOneWidget);
    expect(find.text('maintenance'), findsOneWidget);
  });

  testWidgets('renders logged-by row when loggedBy is set', (tester) async {
    await _pump(tester, _event(loggedBy: 'lan', staffName: 'Lan'));
    expect(find.textContaining(VN.loggedBy), findsOneWidget);
    expect(find.textContaining('Lan'), findsOneWidget);
  });

  testWidgets('omits logged-by row when loggedBy empty', (tester) async {
    await _pump(tester, _event(loggedBy: '', staffName: ''));
    expect(find.textContaining(VN.loggedBy), findsNothing);
  });

  testWidgets('edit button navigates to edit route', (tester) async {
    await _pump(tester, _event(id: 7));
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(find.text('edit-7'), findsOneWidget);
  });

  testWidgets('renders type badge icon for each type', (tester) async {
    await _pump(tester, _event(type: 'production'));
    expect(find.byIcon(Icons.bakery_dining), findsOneWidget);
  });

  testWidgets('renders timestamp', (tester) async {
    await _pump(tester, _event());
    // The detail screen shows the formatted timestamp.
    expect(find.textContaining('2026'), findsOneWidget);
  });
}