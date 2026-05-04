import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

class ReconciliationPriceChip {
  ReconciliationPriceChip({
    required this.id,
    required this.label,
    required this.price,
    required this.position,
  });

  final int id;
  final String label;
  final double price;
  final int position;

  factory ReconciliationPriceChip.fromJson(Map<String, dynamic> json) {
    return ReconciliationPriceChip(
      id: json['id'] as int,
      label: json['label'] as String,
      price: (json['price'] as num).toDouble(),
      position: json['position'] as int,
    );
  }
}

class ReconciliationDraftProduct {
  ReconciliationDraftProduct({
    required this.productId,
    required this.name,
    required this.category,
    required this.expectedQty,
    required this.basePrice,
    required this.priceChips,
  });

  final int productId;
  final String name;
  final String category;
  final int expectedQty;
  final double basePrice;
  final List<ReconciliationPriceChip> priceChips;

  factory ReconciliationDraftProduct.fromJson(Map<String, dynamic> json) {
    final chips = (json['price_chips'] as List<dynamic>? ?? <dynamic>[])
        .map(
          (item) =>
              ReconciliationPriceChip.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    return ReconciliationDraftProduct(
      productId: json['product_id'] as int,
      name: json['name'] as String,
      category: json['category'] as String,
      expectedQty: json['expected_qty'] as int,
      basePrice: (json['base_price'] as num).toDouble(),
      priceChips: chips,
    );
  }
}

class ReconciliationDraft {
  ReconciliationDraft({required this.date, required this.products});

  final String date;
  final List<ReconciliationDraftProduct> products;

  factory ReconciliationDraft.fromJson(Map<String, dynamic> json) {
    final products = (json['products'] as List<dynamic>? ?? <dynamic>[])
        .map(
          (item) =>
              ReconciliationDraftProduct.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    return ReconciliationDraft(
      date: json['date'] as String,
      products: products,
    );
  }
}

class ReconciliationSubmitLine {
  ReconciliationSubmitLine({
    required this.productId,
    required this.expectedQty,
    required this.countedQty,
    required this.saleQty,
    required this.wasteQty,
    this.manualUnitPrice,
  });

  final int productId;
  final int expectedQty;
  final int countedQty;
  final int saleQty;
  final int wasteQty;
  final double? manualUnitPrice;

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'expected_qty': expectedQty,
      'counted_qty': countedQty,
      'sale_qty': saleQty,
      'waste_qty': wasteQty,
      'manual_unit_price': manualUnitPrice,
    };
  }
}

class ReconciliationSubmitRequest {
  ReconciliationSubmitRequest({
    required this.staffName,
    required this.lines,
    this.paymentMethod,
    this.wasteReason,
  });

  final String staffName;
  final String? paymentMethod;
  final String? wasteReason;
  final List<ReconciliationSubmitLine> lines;

  Map<String, dynamic> toJson() {
    return {
      'staff_name': staffName,
      'payment_method': paymentMethod,
      'waste_reason': wasteReason,
      'lines': lines.map((line) => line.toJson()).toList(),
    };
  }
}

class ReconciliationSubmitResult {
  ReconciliationSubmitResult({
    required this.id,
    required this.date,
    required this.message,
  });

  final int id;
  final String date;
  final String message;

  factory ReconciliationSubmitResult.fromJson(Map<String, dynamic> json) {
    return ReconciliationSubmitResult(
      id: json['id'] as int,
      date: json['date'] as String,
      message: json['message'] as String,
    );
  }
}

class ReconciliationService {
  ReconciliationService(this._dio);

  final Dio _dio;

  Future<ReconciliationDraft> getDraft() async {
    final response = await _dio.get('/api/reconciliations/draft');
    return ReconciliationDraft.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ReconciliationSubmitResult> submit(
    ReconciliationSubmitRequest request,
  ) async {
    final response = await _dio.post(
      '/api/reconciliations/submit',
      data: request.toJson(),
    );
    return ReconciliationSubmitResult.fromJson(
      response.data as Map<String, dynamic>,
    );
  }
}

final reconciliationServiceProvider = Provider<ReconciliationService>((ref) {
  final dio = ref.watch(dioProvider);
  return ReconciliationService(dio);
});
