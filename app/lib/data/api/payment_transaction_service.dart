import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../../shared/utils/date_formatting.dart';
import '../models/payment_transaction.dart';
import '../models/payment_transaction_photo.dart';
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
    String? paymentSource,
    DateTime? createdAt,
  }) async {
    final data = <String, dynamic>{
      'amount': amount,
      'type': type,
      'method': method,
      'note': notes,
    };
    if (paymentSource != null && paymentSource.isNotEmpty) {
      data['payment_source'] = paymentSource;
    }
    if (createdAt != null) {
      data['createdAt'] = timestampToJson(createdAt);
    }
    final response = await _dio.post(
      '/api/orders/$orderRef/transactions',
      data: data,
    );
    return PaymentTransaction.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PaymentTransaction> updateTransaction(
    String orderRef,
    String txnId, {
    double? amount,
    String? type,
    String? method,
    String? notes,
    String? paymentSource,
    DateTime? createdAt,
  }) async {
    final data = <String, dynamic>{};
    if (amount != null) data['amount'] = amount;
    if (type != null) data['type'] = type;
    if (method != null) data['method'] = method;
    if (notes != null) data['note'] = notes;
    data['payment_source'] = paymentSource ?? '';
    if (createdAt != null) {
      data['createdAt'] = timestampToJson(createdAt);
    }
    final response = await _dio.patch(
      '/api/orders/$orderRef/transactions/$txnId',
      data: data,
    );
    return PaymentTransaction.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteTransaction(String orderRef, String txnId) async {
    await _dio.delete('/api/orders/$orderRef/transactions/$txnId');
  }

  Future<PaymentTransaction> invalidateTransaction(
    String orderRef,
    String txnId, {
    String invalidatedBy = '',
    String reason = '',
  }) async {
    final response = await _dio.post(
      '/api/orders/$orderRef/transactions/$txnId/invalidate',
      data: {'invalidatedBy': invalidatedBy, 'reason': reason},
    );
    return PaymentTransaction.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PaymentTransaction> restoreTransaction(
    String orderRef,
    String txnId,
  ) async {
    final response = await _dio.post(
      '/api/orders/$orderRef/transactions/$txnId/restore',
    );
    return PaymentTransaction.fromJson(response.data as Map<String, dynamic>);
  }

  // ── Transaction photo (DG-410 Phase 3) ─────────────────────────────────────
  //
  // Wraps the per-transaction photo join-table routes from Phase 2:
  //   GET    /{ref}/transactions/{txn_id}/photo        — fetch the link (404 if none)
  //   POST   /{ref}/transactions/{txn_id}/photo        — upload + attach (multipart)
  //   POST   /{ref}/transactions/{txn_id}/photo/link   — link an already-saved photo by hash
  //   DELETE /{ref}/transactions/{txn_id}/photo        — detach (FR3 remove)
  //
  // The record-payment flow uses [linkTransactionPhoto] against a photo already
  // uploaded to the order-level `chuyen-khoan` strip (FR2). The edit / detail
  // sheets use [attachTransactionPhoto] / [detachTransactionPhoto] for add /
  // replace (upsert) / remove (FR3). [getTransactionPhoto] is the lazy fetch
  // used by the detail sheet (NFR3 — no extra fetch on tab switch).

  Future<PaymentTransactionPhoto?> getTransactionPhoto(
    String orderRef,
    String txnId,
  ) async {
    final response = await _dio.get(
      '/api/orders/$orderRef/transactions/$txnId/photo',
    );
    return PaymentTransactionPhoto.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<PaymentTransactionPhoto> attachTransactionPhoto(
    String orderRef,
    String txnId,
    XFile file,
  ) async {
    final bytes = await file.readAsBytes();
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: file.name),
    });
    final response = await _dio.post(
      '/api/orders/$orderRef/transactions/$txnId/photo',
      data: formData,
    );
    return PaymentTransactionPhoto.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<PaymentTransactionPhoto> linkTransactionPhoto(
    String orderRef,
    String txnId,
    String photoHash,
  ) async {
    final response = await _dio.post(
      '/api/orders/$orderRef/transactions/$txnId/photo/link',
      data: {'photoHash': photoHash},
    );
    return PaymentTransactionPhoto.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<void> detachTransactionPhoto(String orderRef, String txnId) async {
    await _dio.delete('/api/orders/$orderRef/transactions/$txnId/photo');
  }
}

final paymentTransactionServiceProvider =
    Provider<PaymentTransactionService>((ref) {
  final dio = ref.watch(dioProvider);
  return PaymentTransactionService(dio);
});
