import 'package:dio/dio.dart';

import 'package:bakery_app/shared/labels/shared.dart';

// Keep one-line SnackBar messages readable before forcing wrapped formatting.
const _orderStatusFailureInlineThreshold = 280;

enum ApiErrorKind { network, timeout, validation, server, unknown }

class ApiError {
  const ApiError({
    required this.kind,
    required this.message,
    this.statusCode,
  });

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
}

String? extractBackendDetail(Object? data) {
  if (data is Map<String, dynamic>) {
    final detail = data['detail'];
    if (detail is String && detail.trim().isNotEmpty) {
      return detail.trim();
    }
  }
  return null;
}

String orderStatusRecoveryActionFromDetail(String detail) {
  final normalized = detail.toLowerCase();
  if (normalized.contains('ton kho') ||
      normalized.contains('tồn kho') ||
      normalized.contains('insufficient stock')) {
    return VN.orderStatusActionCheckStock;
  }
  if (normalized.contains('price bucket') ||
      normalized.contains('muc gia') ||
      normalized.contains('mức giá')) {
    return VN.orderStatusActionCheckPriceBucket;
  }
  if ((normalized.contains('ly do') || normalized.contains('lý do')) &&
      (normalized.contains('quay lai') ||
          normalized.contains('quaylui') ||
          normalized.contains('trang thai truoc') ||
          normalized.contains('trạng thái trước') ||
          normalized.contains('backward') ||
          normalized.contains('lùi'))) {
    return VN.orderStatusActionAddBackwardReason;
  }
  if (normalized.contains('thanh toan') ||
      normalized.contains('thanh toán') ||
      normalized.contains('incomplete payment')) {
    return VN.orderStatusActionCompletePayment;
  }
  return VN.orderStatusActionContactAdmin;
}

String buildOrderStatusFailureMessage({
  required String reason,
  required String action,
  required String orderRef,
  required int statusCode,
}) {
  final singleLine =
      '${VN.orderStatusChangeFailedPrefix}: $reason. ${VN.orderStatusRecoveryLabel}: $action. ${VN.orderStatusDebugCodeLabel}: $orderRef · $statusCode';
  if (singleLine.length <= _orderStatusFailureInlineThreshold) {
    return singleLine;
  }
  return '${VN.orderStatusChangeFailedPrefix}: $reason.\n${VN.orderStatusRecoveryLabel}: $action.\n${VN.orderStatusDebugCodeLabel}: $orderRef · $statusCode';
}

ApiError normalizeApiError(Object error) {
  if (error is DioException) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return const ApiError(
        kind: ApiErrorKind.timeout,
        message: VN.apiTimeout,
      );
    }

    if (error.type == DioExceptionType.connectionError ||
        error.response == null) {
      return const ApiError(kind: ApiErrorKind.network, message: VN.apiError);
    }

    final statusCode = error.response?.statusCode;
    final detail = extractBackendDetail(error.response?.data);
    if (statusCode == 422) {
      return ApiError(
        kind: ApiErrorKind.validation,
        message: detail ?? VN.loiKhongXacDinhTuMayChu,
        statusCode: statusCode,
      );
    }

    if (statusCode != null && statusCode >= 500) {
      return ApiError(
        kind: ApiErrorKind.server,
        message: VN.loiMayChu,
        statusCode: statusCode,
      );
    }

    return ApiError(
      kind: ApiErrorKind.unknown,
      message: detail ?? VN.loiHeThong,
      statusCode: statusCode,
    );
  }

  return const ApiError(kind: ApiErrorKind.unknown, message: VN.loiHeThong);
}
