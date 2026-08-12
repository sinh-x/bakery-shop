import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/api/staff_service.dart';
import 'package:bakery_app/data/api/user_service.dart';
import 'package:bakery_app/data/models/address.dart';
import 'package:bakery_app/features/auth/auth_provider.dart';
import 'package:bakery_app/features/settings/address_library_screen.dart';
import 'package:bakery_app/features/settings/missing_links_screen.dart';
import 'package:bakery_app/features/settings/settings_screen.dart';
import 'package:bakery_app/providers/address/address_library_provider.dart';
import 'package:bakery_app/providers/address/missing_links_provider.dart';
import 'package:bakery_app/providers/staff_provider.dart';
import 'package:bakery_app/providers/user_binding_provider.dart';
import 'package:bakery_app/shared/labels/address_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 5 navigation tests (DG-388 / FR5 / AC6).
///
/// Verifies that:
/// - The Settings screen renders a `ListTile` entry pointing at the
///   missing-links screen (label = [AddressLabels.missingLinksNavEntry]).
/// - The Address Library screen exposes an AppBar action that routes to
///   the missing-links screen.
/// - The `/settings/missing-links` route is registered and builds
///   [MissingLinksScreen].
/// - The `/settings/addresses` route still builds [AddressLibraryScreen].
///
/// These tests use a minimal `GoRouter` with only the routes under test,
/// so navigation can be observed without standing up the full app shell
/// or backend services.

AuthState _authenticated({String role = 'staff'}) => AuthState.authenticated(
      token: 'test-token',
      username: role == 'admin' ? 'Sinh' : 'An',
      role: role,
    );

/// Test-only [AuthNotifier] that returns a fixed authenticated state
/// without touching [TokenStorage] / SharedPreferences.
class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(this._state);
  final AuthState _state;

  @override
  AuthState build() => _state;
}

/// Test-only [ApiBaseUrlNotifier] that always returns an empty URL so the
/// SettingsScreen's `_fetchServerVersion` probe is a no-op.
class _EmptyUrlNotifier extends ApiBaseUrlNotifier {
  @override
  String build() => '';
}

/// Test-only [StaffListNotifier] that returns an empty list without
/// hitting the network.
class _EmptyStaffListNotifier extends StaffListNotifier {
  @override
  Future<List<StaffMember>> build() async => const <StaffMember>[];
}

/// Test-only [StaffBindingNotifier] that returns an unbound state without
/// hitting the network.
class _EmptyStaffBindingNotifier extends StaffBindingNotifier {
  @override
  Future<StaffBinding> build() async => StaffBinding();
}

/// Test-only [AddressLibraryNotifier] that returns an empty list without
/// hitting the network, so the Address Library screen pumps without
/// triggering real API calls.
class _EmptyAddressLibraryNotifier extends AddressLibraryNotifier {
  @override
  Future<List<AddressLibraryEntry>> build() async =>
      const <AddressLibraryEntry>[];
}

/// Test-only [MissingLinksNotifier] that returns an empty list without
/// hitting the network, so the MissingLinksScreen pumps without triggering
/// real API calls.
class _EmptyMissingLinksNotifier extends MissingLinksNotifier {
  @override
  Future<List<MissingLinkItem>> build() async => const <MissingLinkItem>[];
}

GoRouter _router() => GoRouter(
      routes: [
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/settings/addresses',
          builder: (context, state) => const AddressLibraryScreen(),
        ),
        GoRoute(
          path: '/settings/missing-links',
          builder: (context, state) => const MissingLinksScreen(),
        ),
      ],
      initialLocation: '/settings',
    );

Future<ProviderContainer> _pumpSettings(WidgetTester tester,
    {String role = 'staff'}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // Pin the base URL to empty so SettingsScreen does not fire a real
      // `/api/health` probe during the test (avoids pending timers).
      apiBaseUrlProvider.overrideWith(_EmptyUrlNotifier.new),
      // Stub the staff providers so StaffBindingSection does not fire
      // real network calls during the test.
      staffListProvider.overrideWith(_EmptyStaffListNotifier.new),
      staffBindingProvider.overrideWith(_EmptyStaffBindingNotifier.new),
      // Stub the address providers so navigation targets (AddressLibrary,
      // MissingLinks) do not fire real network calls.
      addressLibraryProvider.overrideWith(_EmptyAddressLibraryNotifier.new),
      missingLinksProvider.overrideWith(_EmptyMissingLinksNotifier.new),
      authProvider
          .overrideWith(() => _FakeAuthNotifier(_authenticated(role: role))),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _pumpAddressLibrary(WidgetTester tester) async {
  // AddressLibraryScreen reads addressLibraryProvider which hits the
  // network; pump just enough to assert the AppBar action is present. We
  // override the address provider so no real call fires.
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      apiBaseUrlProvider.overrideWith(_EmptyUrlNotifier.new),
      addressLibraryProvider.overrideWith(_EmptyAddressLibraryNotifier.new),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AddressLibraryScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Settings navigation — missing-links entry (DG-388 Phase 5 / FR5 / AC6)',
      () {
    testWidgets('Settings screen shows missing-links nav entry for staff',
        (tester) async {
      await _pumpSettings(tester, role: 'staff');
      expect(find.text(AddressLabels.missingLinksNavEntry), findsOneWidget);
      expect(find.text(AddressLabels.missingLinksNavSubtitle), findsOneWidget);
    });

    testWidgets('Settings screen shows missing-links nav entry for admin',
        (tester) async {
      await _pumpSettings(tester, role: 'admin');
      // Admin sees the same General tab entry.
      expect(find.text(AddressLabels.missingLinksNavEntry), findsOneWidget);
    });

    testWidgets('tapping the missing-links entry navigates to the screen',
        (tester) async {
      await _pumpSettings(tester, role: 'staff');
      await tester.tap(find.text(AddressLabels.missingLinksNavEntry));
      await tester.pumpAndSettle();
      // The MissingLinksScreen AppBar title should now be visible.
      expect(find.byType(MissingLinksScreen), findsOneWidget);
      expect(find.text(AddressLabels.missingLinksTitle), findsOneWidget);
    });

    testWidgets('tapping the address-library entry still navigates',
        (tester) async {
      await _pumpSettings(tester, role: 'staff');
      await tester.tap(find.text(AddressLabels.libraryNavEntry));
      await tester.pumpAndSettle();
      expect(find.byType(AddressLibraryScreen), findsOneWidget);
    });
  });

  group('Address Library → missing-links cross-link (DG-388 Phase 5 / FR5)',
      () {
    testWidgets('Address Library AppBar has a link-off action', (tester) async {
      await _pumpAddressLibrary(tester);
      expect(find.byIcon(Icons.link_off), findsOneWidget);
    });

    testWidgets('the link-off action tooltip is the missing-links nav label',
        (tester) async {
      await _pumpAddressLibrary(tester);
      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.link_off),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.tooltip, AddressLabels.missingLinksNavEntry);
    });
  });

  group('Route registration (DG-388 Phase 5 / FR5 / AC6)', () {
    testWidgets('/settings/missing-links builds MissingLinksScreen',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          apiBaseUrlProvider.overrideWith(_EmptyUrlNotifier.new),
          authProvider
              .overrideWith(() => _FakeAuthNotifier(_authenticated())),
          missingLinksProvider.overrideWith(_EmptyMissingLinksNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/settings/missing-links',
            builder: (context, state) => const MissingLinksScreen(),
          ),
        ],
        initialLocation: '/settings/missing-links',
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MissingLinksScreen), findsOneWidget);
      expect(find.text(AddressLabels.missingLinksTitle), findsOneWidget);
    });
  });
}