const String unknownBuildFingerprint = 'unknown';

const String clientBuildFingerprintRaw = String.fromEnvironment(
  'BAKER_BUILD_FINGERPRINT',
  defaultValue: unknownBuildFingerprint,
);

String normalizeBuildFingerprint(String? value) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) {
    return unknownBuildFingerprint;
  }
  return normalized;
}

bool isUsableBuildFingerprint(String value) {
  return value.isNotEmpty && value != unknownBuildFingerprint;
}

String get clientBuildFingerprint {
  return normalizeBuildFingerprint(clientBuildFingerprintRaw);
}
