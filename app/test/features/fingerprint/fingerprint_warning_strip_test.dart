import 'package:bakery_app/app.dart';
import 'package:bakery_app/data/providers/fingerprint_provider.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows top warning strip when fingerprints mismatch', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
  });
}
