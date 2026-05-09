import 'package:dio/dio.dart';

import '../widgets/vietnamese_labels.dart';

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
