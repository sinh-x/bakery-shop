/// Technical settings-domain Vietnamese labels for the pre-login settings
/// screen (DG-367 Phase 2).
///
/// Per the VN Label Policy in CLAUDE.md and §5 of docs/flutter-coding-standards.md,
/// all user-facing copy for the pre-login technical settings screen lives in
/// this domain file rather than as inline Vietnamese strings or appended to
/// the monolithic `VN` class. Wording mirrors the existing settings labels
/// (`VN.apiUrlLabel`, `VN.testConnection`, etc.) so the pre-login screen stays
/// consistent with the post-login Settings > Technical tab.
class TechnicalSettingsLabels {
  TechnicalSettingsLabels._();

  static const screenTitle = 'Cài đặt kết nối';
  static const serverUrlLabel = 'Địa chỉ máy chủ';
  static const serverUrlHint = 'http://hostname:8000';
  static const serverUrlHelp = 'Nhập địa chỉ Tailscale của máy chủ';
  static const testConnection = 'Kiểm tra kết nối';
  static const testing = 'Đang kiểm tra...';
  static const save = 'Lưu';
  static const connectionSuccess = 'Kết nối thành công';
  static const connectionFailed = 'Không thể kết nối';
  static const urlSaved = 'Đã lưu địa chỉ máy chủ';
  static const urlEmpty = 'Vui lòng nhập địa chỉ';
  static const back = 'Quay lại';
}