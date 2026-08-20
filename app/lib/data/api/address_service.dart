import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/address.dart';
import 'api_client.dart';

/// API client for the address library (DG-385 Phase 4 / DG-388 Phase 2).
///
/// Wraps the backend ``/api/addresses`` endpoints:
///   - GET    /api/addresses/autocomplete?q=&customerId=  — autocomplete
///     suggestions returned as a grouped ``{pastOrders, library}`` response
///     (DG-388 FR3). The ``pastOrders`` group holds the caller customer's
///     prior door-delivery addresses and the ``library`` group ranks their
///     own saved addresses first (FR5/AC5). The frontend renders two labeled
///     sections ("Địa chỉ đã giao" / "Thư viện địa chỉ") from this shape
///     (FR4/AC3). Each suggestion in both groups carries ``googleMapsUrl``
///     so the frontend can auto-bind the link on selection (FR2/AC2).
///   - GET    /api/addresses/library             — list all library entries
///     (Phase 5 management screen, FR6/FR8).
///   - POST   /api/addresses/library             — create a new entry (FR8).
///   - PATCH  /api/addresses/library/{id}        — update address and/or
///     link (FR8). Returns 409 on collision.
///   - DELETE /api/addresses/library/{id}        — hard delete (FR8).
///   - GET    /api/addresses/missing-links       — door-delivery addresses
///     missing a Google Maps link (DG-387 / FR1).
///
/// Traceability: FR1, FR2, FR3, FR4, FR5, FR7, FR8, AC1, AC2, AC3, AC5.
class AddressService {
  final Dio _dio;

  AddressService(this._dio);

  /// Autocomplete suggestions for the delivery address field (FR1/FR7).
  ///
  /// DG-388 Phase 2 changed the backend to always return a grouped
  /// ``{pastOrders, library}`` shape (FR3). This method returns the parsed
  /// [AddressAutocompleteResponse] so the dropdown can render two labeled
  /// sections ("Địa chỉ đã giao" / "Thư viện địa chỉ") (FR4). When
  /// [customerId] is supplied, ``pastOrders`` holds that customer's prior
  /// door-delivery addresses and the ``library`` group ranks their own
  /// addresses first (FR5/AC5). Each suggestion carries ``googleMapsUrl``
  /// so the caller can auto-bind the link on selection (FR2/AC2).
  Future<AddressAutocompleteResponse> autocomplete({
    required String query,
    int? customerId,
  }) async {
    final params = <String, dynamic>{'q': query};
    if (customerId != null) params['customerId'] = customerId;
    final response = await _dio.get(
      '/api/addresses/autocomplete',
      queryParameters: params,
    );
    return AddressAutocompleteResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// List all address library entries, optionally filtered by [search]
  /// (FR6/FR8). Used by the Phase 5 management screen.
  Future<List<AddressLibraryEntry>> listLibrary({String? search}) async {
    final params = <String, dynamic>{};
    if (search != null && search.trim().isNotEmpty) {
      params['search'] = search.trim();
    }
    final response = await _dio.get(
      '/api/addresses/library',
      queryParameters: params,
    );
    final list = response.data as List;
    return list
        .map((json) =>
            AddressLibraryEntry.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Create a new address library entry (FR8). Idempotent on duplicate
  /// (address, link) pairs at the backend.
  Future<AddressLibraryEntry> createLibraryEntry({
    required String displayAddress,
    String? googleMapsUrl,
  }) async {
    final body = <String, dynamic>{
      'displayAddress': displayAddress,
      ?googleMapsUrl: googleMapsUrl,
    };
    final response = await _dio.post('/api/addresses/library', data: body);
    return AddressLibraryEntry.fromJson(response.data as Map<String, dynamic>);
  }

  /// Update an address library entry (FR8). Only the supplied fields are
  /// sent; the backend treats missing fields as "no change".
  Future<AddressLibraryEntry> updateLibraryEntry(
    int id, {
    String? displayAddress,
    String? googleMapsUrl,
  }) async {
    final payload = <String, dynamic>{};
    if (displayAddress != null) payload['displayAddress'] = displayAddress;
    if (googleMapsUrl != null) payload['googleMapsUrl'] = googleMapsUrl;
    final response =
        await _dio.patch('/api/addresses/library/$id', data: payload);
    return AddressLibraryEntry.fromJson(response.data as Map<String, dynamic>);
  }

  /// Delete an address library entry (FR8). ``customer_addresses`` rows
  /// cascade via the v101 FK.
  Future<void> deleteLibraryEntry(int id) async {
    await _dio.delete('/api/addresses/library/$id');
  }

  /// Fetch door-delivery addresses that are missing Google Maps links
  /// (DG-387 backend / DG-388 Phase 1 / FR1).
  ///
  /// Calls ``GET /api/addresses/missing-links`` and returns up to [limit]
  /// entries (backend default 100). Each [MissingLinkItem] carries the raw
  /// ``deliveryAddress`` text and the ``orderCount`` of door-delivery
  /// orders referencing it without a link, ordered by ``orderCount``
  /// descending so the most-referenced gap surfaces first. The backend
  /// enforces ``limit >= 1``. On error, the Dio exception propagates to the
  /// caller (the provider surfaces it as an [AsyncError] for the UI).
  Future<List<MissingLinkItem>> missingLinks({int? limit}) async {
    final params = <String, dynamic>{};
    if (limit != null) params['limit'] = limit;
    final response = await _dio.get(
      '/api/addresses/missing-links',
      queryParameters: params,
    );
    final list = response.data as List;
    return list
        .map((json) =>
            MissingLinkItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}

final addressServiceProvider = Provider<AddressService>((ref) {
  final dio = ref.watch(dioProvider);
  return AddressService(dio);
});