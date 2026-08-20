import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/message_template.dart';
import 'api_client.dart';

/// Allowed scenario slugs for message templates (DG-375 FR9).
/// Matches the backend ``_ALLOWED_SCENARIOS`` in `src/baker/api/templates.py`.
const allowedTemplateScenarios = <String>{
  'ask_info',
  'confirm_order',
  'final_message',
  'follow_up',
  'status_update',
  'payment_request',
};

/// API client for ``/api/templates`` (DG-375 Phase 2).
///
/// Wraps the backend CRUD endpoints:
///   - GET    /api/templates            — list (system + caller's personal)
///   - POST   /api/templates            — create (admin→system, staff→personal)
///   - PATCH  /api/templates/{id}       — update (scoped by ownership/role)
///   - DELETE /api/templates/{id}        — delete (scoped by ownership/role)
///
/// Traceability: FR1 (list grouped by scenario), FR4 (raw body storage),
/// FR6 (admin CRUD for system templates), FR7 (staff CRUD for personal
/// templates), FR10 (management API accessible).
class TemplateService {
  final Dio _dio;

  TemplateService(this._dio);

  /// List templates (FR1). Returns system templates plus the caller's
  /// personal templates, ordered by scenario, sort_order, id so the caller
  /// can group them by scenario. When [scenario] is provided, filters to
  /// that scenario.
  Future<List<MessageTemplate>> listTemplates({String? scenario}) async {
    final params = <String, dynamic>{};
    if (scenario != null && scenario.trim().isNotEmpty) {
      params['scenario'] = scenario.trim();
    }
    final response = await _dio.get('/api/templates', queryParameters: params);
    final list = response.data as List;
    return list
        .map((json) => MessageTemplate.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Create a template (FR6 / FR7). Admin callers may create system templates
  /// (``isSystem = true``); staff callers create personal templates owned by
  /// their staff id (``isSystem = false``). The backend rejects a staff
  /// caller attempting to create a system template with 403.
  Future<MessageTemplate> createTemplate({
    required String scenario,
    required String name,
    required String body,
    bool isSystem = false,
    int sortOrder = 0,
    bool active = true,
  }) async {
    final body_ = <String, dynamic>{
      'scenario': scenario,
      'name': name,
      'body': body,
      'is_system': isSystem,
      'sort_order': sortOrder,
      'active': active,
    };
    final response = await _dio.post('/api/templates', data: body_);
    return MessageTemplate.fromJson(response.data as Map<String, dynamic>);
  }

  /// Update a template (FR6 / FR7). Admin may update any template; staff may
  /// update only their own personal templates. System templates are
  /// admin-only. Only non-null parameters are sent; the backend treats
  /// missing fields as "no change".
  Future<MessageTemplate> updateTemplate(
    int id, {
    String? scenario,
    String? name,
    String? body,
    bool? isSystem,
    int? sortOrder,
    bool? active,
  }) async {
    final payload = <String, dynamic>{};
    if (scenario != null) payload['scenario'] = scenario;
    if (name != null) payload['name'] = name;
    if (body != null) payload['body'] = body;
    if (isSystem != null) payload['is_system'] = isSystem;
    if (sortOrder != null) payload['sort_order'] = sortOrder;
    if (active != null) payload['active'] = active;

    final response = await _dio.patch('/api/templates/$id', data: payload);
    return MessageTemplate.fromJson(response.data as Map<String, dynamic>);
  }

  /// Delete a template (FR6 / FR7). Admin may delete any template; staff may
  /// delete only their own personal templates. System templates are
  /// admin-only.
  Future<void> deleteTemplate(int id) async {
    await _dio.delete('/api/templates/$id');
  }
}

final templateServiceProvider = Provider<TemplateService>((ref) {
  final dio = ref.watch(dioProvider);
  return TemplateService(dio);
});