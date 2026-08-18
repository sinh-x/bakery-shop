/// Customer-domain labels (DG-206 Phase 2).
///
/// New customer-facing copy lives here, not in the monolithic `VN` class
/// (per §5 Label Organization). Consumers import this file and use
/// `CustomersLabels.*` for customer-domain strings.
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

  // Duplicate warning at manual customer create (DG-252 Phase 6 — FR8/AC6).
  // Shown as a pre-create dialog when the typed name (diacritic-insensitive)
  // or any typed phone digits match an existing customer. The user can pick
  // an existing customer ("use existing") or proceed with the new create
  // ("create anyway").
  static const duplicateWarningTitle = 'Khách hàng đã tồn tại';
  static const duplicateWarningHint =
      'Có khách hàng trùng tên hoặc số điện thoại. Bạn muốn dùng khách sẵn có hay vẫn tạo mới?';
  static const duplicateWarningUseExisting = 'Dùng khách sẵn có';
  static const duplicateWarningCreateAnyway = 'Vẫn tạo mới';
  static const duplicateWarningCancel = 'Hủy';

  // Customer delete flow (DG-252 review r2 [M2] — FR10/AC7).
  // The DELETE /api/customers/{id} endpoint is admin-only (403 for staff,
  // remediation Mn5) and returns a 409 with a VN guidance message when the
  // customer still has linked orders (phase 2). These labels surface the
  // backend `detail` in the app's delete confirmation flow and gate the
  // delete menu item by role.
  static const customerDeleteFailed = 'Xóa khách hàng thất bại';
  static const customerDeleteAdminOnly = 'Chỉ quản trị viên mới được xóa';

  // Admin duplicate-finder + merge UI (DG-252 Phase 7 — FR7/AC4).
  // Admin-only screen listing duplicate candidate groups (phone-keyed or
  // diacritic-stripped name-keyed) returned by `GET /api/customers/duplicates`.
  // Each group offers a merge action that opens a confirmation dialog showing
  // both records' order counts before calling `POST /api/customers/{id}/merge`.
  static const duplicateFinderTitle = 'Tìm khách trùng lặp';
  static const duplicateFinderRefresh = 'Làm mới';
  static const duplicateFinderEmpty = 'Không có khách trùng lặp';
  static const duplicateFinderGroupPhoneLabel = 'Số điện thoại trùng';
  static const duplicateFinderGroupNameLabel = 'Tên trùng';
  static const duplicateFinderOrderCountSuffix = 'đơn';
  static const duplicateFinderMergeButton = 'Gộp';
  static const duplicateFinderMergeIntoLabel = 'Giữ';
  static const duplicateFinderMergeFromLabel = 'Gộp vào';
  static const duplicateFinderMergeDialogTitle = 'Xác nhận gộp khách';
  static const duplicateFinderMergeDialogBody =
      'Tất cả đơn hàng và số điện thoại của khách "gộp vào" sẽ được chuyển sang khách "giữ". Khách "gộp vào" sẽ bị xóa. Hành động này không thể hoàn tác.';
  static const duplicateFinderMergeConfirm = 'Xác nhận gộp';
  static const duplicateFinderMergeCancel = 'Hủy';
  static const duplicateFinderMergeSuccess = 'Đã gộp khách hàng';
  static const duplicateFinderMergeFailed = 'Gộp khách thất bại';
  static const duplicateFinderLoadingGroups = 'Đang tải...';
  static const duplicateFinderRetry = 'Thử lại';
  static const duplicateFinderSwapDirection = 'Đảo chiều gộp (giữ ↔ gộp vào)';

  /// Hint shown beneath a duplicate group when the admin has not yet selected
  /// two members to merge (DG-252 review M3 + Mn9 — replaces the previous
  /// inline `'${n} khách — chọn 2 để gộp'` string). The hint adapts to the
  /// number of members already selected so the admin knows the two-tap
  /// selection model.
  static String duplicateFinderPickTwoHint(int memberCount, int selectedCount) {
    if (selectedCount == 0) {
      return '$memberCount khách — chạm để chọn khách giữ, rồi chọn khách gộp';
    }
    if (selectedCount == 1) {
      return 'Đã chọn 1 — chạm tiếp để chọn khách gộp';
    }
    return '$memberCount khách — chạm để chọn khách giữ, rồi chọn khách gộp';
  }

  // Batch merge UI (DG-369 Phase 3 — FR5/FR6/AC3/AC4/AC6).
  // Extends the two-tap selection model to multi-select: first tap = primary
  // (keep), subsequent taps = sources (merge-from). Tapping a selected member
  // deselects it. When 2+ members are selected (1 primary + ≥1 source) the
  // merge button appears. For 3+ selections the batch confirmation dialog is
  // shown; for exactly 2 the existing single-pair dialog (with swap) is used
  // so the two-tap flow keeps working for 2-member groups.
  static const duplicateFinderBatchMergeDialogTitle =
      'Xác nhận gộp hàng loạt';
  static const duplicateFinderBatchMergeDialogBody =
      'Tất cả đơn hàng và số điện thoại của các khách "gộp vào" sẽ được chuyển sang khách "giữ". Các khách "gộp vào" sẽ bị xóa. Hành động này không thể hoàn tác.';
  static const duplicateFinderBatchMergeConfirm = 'Xác nhận gộp';
  static const duplicateFinderBatchMergeCancel = 'Hủy';
  static const duplicateFinderBatchMergeSourcesLabel = 'Các khách gộp vào';
  static const duplicateFinderBatchMergePrimaryLabel =
      duplicateFinderMergeIntoLabel;
  static const duplicateFinderBatchMergeSuccess =
      'Đã gộp hàng loạt khách hàng';
  static const duplicateFinderBatchMergeFailed = 'Gộp hàng loạt thất bại';

  // Duplicate-finder search/filter (DG-372 Phase 4.1 — FR3/NFR2).
  // Client-side filter on the duplicate finder screen lets the admin search
  // duplicate groups by customer name or phone. Diacritic-insensitive
  // matching reuses `stripDiacritics` from `shared/utils/diacritics.dart`.
  // `duplicateFinderSearchHint` is shown as the TextField hint text;
  // `duplicateFinderSearchNoResults` is the empty state shown only when the
  // filter query matches no groups (distinct from `duplicateFinderEmpty`,
  // which is the "no duplicates exist" state).
  static const duplicateFinderSearchHint =
      'Tìm theo tên hoặc số điện thoại';
  static const duplicateFinderSearchNoResults =
      'Không tìm thấy nhóm trùng lặp nào';

  // ── Phase 4.2 migration: relocated from VN ──

  // Customer management (DG-182 Phase 3)
  static const manageCustomers = 'Quản lý khách hàng';
  static const addCustomer = 'Thêm khách hàng';
  static const editCustomer = 'Sửa khách hàng';
  static const customerListTitle = 'Khách hàng';
  static const searchCustomers = 'Tìm theo tên hoặc số điện thoại...';
  static const noCustomers = 'Chưa có khách hàng';
  static const noCustomersMatch = 'Không tìm thấy khách phù hợp';
  static const customerCreated = 'Đã thêm khách hàng';
  static const customerUpdated = 'Đã cập nhật khách hàng';
  static const customerDeleted = 'Đã xóa khách hàng';
  static const deleteCustomer = 'Xóa khách hàng';
  static const deleteCustomerConfirm =
      'Xóa khách hàng này? Đơn hàng liên kết sẽ bỏ khách hàng.';
  static const customerOrderHistory = 'Lịch sử đơn hàng';
  static const customerNoOrders = 'Chưa có đơn hàng';
  static const customerOrderCountSuffix = 'đơn';
  static const customerSharedPhoneTitle = 'Cùng số điện thoại';
  static const customerSharedPhoneHint = 'Khách hàng khác dùng chung số này:';
  static const customerPhoneField = 'Số điện thoại (tùy chọn)';
  static const customerNameField = 'Tên khách hàng';
  static const openCustomerManagement = 'Khách hàng';
  static const customerCreatedAt = 'Ngày tạo';

  // Customer search in order flows (DG-182 Phase 4)
  static const customerSearchHint = 'Tìm khách theo tên hoặc SĐT...';
  static const customerSearchLinked = 'Đã chọn: {name}';
  static const customerSearchChange = 'Đổi khách';
  static const customerSearchClear = 'Bỏ chọn khách';
  static const customerSearchNoMatch = 'Không tìm thấy khách';
  static const customerSearchLoading = 'Đang tìm...';
  static const customerSearchError = 'Lỗi tìm kiếm khách hàng';
  static const customerSearchRefineHint = 'Nhập thêm để thu hẹp kết quả';

  // Customer form multi-phone (DG-205 Phase 5)
  static const customerAddPhone = 'Thêm số điện thoại';
  static const customerRemovePhone = 'Xóa số này';
  static const customerPrimaryPhone = 'Số chính';
  static const customerPhoneRequired = 'Cần ít nhất một số điện thoại';
  static const customerPhonePrimaryRequired = 'Chọn một số làm số chính';
  static const customerPhoneDuplicate = 'Số điện thoại bị trùng';

}