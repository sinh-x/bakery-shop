import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/customer.dart';
import 'api_client.dart';

class CustomerService {
  final Dio _dio;

  CustomerService(this._dio);

  /// List customers with optional partial-match search by name or phone (FR1).
  Future<List<Customer>> listCustomers({String? search}) async {
    final params = <String, dynamic>{};
    if (search != null && search.trim().isNotEmpty) params['search'] = search.trim();
    final response = await _dio.get('/api/customers', queryParameters: params);
    final list = response.data as List;
    return list
        .map((json) => Customer.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get a single customer by id (FR3).
  Future<Customer> getCustomer(int id) async {
    final response = await _dio.get('/api/customers/$id');
    return Customer.fromJson(response.data as Map<String, dynamic>);
  }

  /// Create a customer with name (required), phone (optional, legacy), and
  /// phones (optional, multi-phone). When [phones] is provided it is sent as
  /// the `phones` array; otherwise the legacy [phone] string is sent. Returns
  /// the new customer plus other customers sharing the same primary phone
  /// (FR2, FR2a, FR4).
  Future<CustomerMutationResult> createCustomer({
    required String name,
    String phone = '',
    List<CustomerPhone>? phones,
  }) async {
    final body = <String, dynamic>{'name': name};
    if (phones != null) {
      body['phones'] = phones
          .map((p) => {'phone': p.phone, 'isPrimary': p.isPrimary})
          .toList();
    } else {
      body['phone'] = phone;
    }
    final response = await _dio.post('/api/customers', data: body);
    return _parseMutationResult(response.data as Map<String, dynamic>);
  }

  /// Update name, phone (legacy), and/or phones (multi-phone). When [phones]
  /// is provided it replaces all existing phone rows (FR5). Returns the updated
  /// customer plus other customers sharing the new primary phone (FR4, FR2a).
  Future<CustomerMutationResult> updateCustomer(
    int id, {
    String? name,
    String? phone,
    List<CustomerPhone>? phones,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (phones != null) {
      body['phones'] = phones
          .map((p) => {'phone': p.phone, 'isPrimary': p.isPrimary})
          .toList();
    } else if (phone != null) {
      body['phone'] = phone;
    }
    final response = await _dio.patch('/api/customers/$id', data: body);
    return _parseMutationResult(response.data as Map<String, dynamic>);
  }

  /// Delete a customer (hard-delete). Linked orders have their customer_id
  /// cleared by the backend (FR5). Returns the count of orders cleared.
  Future<int> deleteCustomer(int id) async {
    final response = await _dio.delete('/api/customers/$id');
    return (response.data['linkedOrdersCleared'] as num?)?.toInt() ?? 0;
  }

  /// Get a customer's order history (FR6). Orders are returned as raw JSON
  /// maps (full Order shape) so callers can decode them via [Order.fromJson].
  Future<List<Map<String, dynamic>>> getCustomerOrders(int id) async {
    final response = await _dio.get('/api/customers/$id/orders');
    final list = response.data as List;
    return list.cast<Map<String, dynamic>>();
  }

  CustomerMutationResult _parseMutationResult(Map<String, dynamic> json) {
    final customer = Customer.fromJson(json);
    final sharedRaw = json['sharedPhoneCustomers'];
    final shared = <Customer>[];
    if (sharedRaw is List) {
      for (final item in sharedRaw) {
        if (item is Map<String, dynamic>) {
          shared.add(Customer.fromJson(item));
        }
      }
    }
    return (customer: customer, sharedPhoneCustomers: shared);
  }
}

final customerServiceProvider = Provider<CustomerService>((ref) {
  final dio = ref.watch(dioProvider);
  return CustomerService(dio);
});