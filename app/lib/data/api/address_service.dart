import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/address.dart';
import 'api_client.dart';

/// API client for the address library (DG-385 Phase 4).
///
/// Wraps the backend ``/api/addresses`` endpoints exposed in Phase 2:
///   - GET    /api/addresses/autocomplete?q=&customerId=  — autocomplete
///     suggestions ranked with the caller customer's own addresses first
///     (FR1/FR5/AC1/AC5). Returns up to 20 entries, each carrying
///     ``googleMapsUrl`` so the frontend can auto-bind the link on
///     selection (FR2/AC2).
///   - GET    /api/addresses/library             — list all library entries
///     (Phase 5 management screen, FR6/FR8).
///   - POST   /api/addresses/library             — create a new entry (FR8).
///   - PATCH  /api/addresses/library/{id}        — update address and/or
///     link (FR8). Returns 409 on collision.
///   - DELETE /api/addresses/library/{id}        — hard delete (FR8).
///
/// Traceability: FR1, FR2, FR5, FR7, FR8, AC1, AC2, AC5.
class AddressService {
  final Dio _dio;

  AddressService(this._dio);

  /// Autocomplete suggestions for the delivery address field (FR1/FR7).
  ///
  /// The backend requires ``q`` to be at least 2 non-space characters and
  /// returns up to 20 normalized matches. When [customerId] is supplied,
  /// the customer's previously used addresses appear first (FR5/AC5).
  /// Each suggestion carries ``googleMapsUrl`` so the caller can auto-bind
  /// the link on selection (FR2/AC2).
  Future<List<AddressSuggestion>> autocomplete({
    required String query,
    int? customerId,
  }) async {
    final params = <String, dynamic>{'q': query};
    if (customerId != null) params['customerId'] = customerId;
    final response = await _dio.get(
      '/api/addresses/autocomplete',
      queryParameters: params,
    );
    final list = response.data as List;
    return list
        .map((json) =>
            AddressSuggestion.fromJson(json as Map<String, dynamic>))
        .toList();
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
}

final addressServiceProvider = Provider<AddressService>((ref) {
  final dio = ref.watch(dioProvider);
  return AddressService(dio);
});