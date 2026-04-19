import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Stock overview item returned by GET /api/stock/overview
class StockOverviewItem {
  final int productId;
  final String productName;
  final String category;
  final int quantity;

  StockOverviewItem({
    required this.productId,
    required this.productName,
    required this.category,
    required this.quantity,
  });

  factory StockOverviewItem.fromJson(Map<String, dynamic> json) {
    return StockOverviewItem(
      productId: json['product_id'] as int,
      productName: json['product_name'] as String,
      category: json['category'] as String,
      quantity: json['quantity'] as int,
    );
  }
}

/// Stock API client for POS inventory management.
class StockService {
  final Dio _dio;

  StockService(this._dio);

  Future<int> getStock(int productId) async {
    final response = await _dio.get('/api/products/$productId/stock');
    return response.data['quantity'] as int;
  }

  Future<void> restock(int productId, int quantity, {String note = ''}) async {
    await _dio.post(
      '/api/products/$productId/stock/restock',
      data: {'quantity': quantity, 'note': note},
    );
  }

  Future<void> waste(int productId, int quantity, String reason) async {
    await _dio.post(
      '/api/products/$productId/stock/waste',
      data: {'quantity': quantity, 'reason': reason},
    );
  }

  Future<void> adjust(int productId, int quantity, String reason) async {
    await _dio.post(
      '/api/products/$productId/stock/adjust',
      data: {'quantity': quantity, 'reason': reason},
    );
  }

  Future<List<StockOverviewItem>> getStockOverview() async {
    final response = await _dio.get('/api/stock/overview');
    final list = response.data as List;
    return list
        .map((json) => StockOverviewItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}

final stockServiceProvider = Provider<StockService>((ref) {
  final dio = ref.watch(dioProvider);
  return StockService(dio);
});