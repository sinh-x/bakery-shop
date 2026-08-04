import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/knowledge_service.dart';
import 'package:bakery_app/features/knowledge/knowledge_list_screen.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _KnowledgeInterceptor extends Interceptor {
  _KnowledgeInterceptor(this._entries, {this.fail = false});

  final List<Map<String, dynamic>> _entries;
  final bool fail;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (fail && options.path == '/api/knowledge') {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
      return;
    }
    if (options.path == '/api/knowledge') {
      handler.resolve(
        Response<List<dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: _entries,
        ),
      );
      return;
    }
    handler.next(options);
  }
}

Map<String, dynamic> _entryJson({
  required int id,
  required String title,
  String type = 'note',
  String content = '',
  List<String> tags = const [],
  bool pinned = false,
  int photoCount = 0,
}) {
  return {
    'id': id,
    'title': title,
    'content': content,
    'type': type,
    'tags': tags,
    'logged_by': '',
    'source': 'app',
    'created_at': '2026-07-15T08:00:00Z',
    'updated_at': '2026-07-15T08:00:00Z',
    'pinned': pinned,
    'pinned_at': pinned ? '2026-07-15T08:00:00Z' : null,
    'photos': List.generate(
      photoCount,
      (i) => {'hash': 'h$i', 'url': '/api/photos/h$i.jpg', 'caption': '', 'position': i},
    ),
  };
}

GoRouter _router() => GoRouter(
      routes: [
        GoRoute(
          path: '/knowledge',
          builder: (_, _) => const KnowledgeListScreen(),
        ),
        GoRoute(
          path: '/knowledge/new',
          builder: (_, _) => const SizedBox(child: Text('new-entry-page')),
        ),
        GoRoute(
          path: '/knowledge/:id',
          builder: (_, state) =>
              SizedBox(child: Text('detail-${state.pathParameters['id']}')),
        ),
      ],
      initialLocation: '/knowledge',
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
        knowledgeServiceProvider.overrideWithValue(KnowledgeService(dio)),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders app bar with knowledge title and FAB', (tester) async {
    await _pump(tester, interceptor: _KnowledgeInterceptor(const []));
    expect(find.text(VN.knowledgeTitle), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('shows empty state when no entries', (tester) async {
    await _pump(tester, interceptor: _KnowledgeInterceptor(const []));
    expect(find.text(VN.noKnowledgeEntries), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
  });

  testWidgets('renders list entries with title and type label', (tester) async {
    final entries = [
      _entryJson(id: 1, title: 'Công thức bánh kem', type: 'recipe'),
      _entryJson(id: 2, title: 'Quy trình nhào bột', type: 'procedure'),
    ];
    await _pump(tester, interceptor: _KnowledgeInterceptor(entries));
    expect(find.text('Công thức bánh kem'), findsOneWidget);
    expect(find.text('Quy trình nhào bột'), findsOneWidget);
    // Type label from VN.knowledgeTypes — appears once as the type badge.
    // (The filter chip also shows "Công thức"/"Quy trình" so total is 2 each.)
    expect(find.text(VN.knowledgeTypes['recipe']!), findsNWidgets(2));
    expect(find.text(VN.knowledgeTypes['procedure']!), findsNWidgets(2));
  });

  testWidgets('renders pinned section header for pinned entries',
      (tester) async {
    final entries = [
      _entryJson(id: 1, title: 'Ghim mục A', type: 'note', pinned: true),
      _entryJson(id: 2, title: 'Thường mục B', type: 'note', pinned: false),
    ];
    await _pump(tester, interceptor: _KnowledgeInterceptor(entries));
    expect(find.text('📌 Đã ghim'), findsOneWidget);
    expect(find.text('Ghim mục A'), findsOneWidget);
    expect(find.text('Thường mục B'), findsOneWidget);
  });

  testWidgets('shows photo count badge when entry has photos', (tester) async {
    final entries = [
      _entryJson(id: 1, title: 'Có ảnh', type: 'note', photoCount: 3),
    ];
    await _pump(tester, interceptor: _KnowledgeInterceptor(entries));
    expect(find.byIcon(Icons.photo), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('renders tag chips for tagged entries', (tester) async {
    final entries = [
      _entryJson(
        id: 1,
        title: 'Có tag',
        type: 'note',
        tags: const ['baking', 'tips'],
      ),
    ];
    await _pump(tester, interceptor: _KnowledgeInterceptor(entries));
    expect(find.text('baking'), findsOneWidget);
    expect(find.text('tips'), findsOneWidget);
  });

  testWidgets('renders error state with retry button when API fails',
      (tester) async {
    await _pump(tester, interceptor: _KnowledgeInterceptor(const [], fail: true));
    expect(find.text(VN.apiError), findsOneWidget);
    expect(find.text(VN.retry), findsOneWidget);
  });

  testWidgets('type filter chips filter entries by type', (tester) async {
    final entries = [
      _entryJson(id: 1, title: 'Công thức A', type: 'recipe'),
      _entryJson(id: 2, title: 'Ghi chú B', type: 'note'),
    ];
    await _pump(tester, interceptor: _KnowledgeInterceptor(entries));
    // Initially both visible.
    expect(find.text('Công thức A'), findsOneWidget);
    expect(find.text('Ghi chú B'), findsOneWidget);
    // Tap the 'Công thức' FilterChip (the filter bar, not the entry type badge).
    final chipFinder = find
        .descendant(
          of: find.byType(FilterChip),
          matching: find.text('Công thức'),
        )
        .first;
    await tester.ensureVisible(chipFinder);
    await tester.tap(chipFinder);
    await tester.pumpAndSettle();
    // Only recipe entry remains.
    expect(find.text('Công thức A'), findsOneWidget);
    expect(find.text('Ghi chú B', skipOffstage: false), findsNothing);
  });

  testWidgets('search field filters entries by title', (tester) async {
    final entries = [
      _entryJson(id: 1, title: 'Công thức bánh kem', type: 'note'),
      _entryJson(id: 2, title: 'Quy trình nhào bột', type: 'note'),
    ];
    await _pump(tester, interceptor: _KnowledgeInterceptor(entries));
    await tester.enterText(
      find.byType(TextField).first,
      'bánh kem',
    );
    // Debounce is 400ms; pump past it.
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('Công thức bánh kem'), findsOneWidget);
    expect(find.text('Quy trình nhào bột', skipOffstage: false), findsNothing);
  });

  testWidgets('FAB navigates to new-entry route', (tester) async {
    await _pump(tester, interceptor: _KnowledgeInterceptor(const []));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('new-entry-page'), findsOneWidget);
  });
}