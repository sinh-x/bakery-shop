/// Constructs the URL for an event photo given the backend [baseUrl] and
/// the photo's content hash.
///
/// Mirrors [productPhotoUrl] to eliminate the 4 duplicated
/// `'$baseUrl/api/photos/{hash}.jpg'` patterns across the events, expenses,
/// quick-log, and order photo widgets. The hash identifies the stored
/// flat-file (see `src/baker/api/photos.py`); the `.jpg` suffix is part of
/// the storage path convention, not a content-type assertion.
///
/// Pass [cacheBuster] to force a cache refresh (e.g. after a re-upload);
/// empty/whitespace values are ignored to keep URLs stable when not needed.
String eventPhotoUrl(
  String baseUrl,
  String photoHash, {
  String? cacheBuster,
}) {
  final uri = Uri.parse('$baseUrl/api/photos/$photoHash.jpg');
  final tick = cacheBuster?.trim();
  if (tick == null || tick.isEmpty) {
    return uri.toString();
  }
  return uri
      .replace(
        queryParameters: <String, String>{...uri.queryParameters, 'v': tick},
      )
      .toString();
}