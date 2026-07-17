export 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Customer-domain labels (DG-206 Phase 2).
///
/// New customer-facing copy lives here, not in the monolithic `VN` class
/// (per §5 Label Organization). Consumers import this file and use
/// `CustomersLabels.*` for new labels or `VN.*` for legacy labels re-exported
/// above.
class CustomersLabels {
  /// Suffix label for the per-year order count shown on customer cards.
  /// Displayed as "$count $label" e.g. "12 đơn/năm".
  static const orderCountThisYearSuffix = 'đơn/năm';

  /// Tooltip for the phone count badge on customer list avatars.
  static const phoneCountBadgeTooltip = 'Số điện thoại';

  /// Fallback name when a customer has no name set.
  static const customerNoName = 'Không tên';

  /// Non-blocking notice shown when auto-create-customer fails during save
  /// (the order still saves with free-text name/phone, but no link is made).
  static const autoCreateFailedNotice =
      'Không tạo được khách hàng — đơn đã lưu nhưng chưa liên kết khách';

  // Inline order-form customer suggestions (DG-252 Phase 5 — FR4/NFR4/AC2).
  // Surfaced below the name/phone fields in OrderCustomerSection; debounced
  // 350 ms, capped at 10 rows, diacritic-insensitive via the backend search
  // endpoint (`GET /api/customers?search=`).
  static const orderSuggestionsHint = 'Gợi ý khách hàng';
  static const orderSuggestionsNoMatch = 'Không tìm thấy khách';
  static const orderSuggestionsRefineHint = 'Nhập thêm để thu hẹp kết quả';
  static const orderSuggestionsLoading = 'Đang tìm...';
  static const orderSuggestionsError = 'Lỗi tìm kiếm khách hàng';
  static const orderSuggestionsRetry = 'Thử lại';
  static const int orderSuggestionsCap = 10;
}