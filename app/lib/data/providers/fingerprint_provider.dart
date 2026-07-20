import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/fingerprint_service.dart';
import '../../shared/build_fingerprint.dart';

final fingerprintWarningDismissedProvider = NotifierProvider<
  _FingerprintWarningDismissedNotifier, bool>(
  _FingerprintWarningDismissedNotifier.new,
);

enum FingerprintComparisonState { match, mismatch, serverUnknown, unknown }

class FingerprintComparison {
  const FingerprintComparison({
    required this.state,
    required this.clientFingerprint,
    required this.serverFingerprint,
  });

  final FingerprintComparisonState state;
  final String clientFingerprint;
  final String serverFingerprint;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is FingerprintComparison &&
        other.state == state &&
        other.clientFingerprint == clientFingerprint &&
        other.serverFingerprint == serverFingerprint;
  }

  @override
  int get hashCode {
    return Object.hash(state, clientFingerprint, serverFingerprint);
  }

  @override
  String toString() {
    return 'FingerprintComparison(state: $state, '
        'clientFingerprint: $clientFingerprint, '
        'serverFingerprint: $serverFingerprint)';
  }
}

class _FingerprintWarningDismissedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() {
    state = true;
  }
}

final clientFingerprintProvider = Provider<String>((ref) {
  return clientBuildFingerprint;
});

final fingerprintComparisonProvider = FutureProvider<FingerprintComparison>((ref) async {
  final clientFingerprintValue = normalizeBuildFingerprint(
    ref.read(clientFingerprintProvider),
  );
  final serverFingerprintResult = await ref
      .read(fingerprintServiceProvider)
      .fetchServerFingerprint();
  final serverFingerprintValue = normalizeBuildFingerprint(
    serverFingerprintResult.fingerprint,
  );
  final hasUsableClientFingerprint = isUsableBuildFingerprint(
    clientFingerprintValue,
  );
  final hasUsableServerFingerprint = isUsableBuildFingerprint(
    serverFingerprintValue,
  );

  if (!hasUsableClientFingerprint || !hasUsableServerFingerprint) {
    final state = serverFingerprintResult.healthReachable &&
            !hasUsableServerFingerprint &&
            hasUsableClientFingerprint
        ? FingerprintComparisonState.serverUnknown
        : FingerprintComparisonState.unknown;

    return FingerprintComparison(
      state: state,
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
