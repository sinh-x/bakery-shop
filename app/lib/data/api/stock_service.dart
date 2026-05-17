import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Stock overview item returned by GET /api/stock/overview
class StockOverviewItem {
  final int productId;
  final String productName;
  final String category;
  final int quantity;
  final double? basePrice;
  final List<StockOverviewOption> perChip;

  StockOverviewItem({
    required this.productId,
    required this.productName,
    required this.category,
    required this.quantity,
    required this.basePrice,
    required this.perChip,
  });

  int get totalQuantity =>
      perChip.fold(0, (sum, option) => sum + option.quantity);

  factory StockOverviewItem.fromJson(Map<String, dynamic> json) {
    return StockOverviewItem(
      productId: json['product_id'] as int,
      productName: json['product_name'] as String,
      category: json['category'] as String,
      quantity: json['quantity'] as int? ?? 0,
      basePrice: (json['base_price'] as num?)?.toDouble(),
      perChip: (json['per_chip'] as List<dynamic>? ?? <dynamic>[])
          .map(
            (entry) =>
                StockOverviewOption.fromJson(entry as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class StockOverviewOption {
  final int normalizedPrice;
  final int quantity;
  final List<String> chipLabels;
  final String? chipLabel;

  StockOverviewOption({
    required this.normalizedPrice,
    required this.quantity,
    required this.chipLabels,
    required this.chipLabel,
  });

  String get displayLabel {
    if (chipLabel != null && chipLabel!.trim().isNotEmpty) {
      return chipLabel!.trim();
    }
    if (chipLabels.isNotEmpty) {
      return chipLabels.join(', ');
    }
    return 'Giá gốc';
  }

  factory StockOverviewOption.fromJson(Map<String, dynamic> json) {
    final labels = (json['chip_labels'] as List<dynamic>? ?? <dynamic>[])
        .map((entry) => entry.toString().trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
    final fallbackPrice = (json['price'] as num?)?.toInt();
    final normalizedPrice =
        (json['normalized_price'] as num?)?.toInt() ?? fallbackPrice ?? 0;
    return StockOverviewOption(
      normalizedPrice: normalizedPrice,
      quantity: json['quantity'] as int? ?? 0,
      chipLabels: labels,
      chipLabel: (json['chip_label'] as String?)?.trim(),
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

  Future<void> restock(
    int productId,
    int quantity, {
    String note = '',
    int? normalizedPrice,
  }) async {
    await _dio.post(
      '/api/products/$productId/stock/restock',
      data: {
        'quantity': quantity,
        'note': note,
        'normalized_price': normalizedPrice,
      },
    );
  }

  Future<void> waste(
    int productId,
    int quantity,
    String reason, {
    int? normalizedPrice,
  }) async {
    await _dio.post(
      '/api/products/$productId/stock/waste',
      data: {
        'quantity': quantity,
        'reason': reason,
        'normalized_price': normalizedPrice,
      },
    );
  }

  Future<void> adjust(
    int productId,
    int quantity,
    String reason, {
    int? normalizedPrice,
  }) async {
    await _dio.post(
      '/api/products/$productId/stock/adjust',
      data: {
        'quantity': quantity,
        'reason': reason,
        'normalized_price': normalizedPrice,
      },
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
