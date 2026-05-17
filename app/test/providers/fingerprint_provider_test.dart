import 'package:bakery_app/data/api/fingerprint_service.dart';
import 'package:bakery_app/data/providers/fingerprint_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFingerprintService extends FingerprintService {
  _FakeFingerprintService({
    required this.serverFingerprint,
    this.healthReachable = true,
  }) : super(Dio());

  final String? serverFingerprint;
  final bool healthReachable;

  @override
  Future<ServerFingerprintResult> fetchServerFingerprint() async {
    return ServerFingerprintResult(
      healthReachable: healthReachable,
      fingerprint: serverFingerprint,
    );
  }
}

void main() {
  group('FingerprintComparison value semantics', () {
    test('supports equality and hashCode by value', () {
      const a = FingerprintComparison(
        state: FingerprintComparisonState.match,
        clientFingerprint: 'abc1234',
        serverFingerprint: 'abc1234',
      );
      const b = FingerprintComparison(
        state: FingerprintComparisonState.match,
        clientFingerprint: 'abc1234',
        serverFingerprint: 'abc1234',
      );
      const c = FingerprintComparison(
        state: FingerprintComparisonState.mismatch,
        clientFingerprint: 'abc1234',
        serverFingerprint: 'def5678',
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('includes fields in toString for debugging', () {
      const value = FingerprintComparison(
        state: FingerprintComparisonState.unknown,
        clientFingerprint: 'abc1234',
        serverFingerprint: 'unknown',
      );

      expect(value.toString(), contains('FingerprintComparison('));
      expect(value.toString(), contains('state: FingerprintComparisonState.unknown'));
      expect(value.toString(), contains('clientFingerprint: abc1234'));
      expect(value.toString(), contains('serverFingerprint: unknown'));
    });
  });

  group('fingerprintComparisonProvider', () {
    test('returns match when client and server fingerprints are equal', () async {
      final container = ProviderContainer(
        overrides: [
          clientFingerprintProvider.overrideWithValue('abc1234'),
          fingerprintServiceProvider.overrideWithValue(
            _FakeFingerprintService(serverFingerprint: 'abc1234'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(fingerprintComparisonProvider.future);

      expect(result.state, FingerprintComparisonState.match);
      expect(result.clientFingerprint, 'abc1234');
      expect(result.serverFingerprint, 'abc1234');
    });

    test('returns mismatch when client and server fingerprints differ', () async {
      final container = ProviderContainer(
        overrides: [
          clientFingerprintProvider.overrideWithValue('abc1234'),
          fingerprintServiceProvider.overrideWithValue(
            _FakeFingerprintService(serverFingerprint: 'def5678'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(fingerprintComparisonProvider.future);

      expect(result.state, FingerprintComparisonState.mismatch);
      expect(result.clientFingerprint, 'abc1234');
      expect(result.serverFingerprint, 'def5678');
    });

    test('returns serverUnknown when health is reachable but fingerprint is unavailable', () async {
      final container = ProviderContainer(
        overrides: [
          clientFingerprintProvider.overrideWithValue('abc1234'),
          fingerprintServiceProvider.overrideWithValue(
            _FakeFingerprintService(serverFingerprint: null),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(fingerprintComparisonProvider.future);

      expect(result.state, FingerprintComparisonState.serverUnknown);
      expect(result.clientFingerprint, 'abc1234');
      expect(result.serverFingerprint, 'unknown');
    });

    test('returns unknown when health is unreachable', () async {
      final container = ProviderContainer(
        overrides: [
          clientFingerprintProvider.overrideWithValue('abc1234'),
          fingerprintServiceProvider.overrideWithValue(
            _FakeFingerprintService(
              serverFingerprint: null,
              healthReachable: false,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(fingerprintComparisonProvider.future);

      expect(result.state, FingerprintComparisonState.unknown);
      expect(result.clientFingerprint, 'abc1234');
      expect(result.serverFingerprint, 'unknown');
    });

    test('returns unknown when client fingerprint is unavailable', () async {
      final container = ProviderContainer(
        overrides: [
          clientFingerprintProvider.overrideWithValue('unknown'),
          fingerprintServiceProvider.overrideWithValue(
            _FakeFingerprintService(serverFingerprint: null),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(fingerprintComparisonProvider.future);

      expect(result.state, FingerprintComparisonState.unknown);
      expect(result.clientFingerprint, 'unknown');
      expect(result.serverFingerprint, 'unknown');
    });
  });
}
