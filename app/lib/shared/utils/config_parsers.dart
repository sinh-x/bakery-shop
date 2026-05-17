double firstFeeOrFallback(List<String> values, double fallback) {
  for (final value in values) {
    final parsed = double.tryParse(value.trim());
    if (parsed != null && parsed >= 0) {
      return parsed;
    }
  }
  return fallback;
}
