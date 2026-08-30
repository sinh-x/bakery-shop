import 'package:dio/dio.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import 'package:bakery_app/shared/labels/stock.dart';

// Keep one-line SnackBar messages readable before forcing wrapped formatting.
const _orderStatusFailureInlineThreshold = 280;

enum ApiErrorKind { network, timeout, validation, server, unknown }

class ApiError {
  const ApiError({required this.kind, required this.message, this.statusCode});

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

String? _safeBackendDetail(Object? data) {
  final detail = extractBackendDetail(data);
  if (detail == null || detail.length > 240) return null;
  final normalized = detail.toLowerCase();
  const diagnosticMarkers = <String>[
    'dioexception',
    'exception:',
    'traceback',
    'stack trace',
    'package:',
    'sqlite',
    'sqlstate',
    'syntax error',
    'python',
  ];
  if (detail.contains('\n') || diagnosticMarkers.any(normalized.contains)) {
    return null;
  }
  return detail;
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

String apiErrorRecoveryAction(ApiErrorKind kind) {
  switch (kind) {
    case ApiErrorKind.network:
      return SharedLabels.checkConnectionAndRetry;
    case ApiErrorKind.timeout:
      return SharedLabels.retryWhenConnectionStable;
    case ApiErrorKind.validation:
      return OrdersLabels.workItemValidationRecovery;
    case ApiErrorKind.server:
    case ApiErrorKind.unknown:
      return SharedLabels.retryOrContactAdmin;
  }
}

String buildApiActionFailureMessage({
  required String action,
  required Object error,
  String? nextStep,
}) {
  final normalized = normalizeApiError(error);
  final recovery = nextStep ?? apiErrorRecoveryAction(normalized.kind);
  return '$action. ${SharedLabels.failureReasonLabel}: '
      '${normalized.message}. ${SharedLabels.nextStepLabel}: $recovery';
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
      return const ApiError(
        kind: ApiErrorKind.network,
        message: SharedLabels.apiError,
      );
    }

    final statusCode = error.response?.statusCode;
    final detail = _safeBackendDetail(error.response?.data);
    if (statusCode == 422) {
      return ApiError(
        kind: ApiErrorKind.validation,
        message: detail ?? SharedLabels.apiValidationError,
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

  return const ApiError(
    kind: ApiErrorKind.unknown,
    message: StockLabels.loiHeThong,
  );
}
