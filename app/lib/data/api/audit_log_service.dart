import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// One audit log entry as returned by `GET /api/audit-log` (Phase 5, FR23).
///
/// Backend row shape: `id`, `username`, `action`, `entity_type`,
/// `entity_id`, `old_value`, `new_value`, `created_at`. The
/// `old_value`/`new_value` fields are JSON-encoded strings (or `null`) as
/// written by `record_audit_log` in `baker.api.auth`.
class AuditLogEntry {
  AuditLogEntry({
    required this.id,
    required this.username,
    required this.action,
    required this.entityType,
    required this.entityId,
    this.oldValue,
    this.newValue,
    required this.createdAt,
  });

  final int id;
  final String username;
  final String action;
  final String entityType;
  final String entityId;
  final String? oldValue;
  final String? newValue;
  final String createdAt;

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) => AuditLogEntry(
        id: json['id'] as int,
        username: json['username'] as String? ?? '',
        action: json['action'] as String? ?? '',
        entityType: json['entity_type'] as String? ?? '',
        entityId: '${json['entity_id'] ?? ''}',
        oldValue: json['old_value'] as String?,
        newValue: json['new_value'] as String?,
        createdAt: json['created_at'] as String? ?? '',
      );
}

/// Paginated response envelope returned by `GET /api/audit-log`.
class AuditLogPage {
  AuditLogPage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final List<AuditLogEntry> items;
  final int page;
  final int pageSize;
  final int total;

  int get totalPages => pageSize <= 0 ? 0 : (total + pageSize - 1) ~/ pageSize;

  factory AuditLogPage.fromJson(Map<String, dynamic> json) => AuditLogPage(
        items: ((json['items'] as List?) ?? const [])
            .map((e) => AuditLogEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        page: (json['page'] as num?)?.toInt() ?? 1,
        pageSize: (json['page_size'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
      );
}

/// Filter parameters for audit log queries (FR24).
///
/// All fields are nullable/empty to mean "no filter on this dimension". The
/// backend treats empty-string query params as "no filter" (Phase 5).
class AuditLogFilters {
  const AuditLogFilters({
    this.username = '',
    this.entityType = '',
    this.dateFrom = '',
    this.dateTo = '',
  });

  final String username;
  final String entityType;
  final String dateFrom;
  final String dateTo;

  bool get isEmpty =>
      username.isEmpty &&
      entityType.isEmpty &&
      dateFrom.isEmpty &&
      dateTo.isEmpty;

  AuditLogFilters copyWith({
    String? username,
    String? entityType,
    String? dateFrom,
    String? dateTo,
  }) =>
      AuditLogFilters(
        username: username ?? this.username,
        entityType: entityType ?? this.entityType,
        dateFrom: dateFrom ?? this.dateFrom,
        dateTo: dateTo ?? this.dateTo,
      );

  Map<String, dynamic> toQueryParams({required int page, int pageSize = 50}) {
    final params = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
    };
    if (username.isNotEmpty) params['username'] = username;
    if (entityType.isNotEmpty) params['entity_type'] = entityType;
    if (dateFrom.isNotEmpty) params['date_from'] = dateFrom;
    if (dateTo.isNotEmpty) params['date_to'] = dateTo;
    return params;
  }
}

/// Audit log API service — calls `GET /api/audit-log` (admin-only, FR23).
///
/// Follows the existing `ServiceClass(Dio)` + `serviceProvider` pattern (see
/// `EventService`, `StaffService`). Pagination uses `page`/`page_size` per
/// the backend contract; the client should page rather than fetch all
/// (NFR9).
class AuditLogService {
  AuditLogService(this._dio);

  final Dio _dio;

  Future<AuditLogPage> list({
    AuditLogFilters filters = const AuditLogFilters(),
    int page = 1,
    int pageSize = 50,
  }) async {
    final response = await _dio.get(
      '/api/audit-log',
      queryParameters: filters.toQueryParams(page: page, pageSize: pageSize),
    );
    return AuditLogPage.fromJson(response.data as Map<String, dynamic>);
  }
}

final auditLogServiceProvider = Provider<AuditLogService>((ref) {
  final dio = ref.watch(dioProvider);
  return AuditLogService(dio);
});