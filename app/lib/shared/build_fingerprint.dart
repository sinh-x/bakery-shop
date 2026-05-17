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

String shortBuildFingerprint(String value) {
  const shortLength = 7;
  if (value.length <= shortLength) {
    return value;
  }
  return value.substring(0, shortLength);
}

String get clientBuildFingerprint {
  return normalizeBuildFingerprint(clientBuildFingerprintRaw);
}
