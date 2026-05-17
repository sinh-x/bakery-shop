import 'package:bakery_app/data/api/fingerprint_service.dart';
import 'package:bakery_app/data/providers/fingerprint_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFingerprintService extends FingerprintService {
  _FakeFingerprintService(this._serverFingerprint) : super(Dio());

  final String? _serverFingerprint;

  @override
  Future<String?> fetchServerFingerprint() async {
    return _serverFingerprint;
  }
}

void main() {
  group('fingerprintComparisonProvider', () {
    test('returns match when client and server fingerprints are equal', () async {
      final container = ProviderContainer(
        overrides: [
          clientFingerprintProvider.overrideWithValue('abc1234'),
          fingerprintServiceProvider.overrideWithValue(
            _FakeFingerprintService('abc1234'),
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
            _FakeFingerprintService('def5678'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(fingerprintComparisonProvider.future);

      expect(result.state, FingerprintComparisonState.mismatch);
      expect(result.clientFingerprint, 'abc1234');
      expect(result.serverFingerprint, 'def5678');
    });

    test('returns unknown when server fingerprint is unavailable', () async {
      final container = ProviderContainer(
        overrides: [
          clientFingerprintProvider.overrideWithValue('abc1234'),
          fingerprintServiceProvider.overrideWithValue(
            _FakeFingerprintService(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(fingerprintComparisonProvider.future);

      expect(result.state, FingerprintComparisonState.unknown);
      expect(result.clientFingerprint, 'abc1234');
      expect(result.serverFingerprint, 'unknown');
    });
  });
}
