import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'reconciliation_models.dart';

export 'reconciliation_models.dart';

class ReconciliationService {
  ReconciliationService(this._dio);

  final Dio _dio;

  Future<ReconciliationDraft> getDraft() async {
    final response = await _dio.get('/api/reconciliations/draft');
    return ReconciliationDraft.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ReconciliationSubmitResult> submit(
    ReconciliationSubmitRequest request,
  ) async {
    final response = await _dio.post(
      '/api/reconciliations/submit',
      data: request.toJson(),
    );
    return ReconciliationSubmitResult.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<List<ReconciliationHistorySession>> getHistorySessions() async {
    final response = await _dio.get('/api/reconciliations/history');
    final data = response.data as Map<String, dynamic>;
    final sessions = (data['sessions'] as List<dynamic>? ?? <dynamic>[])
        .map(
          (item) =>
              ReconciliationHistorySession.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    return sessions;
  }

  Future<ReconciliationHistoryDetail> getHistoryDetail(int sessionId) async {
    final response = await _dio.get('/api/reconciliations/history/$sessionId');
    return ReconciliationHistoryDetail.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

}


final reconciliationServiceProvider = Provider<ReconciliationService>((ref) {
  final dio = ref.watch(dioProvider);
  return ReconciliationService(dio);
});
