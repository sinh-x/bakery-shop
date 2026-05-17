/// Sanitize [input] for use in a file name.
///
/// - Replaces invalid chars and path separators with underscores.
/// - Strips `..` sequences.
/// - Truncates at 100 Unicode scalar values (no surrogate-pair split).
/// - Returns `'photo'` when the sanitized string is empty.
String safeFileName(String input) {
  final sanitized = input
      .replaceAll(RegExp(r'[^\w\s\-]'), '_')
      .replaceAll(RegExp(r'[\/\\]'), '_')
      .replaceAll(RegExp(r'\.\.'), '_')
      .trim();
  if (sanitized.isEmpty) return 'photo';
  final runes = sanitized.runes;
  if (runes.length > 100) {
    return String.fromCharCodes(runes.take(100));
  }
  return sanitized;
}

/// Produces a unique file base for a catalog photo.
/// Includes productId + photoId so names cannot collide even when two
/// different products share the same sanitized name.
String catalogPhotoFileName({
  required String productName,
  required int productId,
  required int photoId,
  String extension = 'jpg',
}) {
  final safe = safeFileName(productName);
  final safeExtension = safeFileName(extension).toLowerCase();
  return '${safe}_p${productId}_$photoId.$safeExtension';
}
