import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/features/settings/pre_login_settings_screen.dart';
import 'package:bakery_app/features/settings/widgets/settings_sections.dart';
import 'package:bakery_app/shared/labels/technical_settings.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// HttpClientAdapter that returns a 200 /api/health response, mirroring the
/// success path the pre-login connection test hits in production.
class _HealthOkAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"status":"ok","version":"1.0.0"}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

/// HttpClientAdapter that always fails — simulates an unreachable host so the
/// connection test exercises the failure-display path.
class _FailingAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      message: 'connection refused',
    );
  }
}

/// Build a router whose only route is the pre-login settings screen, so the
/// back button's `context.go('/login')` can be verified via navigation.
GoRouter _router() => GoRouter(
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const Scaffold(
            body: KeyedSubtree(key: ValueKey('login'), child: SizedBox()),
          ),
        ),
        GoRoute(
          path: '/settings/connection',
          builder: (context, state) => const PreLoginSettingsScreen(),
        ),
      ],
      initialLocation: '/settings/connection',
    );

/// Pump the pre-login screen inside a [ProviderScope] with the given Dio
/// factory and SharedPreferences overrides.
Future<void> _pumpScreen(
  WidgetTester tester, {
  DioFactory? dioFactory,
  Map<String, Object> initialPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  if (dioFactory != null) {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          preLoginDioFactoryProvider.overrideWithValue(dioFactory),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      ),
    );
  } else {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp.router(routerConfig: _router()),
      ),
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  group('PreLoginSettingsScreen (DG-367 Phase 2 / FR2 / FR3)', () {
    testWidgets('renders screen title, URL input, and action buttons',
        (tester) async {
      await _pumpScreen(tester);

      expect(find.text(TechnicalSettingsLabels.screenTitle), findsOneWidget);
      expect(find.text(TechnicalSettingsLabels.serverUrlLabel), findsOneWidget);
      expect(find.text(TechnicalSettingsLabels.serverUrlHelp), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        find.text(TechnicalSettingsLabels.testConnection),
        findsOneWidget,
      );
      expect(find.text(TechnicalSettingsLabels.save), findsOneWidget);
    });

    testWidgets('pre-fills URL from ApiBaseUrlNotifier when set', (tester) async {
      await _pumpScreen(tester, initialPrefs: {
        kApiUrlKey: 'http://10.0.0.5:8000',
      });

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'http://10.0.0.5:8000',
      );
    });

    testWidgets('save with empty URL shows validation snackbar', (tester) async {
      await _pumpScreen(tester);

      // Clear the pre-filled default URL (ApiBaseUrlNotifier defaults to
      // http://localhost:8000 on mobile).
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      await tester.tap(find.text(TechnicalSettingsLabels.save));
      await tester.pumpAndSettle();

      expect(find.text(TechnicalSettingsLabels.urlEmpty), findsOneWidget);
    });

    testWidgets('save persists URL via ApiBaseUrlNotifier and shows snackbar',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: MaterialApp.router(routerConfig: _router()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField),
        'http://192.168.1.10:8000',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(TechnicalSettingsLabels.save));
      await tester.pumpAndSettle();

      expect(prefs.getString(kApiUrlKey), 'http://192.168.1.10:8000');
      expect(find.text(TechnicalSettingsLabels.urlSaved), findsOneWidget);
    });

    testWidgets('test connection success displays success result card',
        (tester) async {
      Dio successFactory() => Dio()
        ..httpClientAdapter = _HealthOkAdapter()
        ..options.validateStatus = (_) => true;

      await _pumpScreen(tester, dioFactory: successFactory);

      await tester.enterText(find.byType(TextField), 'http://example.com');
      await tester.pumpAndSettle();
      await tester.tap(find.text(TechnicalSettingsLabels.testConnection));
      await tester.pumpAndSettle();

      expect(find.text(TechnicalSettingsLabels.connectionSuccess),
          findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('test connection failure displays failure result card',
        (tester) async {
      Dio failFactory() => Dio()..httpClientAdapter = _FailingAdapter();

      await _pumpScreen(tester, dioFactory: failFactory);

      await tester.enterText(find.byType(TextField), 'http://unreachable.host');
      await tester.pumpAndSettle();
      await tester.tap(find.text(TechnicalSettingsLabels.testConnection));
      await tester.pumpAndSettle();

      expect(
        find.text(TechnicalSettingsLabels.connectionFailed),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('test connection does nothing when URL is empty',
        (tester) async {
      Dio successFactory() => Dio()..httpClientAdapter = _HealthOkAdapter();

      await _pumpScreen(tester, dioFactory: successFactory);

      // Clear the pre-filled default URL so _testConnection short-circuits.
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      await tester.tap(find.text(TechnicalSettingsLabels.testConnection));
      await tester.pumpAndSettle();

      // No result card rendered because empty URL short-circuits.
      expect(find.byType(ConnectionResult), findsNothing);
      expect(find.text(TechnicalSettingsLabels.connectionSuccess), findsNothing);
      expect(find.text(TechnicalSettingsLabels.connectionFailed), findsNothing);
    });

    testWidgets('typing into URL field clears a previous test result',
        (tester) async {
      Dio successFactory() => Dio()
        ..httpClientAdapter = _HealthOkAdapter()
        ..options.validateStatus = (_) => true;

      await _pumpScreen(tester, dioFactory: successFactory);

      await tester.enterText(find.byType(TextField), 'http://example.com');
      await tester.pumpAndSettle();
      await tester.tap(find.text(TechnicalSettingsLabels.testConnection));
      await tester.pumpAndSettle();
      expect(find.text(TechnicalSettingsLabels.connectionSuccess),
          findsOneWidget);

      // Editing the URL should clear the prior result.
      await tester.enterText(find.byType(TextField), 'http://other.com');
      await tester.pumpAndSettle();

      expect(find.text(TechnicalSettingsLabels.connectionSuccess), findsNothing);
    });

    testWidgets('back button navigates to /login (AC6)', (tester) async {
      await _pumpScreen(tester);

      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // Router should have navigated to /login.
      expect(find.byKey(const ValueKey('login')), findsOneWidget);
    });
  });
}