import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

enum ReceiptType {
  workTicket('work_ticket', 'Phiếu sản xuất'),
  customer('customer', 'Hóa đơn khách hàng'),
  busLabel('bus_label', 'Phiếu xe khách'),
  shop('shop', 'Phiếu giao hàng'),
  delivery('delivery', 'Phiếu giao tận nơi');

  const ReceiptType(this.value, this.label);
  final String value;
  final String label;
}

class ReceiptService {
  final Dio _dio;

  ReceiptService(this._dio);

  /// Fetches receipt image bytes from the backend API.
  ///
  /// [orderRef] - The order reference (e.g., "ORD-260324-003")
  /// [type] - The type of receipt: order summary, work ticket, or customer receipt
  /// [itemId] - Optional work item ID for work ticket receipts (single item)
  Future<Uint8List> fetchReceipt({
    required String orderRef,
    required ReceiptType type,
    int? itemId,
    bool photos = true,
  }) async {
    final params = <String, dynamic>{'type': type.value};
    if (itemId != null) {
      params['item_id'] = itemId.toString();
    }
    if (!photos) {
      params['photos'] = 'false';
    }

    final response = await _dio.get(
      '/api/orders/$orderRef/receipt',
      queryParameters: params,
      options: Options(responseType: ResponseType.bytes),
    );

    return Uint8List.fromList(response.data as List<int>);
  }

  /// Triggers server-side thermal printing via the backend API.
  ///
  /// [orderRef] - The order reference (e.g., "ORD-260324-003")
  /// [type] - The type of receipt: work ticket or customer receipt
  /// [itemId] - Optional work item ID for work ticket receipts
  ///
  /// Returns true on success, throws on failure.
  Future<void> printReceipt({
    required String orderRef,
    required ReceiptType type,
    int? itemId,
  }) async {
    final params = <String, dynamic>{'type': type.value};
    if (itemId != null) {
      params['item_id'] = itemId.toString();
    }

    await _dio.post(
      '/api/orders/$orderRef/print',
      queryParameters: params,
    );
  }
}

final receiptServiceProvider = Provider<ReceiptService>((ref) {
  final dio = ref.watch(dioProvider);
  return ReceiptService(dio);
});
