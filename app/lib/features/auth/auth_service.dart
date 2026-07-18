import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';

/// Response body from `POST /api/auth/login` (FR1).
class LoginResult {
  LoginResult({required this.token, required this.username, required this.role});

  final String token;
  final String username;
  final String role;
}

/// Calls the backend auth endpoints.
///
/// Uses a plain [Dio] instance (without the auth interceptor) for the login
/// call itself, since `/api/auth/login` is a public endpoint that must not
/// require a token.
class AuthService {
  AuthService(this._dio);

  final Dio _dio;

  /// `POST /api/auth/login` with `{username, password}`.
  ///
  /// Returns the JWT token + identity claims on success. Throws
  /// [DioException] on network/HTTP failure; callers map the status code to
  /// a user-facing message.
  Future<LoginResult> login({required String username, required String password}) async {
    final response = await _dio.post<dynamic>(
      '/api/auth/login',
      data: <String, dynamic>{
        'username': username,
        'password': password,
      },
    );
    final data = response.data;
    if (data is Map<String, dynamic>) {
      final token = data['token'];
      final user = data['username'];
      final role = data['role'];
      if (token is String && user is String && role is String) {
        return LoginResult(token: token, username: user, role: role);
      }
    }
    debugPrint('auth_service: malformed login response: $data');
    throw DioException(
      requestOptions: response.requestOptions,
      type: DioExceptionType.unknown,
      message: 'Malformed login response',
    );
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  final dio = ref.watch(dioProvider);
  return AuthService(dio);
});