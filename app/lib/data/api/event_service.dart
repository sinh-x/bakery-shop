import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/utils/date_formatting.dart';
import '../models/event.dart';
import '../models/event_photo.dart';
import 'api_client.dart';

class EventService {
  final Dio _dio;

  EventService(this._dio);

  Future<BakeryEvent> createEvent({
    required String summary,
    String type = 'note',
    List<String> tags = const [],
    String loggedBy = '',
    Map<String, dynamic> data = const {},
    String source = 'app',
    DateTime? timestamp,
    int? orderId,
  }) async {
    final body = <String, dynamic>{
      'summary': summary,
      'type': type,
      'tags': tags,
      'logged_by': loggedBy,
      'data': data,
      'source': source,
    };
    if (timestamp != null) {
      body['timestamp'] = timestampToJson(timestamp);
    }
    if (orderId != null) {
      body['order_id'] = orderId;
    }
    final response = await _dio.post('/api/events', data: body);
    return BakeryEvent.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<BakeryEvent>> listEvents({
    String? type,
    String? tag,
    String? search,
    String? since,
    String? until,
    String? loggedBy,
    String? expenseCategory,
    String? expensePaymentMethod,
    String? expensePaymentSource,
    String? expenseStaffName,
    String? expensePaidByName,
    String? expenseSearch,
    String? expenseDebtStatus,
    int limit = 50,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (type != null) params['type'] = type;
    if (tag != null) params['tag'] = tag;
    if (search != null) params['search'] = search;
    if (since != null) params['since'] = since;
    if (until != null) params['until'] = until;
    if (loggedBy != null) params['logged_by'] = loggedBy;
    if (expenseCategory != null && expenseCategory.isNotEmpty) {
      params['expense_category'] = expenseCategory;
    }
    if (expensePaymentMethod != null && expensePaymentMethod.isNotEmpty) {
      params['expense_payment_method'] = expensePaymentMethod;
    }
    if (expensePaymentSource != null && expensePaymentSource.isNotEmpty) {
      params['expense_payment_source'] = expensePaymentSource;
    }
    if (expenseStaffName != null && expenseStaffName.isNotEmpty) {
      params['expense_staff_name'] = expenseStaffName;
    }
    if (expensePaidByName != null && expensePaidByName.isNotEmpty) {
      params['expense_paid_by_name'] = expensePaidByName;
    }
    if (expenseSearch != null && expenseSearch.isNotEmpty) {
      params['expense_search'] = expenseSearch;
    }
    if (expenseDebtStatus != null && expenseDebtStatus.isNotEmpty) {
      params['debt_status'] = expenseDebtStatus;
    }

    final response = await _dio.get('/api/events', queryParameters: params);
    final list = response.data as List;
    return list
        .map((json) => BakeryEvent.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<BakeryEvent> getEvent(int id) async {
    final response = await _dio.get('/api/events/$id');
    return BakeryEvent.fromJson(response.data as Map<String, dynamic>);
  }

  Future<BakeryEvent> updateEvent(
    int id, {
    String? summary,
    String? type,
    List<String>? tags,
    String? loggedBy,
    Map<String, dynamic>? data,
    DateTime? timestamp,
  }) async {
    final body = <String, dynamic>{};
    if (summary != null) body['summary'] = summary;
    if (type != null) body['type'] = type;
    if (tags != null) body['tags'] = tags;
    if (loggedBy != null) body['logged_by'] = loggedBy;
    if (data != null) body['data'] = data;
    if (timestamp != null) body['timestamp'] = timestampToJson(timestamp);
    final response = await _dio.patch('/api/events/$id', data: body);
    return BakeryEvent.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<BakeryEvent>> getOrderEvents(String orderRef) async {
    final response = await _dio.get('/api/orders/$orderRef/events');
    final list = response.data as List;
    return list
        .map((json) => BakeryEvent.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<EventPhoto> uploadEventPhoto(
    int eventId,
    File file, {
    String tags = '',
  }) async {
    final bytes = await file.readAsBytes();
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: file.path.split('/').last),
      'tags': tags,
    });
    final response = await _dio.post(
      '/api/events/$eventId/photos',
      data: formData,
    );
    return EventPhoto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteEvent(int id, {String deletedBy = ''}) async {
    await _dio.delete('/api/events/$id', queryParameters: {'deleted_by': deletedBy});
  }

  /// Settle a debt expense (DG-212 Phase 4 — FR4).
  ///
  /// POST /api/expenses/{id}/settle with [amount], [paymentMethod],
  /// [paymentSource], optional [note] and [timestamp]. Returns the parsed
  /// settlement response: ``event_id``, ``settlement_id``, ``amount``,
  /// ``settled_amount``, ``remaining``, ``status``, ``accounting_sync``.
  Future<Map<String, dynamic>> settleDebt({
    required int eventId,
    required int amount,
    String paymentMethod = 'Tiền mặt',
    required String paymentSource,
    String note = '',
    DateTime? timestamp,
  }) async {
    final body = <String, dynamic>{
      'amount': amount,
      'payment_method': paymentMethod,
      'payment_source': paymentSource,
      'note': note,
    };
    if (timestamp != null) {
      body['timestamp'] = timestampToJson(timestamp);
    }
    final response = await _dio.post(
      '/api/expenses/$eventId/settle',
      data: body,
    );
    return response.data as Map<String, dynamic>;
  }

  /// List outstanding debt expenses grouped by creditor (DG-212 Phase 4 — FR5).
  ///
  /// GET /api/expenses/debts with optional [creditor], [since], [until],
  /// [status] filters. Returns the parsed response: ``creditors`` (list of
  /// grouped debt objects with ``creditor``, ``debts``, ``total_owed``,
  /// ``count``), ``total_owed``, ``count``.
  Future<Map<String, dynamic>> listDebts({
    String? creditor,
    String? since,
    String? until,
    String? status,
  }) async {
    final params = <String, dynamic>{};
    if (creditor != null && creditor.isNotEmpty) {
      params['creditor'] = creditor;
    }
    if (since != null && since.isNotEmpty) {
      params['since'] = since;
    }
    if (until != null && until.isNotEmpty) {
      params['until'] = until;
    }
    if (status != null && status.isNotEmpty) {
      params['status'] = status;
    }
    final response = await _dio.get(
      '/api/expenses/debts',
      queryParameters: params,
    );
    return response.data as Map<String, dynamic>;
  }
}

final eventServiceProvider = Provider<EventService>((ref) {
  final dio = ref.watch(dioProvider);
  return EventService(dio);
});
