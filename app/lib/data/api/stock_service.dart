import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

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
}

final stockServiceProvider = Provider<StockService>((ref) {
  final dio = ref.watch(dioProvider);
  return StockService(dio);
});