import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/payment_transaction.dart';
import 'api_client.dart';

class UnresolvedReceipt {
  const UnresolvedReceipt(this.transaction, this.orderRef, this.customerName);

  final PaymentTransaction transaction;
  final String orderRef;
  final String customerName;
}

class UnresolvedReceiptPage {
  const UnresolvedReceiptPage({
    required this.items,
    required this.total,
    required this.amount,
    required this.hasMore,
  });

  final List<UnresolvedReceipt> items;
  final int total;
  final double amount;
  final bool hasMore;
}

class PaymentDestinationService {
  PaymentDestinationService(this._dio);
  final Dio _dio;

  Future<UnresolvedReceiptPage> list({
    String search = '',
    int offset = 0,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/payment-destinations',
      queryParameters: {'search': search, 'offset': offset, 'limit': 50},
    );
    final data = response.data!;
    return UnresolvedReceiptPage(
      items: (data['items'] as List).map((item) {
        final json = item as Map<String, dynamic>;
        return UnresolvedReceipt(
          PaymentTransaction.fromJson(json),
          json['orderRef'] as String,
          json['customerName'] as String,
        );
      }).toList(),
      total: data['total'] as int,
      amount: (data['unresolvedAmount'] as num).toDouble(),
      hasMore: data['has_more'] as bool,
    );
  }

  Future<PaymentTransaction> assign(
    String orderRef,
    String transactionId, {
    required String method,
    String paymentSource = '',
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/orders/$orderRef/transactions/$transactionId/destination',
      data: {'method': method, 'payment_source': paymentSource},
    );
    return PaymentTransaction.fromJson(response.data!);
  }
}

final paymentDestinationServiceProvider = Provider<PaymentDestinationService>(
  (ref) => PaymentDestinationService(ref.watch(dioProvider)),
);
