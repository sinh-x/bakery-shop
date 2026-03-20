import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/payment_transaction.dart';
import 'api_client.dart';

class PaymentTransactionService {
  final Dio _dio;

  PaymentTransactionService(this._dio);

  Future<List<PaymentTransaction>> listTransactions(String orderRef) async {
    final response = await _dio.get('/api/orders/$orderRef/transactions');
    final list = response.data as List;
    return list
        .map(
          (json) =>
              PaymentTransaction.fromJson(json as Map<String, dynamic>),
        )
        .toList();
  }

  Future<PaymentTransaction> createTransaction(
    String orderRef, {
    required double amount,
    String type = 'deposit',
    String method = 'cash',
    String notes = '',
  }) async {
    final response = await _dio.post(
      '/api/orders/$orderRef/transactions',
      data: {
        'amount': amount,
        'type': type,
        'method': method,
        'note': notes,
      },
    );
    return PaymentTransaction.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteTransaction(String orderRef, String txnId) async {
    await _dio.delete('/api/orders/$orderRef/transactions/$txnId');
  }
}

final paymentTransactionServiceProvider =
    Provider<PaymentTransactionService>((ref) {
  final dio = ref.watch(dioProvider);
  return PaymentTransactionService(dio);
});
