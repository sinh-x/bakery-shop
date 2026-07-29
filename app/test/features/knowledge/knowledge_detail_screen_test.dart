import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/knowledge_service.dart';
import 'package:bakery_app/features/knowledge/knowledge_detail_screen.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _KnowledgeDetailInterceptor extends Interceptor {
  _KnowledgeDetailInterceptor(this._entry, {this.fail = false});

  final Map<String, dynamic>? _entry;
  final bool fail;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (fail && options.path == '/api/knowledge/1') {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
      return;
    }
    if (options.path == '/api/knowledge/1') {
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: _entry,
        ),
      );
      return;
    }
    if (options.path == '/api/knowledge/1/pin') {
      final toggled = Map<String, dynamic>.from(_entry ?? {})
        ..['pinned'] = options.method == 'POST'
        ..['pinned_at'] = options.method == 'POST' ? '2026-07-15T08:00:00Z' : null;
      handler.resolve(
        Response<Map<String, dynamic>>(
          requestOptions: options,
          statusCode: 200,
          data: toggled,
        ),
      );
      return;
    }
    if (options.method == 'DELETE' && options.path == '/api/knowledge/1') {
      handler.resolve(Response(requestOptions: options, statusCode: 204));
      return;
    }
    handler.next(options);
  }
}

Map<String, dynamic> _entryJson({
  int id = 1,
  String title = 'Mục sổ tay',
  String type = 'recipe',
  String content = 'Nội dung chi tiết',
  List<String> tags = const ['baking', 'tips'],
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

GoRouter _router({int entryId = 1}) => GoRouter(
      routes: [
        GoRoute(
          path: '/knowledge/:id',
          builder: (_, state) => KnowledgeDetailScreen(
            entryId: int.parse(state.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/knowledge/:id/edit',
          builder: (_, state) =>
              SizedBox(child: Text('edit-${state.pathParameters['id']}')),
        ),
      ],
      initialLocation: '/knowledge/$entryId',
    );

Future<void> _pump(
  WidgetTester tester, {
  required Interceptor interceptor,
  int entryId = 1,
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
      child: MaterialApp.router(routerConfig: _router(entryId: entryId)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders entry title and content', (tester) async {
    await _pump(
      tester,
      interceptor: _KnowledgeDetailInterceptor(_entryJson()),
    );
    expect(find.text('Mục sổ tay'), findsNWidgets(2)); // AppBar + body
    expect(find.text('Nội dung chi tiết'), findsOneWidget);
  });

  testWidgets('renders type label chip', (tester) async {
    await _pump(
      tester,
      interceptor: _KnowledgeDetailInterceptor(_entryJson(type: 'recipe')),
    );
    expect(find.text(VN.knowledgeTypes['recipe']!), findsOneWidget);
  });

  testWidgets('renders tag chips', (tester) async {
    await _pump(
      tester,
      interceptor:
          _KnowledgeDetailInterceptor(_entryJson(tags: ['baking', 'tips'])),
    );
    expect(find.text('baking'), findsOneWidget);
    expect(find.text('tips'), findsOneWidget);
  });

  testWidgets('renders updated-at timestamp', (tester) async {
    await _pump(
      tester,
      interceptor: _KnowledgeDetailInterceptor(_entryJson()),
    );
    expect(find.textContaining('Cập nhật:'), findsOneWidget);
  });

  testWidgets('renders error state with retry when API fails', (tester) async {
    await _pump(
      tester,
      interceptor: _KnowledgeDetailInterceptor(null, fail: true),
    );
    expect(find.text(VN.apiError), findsOneWidget);
    expect(find.text(VN.retry), findsOneWidget);
  });

  testWidgets('edit button navigates to edit route', (tester) async {
    await _pump(
      tester,
      interceptor: _KnowledgeDetailInterceptor(_entryJson()),
    );
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(find.text('edit-1'), findsOneWidget);
  });

  testWidgets('pin toggle button is present', (tester) async {
    await _pump(
      tester,
      interceptor:
          _KnowledgeDetailInterceptor(_entryJson(pinned: false)),
    );
    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
  });

  testWidgets('delete menu item opens confirmation dialog', (tester) async {
    await _pump(
      tester,
      interceptor: _KnowledgeDetailInterceptor(_entryJson()),
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    // The popup menu shows the delete item.
    expect(find.text(VN.deleteKnowledge), findsOneWidget);
    // Tap the delete menu item to open the confirmation dialog.
    await tester.tap(find.text(VN.deleteKnowledge).last);
    await tester.pumpAndSettle();
    // Confirmation dialog now shows the title and cancel button.
    expect(find.text(VN.confirmDeleteKnowledge), findsOneWidget);
    expect(find.text(VN.cancel), findsOneWidget);
  });

  testWidgets('share button is present', (tester) async {
    await _pump(
      tester,
      interceptor: _KnowledgeDetailInterceptor(_entryJson()),
    );
    expect(find.byIcon(Icons.share), findsOneWidget);
  });
}