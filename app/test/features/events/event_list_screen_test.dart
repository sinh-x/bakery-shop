import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/event_service.dart';
import 'package:bakery_app/features/events/event_list_screen.dart';
import 'package:bakery_app/shared/labels/events.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EventsInterceptor extends Interceptor {
  _EventsInterceptor(this._events, {this.fail = false});

  final List<Map<String, dynamic>> _events;
  final bool fail;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (fail && options.path == '/api/events') {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
      return;
    }
    if (options.path == '/api/events') {
      handler.resolve(
        Response<List<dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: _events,
        ),
      );
      return;
    }
    handler.next(options);
  }
}

Map<String, dynamic> _eventJson({
  required int id,
  String type = 'note',
  String summary = 'Sự kiện test',
  List<String> tags = const [],
  String loggedBy = '',
  String staffName = '',
  String timestamp = '2026-07-15T08:00:00Z',
}) {
  return {
    'id': id,
    'timestamp': timestamp,
    'type': type,
    'summary': summary,
    'tags': tags,
    'logged_by': loggedBy,
    'staff_name': staffName,
    'source': 'app',
    'data': <String, dynamic>{},
    'order_id': null,
  };
}

GoRouter _router() => GoRouter(
      routes: [
        GoRoute(
          path: '/events',
          builder: (_, _) => const EventListScreen(),
        ),
        GoRoute(
          path: '/events/new',
          builder: (_, _) => const SizedBox(child: Text('new-event-page')),
        ),
        GoRoute(
          path: '/events/:id',
          builder: (_, _) => const SizedBox(child: Text('event-detail-page')),
        ),
      ],
      initialLocation: '/events',
    );

Future<void> _pump(
  WidgetTester tester, {
  required Interceptor interceptor,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..interceptors.add(interceptor);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        sharedPreferencesProvider.overrideWithValue(prefs),
        eventServiceProvider.overrideWithValue(EventService(dio)),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders app bar with events title and FAB', (tester) async {
    await _pump(tester, interceptor: _EventsInterceptor(const []));
    expect(find.text(SharedLabels.tabEvents), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('shows empty state when no events', (tester) async {
    await _pump(tester, interceptor: _EventsInterceptor(const []));
    expect(find.text(EventsLabels.noEvents), findsOneWidget);
  });

  testWidgets('renders event cards with summary', (tester) async {
    final events = [
      _eventJson(id: 1, summary: 'Sự kiện A', type: 'note'),
      _eventJson(id: 2, summary: 'Sự kiện B', type: 'equipment'),
    ];
    await _pump(tester, interceptor: _EventsInterceptor(events));
    expect(find.text('Sự kiện A'), findsOneWidget);
    expect(find.text('Sự kiện B'), findsOneWidget);
  });

  testWidgets('renders tag chips for tagged events', (tester) async {
    final events = [
      _eventJson(id: 1, summary: 'Tagged', tags: const ['incident', 'staff']),
    ];
    await _pump(tester, interceptor: _EventsInterceptor(events));
    expect(find.text('incident'), findsOneWidget);
    expect(find.text('staff'), findsOneWidget);
  });

  testWidgets('shows error state with retry when API fails', (tester) async {
    await _pump(tester, interceptor: _EventsInterceptor(const [], fail: true));
    expect(find.text(SharedLabels.errorLoading), findsOneWidget);
    expect(find.text(SharedLabels.retry), findsOneWidget);
  });

  testWidgets('date range chips are present', (tester) async {
    await _pump(tester, interceptor: _EventsInterceptor(const []));
    expect(find.text(EventsLabels.filterToday), findsOneWidget);
    expect(find.text(EventsLabels.filterWeek), findsOneWidget);
    expect(find.text(EventsLabels.filterMonth), findsOneWidget);
    expect(find.text(EventsLabels.filterAll), findsAtLeast(1));
  });

  testWidgets('type filter dropdown shows all type labels', (tester) async {
    await _pump(tester, interceptor: _EventsInterceptor(const []));
    // The dropdown hint shows "Tất cả" initially.
    expect(find.text(EventsLabels.filterAll), findsAtLeast(1));
    // Tap the dropdown to open it.
    await tester.tap(find.byType(DropdownButton<String?>).first);
    await tester.pumpAndSettle();
    expect(find.text(EventsLabels.eventNote), findsOneWidget);
    expect(find.text(EventsLabels.typeEquipment), findsOneWidget);
  });

  testWidgets('FAB navigates to new-event route', (tester) async {
    await _pump(tester, interceptor: _EventsInterceptor(const []));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('new-event-page'), findsOneWidget);
  });

  testWidgets('tapping an event card navigates to detail route', (tester) async {
    final events = [_eventJson(id: 42, summary: 'Tap me', type: 'note')];
    await _pump(tester, interceptor: _EventsInterceptor(events));
    await tester.tap(find.text('Tap me'));
    await tester.pumpAndSettle();
    expect(find.text('event-detail-page'), findsOneWidget);
  });

  testWidgets('search toggle reveals search field', (tester) async {
    await _pump(tester, interceptor: _EventsInterceptor(const []));
    expect(find.byIcon(Icons.search), findsOneWidget);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    // Search field now visible with hint text.
    expect(find.text(EventsLabels.searchEvents), findsOneWidget);
  });
}