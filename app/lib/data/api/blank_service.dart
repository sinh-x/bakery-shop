import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/blank.dart';
import 'api_client.dart';

/// Dio-based service for the blanks (phôi bánh) management API (DG-290).
///
/// All endpoints use camelCase JSON keys per the backend convention. Delete
/// operations return 204 with no JSON body and are handled as `void`.
class BlankService {
  final Dio _dio;

  BlankService(this._dio);

  // --- Blank CRUD (FR1) -----------------------------------------------------

  /// List all blanks, optionally filtered by [category].
  Future<List<Blank>> listBlanks({String? category}) async {
    final params = <String, dynamic>{};
    if (category != null && category.isNotEmpty) params['category'] = category;
    final response = await _dio.get('/api/blanks', queryParameters: params);
    final list = response.data as List;
    return list
        .map((json) => Blank.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Create a new blank. Returns the created blank (201).
  Future<Blank> createBlank({
    required String name,
    String category = '',
    String unit = '',
    String notes = '',
  }) async {
    final data = <String, dynamic>{
      'name': name,
      'category': category,
      'unit': unit,
      'notes': notes,
    };
    final response = await _dio.post('/api/blanks', data: data);
    return Blank.fromJson(response.data as Map<String, dynamic>);
  }

  /// Update an existing blank. Only non-null fields are sent.
  Future<Blank> updateBlank(
    int id, {
    String? name,
    String? category,
    String? unit,
    String? notes,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (category != null) data['category'] = category;
    if (unit != null) data['unit'] = unit;
    if (notes != null) data['notes'] = notes;
    final response = await _dio.patch('/api/blanks/$id', data: data);
    return Blank.fromJson(response.data as Map<String, dynamic>);
  }

  /// Delete a blank. Returns 204 with no body.
  Future<void> deleteBlank(int id) async {
    await _dio.delete('/api/blanks/$id');
  }

  // --- BOM mapping via price_chip (FR2) ------------------------------------

  /// List all BOM mappings for a price chip.
  Future<List<ProductBlankBom>> listBom(int chipId) async {
    final response = await _dio.get('/api/price-chips/$chipId/blanks');
    final list = response.data as List;
    return list
        .map((json) => ProductBlankBom.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Create a new BOM mapping for a price chip. Returns the created BOM (201).
  Future<ProductBlankBom> createBom(
    int chipId,
    int blankId,
    double quantity,
  ) async {
    final data = <String, dynamic>{
      'blankId': blankId,
      'quantity': quantity,
    };
    final response =
        await _dio.post('/api/price-chips/$chipId/blanks', data: data);
    return ProductBlankBom.fromJson(response.data as Map<String, dynamic>);
  }

  /// Update a BOM mapping's quantity. Returns the updated BOM.
  Future<ProductBlankBom> updateBom(
    int chipId,
    int bomId,
    double quantity,
  ) async {
    final data = <String, dynamic>{'quantity': quantity};
    final response = await _dio.patch(
      '/api/price-chips/$chipId/blanks/$bomId',
      data: data,
    );
    return ProductBlankBom.fromJson(response.data as Map<String, dynamic>);
  }

  /// Delete a BOM mapping. Returns 204 with no body.
  Future<void> deleteBom(int chipId, int bomId) async {
    await _dio.delete('/api/price-chips/$chipId/blanks/$bomId');
  }

  // --- Stock (FR4, FR5) -----------------------------------------------------

  /// Get current net stock per blank.
  Future<List<BlankStockSummary>> getStock() async {
    final response = await _dio.get('/api/blanks/stock');
    final list = response.data as List;
    return list
        .map((json) => BlankStockSummary.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Record a stock change (production or usage). Returns the created entry (201).
  Future<BlankStockEntry> recordStock(
    int blankId,
    double quantity,
    String type, {
    String producedDate = '',
    String? expiryDate,
  }) async {
    final data = <String, dynamic>{
      'blankId': blankId,
      'quantity': quantity,
      'type': type,
      'producedDate': producedDate,
      'expiryDate': expiryDate,
    };
    final response = await _dio.post('/api/blanks/stock', data: data);
    return BlankStockEntry.fromJson(response.data as Map<String, dynamic>);
  }

  // --- Audit log (FR5) -----------------------------------------------------

  /// List the stock audit log for a single blank, newest-first.
  Future<List<BlankStockLog>> listStockLog(int blankId) async {
    final response = await _dio.get('/api/blanks/$blankId/stock-log');
    final list = response.data as List;
    return list
        .map((json) => BlankStockLog.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // --- Demand (FR3) --------------------------------------------------------

  /// Get demand vs stock vs shortage per blank from pending orders.
  Future<List<BlankDemand>> getDemand() async {
    final response = await _dio.get('/api/blanks/demand');
    final list = response.data as List;
    return list
        .map((json) => BlankDemand.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // --- Reverse lookup (DG-293 FR3) -----------------------------------------

  /// Get products/work items linked to a blank (BOM products + work items).
  Future<BlankProducts> getBlankProducts(int blankId) async {
    final response = await _dio.get('/api/blanks/$blankId/products');
    return BlankProducts.fromJson(response.data as Map<String, dynamic>);
  }
}

/// Riverpod provider for [BlankService].
final blankServiceProvider = Provider<BlankService>((ref) {
  final dio = ref.watch(dioProvider);
  return BlankService(dio);
});