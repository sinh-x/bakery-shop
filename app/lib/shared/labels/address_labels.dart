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
}