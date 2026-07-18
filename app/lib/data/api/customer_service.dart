import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/customer.dart';
import 'api_client.dart';

/// One customer entry inside a duplicate-group payload (FR6).
///
/// Mirrors the backend `_duplicate_customer_row` shape returned by
/// `GET /api/customers/duplicates`. Plain Dart class (no freezed) because it
/// is a transient API response envelope, not a persisted model — matches the
/// `CustomerMutationResult` typedef convention.
class DuplicateCustomerEntry {
  const DuplicateCustomerEntry({
    required this.id,
    required this.name,
    required this.phone,
    required this.orderCount,
  });

  final int id;
  final String name;
  final String phone;
  final int orderCount;

  factory DuplicateCustomerEntry.fromJson(Map<String, dynamic> json) {
    return DuplicateCustomerEntry(
      id: (json['id'] as num).toInt(),
      name: (json['name'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      orderCount: (json['orderCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One duplicate candidate group (FR6).
///
/// `kind` is `"phone"` (shared normalized phone) or `"name"` (shared
/// diacritic-stripped `search_name`). `customers` always has ≥2 entries.
class DuplicateGroup {
  const DuplicateGroup({
    required this.key,
    required this.kind,
    required this.customers,
  });

  final String key;
  final String kind;
  final List<DuplicateCustomerEntry> customers;

  factory DuplicateGroup.fromJson(Map<String, dynamic> json) {
    final raw = json['customers'] as List? ?? const [];
    return DuplicateGroup(
      key: (json['key'] as String?) ?? '',
      kind: (json['kind'] as String?) ?? '',
      customers: raw
          .map((e) => DuplicateCustomerEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Response envelope for `GET /api/customers/duplicates` (FR6).
class DuplicateGroupsResult {
  const DuplicateGroupsResult({required this.groups});

  final List<DuplicateGroup> groups;

  factory DuplicateGroupsResult.fromJson(Map<String, dynamic> json) {
    final raw = json['groups'] as List? ?? const [];
    return DuplicateGroupsResult(
      groups: raw
          .map((g) => DuplicateGroup.fromJson(g as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Response envelope for `POST /api/customers/{id}/merge` (FR5/AC3).
///
/// Carries the merged target customer plus the merge effect counts
/// (`movedOrders`, `addedPhones`, `recomputedYears`) returned by the backend.
class MergeResult {
  const MergeResult({
    required this.ok,
    required this.targetId,
    required this.sourceId,
    required this.customer,
    required this.movedOrders,
    required this.addedPhones,
    required this.recomputedYears,
  });

  final bool ok;
  final int targetId;
  final int sourceId;
  final Customer customer;
  final int movedOrders;
  final int addedPhones;
  final List<int> recomputedYears;

  factory MergeResult.fromJson(Map<String, dynamic> json) {
    return MergeResult(
      ok: (json['ok'] as bool?) ?? false,
      targetId: (json['targetId'] as num?)?.toInt() ?? 0,
      sourceId: (json['sourceId'] as num?)?.toInt() ?? 0,
      customer: Customer.fromJson(
        (json['customer'] as Map<String, dynamic>?) ?? const {},
      ),
      movedOrders: (json['movedOrders'] as num?)?.toInt() ?? 0,
      addedPhones: (json['addedPhones'] as num?)?.toInt() ?? 0,
      recomputedYears: ((json['recomputedYears'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
    );
  }
}

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

  /// Delete a customer (hard-delete). Admin-only on the backend.
  ///
  /// FR10/AC7: linked orders are NEVER unlinked. If the customer has ≥1
  /// linked order, the backend returns 409 with VN guidance directing the
  /// caller to merge instead; no data is mutated. On success the customer
  /// row and its `customer_phones` rows are removed.
  ///
  /// Throws a `DioException` on 403 (non-admin) or 409 (linked orders); the
  /// caller surfaces the backend's VN `detail` message.
  Future<void> deleteCustomer(int id) async {
    await _dio.delete('/api/customers/$id');
  }

  /// Get a customer's order history (FR6). Orders are returned as raw JSON
  /// maps (full Order shape) so callers can decode them via `Order.fromJson`.
  Future<List<Map<String, dynamic>>> getCustomerOrders(int id) async {
    final response = await _dio.get('/api/customers/$id/orders');
    final list = response.data as List;
    return list.cast<Map<String, dynamic>>();
  }

  /// List duplicate customer candidate groups (FR6/AC4). Admin-only on the
  /// backend (`RequireRole("admin")`). Groups are keyed by normalized phone
  /// or diacritic-stripped `search_name`; each member carries its order
  /// count for the merge confirmation dialog.
  Future<DuplicateGroupsResult> listDuplicates() async {
    final response = await _dio.get('/api/customers/duplicates');
    return DuplicateGroupsResult.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// Merge a source customer into a target customer (FR5/AC3). Admin-only on
  /// the backend. Relinks the source's orders and phones to the target,
  /// recomputes the target's year summary, hard-deletes the source, and
  /// writes an audit-log entry — all in one SQLite transaction.
  ///
  /// [targetId] is the customer to keep (path param); [sourceId] is the
  /// customer to merge into the target and then delete (body
  /// `sourceCustomerId`).
  Future<MergeResult> mergeCustomers({
    required int targetId,
    required int sourceId,
  }) async {
    final response = await _dio.post(
      '/api/customers/$targetId/merge',
      data: {'sourceCustomerId': sourceId},
    );
    return MergeResult.fromJson(response.data as Map<String, dynamic>);
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