import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import '../models/checklist_template.dart';
import '../models/checklist_entry.dart';

class ChecklistService {
  final Dio _dio;

  ChecklistService(this._dio);

  // ── Template CRUD ──────────────────────────────────────────────────────────

  Future<List<ChecklistTemplate>> listTemplates({String? period}) async {
    final response = await _dio.get(
      '/api/checklist/templates',
      queryParameters: period != null ? {'period': period} : null,
    );
    final list = response.data as List;
    return list
        .map((json) =>
            ChecklistTemplate.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<ChecklistTemplate> createTemplate({
    required String name,
    required String period,
    int sortOrder = 0,
  }) async {
    final response = await _dio.post('/api/checklist/templates', data: {
      'name': name,
      'period': period,
      'sort_order': sortOrder,
      'active': true,
    });
    return ChecklistTemplate.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ChecklistTemplate> updateTemplate(
    int id, {
    String? name,
    String? period,
    int? sortOrder,
    bool? active,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (period != null) body['period'] = period;
    if (sortOrder != null) body['sort_order'] = sortOrder;
    if (active != null) body['active'] = active;

    final response = await _dio.put('/api/checklist/templates/$id', data: body);
    return ChecklistTemplate.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteTemplate(int id) async {
    await _dio.delete('/api/checklist/templates/$id');
  }

  // ── Daily checklist ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDailyChecklist({String? date}) async {
    final response = await _dio.get(
      '/api/checklist/daily',
      queryParameters: date != null ? {'date': date} : null,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<ChecklistEntry> toggleEntry(int entryId, String staffName) async {
    final response = await _dio.post(
      '/api/checklist/daily/$entryId/toggle',
      data: {'staff_name': staffName},
    );
    return ChecklistEntry.fromJson(response.data as Map<String, dynamic>);
  }

  // ── History ───────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getHistory({
    String? fromDate,
    String? toDate,
  }) async {
    final params = <String, dynamic>{};
    if (fromDate != null) params['from_date'] = fromDate;
    if (toDate != null) params['to_date'] = toDate;

    final response = await _dio.get(
      '/api/checklist/history',
      queryParameters: params.isNotEmpty ? params : null,
    );
    return (response.data as List).cast<Map<String, dynamic>>();
  }
}

final checklistServiceProvider = Provider<ChecklistService>((ref) {
  final dio = ref.watch(dioProvider);
  return ChecklistService(dio);
});
