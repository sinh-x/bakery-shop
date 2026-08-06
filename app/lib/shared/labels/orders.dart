export 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

class OrdersLabels {
  static const checkoutReviewTitle = 'Xem lại đơn hàng';
  static const checkoutReviewHint = 'Kiểm tra thông tin trước khi tạo đơn.';
  static const done = 'Xong';

  // Stage indicator
  static const stage1Label = 'Sản phẩm';
  static const stage1Desc = 'Chọn sản phẩm và phụ kiện';
  static const stage2Label = 'Khách hàng';
  static const stage2Desc = 'Thông tin khách hàng';
  static const stage3Label = 'Giao hàng';
  static const stage3Desc = 'Hình thức, thời gian, địa chỉ';
  static const stage4Label = 'Xem lại';
  static const stage4Desc = 'Kiểm tra và tạo đơn';
  static const stage5Label = 'Thanh toán';
  static const stage5Desc = 'Thanh toán hoặc để sau';

  // Navigation
  static const continueLabel = 'Tiếp tục';
  static const backLabel = 'Quay lại';

  // Stage 1
  static const selectedProducts = 'Sản phẩm đã chọn';
  static const noProductsSelected = 'Chưa chọn sản phẩm';
  static const stage1AddProductHint = 'Thêm sản phẩm vào đơn';
  static const stage1EmptyTitle = 'Chưa có sản phẩm nào';
  static const stage1EmptyBody = 'Bấm (+) để chọn sản phẩm cho đơn hàng.';
  static const stage1ExtrasLoading = 'Đang tải phụ kiện...';
  static const stage1ExtrasLoadError = 'Không tải được danh sách phụ kiện';

  // Stage 3
  static const deliveryPhone = 'SĐT nhận hàng';
  static const validationDeliveryAddressRequired =
      'Vui lòng nhập địa chỉ giao hàng';

  // Stage 4
  static const reviewSummary = 'Tóm tắt đơn hàng';
  static const reviewCreateOrder = 'Tạo đơn hàng';

  // Stage summary cards (DG-211 Phase 4)
  static const previousStagesSummary = 'Tóm tắt bước trước';

  // Order source options (DG-211 review cycle 1 — CQ-1)
  static const sourceTaiTiem = 'Tại tiệm';
  static const sourceOnline = 'Online';
  static const sourceDienThoai = 'Điện thoại';
  static const sourceFbDoangia = 'Facebook-DoanGia';
  static const sourceFbPageMoi = 'Facebook-Page-mới';
  static const sourceZalo = 'Zalo';

  // Summary card titles
  static const summaryProducts = 'Tóm tắt sản phẩm';
  static const summaryCustomer = 'Thông tin khách hàng';
  static const summaryDelivery = 'Thông tin giao hàng';

  // Generic placeholder for unselected values (DG-211 review cycle 1 — CQ-3)
  static const notSelected = 'Chưa chọn';

  // Customer search modal trigger (DG-218 Phase 1 — FR-8, moved from VN per
  // flutter-coding-standards.md §5).
  static const customerSearchButton = 'Tìm khách hàng';
  static const customerSearchModalTitle = 'Tìm khách hàng';

  // Validation messages (DG-211 review cycle 1 — CQ-4)
  static const validationSelectAtLeastOneProduct =
      'Vui lòng chọn ít nhất một sản phẩm';
  static const validationCustomerNameRequired =
      'Vui lòng nhập tên khách hàng';

  // Product/extras count strings (DG-211 review cycle 1 — CQ-2)
  static String productCount(int count) => '$count sản phẩm';
  static String extraCount(int count) => '$count phụ kiện';

  // Order submission (DG-216 Phase 6)
  static const walkInCustomerFallback = 'Khách';
  static String photoUploadResult(int success, int total, int failed) =>
      'Tải lên ảnh: $success/$total thành công, $failed lỗi';

  // Urgency tier labels (DG-221 Phase 2)
  static const urgencyCritical = 'Khẩn cấp';
  static const urgencyUrgent = 'Gấp';
  static const urgencyNormal = '';
  static const urgencyCriticalBadge = 'KHẨN CẤP';
  static const urgencyUrgentBadge = 'GẤP';

  // Urgency banner (DG-221 Phase 3 — FR-6)
  static const urgencyBannerTitle = 'Đơn hàng khẩn cấp';
  static const urgencyBannerCritical = 'Khẩn cấp';
  static const urgencyBannerUrgent = 'Gấp';
  static String urgencyBannerText(int critical, int urgent) {
    if (critical > 0 && urgent > 0) {
      return '$critical khẩn cấp, $urgent gấp';
    }
    if (critical > 0) {
      return '$critical khẩn cấp';
    }
    return '$urgent gấp';
  }

  // Urgency badge tooltip (DG-221 Phase 3 — FR-5)
  static String urgencyBadgeTooltip(int count) =>
      '$count đơn hàng khẩn cấp/gấp';

  // In-app alert (DG-221 Phase 4 — FR-7)
  static const criticalAlertTitle = 'Đơn hàng khẩn cấp mới';
  static String criticalAlertBody(int count) =>
      '$count đơn hàng khẩn cấp vừa xuất hiện';
  static const criticalAlertDismiss = 'Đã hiểu';

  // Urgency filter empty state (DG-221 Phase 5)
  static const urgencyFilterEmpty = 'Không có đơn hàng khẩn cấp';

  // Critical orders screen
  static const criticalOrdersTitle = 'Đơn hàng khẩn cấp';
  // Combined urgency listing title (critical + urgent) — DG-250 Phase 2
  static const combinedUrgencyTitle = 'Đơn hàng khẩn cấp & gấp';
  // Combined urgency listing empty state (critical + urgent) — DG-250 5.6-c1
  static const combinedUrgencyFilterEmpty = 'Không có đơn hàng khẩn cấp hoặc gấp';

  // Completeness labels (DG-241 Phase 2 — FR-3, FR-4)
  static const completenessIncompleteBadge = 'THIẾU THÔNG TIN';
  static const completenessMissingPrefix = 'Thiếu: ';
  static const completenessComplete = '';

  // Incomplete banner (DG-241 Phase 3 — FR-5)
  static const incompleteBannerTitle = 'Đơn hàng thiếu thông tin';
  static String incompleteBannerText(int count) => '$count đơn hàng thiếu thông tin';

  // Incomplete badge tooltip (DG-241 Phase 3 — FR-6)
  static String incompleteBadgeTooltip(int count) =>
      '$count đơn hàng thiếu thông tin';

  // Incomplete filter empty state (DG-241 Phase 3 — FR-7)
  static const incompleteFilterEmpty = 'Không có đơn hàng thiếu thông tin';

  // Missing fields section title (DG-241 Phase 3 — order detail)
  static const missingFieldsSection = 'Thông tin còn thiếu';

  // Missing field short labels (DG-241 Phase 4 — card indicators)
  static const missingFieldCustomerName = 'tên KH';
  static const missingFieldItems = 'sản phẩm';
  static const missingFieldTotalPrice = 'tổng tiền';
  static const missingFieldDueDate = 'ngày giao';
  static const missingFieldDueTime = 'giờ giao';
  static const missingFieldDeliveryAddress = 'địa chỉ';
  static const missingFieldCustomerPhone = 'SĐT';
  static const missingFieldDeliveryPhone = 'SĐT nhận';
  static const missingFieldSource = 'nguồn';

  // Banner collapse/expand tooltips (DG-262 Phase 2)
  static const bannerCollapseTooltip = 'Thu gọn';
  static const bannerExpandTooltip = 'Mở rộng';

  // Stage 5 payment (DG-267 Phase 3)
  static const payNow = 'Thanh toán ngay';
  static const payLater = 'Thanh toán sau';

  // Stage 3 pickup options (DG-267 Phase 3)
  static const pickupNow = 'Giao ngay';
  static const pickupLater = 'Giao hàng sau';
  static const pickupTitle = 'Nhận bánh';
  static const pickupSubtitle = 'Vui lòng chọn hình thức nhận bánh';

  // POS cart bar fast-path button (DG-370 Phase 1) — one-tap Giao ngay +
  // Thanh toán jump to Stage 5 with walk-in defaults.
  static const posGiaoNgayThanhToan = 'Giao ngay & Thanh toán';

  // Delivery filter labels (DG-261 Phase 1)
  static const deliveryFilterToday = 'Hôm nay';
  static const deliveryFilterAll = 'Tất cả';
  static const deliveryNoDueDate = 'Chưa có ngày';
  static const deliveryEmptyToday = 'Không có đơn giao hàng hôm nay';
  static const deliveryEmptyAll = 'Không có đơn giao hàng';

  // Delivery tab with count (DG-261 review CQ-2)
  static String deliveryTabWithCount(int count) => 'Giao hàng ($count)';

  // Date filter labels for order list (DG-193 Phase 1).
  // "Hôm nay" and "Tất cả" reuse VN.filterToday and VN.filterAll respectively
  // (see vietnamese_labels.dart) — only the two new options live here.
  static const dateFilterTomorrow = 'Ngày mai';
  static const dateFilterTodayTomorrow = 'Nay + Mai';

  // Phone dialer launch failure (DG-283 review cycle 1 — CQ-1)
  static const cannotOpenDialer = 'Không mở được trình quay số.';

  // Delivery schedule + GPS (DG-303 Phase 4) — door delivery only
  static const latitudeLabel = 'Vĩ độ';
  static const longitudeLabel = 'Kinh độ';
  static const googleMapsUrlLabel = 'Liên kết Google Maps';
  static const deliveryTimeSlotLabel = 'Khung giờ giao';
  static const gpsCoordinatesLabel = 'Tọa độ GPS';
  static const openMap = 'Mở bản đồ';
  static const cannotOpenMap = 'Không mở được bản đồ.';
  static const latitudeInvalid = 'Vĩ độ phải từ -90 đến 90';
  static const longitudeInvalid = 'Kinh độ phải từ -180 đến 180';

  /// Predefined 1-hour delivery time slots (FR3): "6:00" … "21:00".
  static const deliveryTimeSlots = <String>[
    '6:00',
    '7:00',
    '8:00',
    '9:00',
    '10:00',
    '11:00',
    '12:00',
    '13:00',
    '14:00',
    '15:00',
    '16:00',
    '17:00',
    '18:00',
    '19:00',
    '20:00',
    '21:00',
  ];

  // Delivery tab calendar view toggle + grouping (DG-303 Phase 5) — FR5, AC6.
  static const deliverySwitchToList = 'Chuyển sang danh sách';
  static const deliverySwitchToWeek = 'Chuyển sang tuần';
  static const deliverySwitchToDay = 'Chuyển sang ngày';
  static const deliveryCalendarNoSlot = 'Chưa có khung giờ';

  // Delivery week calendar view (DG-306 Phase 2) — FR3, FR5, AC1–AC3.
  static const deliveryWeekToday = 'Hôm nay';
  static const deliveryWeekPrevTooltip = 'Tuần trước';
  static const deliveryWeekNextTooltip = 'Tuần sau';
  static const deliveryWeekUnscheduled = 'Chưa có giờ';

  // Delivery day calendar view — day navigation.
  static const deliveryDayToday = 'Hôm nay';
  static const deliveryDayPrevTooltip = 'Ngày trước';
  static const deliveryDayNextTooltip = 'Ngày sau';

  // Delivery calendar time-slot count badge + compact layout (DG-329
  // Phase 4 / FR5 / AC4). Shown next to a slot label when the slot has 3+
  // orders, e.g. "15:00 (3 đơn)".
  static String deliverySlotCountBadge(int count) => '$count đơn';

  /// Minimum readable width (in logical pixels) of a compact order chip in
  /// the calendar time-slot row (NFR2). Below this width chips become too
  /// narrow to display the customer name and staff line legibly.
  static const double compactOrderChipMinWidth = 120.0;

  /// Maximum number of compact order chips rendered per row in a calendar
  /// time-slot row on screens ≥ 480px wide (NFR2). On narrower screens the
  /// slot falls back to a vertically scrollable list.
  static const int compactOrderChipsPerRow = 4;

  /// Screen-width threshold (in logical pixels) at or above which the
  /// calendar time-slot row renders the compact `Wrap` layout. Below this
  /// width the slot falls back to a scrollable single-column list.
  static const double compactLayoutMinScreenWidth = 480.0;

  // Delivery staff claiming UI (DG-310 Phase 4) — FR5/FR6/FR7.
  static const deliveryClaimButton = 'Nhận giao';
  static const deliveryUnclaimButton = 'Trả đơn';
  static const deliveryClaimedBy = 'Đã nhận';
  static const deliveryUnassigned = 'Chưa có nhân viên giao hàng';
  static const deliveryStaffLabel = 'Nhân viên giao hàng';
  static const deliveryClaimFailed = 'Không nhận được đơn hàng.';
  static const deliveryUnclaimFailed = 'Không trả được đơn hàng.';
  static const deliveryClaimSuccess = 'Đã nhận giao';
  static const deliveryUnclaimSuccess = 'Đã trả đơn';

  // Delivery staff filter + workload summary (DG-304 Phase 3) — FR2/FR3/FR5.
  static const staffFilterAll = 'Tất cả nhân viên';
  static const staffFilterLabel = 'Lọc theo nhân viên';
  static const workloadSummaryTitle = 'Khối lượng công việc hôm nay';
  static const workloadSummaryEmpty = 'Không có đơn giao đang xử lý';
  static const workloadUnassigned = 'Chưa gán';
  static String workloadStaffCount(String staffName, int count) =>
      '$staffName: $count đơn';

  // Staff assignment dropdown (DG-304 Phase 5) — FR8/FR9/FR10/AC5/AC6.
  static const assignStaffLabel = 'Nhân viên giao hàng';
  static const assignStaffUnassign = 'Chưa gán';
  static const assignStaffLoadError = 'Không tải được danh sách nhân viên';
  static const assignStaffSaved = 'Đã cập nhật nhân viên giao hàng';
  static const assignStaffSaveFailed = 'Không cập nhật được nhân viên giao hàng';
  /// Display label for an inactive (deactivated) staff member in the
  /// assignment dropdown. Shows the real name followed by the "(đã ngưng)"
  /// suffix only when the staff record exists but is deactivated (DG-329
  /// Phase 2 / FR3 / AC2).
  static String assignStaffInactive(String staffName) => '$staffName (đã ngưng)';

  /// Fallback label for an assigned staff member whose record is missing
  /// entirely from the staff list (e.g. deleted). Shows "NV #`<id>`" without
  /// the misleading "(đã ngưng)" suffix (DG-329 Phase 2 / FR3 / AC2).
  static String assignStaffMissing(String staffId) => 'NV #$staffId';

  /// Formats a single day label as "T2, 29/07".
  static String deliveryDayLabel(DateTime d) {
    final weekday = deliveryWeekdayHeaders[d.weekday - 1];
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$weekday, $day/$month';
  }

  // Google Maps modal (DG-306 Phase 3) — FR6, AC6.
  static const googleMapsContextMenuLabel = 'Google Maps';
  static const googleMapsModalTitle = 'Liên kết Google Maps';
  static const googleMapsModalHint =
      'Dán liên kết Google Maps cho địa chỉ giao hàng.';
  static const googleMapsModalEmpty = 'Chưa có liên kết Google Maps.';
  static const googleMapsModalOpenMap = 'Mở bản đồ';
  static const googleMapsModalSave = 'Lưu';
  static const googleMapsModalClear = 'Xoá liên kết';
  static const googleMapsModalSaved = 'Đã lưu liên kết Google Maps.';
  static const googleMapsModalCleared = 'Đã xoá liên kết Google Maps.';

  /// Short Vietnamese weekday headers (Mon–Sun), aligned to DateTime.weekday
  /// (Mon=1..Sun=7 → index 0..6).
  static const deliveryWeekdayHeaders = <String>[
    'T2',
    'T3',
    'T4',
    'T5',
    'T6',
    'T7',
    'CN',
  ];

  /// Formats a week range as `dd/MM – dd/MM` (the visible week label).
  static String deliveryWeekRangeLabel(DateTime start, DateTime end) {
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    return '${fmt(start)} – ${fmt(end)}';
  }
}
