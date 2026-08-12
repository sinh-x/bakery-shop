import 'package:bakery_app/data/api/address_service.dart';
import 'package:bakery_app/data/models/address.dart';
import 'package:bakery_app/features/settings/missing_links_screen.dart';
import 'package:bakery_app/shared/labels/address_labels.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake [AddressService] with an in-memory missing-links store for the
/// screen. Mirrors the [address_library_screen_test] pattern
/// (DG-385 Phase 5).
class _FakeAddressService extends AddressService {
  _FakeAddressService(this._store) : super(Dio());

  final List<MissingLinkItem> _store;
  int _refreshCalls = 0;

  @override
  Future<List<MissingLinkItem>> missingLinks({int? limit}) async {
    _refreshCalls++;
    return List<MissingLinkItem>.from(_store);
  }

  int get refreshCalls => _refreshCalls;
}

/// Service that always throws on `missingLinks()` to exercise the
/// error state.
class _ThrowingAddressService extends AddressService {
  _ThrowingAddressService() : super(Dio());

  @override
  Future<List<MissingLinkItem>> missingLinks({int? limit}) async {
    throw Exception('backend down');
  }
}

List<MissingLinkItem> _seedStore() => const <MissingLinkItem>[
      MissingLinkItem(deliveryAddress: '12 Nguyễn Huệ, Q1', orderCount: 5),
      MissingLinkItem(deliveryAddress: '45 Lê Lợi', orderCount: 2),
    ];

Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  List<MissingLinkItem>? seed,
  AddressService? service,
}) async {
  final svc = service ??
      _FakeAddressService(
        seed != null ? List<MissingLinkItem>.from(seed) : <MissingLinkItem>[],
      );
  // Disable Riverpod's default retry-on-Exception so error-state tests
  // settle into AsyncError immediately instead of AsyncLoading(retrying).
  final container = ProviderContainer(
    overrides: [addressServiceProvider.overrideWithValue(svc)],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MissingLinksScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('MissingLinksScreen (DG-388 Phase 3 / FR1/FR2/FR6/AC1/AC2/AC5)',
      () {
    testWidgets('renders title and seed entries (FR1/AC1)', (tester) async {
      await _pumpScreen(tester, seed: _seedStore());
      expect(find.text(AddressLabels.missingLinksTitle), findsOneWidget);
      expect(find.text('12 Nguyễn Huệ, Q1'), findsOneWidget);
      expect(find.text('45 Lê Lợi'), findsOneWidget);
      // order-count subtitles
      expect(
        find.textContaining('5${AddressLabels.missingLinksOrderCountSuffix}'),
        findsOneWidget,
      );
      expect(
        find.textContaining('2${AddressLabels.missingLinksOrderCountSuffix}'),
        findsOneWidget,
      );
    });

    testWidgets('uses ListView.builder for lazy rendering (NFR2)',
        (tester) async {
      await _pumpScreen(tester, seed: _seedStore());
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('shows empty state when list is empty (AC5)', (tester) async {
      await _pumpScreen(tester, seed: const <MissingLinkItem>[]);
      expect(find.text(AddressLabels.missingLinksEmpty), findsOneWidget);
    });

    testWidgets('shows error state with retry button on backend error (AC5)',
        (tester) async {
      await _pumpScreen(
        tester,
        service: _ThrowingAddressService(),
      );
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      expect(find.textContaining(VN.apiError), findsOneWidget);
      expect(find.widgetWithText(FilledButton, VN.retry), findsOneWidget);
    });

    testWidgets('retry button re-fetches the list (AC5)', (tester) async {
      // Make the first call throw, then succeed.
      var shouldThrow = true;
      final throwingFake = _ConditionalThrowService(
        List<MissingLinkItem>.from(_seedStore()),
        () => shouldThrow,
      );
      await _pumpScreen(tester, service: throwingFake);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      // Now allow success and tap retry.
      shouldThrow = false;
      await tester.tap(find.widgetWithText(FilledButton, VN.retry));
      await tester.pumpAndSettle();
      expect(find.text('12 Nguyễn Huệ, Q1'), findsOneWidget);
    });

    testWidgets('renders Open in Google Maps button on each row (FR2/AC2)',
        (tester) async {
      await _pumpScreen(tester, seed: _seedStore());
      expect(find.byIcon(Icons.open_in_new), findsNWidgets(2));
      expect(
        find.byTooltip(AddressLabels.missingLinksOpenMapTooltip),
        findsNWidgets(2),
      );
    });

    testWidgets('pull-to-refresh RefreshIndicator is present (FR6)',
        (tester) async {
      await _pumpScreen(tester, seed: _seedStore());
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('RefreshIndicator onRefresh calls provider refresh (FR6)',
        (tester) async {
      final fake =
          _FakeAddressService(List<MissingLinkItem>.from(_seedStore()));
      await _pumpScreen(tester, service: fake);
      final initialCalls = fake.refreshCalls;
      // Drag the list down to trigger refresh.
      await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(fake.refreshCalls, greaterThan(initialCalls));
    });

    testWidgets('googleMapsSearchUrl encodes the address (FR2/AC2)',
        (tester) async {
      final url = MissingLinksScreen.googleMapsSearchUrl('12 Nguyễn Huệ, Q1');
      expect(url, startsWith('https://www.google.com/maps/search/?api=1&'));
      // The address text is included as the query parameter value, with
      // spaces encoded as '+' (form-encoding mode).
      expect(url, contains('query=12+Nguy'));
    });
  });
}

/// Service whose `missingLinks()` throws when [shouldThrow] returns true,
/// so tests can flip the backend state between error and success.
class _ConditionalThrowService extends AddressService {
  _ConditionalThrowService(this._store, this._shouldThrow) : super(Dio());

  final List<MissingLinkItem> _store;
  final bool Function() _shouldThrow;

  @override
  Future<List<MissingLinkItem>> missingLinks({int? limit}) async {
    if (_shouldThrow()) {
      throw Exception('backend down');
    }
    return List<MissingLinkItem>.from(_store);
  }
}