import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/order.dart';
import 'api_client.dart';

class OrderService {
  final Dio _dio;

  OrderService(this._dio);

  Future<List<Order>> listOrders({
    String? status,
    String? dueDate,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{'limit': limit, 'offset': offset};
    if (status != null) params['status'] = status;
    if (dueDate != null) params['due_date'] = dueDate;

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
    List<Map<String, dynamic>> items = const [],
    String? dueDate,
    String? dueTime,
    String deliveryType = 'pickup',
    String deliveryAddress = '',
    String notes = '',
  }) async {
    final body = <String, dynamic>{
      'customerName': customerName,
      'customerPhone': customerPhone,
      'items': items,
      'deliveryType': deliveryType,
      'deliveryAddress': deliveryAddress,
      'notes': notes,
    };
    if (dueDate != null) body['dueDate'] = dueDate;
    if (dueTime != null) body['dueTime'] = dueTime;

    final response = await _dio.post('/api/orders', data: body);
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Order> editOrder(
    String ref, {
    String? customerName,
    String? customerPhone,
    String? dueDate,
    String? dueTime,
    String? deliveryType,
    String? deliveryAddress,
    String? notes,
  }) async {
    final body = <String, dynamic>{};
    if (customerName != null) body['customerName'] = customerName;
    if (customerPhone != null) body['customerPhone'] = customerPhone;
    if (dueDate != null) body['dueDate'] = dueDate;
    if (dueTime != null) body['dueTime'] = dueTime;
    if (deliveryType != null) body['deliveryType'] = deliveryType;
    if (deliveryAddress != null) body['deliveryAddress'] = deliveryAddress;
    if (notes != null) body['notes'] = notes;

    final response = await _dio.patch('/api/orders/$ref', data: body);
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Order> updateStatus(
    String ref,
    String status, {
    String reason = '',
  }) async {
    final response = await _dio.post(
      '/api/orders/$ref/status',
      data: {'status': status, 'reason': reason},
    );
    return Order.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Order> updatePayment(String ref, double amountPaid) async {
    final response = await _dio.patch(
      '/api/orders/$ref/payment',
      data: {'amountPaid': amountPaid},
    );
    return Order.fromJson(response.data as Map<String, dynamic>);
  }
}

final orderServiceProvider = Provider<OrderService>((ref) {
  final dio = ref.watch(dioProvider);
  return OrderService(dio);
});
