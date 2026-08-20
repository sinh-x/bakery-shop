/// Shared order photo tag parsing utilities.
///
/// Single source of truth for parsing the comma-separated tag string stored
/// on [OrderPhoto.tags] into a set of trimmed, non-empty keys. Extracted from
/// the former private `_parseTags` helpers that were duplicated between
/// `order_photo_section.dart` and `order_photo_thumbnail.dart` (DG-364
/// review-auto cycle 1, MN-2).
Set<String> parseOrderPhotoTags(String tags) {
  if (tags.isEmpty) return {};
  return tags
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toSet();
}