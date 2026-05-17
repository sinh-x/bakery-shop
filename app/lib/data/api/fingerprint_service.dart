import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

class ServerFingerprintResult {
  const ServerFingerprintResult({
    required this.healthReachable,
    required this.fingerprint,
  });

  final bool healthReachable;
  final String? fingerprint;
}

class FingerprintService {
  FingerprintService(this._dio);

  final Dio _dio;

  Future<ServerFingerprintResult> fetchServerFingerprint() async {
    try {
      final response = await _dio.get('/api/health');
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return const ServerFingerprintResult(
          healthReachable: true,
          fingerprint: null,
        );
      }
      final fingerprint = data['fingerprint'];
      if (fingerprint is! String) {
        return const ServerFingerprintResult(
          healthReachable: true,
          fingerprint: null,
        );
      }
      return ServerFingerprintResult(
        healthReachable: true,
        fingerprint: fingerprint,
      );
    } on DioException catch (error) {
      debugPrint(
        'FingerprintService.fetchServerFingerprint DioException: '
        '${error.message ?? error.type.name}',
      );
      return const ServerFingerprintResult(
        healthReachable: false,
        fingerprint: null,
      );
    }
  }
}

final fingerprintServiceProvider = Provider<FingerprintService>((ref) {
  final dio = ref.watch(dioProvider);
  return FingerprintService(dio);
});
