import 'package:bakery_app/app.dart';
import 'package:bakery_app/data/api/api_client.dart';
import 'package:bakery_app/data/providers/fingerprint_provider.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/login_screen_test_helpers.dart';

void main() {
  testWidgets('shows top warning strip when fingerprints mismatch', (
    tester,
  ) async {
    final prefs = await seedAuthenticatedPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          fingerprintComparisonProvider.overrideWith((ref) async {
            return const FingerprintComparison(
              state: FingerprintComparisonState.mismatch,
              clientFingerprint: 'abc1234',
              serverFingerprint: 'def5678',
            );
          }),
        ],
        child: const BakeryApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(VN.fingerprintMismatchWarning), findsOneWidget);
    expect(find.textContaining('abc1234/def5678'), findsOneWidget);
  });

  testWidgets('hides warning strip when fingerprints match', (tester) async {
    final prefs = await seedAuthenticatedPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          fingerprintComparisonProvider.overrideWith((ref) async {
            return const FingerprintComparison(
              state: FingerprintComparisonState.match,
              clientFingerprint: 'abc1234',
              serverFingerprint: 'abc1234',
            );
          }),
        ],
        child: const BakeryApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(VN.fingerprintMismatchWarning), findsNothing);
    expect(
      find.textContaining(VN.serverFingerprintUnavailableWarning),
      findsNothing,
    );
  });

  testWidgets('shows top warning strip when server fingerprint is unknown', (
    tester,
  ) async {
    final prefs = await seedAuthenticatedPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          fingerprintComparisonProvider.overrideWith((ref) async {
            return const FingerprintComparison(
              state: FingerprintComparisonState.serverUnknown,
              clientFingerprint: 'abc1234',
              serverFingerprint: 'unknown',
            );
          }),
        ],
        child: const BakeryApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(VN.serverFingerprintUnavailableWarning),
      findsOneWidget,
    );
  });

  testWidgets('hides warning strip when fingerprint state is unknown', (
    tester,
  ) async {
    final prefs = await seedAuthenticatedPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          fingerprintComparisonProvider.overrideWith((ref) async {
            return const FingerprintComparison(
              state: FingerprintComparisonState.unknown,
              clientFingerprint: 'abc1234',
              serverFingerprint: 'unknown',
            );
          }),
        ],
        child: const BakeryApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(VN.fingerprintMismatchWarning), findsNothing);
    expect(
      find.textContaining(VN.serverFingerprintUnavailableWarning),
      findsNothing,
    );
  });
}
