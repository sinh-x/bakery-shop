import 'dart:convert';

/// Decoded JWT payload (only the fields this app cares about).
class JwtClaims {
  JwtClaims({
    required this.subject,
    required this.role,
    required this.expiresAt,
    required this.tokenId,
  });

  /// `sub` claim — the authenticated username.
  final String subject;

  /// `role` claim — `admin` or `staff`.
  final String role;

  /// `exp` claim — expiry as a Unix epoch second.
  final int expiresAt;

  /// `jti` claim — unique token id (used for session revoke).
  final String tokenId;

  /// Whether the token has passed its `exp` time.
  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expiresAt;
}

/// Lightweight JWT payload decoder.
///
/// Decodes only the payload segment (no signature verification — the server
/// validates the signature via `AuthMiddleware`). The client decodes the
/// payload solely to read the `exp` claim for client-side expiry detection
/// (NFR2 — 7-day expiry, no refresh) and the `sub`/`role` claims so the UI
/// can display the authenticated identity without a round-trip.
JwtClaims? decodeJwt(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final normalized = base64Url.normalize(parts[1]);
    final decoded = utf8.decode(base64Url.decode(normalized));
    final payload = jsonDecode(decoded) as Map<String, dynamic>;
    final sub = payload['sub'];
    final role = payload['role'];
    final exp = payload['exp'];
    final jti = payload['jti'];
    if (sub is! String || role is! String || exp is! int) return null;
    return JwtClaims(
      subject: sub,
      role: role,
      expiresAt: exp,
      tokenId: (jti is String) ? jti : '',
    );
  } catch (_) {
    return null;
  }
}