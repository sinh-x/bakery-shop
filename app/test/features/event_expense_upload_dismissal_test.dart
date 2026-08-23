import 'dart:async';

import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/event_service.dart';
import 'package:bakery_app/data/models/event.dart';
import 'package:bakery_app/data/models/event_photo.dart';
import 'package:bakery_app/features/events/event_form_screen.dart';
import 'package:bakery_app/features/events/providers/event_form_notifier.dart';
import 'package:bakery_app/features/expenses/expense_form_screen.dart';
import 'package:bakery_app/features/expenses/providers/expense_form_notifier.dart';
import 'package:bakery_app/providers/photo_upload_provider.dart';
import 'package:bakery_app/shared/labels/events.dart';
import 'package:bakery_app/shared/labels/expenses.dart';
import 'package:bakery_app/shared/models/form_draft_context.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyGetInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.method == 'GET') {
      handler.resolve(
        Response<List<dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: const [],
        ),
      );
      return;
    }
    handler.next(options);
  }
}

class _DelayedUploadEventService extends EventService {
  _DelayedUploadEventService(this.testDio) : super(testDio);

  final Dio testDio;
  final uploadedPaths = <String>[];
  final uploadGates = <Completer<void>>[];

  @override
  Future<List<BakeryEvent>> listEvents({
    String? type,
    String? tag,
    String? search,
    String? since,
    String? until,
    String? loggedBy,
    String? expenseCategory,
    String? expensePaymentMethod,
    String? expensePaymentSource,
    String? expenseStaffName,
    String? expensePaidByName,
    String? expenseSearch,
    String? expenseDebtStatus,
    String? expenseSubcategory,
    int limit = 50,
  }) async => const [];

  @override
  Future<BakeryEvent> createEvent({
    required String summary,
    String type = 'note',
    List<String> tags = const [],
    String loggedBy = '',
    Map<String, dynamic> data = const {},
    String source = 'app',
    DateTime? timestamp,
    int? orderId,
  }) async => BakeryEvent(
    id: 99,
    timestamp: timestamp ?? DateTime(2026, 8, 24),
    type: type,
    summary: summary,
    tags: tags,
    loggedBy: loggedBy,
    data: data,
    orderId: orderId,
  );

  @override
  Future<EventPhoto> uploadEventPhoto(
    int eventId,
    XFile file, {
    String tags = '',
  }) async {
    uploadedPaths.add(file.path);
    final gate = Completer<void>();
    uploadGates.add(gate);
    await gate.future;
    return EventPhoto(
      id: uploadGates.length,
      eventId: eventId,
      photoId: uploadGates.length,
      photoHash: 'hash-${uploadGates.length}',
    );
  }
}

Future<ProviderContainer> _container(_DelayedUploadEventService service) async {
  SharedPreferences.setMockInitialValues({'logged_by_name': 'Lan'});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      dioProvider.overrideWithValue(service.testDio),
      sharedPreferencesProvider.overrideWithValue(prefs),
      eventServiceProvider.overrideWithValue(service),
    ],
  );
}

Future<void> _finishUploads(
  WidgetTester tester,
  _DelayedUploadEventService service,
) async {
  expect(service.uploadGates, hasLength(1));
  service.uploadGates.first.complete();
  await tester.pump();
  expect(service.uploadGates, hasLength(2));
  service.uploadGates.last.complete();
  await tester.pump();
}

void main() {
  testWidgets('event selected photos finish uploading after route dismissal', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..interceptors.add(_EmptyGetInterceptor());
    final service = _DelayedUploadEventService(dio);
    final container = await _container(service);
    addTearDown(container.dispose);
    const context = FormDraftContext(
      formType: 'event',
      mode: FormDraftMode.create,
    );
    container.read(contextualEventFormProvider(context).notifier)
      ..startNew('standalone')
      ..setSummary('Upload after dismissal')
      ..setSelectedPhotos([
        XFile('/tmp/event-one.jpg'),
        XFile('/tmp/event-two.jpg'),
      ]);
    final router = GoRouter(
      initialLocation: '/events/new',
      routes: [
        GoRoute(
          path: '/events/new',
          builder: (_, _) => const EventFormScreen(),
        ),
        GoRoute(
          path: '/events',
          builder: (_, _) => const Scaffold(body: Text('events-list')),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    final submit = find.widgetWithText(FilledButton, EventsLabels.logEvent);
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(service.uploadedPaths, ['/tmp/event-one.jpg']);

    router.go('/events');
    await tester.pumpAndSettle();
    expect(find.text('events-list'), findsOneWidget);
    await _finishUploads(tester, service);

    expect(service.uploadedPaths, ['/tmp/event-one.jpg', '/tmp/event-two.jpg']);
    expect(container.read(photoUploadNotifierProvider).completedCount, 2);
  });

  testWidgets(
    'expense selected photos finish uploading after route dismissal',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final dio = Dio(BaseOptions(baseUrl: 'http://test'))
        ..interceptors.add(_EmptyGetInterceptor());
      final service = _DelayedUploadEventService(dio);
      final container = await _container(service);
      addTearDown(container.dispose);
      const context = FormDraftContext(
        formType: 'expense',
        mode: FormDraftMode.create,
      );
      container.read(contextualExpenseFormProvider(context).notifier)
        ..startNew(staffName: 'Lan')
        ..setAmount('125000')
        ..setCategory(ExpensesLabels.expenseCategoryOther)
        ..setPaidByName('Lan')
        ..setSelectedPhotos([
          XFile('/tmp/expense-one.jpg'),
          XFile('/tmp/expense-two.jpg'),
        ]);
      final router = GoRouter(
        initialLocation: '/expenses/new',
        routes: [
          GoRoute(
            path: '/expenses/new',
            builder: (_, _) => const ExpenseFormScreen(),
          ),
          GoRoute(
            path: '/expenses',
            builder: (_, _) => const Scaffold(body: Text('expenses-list')),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      final submit = find.widgetWithText(
        FilledButton,
        ExpensesLabels.expenseSaveAction,
      );
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(service.uploadedPaths, ['/tmp/expense-one.jpg']);

      router.go('/expenses');
      await tester.pumpAndSettle();
      expect(find.text('expenses-list'), findsOneWidget);
      await _finishUploads(tester, service);

      expect(service.uploadedPaths, [
        '/tmp/expense-one.jpg',
        '/tmp/expense-two.jpg',
      ]);
      expect(container.read(photoUploadNotifierProvider).completedCount, 2);
    },
  );
}
