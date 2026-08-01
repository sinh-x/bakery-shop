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

  // Password change (DG-319 Phase 4 / FR5 / NFR3).
  static const changePasswordTitle = 'Đổi mật khẩu';
  static const changePasswordButton = 'ĐỔI MẬT KHẨU';
  static const oldPasswordLabel = 'Mật khẩu hiện tại';
  static const oldPasswordHint = 'Nhập mật khẩu hiện tại';
  static const newPasswordLabel = 'Mật khẩu mới';
  static const newPasswordHint = 'Nhập mật khẩu mới';
  static const confirmPasswordLabel = 'Xác nhận mật khẩu mới';
  static const confirmPasswordHint = 'Nhập lại mật khẩu mới';
  static const changingPassword = 'Đang đổi mật khẩu...';
  static const changePasswordSuccess = 'Đổi mật khẩu thành công';
  static const changePasswordFailed = 'Đổi mật khẩu thất bại';
  static const oldPasswordIncorrect = 'Mật khẩu hiện tại không đúng';
  static const passwordsDoNotMatch = 'Mật khẩu mới và xác nhận không khớp';
  static const passwordRequired = 'Vui lòng nhập mật khẩu';
  static const forcePasswordChangeTitle = 'Đổi mật khẩu bắt buộc';
  static const forcePasswordChangeMessage =
      'Tài khoản của bạn yêu cầu đổi mật khẩu trước khi tiếp tục.';
}
