import 'package:dio/dio.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:bakery_app/shared/labels/stock.dart';
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
    return OrdersLabels.orderStatusActionCheckStock;
  }
  if (normalized.contains('price bucket') ||
      normalized.contains('muc gia') ||
      normalized.contains('mức giá')) {
    return OrdersLabels.orderStatusActionCheckPriceBucket;
  }
  if ((normalized.contains('ly do') || normalized.contains('lý do')) &&
      (normalized.contains('quay lai') ||
          normalized.contains('quaylui') ||
          normalized.contains('trang thai truoc') ||
          normalized.contains('trạng thái trước') ||
          normalized.contains('backward') ||
          normalized.contains('lùi'))) {
    return OrdersLabels.orderStatusActionAddBackwardReason;
  }
  if (normalized.contains('thanh toan') ||
      normalized.contains('thanh toán') ||
      normalized.contains('incomplete payment')) {
    return OrdersLabels.orderStatusActionCompletePayment;
  }
  return OrdersLabels.orderStatusActionContactAdmin;
}

String buildOrderStatusFailureMessage({
  required String reason,
  required String action,
  required String orderRef,
  required int statusCode,
}) {
  final singleLine =
      '${OrdersLabels.orderStatusChangeFailedPrefix}: $reason. ${OrdersLabels.orderStatusRecoveryLabel}: $action. ${OrdersLabels.orderStatusDebugCodeLabel}: $orderRef · $statusCode';
  if (singleLine.length <= _orderStatusFailureInlineThreshold) {
    return singleLine;
  }
  return '${OrdersLabels.orderStatusChangeFailedPrefix}: $reason.\n${OrdersLabels.orderStatusRecoveryLabel}: $action.\n${OrdersLabels.orderStatusDebugCodeLabel}: $orderRef · $statusCode';
}

ApiError normalizeApiError(Object error) {
  if (error is DioException) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return const ApiError(
        kind: ApiErrorKind.timeout,
        message: SharedLabels.apiTimeout,
      );
    }

    if (error.type == DioExceptionType.connectionError ||
        error.response == null) {
      return const ApiError(kind: ApiErrorKind.network, message: SharedLabels.apiError);
    }

    final statusCode = error.response?.statusCode;
    final detail = extractBackendDetail(error.response?.data);
    if (statusCode == 422) {
      return ApiError(
        kind: ApiErrorKind.validation,
        message: detail ?? OrdersLabels.loiKhongXacDinhTuMayChu,
        statusCode: statusCode,
      );
    }

    if (statusCode != null && statusCode >= 500) {
      return ApiError(
        kind: ApiErrorKind.server,
        message: OrdersLabels.loiMayChu,
        statusCode: statusCode,
      );
    }

    return ApiError(
      kind: ApiErrorKind.unknown,
      message: detail ?? StockLabels.loiHeThong,
      statusCode: statusCode,
    );
  }

  return const ApiError(kind: ApiErrorKind.unknown, message: StockLabels.loiHeThong);
}
