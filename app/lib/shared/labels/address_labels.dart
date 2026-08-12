export 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Address-library domain labels (DG-385 Phase 4 / NFR3).
///
/// All user-facing copy for the address autocomplete widget, the auto-bind
/// hint, and the customer-prioritized badge lives here per the VN Label
/// Policy in CLAUDE.md and §5 of docs/flutter-coding-standards.md.
/// Consumers import this file and use `AddressLabels.*` for address-domain
/// strings, or `VN.*` for legacy labels re-exported above.
class AddressLabels {
  AddressLabels._();

  // Autocomplete field (FR1/AC1).
  static const autocompleteHint = 'Nhập địa chỉ để tìm trong thư viện';
  static const autocompleteMinHint = 'Nhập từ 2 ký tự để xem gợi ý';
  static const autocompleteLoading = 'Đang tìm địa chỉ...';
  static const autocompleteError = 'Không tải được gợi ý địa chỉ';
  static const autocompleteNoResults = 'Không tìm thấy địa chỉ phù hợp';

  // Suggestion badges (FR5/AC5).
  static const customerAddressBadge = 'Khách';

  // Auto-bind map link (FR2/AC2).
  static const mapsLinkBoundSnack = 'Đã gắn link Google Maps cho đơn';
  static const mapsLinkNoLinkSnack = 'Địa chỉ chưa có link Google Maps';

  // ── Phase 5 — Address library management screen (FR6/FR8/AC6) ─────────
  /// Screen title shown in the AppBar of [AddressLibraryScreen].
  static const libraryTitle = 'Thư viện địa chỉ';

  /// Settings → Address Library navigation entry label.
  static const libraryNavEntry = 'Thư viện địa chỉ';

  /// Search bar hint inside the library management screen.
  static const librarySearchHint = 'Tìm địa chỉ...';

  /// Empty state body when the library has no entries (or no matches).
  static const libraryEmpty = 'Chưa có địa chỉ nào.';

  /// Empty state body when the active search returns nothing.
  static const libraryNoMatches = 'Không tìm thấy địa chỉ phù hợp.';

  /// Add button tooltip + FAB semantic label.
  static const libraryAddTooltip = 'Thêm địa chỉ';

  /// Edit action tooltip shown on each library row.
  static const libraryEditTooltip = 'Sửa địa chỉ';

  /// Delete action tooltip shown on each library row.
  static const libraryDeleteTooltip = 'Xoá địa chỉ';

  /// Delete confirmation dialog title.
  static const libraryDeleteConfirmTitle = 'Xoá địa chỉ';

  /// Delete confirmation dialog body. `{address}` is replaced with the
  /// entry's `displayAddress`.
  static const libraryDeleteConfirmBody =
      'Bạn có chắc muốn xoá địa chỉ "{address}" khỏi thư viện?';

  /// Delete confirmation dialog confirm action.
  static const libraryDeleteConfirmAction = 'Xoá';

  /// Snackbar shown after a successful delete. `{address}` is replaced.
  static const libraryDeletedSnack = 'Đã xoá "{address}" khỏi thư viện.';

  /// Snackbar shown after a successful create.
  static const libraryCreatedSnack = 'Đã thêm địa chỉ vào thư viện.';

  /// Snackbar shown after a successful update.
  static const libraryUpdatedSnack = 'Đã cập nhật địa chỉ.';

  /// Generic error snackbar when a CRUD call fails (e.g. 409 collision).
  static const libraryErrorSnack = 'Không lưu được địa chỉ. Thử lại sau.';

  // ── Address library editor dialog (FR8/AC6) ───────────────────────────
  /// Editor dialog title for create mode.
  static const editorCreateTitle = 'Thêm địa chỉ';

  /// Editor dialog title for edit mode.
  static const editorEditTitle = 'Sửa địa chỉ';

  /// Text-field label for the address text in the editor dialog.
  static const editorAddressLabel = 'Địa chỉ';

  /// Text-field hint for the address text in the editor dialog.
  static const editorAddressHint = 'VD: 123 Nguyễn Huệ, Q1';

  /// Validator message shown when the address field is empty.
  static const editorAddressRequired = 'Vui lòng nhập địa chỉ';

  /// Text-field label for the optional Google Maps link in the editor.
  static const editorMapsLinkLabel = 'Link Google Maps';

  /// Text-field hint for the optional Google Maps link.
  static const editorMapsLinkHint = 'https://maps.app.goo.gl/...';

  /// Validator message shown when the maps link is not a URL.
  static const editorMapsLinkInvalid = 'Link Google Maps không hợp lệ';
}