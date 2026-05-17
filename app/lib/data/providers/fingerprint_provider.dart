import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/fingerprint_service.dart';
import '../../shared/build_fingerprint.dart';

enum FingerprintComparisonState { match, mismatch, unknown }

class FingerprintComparison {
  const FingerprintComparison({
    required this.state,
    required this.clientFingerprint,
    required this.serverFingerprint,
  });

  final FingerprintComparisonState state;
  final String clientFingerprint;
  final String serverFingerprint;
}

final clientFingerprintProvider = Provider<String>((ref) {
  return clientBuildFingerprint;
});

final fingerprintComparisonProvider = FutureProvider<FingerprintComparison>((ref) async {
  final clientFingerprintValue = normalizeBuildFingerprint(
    ref.read(clientFingerprintProvider),
  );
  final serverFingerprintValue = normalizeBuildFingerprint(
    await ref.read(fingerprintServiceProvider).fetchServerFingerprint(),
  );

  if (!isUsableBuildFingerprint(clientFingerprintValue) ||
      !isUsableBuildFingerprint(serverFingerprintValue)) {
    return FingerprintComparison(
      state: FingerprintComparisonState.unknown,
      clientFingerprint: clientFingerprintValue,
      serverFingerprint: serverFingerprintValue,
    );
  }

  final state = clientFingerprintValue == serverFingerprintValue
      ? FingerprintComparisonState.match
      : FingerprintComparisonState.mismatch;

  return FingerprintComparison(
    state: state,
    clientFingerprint: clientFingerprintValue,
    serverFingerprint: serverFingerprintValue,
  );
});
