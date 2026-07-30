import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/event_service.dart';
import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/features/events/event_form_screen.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EventsInterceptor extends Interceptor {
  _EventsInterceptor();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/api/events' && options.method == 'POST') {
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 201,
          data: {
            'id': 99,
            'timestamp': '2026-07-15T08:00:00Z',
            'type': 'note',
            'summary': 'New event',
            'tags': <String>[],
            'logged_by': '',
            'staff_name': '',
            'source': 'app',
            'data': <String, dynamic>{},
            'order_id': null,
          },
        ),
      );
      return;
    }
    handler.next(options);
  }
}

GoRouter _router({BakeryEvent? event, int? orderId, String? orderRef}) =>
    GoRouter(
      routes: [
        GoRoute(
          path: '/events/new',
          builder: (_, _) => EventFormScreen(
            event: event,
            orderId: orderId,
            orderRef: orderRef,
          ),
        ),
        GoRoute(
          path: '/events',
          builder: (_, _) => const SizedBox(child: Text('events-list-page')),
        ),
      ],
      initialLocation: '/events/new',
    );

Future<ProviderContainer> _buildContainer(Interceptor interceptor) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..interceptors.add(interceptor);
  return ProviderContainer(
    overrides: [
      dioProvider.overrideWithValue(dio),
      sharedPreferencesProvider.overrideWithValue(prefs),
      eventServiceProvider.overrideWithValue(EventService(dio)),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  BakeryEvent? event,
  int? orderId,
  String? orderRef,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: _router(
          event: event,
          orderId: orderId,
          orderRef: orderRef,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('create mode renders create-event title', (tester) async {
    final container = await _buildContainer(_EventsInterceptor());
    addTearDown(container.dispose);
    await _pump(tester, container);
    expect(find.text(VN.createEvent), findsOneWidget);
  });

  testWidgets('edit mode renders edit-event title and prefilled summary',
      (tester) async {
    final event = BakeryEvent(
      id: 5,
      timestamp: DateTime(2026, 7, 15, 8, 30),
      type: 'equipment',
      summary: 'Sửa lò',
      tags: const ['maintenance'],
      loggedBy: 'lan',
      source: 'app',
      data: const {},
    );
    final container = await _buildContainer(_EventsInterceptor());
    addTearDown(container.dispose);
    await _pump(tester, container, event: event);
    expect(find.text(VN.editEvent), findsOneWidget);
    expect(find.text('Sửa lò'), findsOneWidget);
  });

  testWidgets('order-linked mode renders add-incident title and order ref',
      (tester) async {
    final container = await _buildContainer(_EventsInterceptor());
    addTearDown(container.dispose);
    await _pump(tester, container, orderId: 42, orderRef: 'ORD-42');
    expect(find.text(VN.addOrderIncident), findsOneWidget);
    expect(find.textContaining('ORD-42'), findsOneWidget);
  });

  testWidgets('renders all event type chips', (tester) async {
    final container = await _buildContainer(_EventsInterceptor());
    addTearDown(container.dispose);
    await _pump(tester, container);
    expect(find.text(VN.eventNote), findsOneWidget);
    expect(find.text(VN.typeEquipment), findsOneWidget);
    expect(find.text(VN.eventProduction), findsOneWidget);
    expect(find.text(VN.eventInventory), findsOneWidget);
    expect(find.text(VN.eventExpense), findsOneWidget);
    expect(find.text(VN.eventDelivery), findsOneWidget);
    expect(find.text(VN.eventOrder), findsOneWidget);
  });

  testWidgets('renders standard tag chips', (tester) async {
    final container = await _buildContainer(_EventsInterceptor());
    addTearDown(container.dispose);
    await _pump(tester, container);
    expect(find.text(VN.tagIncident), findsOneWidget);
    expect(find.text(VN.tagMaintenance), findsOneWidget);
    expect(find.text(VN.tagStaff), findsOneWidget);
  });

  testWidgets('summary field is empty in create mode', (tester) async {
    final container = await _buildContainer(_EventsInterceptor());
    addTearDown(container.dispose);
    await _pump(tester, container);
    final textField = tester.widget<TextField>(
      find.widgetWithText(TextField, VN.eventSummary).first,
    );
    expect(textField.controller?.text, '');
  });

  testWidgets('log-event button is present in create mode', (tester) async {
    final container = await _buildContainer(_EventsInterceptor());
    addTearDown(container.dispose);
    await _pump(tester, container);
    expect(find.text(VN.logEvent, skipOffstage: false), findsOneWidget);
  });

  testWidgets('save button is present in edit mode', (tester) async {
    final event = BakeryEvent(
      id: 5,
      timestamp: DateTime(2026, 7, 15, 8, 30),
      type: 'note',
      summary: 'Edit me',
      tags: const [],
      loggedBy: '',
      source: 'app',
      data: const {},
    );
    final container = await _buildContainer(_EventsInterceptor());
    addTearDown(container.dispose);
    await _pump(tester, container, event: event);
    expect(find.text(VN.save, skipOffstage: false), findsOneWidget);
  });

  testWidgets('change-logger button is present', (tester) async {
    final container = await _buildContainer(_EventsInterceptor());
    addTearDown(container.dispose);
    await _pump(tester, container);
    expect(find.text(VN.changeLogger, skipOffstage: false), findsOneWidget);
  });

  testWidgets('add-tag action chip is present', (tester) async {
    final container = await _buildContainer(_EventsInterceptor());
    addTearDown(container.dispose);
    await _pump(tester, container);
    expect(find.text(VN.addTag, skipOffstage: false), findsOneWidget);
  });
}