import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cake_queue_item.dart';
import '../models/work_item.dart';
import 'api_client.dart';

class WorkItemService {
  final Dio _dio;

  WorkItemService(this._dio);

  /// Returns the base path for blank CRUD on a work item.
  static String _blanksBasePath(String orderRef, String itemId) =>
      '/api/orders/$orderRef/items/$itemId/blanks';

  Future<List<WorkItem>> listWorkItems(String orderRef) async {
    final response = await _dio.get('/api/orders/$orderRef/items');
    final list = response.data as List;
    return list
        .map((json) => WorkItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<WorkItem> createWorkItem(
    String orderRef, {
    required String productName,
    String productId = '',
    int quantity = 1,
    double unitPrice = 0.0,
    String notes = '',
    int position = 0,
    bool isExtra = false,
    bool isGift = false,
    Map<String, dynamic>? attributes,
    int? priceChipId,
  }) async {
    final response = await _dio.post(
      '/api/orders/$orderRef/items',
      data: {
        'productName': productName,
        'productId': productId,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'notes': notes,
        'position': position,
        'isExtra': isExtra,
        'isGift': isGift,
        'attributes': ?attributes,
        'priceChipId': priceChipId,
      },
    );
    return WorkItem.fromJson(response.data as Map<String, dynamic>);
  }

  Future<WorkItem> updateWorkItem(
    String orderRef,
    String itemId, {
    String? productName,
    String? productId,
    int? quantity,
    double? unitPrice,
    String? notes,
    int? position,
    bool? isBirthday,
    int? age,
    bool? isExtra,
    bool? isGift,
    Map<String, dynamic>? attributes,
    double? assignedPrice,
  }) async {
    final body = <String, dynamic>{};
    if (productName != null) body['productName'] = productName;
    if (productId != null) body['productId'] = productId;
    if (quantity != null) body['quantity'] = quantity;
    if (unitPrice != null) body['unitPrice'] = unitPrice;
    if (notes != null) body['notes'] = notes;
    if (position != null) body['position'] = position;
    if (isBirthday != null) body['isBirthday'] = isBirthday;
    if (age != null) body['age'] = age;
    if (isExtra != null) body['isExtra'] = isExtra;
    if (isGift != null) body['isGift'] = isGift;
    if (attributes != null) body['attributes'] = attributes;
    if (assignedPrice != null) body['assignedPrice'] = assignedPrice;

    final response = await _dio.patch(
      '/api/orders/$orderRef/items/$itemId',
      data: body,
    );
    return WorkItem.fromJson(response.data as Map<String, dynamic>);
  }

  /// Add a blank assignment to a work item.
  /// POST /api/orders/{ref}/items/{id}/blanks
  Future<BlankAssignment> addBlank(
    String orderRef,
    String itemId, {
    required int blankId,
    double quantity = 1.0,
    String notes = '',
  }) async {
    final response = await _dio.post(
      _blanksBasePath(orderRef, itemId),
      data: {
        'blankId': blankId,
        'quantity': quantity,
        'notes': notes,
      },
    );
    return BlankAssignment.fromJson(response.data as Map<String, dynamic>);
  }

  /// Update quantity/notes on an existing blank assignment.
  /// PATCH /api/orders/{ref}/items/{id}/blanks/{blankItemId}
  Future<BlankAssignment> updateBlank(
    String orderRef,
    String itemId,
    int blankItemId, {
    double? quantity,
    String? notes,
  }) async {
    final body = <String, dynamic>{};
    if (quantity != null) body['quantity'] = quantity;
    if (notes != null) body['notes'] = notes;
    final response = await _dio.patch(
      '${_blanksBasePath(orderRef, itemId)}/$blankItemId',
      data: body,
    );
    return BlankAssignment.fromJson(response.data as Map<String, dynamic>);
  }

  /// Remove a blank assignment from a work item.
  /// DELETE /api/orders/{ref}/items/{id}/blanks/{blankItemId}
  Future<void> deleteBlank(
    String orderRef,
    String itemId,
    int blankItemId,
  ) async {
    await _dio.delete('${_blanksBasePath(orderRef, itemId)}/$blankItemId');
  }

  Future<void> deleteWorkItem(String orderRef, String itemId) async {
    await _dio.delete('/api/orders/$orderRef/items/$itemId');
  }

  Future<WorkItem> transitionStatus(
    String orderRef,
    String itemId,
    String status, {
    String reason = '',
  }) async {
    final response = await _dio.post(
      '/api/orders/$orderRef/items/$itemId/status',
      data: {'status': status, 'reason': reason},
    );
    return WorkItem.fromJson(response.data as Map<String, dynamic>);
  }

  /// Fetch cross-order cake queue: pending + working items (optionally include ready).
  /// Calls GET /api/work-items. Returns items sorted by due date ascending.
  Future<List<CakeQueueItem>> listCakeQueue({bool includeReady = false}) async {
    final params = <String, dynamic>{};
    if (includeReady) params['include_ready'] = 'true';
    final response = await _dio.get('/api/work-items', queryParameters: params);
    final list = response.data as List;
    return list
        .map((json) => CakeQueueItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}

final workItemServiceProvider = Provider<WorkItemService>((ref) {
  final dio = ref.watch(dioProvider);
  return WorkItemService(dio);
});
