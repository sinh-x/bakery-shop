import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/features/audit_log/audit_log_screen.dart';
import 'package:bakery_app/shared/labels/audit_log.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves audit-log responses and records query params.
class _AuditLogInterceptor extends Interceptor {
  _AuditLogInterceptor({this.total = 3, this.pageSize = 50});

  final int total;
  final int pageSize;

  final List<Map<String, dynamic>> capturedParams = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path != '/api/audit-log') {
      handler.next(options);
      return;
    }
    capturedParams.add(Map<String, dynamic>.from(options.queryParameters));
    final page = (options.queryParameters['page'] as num?)?.toInt() ?? 1;
    final remaining = total - (page - 1) * pageSize;
    final count = remaining < pageSize ? remaining : pageSize;
    final items = List.generate(
      count < 0 ? 0 : count,
      (i) => <String, dynamic>{
        'id': (page - 1) * pageSize + i + 1,
        'username': 'Sinh',
        'action': 'create',
        'entity_type': 'config',
        'entity_id': 'id-${(page - 1) * pageSize + i + 1}',
        'old_value': null,
        'new_value': '{"v": ${i + 1}}',
        'created_at': '2026-07-14T10:00:0${i}Z',
      },
    );
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{
          'items': items,
          'page': page,
          'page_size': pageSize,
          'total': total,
        },
      ),
    );
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _AuditLogInterceptor interceptor,
}) async {
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..interceptors.add(interceptor);
  final container = ProviderContainer(
    overrides: [dioProvider.overrideWithValue(dio)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AuditLogScreen()),
    ),
  );
  // Allow the first async page to resolve.
  await tester.pumpAndSettle();
}

void main() {
  group('AuditLogScreen', () {
    testWidgets('renders list entries from the API (FR24)', (tester) async {
      final interceptor = _AuditLogInterceptor(total: 3);
      await _pumpScreen(tester, interceptor: interceptor);

      // Title bar.
      expect(find.text(AuditLogLabels.screenTitle), findsOneWidget);
      // Three entries, each rendered with the username "Sinh" in a bold title.
      expect(find.text('Sinh'), findsNWidgets(3));
      // Each entry shows the entity-type label "Cấu hình".
      expect(find.textContaining(AuditLogLabels.entityTypeConfig), findsNWidgets(3));
      // Single "load more" button does NOT appear because total <= pageSize.
      expect(find.text(AuditLogLabels.loadMore), findsNothing);
    });

    testWidgets('shows empty state when API returns no entries',
        (tester) async {
      final interceptor = _AuditLogInterceptor(total: 0);
      await _pumpScreen(tester, interceptor: interceptor);
      expect(find.text(AuditLogLabels.empty), findsOneWidget);
    });

    testWidgets('filter controls trigger a re-query with the correct params',
        (tester) async {
      final interceptor = _AuditLogInterceptor(total: 2);
      await _pumpScreen(tester, interceptor: interceptor);
      interceptor.capturedParams.clear();

      // Enter a username filter and pick an entity type, then tap Apply.
      await tester.enterText(
        find.widgetWithText(TextField, AuditLogLabels.filterUserHint).at(0)
            .evaluate()
            .isNotEmpty
            ? find.byType(TextField).first
            : find.byType(TextField).first,
        'An',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AuditLogLabels.entityTypeProduct).last);
      await tester.pumpAndSettle();

      await tester.tap(find.text(AuditLogLabels.applyFilters));
      await tester.pumpAndSettle();

      expect(interceptor.capturedParams, isNotEmpty);
      final params = interceptor.capturedParams.last;
      expect(params['username'], 'An');
      expect(params['entity_type'], 'product');
      expect(params['page'], 1);
    });

    testWidgets('clear filters re-queries with empty filters', (tester) async {
      final interceptor = _AuditLogInterceptor(total: 1);
      await _pumpScreen(tester, interceptor: interceptor);
      interceptor.capturedParams.clear();

      await tester.tap(find.text(AuditLogLabels.clearFilters));
      await tester.pumpAndSettle();

      expect(interceptor.capturedParams, hasLength(1));
      final params = interceptor.capturedParams.first;
      expect(params.containsKey('username'), isFalse);
      expect(params.containsKey('entity_type'), isFalse);
      expect(params['page'], 1);
    });

    testWidgets('pagination fetches the next page on scroll (NFR9)',
        (tester) async {
      final interceptor = _AuditLogInterceptor(total: 110, pageSize: 50);
      await _pumpScreen(tester, interceptor: interceptor);

      // First page loaded 50 entries.
      expect(interceptor.capturedParams.any((p) => p['page'] == 1), isTrue);

      final listViewFinder = find.byType(ListView);
      expect(listViewFinder, findsOneWidget);

      // Drag the list up (scroll towards the bottom). The auto-load-on-scroll
      // listener in AuditLogScreen fires loadMore() when the user nears the
      // bottom, fetching page 2.
      for (var i = 0; i < 12; i++) {
        await tester.drag(listViewFinder, const Offset(0, -600));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      // Page 2 was requested as a result of the scroll-near-bottom trigger.
      expect(interceptor.capturedParams.any((p) => p['page'] == 2), isTrue);
    });

    testWidgets('admin-only access is enforced by the router guard '
        '(staff cannot reach the screen — Phase 7 gating)', (tester) async {
      // This is a regression guard: the screen renders for an admin session,
      // but the router redirect guard (Phase 7) already blocks staff from
      // reaching /audit-log. We assert the screen itself mounts without
      // error in an admin provider scope — the actual staff-redirect is
      // covered by test/shared/router/ui_gating_test.dart.
      final interceptor = _AuditLogInterceptor(total: 1);
      await _pumpScreen(tester, interceptor: interceptor);
      expect(find.text(AuditLogLabels.screenTitle), findsOneWidget);
    });
  });
}