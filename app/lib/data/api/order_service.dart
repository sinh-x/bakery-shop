import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../models/order.dart';
import '../models/order_photo.dart';
import 'api_client.dart';

class OrderService {
  final Dio _dio;

  OrderService(this._dio);

  Future<List<Order>> listOrders({
    String? status,
    String? dueDate,
    String? dueDateFrom,
    String? dueDateTo,
    int limit = 50,
    int offset = 0,
    bool activeOnly = false,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (status != null) params['status'] = status;
    if (dueDate != null) params['due_date'] = dueDate;
    if (dueDateFrom != null) params['due_date_from'] = dueDateFrom;
    if (dueDateTo != null) params['due_date_to'] = dueDateTo;
    if (activeOnly) params['active_only'] = true;

    final response = await _dio.get('/api/orders', queryParameters: params);
    final list = response.data as List;
    return list
        .map((json) => Order.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Order> getOrder(String ref) async {
    final response = await _dio.get('/api/orders/$ref');
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Order> createOrder({
    required String customerName,
    String customerPhone = '',
    String deliveryPhone = '',
    int? customerId,
    List<Map<String, dynamic>> items = const [],
    String? dueDate,
    String? dueTime,
    String deliveryType = 'pickup',
    String deliveryAddress = '',
    String notes = '',
    String? source,
    String createdBy = '',
    double shippingFee = 0.0,
    String? status,
    String? paymentMethod,
    double? latitude,
    double? longitude,
    String? googleMapsUrl,
    String? deliveryTimeSlot,
  }) async {
    final body = <String, dynamic>{
      'customerName': customerName,
      'customerPhone': customerPhone,
      'deliveryPhone': deliveryPhone,
      'items': items,
      'deliveryType': deliveryType,
      'deliveryAddress': deliveryAddress,
      'notes': notes,
      'shippingFee': shippingFee,
    };
    if (customerId != null) body['customerId'] = customerId;
    if (dueDate != null) body['dueDate'] = dueDate;
    if (dueTime != null) body['dueTime'] = dueTime;
    if (source != null && source.isNotEmpty) body['source'] = source;
    if (createdBy.isNotEmpty) body['createdBy'] = createdBy;
    if (status != null) body['status'] = status;
    if (paymentMethod != null) body['paymentMethod'] = paymentMethod;
    if (latitude != null) body['latitude'] = latitude;
    if (longitude != null) body['longitude'] = longitude;
    if (googleMapsUrl != null && googleMapsUrl.isNotEmpty) {
      body['googleMapsUrl'] = googleMapsUrl;
    }
    if (deliveryTimeSlot != null && deliveryTimeSlot.isNotEmpty) {
      body['deliveryTimeSlot'] = deliveryTimeSlot;
    }

    final response = await _dio.post('/api/orders', data: body);
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Order> editOrder(
    String ref, {
    String? customerName,
    String? customerPhone,
    String? deliveryPhone,
    int? customerId,
    bool customerTouched = false,
    String? dueDate,
    String? dueTime,
    String? deliveryType,
    String? deliveryAddress,
    String? notes,
    String? source,
    String? publicCodeDateChangeDecision,
    String changedBy = '',
    double? shippingFee,
    double? latitude,
    double? longitude,
    String? googleMapsUrl,
    String? deliveryTimeSlot,
    // DG-304 Phase 5: admin staff assignment on any order. Sent explicitly
    // (incl. null to unassign) so the backend persists via the `field_map`
    // and logs the change in `order_history` (FR7/FR8/FR9/AC5). Mirrors the
    // `customerTouched` pattern: when the admin touched the assignment
    // dropdown, send `assignedStaffId` including null to unassign.
    String? assignedStaffId,
    bool assignedStaffTouched = false,
  }) async {
    final body = <String, dynamic>{};
    if (customerName != null) body['customerName'] = customerName;
    if (customerPhone != null) body['customerPhone'] = customerPhone;
    if (deliveryPhone != null) body['deliveryPhone'] = deliveryPhone;
    // OPS-1: when the customer was explicitly touched (selected or cleared) in
    // the edit screen, always send customerId — including null to unlink.
    if (customerTouched) {
      body['customerId'] = customerId;
    } else if (customerId != null) {
      body['customerId'] = customerId;
    }
    if (dueDate != null) body['dueDate'] = dueDate;
    if (dueTime != null) body['dueTime'] = dueTime;
    if (deliveryType != null) body['deliveryType'] = deliveryType;
    if (deliveryAddress != null) body['deliveryAddress'] = deliveryAddress;
    if (notes != null) body['notes'] = notes;
    if (source != null) body['source'] = source;
    if (publicCodeDateChangeDecision != null) {
      body['publicCodeDateChangeDecision'] = publicCodeDateChangeDecision;
    }
    if (changedBy.isNotEmpty) body['changedBy'] = changedBy;
    if (shippingFee != null) body['shippingFee'] = shippingFee;
    // DG-303 Phase 4: GPS + delivery time slot — nullable, door delivery only.
    // Send null explicitly so the backend can clear a previously-set value.
    body['latitude'] = latitude;
    body['longitude'] = longitude;
    body['googleMapsUrl'] = googleMapsUrl;
    body['deliveryTimeSlot'] = deliveryTimeSlot;
    // DG-304 Phase 5: only include when the admin touched the assignment so
    // a non-admin save (without the dropdown) never clears it inadvertently.
    // When touched, send the value including null to unassign (FR6).
    if (assignedStaffTouched) body['assignedStaffId'] = assignedStaffId;

    final response = await _dio.patch('/api/orders/$ref', data: body);
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Order> updateStatus(
    String ref,
    String status, {
    String reason = '',
    String changedBy = '',
  }) async {
    final body = <String, dynamic>{'status': status, 'reason': reason};
    if (changedBy.isNotEmpty) body['changedBy'] = changedBy;
    final response = await _dio.post('/api/orders/$ref/status', data: body);
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Order> updatePayment(
    String ref,
    double amountPaid, {
    String changedBy = '',
  }) async {
    final body = <String, dynamic>{'amountPaid': amountPaid};
    if (changedBy.isNotEmpty) body['changedBy'] = changedBy;
    final response = await _dio.patch('/api/orders/$ref/payment', data: body);
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Order> updatePaymentMethod(String ref, String method) async {
    final response = await _dio.patch(
      '/api/orders/$ref/payment-method',
      data: {'method': method},
    );
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Order> updateWorkTicketPrintedAt(String ref, String printedAt, {String changedBy = ''}) async {
    final body = <String, dynamic>{'workTicketPrintedAt': printedAt};
    if (changedBy.isNotEmpty) body['changedBy'] = changedBy;
    final response = await _dio.patch('/api/orders/$ref', data: body);
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  // ── Order Photos ──────────────────────────────────────────────────────────

  Future<List<OrderPhoto>> listOrderPhotos(String orderRef) async {
    final response = await _dio.get('/api/orders/$orderRef/photos');
    final list = response.data as List;
    return list
        .map((json) => OrderPhoto.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<OrderPhoto> uploadOrderPhoto(
    String orderRef,
    XFile file, {
    String tags = '',
    int? workItemId,
  }) async {
    final bytes = await file.readAsBytes();
    final map = <String, dynamic>{
      'file': MultipartFile.fromBytes(bytes, filename: file.name),
      'tags': tags,
    };
    if (workItemId != null) map['workItemId'] = workItemId.toString();
    final formData = FormData.fromMap(map);
    final response = await _dio.post(
      '/api/orders/$orderRef/photos',
      data: formData,
    );
    return OrderPhoto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<OrderPhoto> updatePhotoTags(
    String orderRef,
    int photoId,
    String tags,
  ) async {
    final response = await _dio.patch(
      '/api/orders/$orderRef/photos/$photoId',
      data: {'tags': tags},
    );
    return OrderPhoto.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteOrderPhoto(String orderRef, int photoId) async {
    await _dio.delete('/api/orders/$orderRef/photos/$photoId');
  }

  /// Acknowledges an order by setting `acknowledgedAt` on the backend.
  ///
  /// Called when the user opens an order detail that has not been acknowledged
  /// yet. Idempotent — safe to call multiple times.
  Future<Order> acknowledgeOrder(String ref) async {
    final response = await _dio.post('/api/orders/$ref/acknowledge');
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Claims a delivery order for the currently logged-in staff (FR5/AC6).
  /// Server enforces non-terminal status and single-assignee (any linked staff member may claim).
  Future<Order> assignOrder(String ref) async {
    final response = await _dio.post('/api/orders/$ref/assign');
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Releases a previously claimed delivery order (FR6/AC8). Only the assigned
  /// staff or an admin may unclaim; enforced server-side.
  Future<Order> unassignOrder(String ref) async {
    final response = await _dio.post('/api/orders/$ref/unassign');
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// DG-304 Phase 5: admin sets or clears the delivery staff assignment on
  /// any order (FR9/AC5). PATCHes only `assignedStaffId` (incl. null to
  /// unassign — FR6) via the `field_map` path so other fields are not
  /// clobbered and the change is logged in `order_history` (FR7).
  Future<Order> setAssignedStaff(
    String ref, {
    required String? assignedStaffId,
    String changedBy = '',
  }) async {
    final body = <String, dynamic>{'assignedStaffId': assignedStaffId};
    if (changedBy.isNotEmpty) body['changedBy'] = changedBy;
    final response = await _dio.patch('/api/orders/$ref', data: body);
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  /// Fetches lightweight order badge counts (urgency, incomplete) for active
  /// orders from `GET /api/orders/counts` (DG-409 Phase 2 / FR1/NFR2/NFR4).
  ///
  /// Returns a record `({urgency, incomplete})`. The backend already degrades
  /// to `{"urgency": 0, "incomplete": 0}` on error, so callers can rely on
  /// non-null ints. Used by shell-scaffold badge providers so the bottom nav
  /// no longer depends on the full order list fetch.
  Future<({int urgency, int incomplete})> fetchOrderCounts() async {
    final response = await _dio.get('/api/orders/counts');
    final data = response.data as Map<String, dynamic>;
    return (
      urgency: (data['urgency'] as num?)?.toInt() ?? 0,
      incomplete: (data['incomplete'] as num?)?.toInt() ?? 0,
    );
  }

  /// Fetches all active (non-terminal) orders for the dashboard view.
  Future<List<Order>> listActiveOrders({int limit = 200}) async {
    final response = await _dio.get(
      '/api/orders',
      queryParameters: {'limit': limit, 'offset': 0, 'active_only': true},
    );
    final list = response.data as List;
    return list
        .map((json) => Order.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}

final orderServiceProvider = Provider<OrderService>((ref) {
  final dio = ref.watch(dioProvider);
  return OrderService(dio);
});
