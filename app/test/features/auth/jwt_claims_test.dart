import 'dart:convert';

import 'package:bakery_app/features/auth/jwt_claims.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a minimal JWT (header.payload.sig) with the given payload. The
/// signature segment is a dummy placeholder — the client decoder only reads
/// the payload.
String _jwt(Map<String, dynamic> payload) {
  final header = {'alg': 'HS256', 'typ': 'JWT'};
  String b64(Map<String, dynamic> m) {
    final json = jsonEncode(m);
    var s = base64Url.encode(utf8.encode(json));
    while (s.endsWith('=')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }
  return '${b64(header)}.${b64(payload)}.sig';
}

void main() {
  group('decodeJwt', () {
    test('decodes sub, role, exp, jti claims from a valid JWT', () {
      final token = _jwt({
        'sub': 'Sinh',
        'role': 'admin',
        'exp': 9999999999,
        'jti': 'abc-123',
      });
      final claims = decodeJwt(token);
      expect(claims, isNotNull);
      expect(claims!.subject, 'Sinh');
      expect(claims.role, 'admin');
      expect(claims.expiresAt, 9999999999);
      expect(claims.tokenId, 'abc-123');
      expect(claims.isExpired, isFalse);
    });

    test('marks expired tokens as expired', () {
      final token = _jwt({
        'sub': 'Tan',
        'role': 'staff',
        'exp': 1,
        'jti': 'old',
      });
      final claims = decodeJwt(token);
      expect(claims, isNotNull);
      expect(claims!.isExpired, isTrue);
    });

    test('returns null for malformed token (wrong segment count)', () {
      expect(decodeJwt('not-a-jwt'), isNull);
      expect(decodeJwt('a.b'), isNull);
      expect(decodeJwt('a.b.c.d'), isNull);
    });

    test('returns null when required claims are missing', () {
      final token = _jwt({'sub': 'Sinh'});
      expect(decodeJwt(token), isNull);
    });
  });
}