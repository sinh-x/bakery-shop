import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      body['timestamp'] = timestamp.toIso8601String();
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
    if (timestamp != null) body['timestamp'] = timestamp.toIso8601String();
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
}

final eventServiceProvider = Provider<EventService>((ref) {
  final dio = ref.watch(dioProvider);
  return EventService(dio);
});
