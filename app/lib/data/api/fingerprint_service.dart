import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

class FingerprintService {
  FingerprintService(this._dio);

  final Dio _dio;

  Future<String?> fetchServerFingerprint() async {
    try {
      final response = await _dio.get('/api/health');
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return null;
      }
      final fingerprint = data['fingerprint'];
      if (fingerprint is! String) {
        return null;
      }
      return fingerprint;
    } on DioException {
      return null;
    }
  }
}

final fingerprintServiceProvider = Provider<FingerprintService>((ref) {
  final dio = ref.watch(dioProvider);
  return FingerprintService(dio);
});
