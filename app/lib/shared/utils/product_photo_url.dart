String productPhotoUrl(
  String baseUrl,
  int productId, {
  String? cacheBuster,
}) {
  final uri = Uri.parse('$baseUrl/api/products/$productId/photo');
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
