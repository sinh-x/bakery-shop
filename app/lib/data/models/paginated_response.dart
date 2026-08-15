/// Generic pagination envelope mirroring the backend
/// ``{items, total, has_more, limit, offset}`` shape (DG-409 Phase 3/4, FR14).
///
/// Returned by opt-in paginated endpoints (``paginated=true`` or ``limit``
/// supplied). Plain Dart class (no freezed) because it is a transient API
/// response envelope, not a persisted model — matches the
/// `JournalListResponse` convention but kept generic so products, customers,
/// and order history can share one decoder.
class PaginatedResponse<T> {
  const PaginatedResponse({
    required this.items,
    required this.total,
    required this.hasMore,
    required this.limit,
    required this.offset,
  });

  final List<T> items;
  final int total;
  final bool hasMore;
  final int limit;
  final int offset;

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    final raw = json['items'] as List? ?? const [];
    return PaginatedResponse<T>(
      items: raw.map((e) => fromJsonT(e as Map<String, dynamic>)).toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      hasMore: (json['has_more'] as bool?) ?? false,
      limit: (json['limit'] as num?)?.toInt() ?? 0,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
    );
  }
}
