/// Auth-domain Vietnamese labels for the bakery app (DG-029 Phase 6).
///
/// Per the VN Label Policy in CLAUDE.md and §5 of docs/flutter-coding-standards.md,
/// new user-facing copy for the auth feature lives in its own domain file rather
/// than being appended to the monolithic `VN` class.
class AuthLabels {
  AuthLabels._();

  static const loginTitle = 'Đăng nhập';
  static const usernameLabel = 'Tên đăng nhập';
  static const usernameHint = 'Nhập tên đăng nhập';
  static const passwordLabel = 'Mật khẩu';
  static const passwordHint = 'Nhập mật khẩu';
  static const loginButton = 'ĐĂNG NHẬP';
  static const loggingIn = 'Đang đăng nhập...';
  static const loginFailed = 'Đăng nhập thất bại';
  static const invalidCredentials = 'Tên đăng nhập hoặc mật khẩu không đúng';
  static const accountLocked = 'Tài khoản đã bị khóa. Vui lòng thử lại sau.';
  static const tooManyAttempts =
      'Quá nhiều lần thử. Vui lòng thử lại sau vài phút.';
  static const loginErrorGeneric = 'Không thể đăng nhập. Vui lòng thử lại.';
  static const logout = 'Đăng xuất';
  static const welcome = 'Xin chào';
}