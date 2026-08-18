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
  // "Hôm nay" and "Tất cả" reuse `EventsLabels.filterToday` and
  // `EventsLabels.filterAll` respectively (see events.dart) — only the two
  // new options live here.
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

  // ── Phase 4.2 migration: relocated from VN ──

  // Order statuses
  static const statusNew = 'Mới';
  static const statusConfirmed = 'Đã xác nhận';
  static const statusInProgress = 'Đang làm';
  static const statusReady = 'Sẵn sàng';
  static const statusDelivered = 'Đã giao';
  static const statusCompleted = 'Hoàn thành';
  static const statusCancelled = 'Đã hủy';

  // Status actions (transition buttons)
  static const actionConfirm = 'Xác nhận';
  static const actionStart = 'Bắt đầu làm';
  static const actionReady = 'Sẵn sàng';
  static const actionDeliver = 'Giao hàng';
  static const actionComplete = 'Hoàn thành';
  // Order form
  static const createOrder = 'Tạo đơn hàng mới';
  static const customerName = 'Tên khách hàng';
  static const customerPhone = 'Số điện thoại';
  static const selectProducts = 'Chọn sản phẩm';
  static const addProduct = 'Thêm sản phẩm';
  static const dueDate = 'Hạn giao';
  static const deliveryType = 'Hình thức nhận hàng';
  static const pickup = 'Lấy tại tiệm';
  static const delivery = 'Giao hàng';
  static const deliveryAddress = 'Địa chỉ giao hàng';
  static const notes = 'Ghi chú';
  static const total = 'Tổng cộng';
  static const submitOrder = 'TẠO ĐƠN HÀNG';

  // Order detail
  static const orderDetail = 'Chi tiết đơn hàng';
  static const editOrder = 'Sửa đơn hàng';

  // Order detail tabs (DG-334 Phase 1 — FR1, AC1)
  static const orderDetailTabGeneral = 'Tổng quan';
  static const orderDetailTabWorkItems = 'Sản xuất';
  static const orderDetailTabTransactions = 'Giao dịch';
  static const customer = 'Khách hàng';

  // Order detail — Customer tab (DG-371 Phase 1 — FR8/FR9/FR10, AC7/AC8)
  /// 4th tab title on the order detail screen. Reuses [customer] wording so
  /// the tab label stays consistent with the customer list/management copy.
  static const orderDetailTabCustomer = 'Khách hàng';

  /// Section header above the customer profile card (name, phone, created).
  static const orderDetailCustomerInfoTitle = 'Thông tin khách hàng';

  /// Empty state shown when an order has no linked `customerId` (FR10/AC8).
  static const orderDetailCustomerEmpty = 'Chưa có khách hàng';

  // Order detail — Transactions tab (DG-371 Phase 3 — FR5/FR6, AC4/AC5)
  /// Add-transaction button shown at the top of the transactions tab. Opens
  /// the existing [OrderRecordPaymentSheet] to record a new transaction.
  static const orderDetailAddTransaction = 'Thêm giao dịch';
  static const products = 'Sản phẩm';
  static const payment = 'Thanh toán';
  static const paid = 'Đã thanh toán';
  static const partialPaid = 'Trả một phần';
  static const unpaid = 'Chưa thanh toán';
  static const amountPaidLabel = 'Đã trả';
  static const remainingLabel = 'Còn lại';
  static const actions = 'Thao tác';
  static const cancelOrderTitle = 'Hủy đơn hàng';
  static const cancelReasonLabel = 'Lý do hủy (tùy chọn)';
  static const cancelReasonHint = 'Nhập lý do hủy...';
  static const confirmCancelAction = 'Xác nhận hủy';
  static const orderStatusUpdated = 'Đã cập nhật trạng thái';
  static const orderStatusChangeFailedPrefix = 'Không thể đổi trạng thái';
  static const orderStatusRecoveryLabel = 'Cách xử lý';
  static const orderStatusDebugCodeLabel = 'Mã';
  static const orderStatusActionCheckStock =
      'Kiểm tra tồn kho hoặc số lượng sản phẩm rồi thử lại.';
  static const orderStatusActionCheckPriceBucket =
      'Kiểm tra mức giá sản phẩm trong đơn rồi thử lại.';
  static const orderStatusActionAddBackwardReason =
      'Nhập lý do chuyển trạng thái lùi rồi thử lại.';
  static const orderStatusActionCompletePayment =
      'Hoàn tất thanh toán còn thiếu trước khi đổi trạng thái.';
  static const orderStatusActionContactAdmin =
      'Kiểm tra dữ liệu đơn hàng hoặc liên hệ quản trị để hỗ trợ.';
  static const orderEditSaved = 'Đã lưu thay đổi';
  static const publicOrderCode = 'Mã nhận bánh';
  static const publicCodeKeep = 'Giữ mã hiện tại';
  static const publicCodeRegenerate = 'Tạo mã mới';
  static const publicCodeDateChangeTitle = 'Đổi mã nhận bánh?';
  static const publicCodeDateChangePrompt =
      'Bạn vừa đổi ngày nhận/giao. Chọn giữ mã hiện tại hoặc tạo mã mới trước khi lưu.';
  static const publicCodeChangedNotice = 'Mã nhận bánh đã đổi:';

  // Refresh
  // Packing items
  static const packCandles = 'Nến';
  static const packCutlery = 'Dao/dĩa';
  static const packBox = 'Hộp';
  static const packBase = 'Đế';
  static const packRibbon = 'Ruy-băng';

  // Search
  // Order history
  static const lichSuDonHang = 'Lịch sử đơn hàng';
  static const lichSuDonHangLocMotNgay = 'Một ngày';
  static const lichSuDonHangLocKhoangNgay = 'Khoảng ngày';
  static const lichSuDonHangTimKiem = 'Tìm theo tên, số điện thoại, mã đơn...';
  static const lichSuDonHangTrong = 'Không có đơn trong khoảng đã chọn';
  static const lichSuDonHangKhongTimThay = 'Không tìm thấy đơn phù hợp';
  static const lichSuDonHangToiDa7Ngay = 'Chỉ được chọn tối đa 7 ngày';
  static const lichSuDonHangKhoangNgayKhongHopLe = 'Khoảng ngày không hợp lệ';

  // Product form
  // Delivery types (detailed)
  static const deliveryBus = 'Giao xe khách';
  static const deliveryDoor = 'Giao tận nơi';

  // Order create form extras
  static const orderSource = 'Nguồn đặt hàng';
  static const deliveryAssignee = 'Nhân viên giao hàng';
  static const walkInCustomer = 'Khách Vãng Lai';
  static const dueTime = 'Giờ giao';
  static const isBirthday = 'Nến tuổi sinh nhật';
  static const birthdayAge = 'Tuổi khách hàng';

  // Candle type selection (DG-340 Phase 1)
  /// Radio button group shown on cake item edit screens when is_birthday is
  /// checked. Values persist under `order_items.attributes['candle_type']`.
  /// `khong_nen` represents the explicit "no candle" choice; an absent
  /// `candle_type` key also means no candle (AC7).
  static const candleTypeSectionLabel = 'Loại nến';
  static const candleTypeNenSo = 'Nến số';
  static const candleTypeNenXoan = 'Nến xoắn';
  static const candleTypeNenNho = 'Nến nhỏ';
  static const candleTypeKhongNen = 'Không nến';

  /// Map a stored `candle_type` value to its Vietnamese display label.
  /// Falls back to the raw `value` so unknown keys remain visible rather
  /// than blank.
  static String candleTypeLabel(String? value) {
    switch (value) {
      case 'nen_so':
        return candleTypeNenSo;
      case 'nen_xoan':
        return candleTypeNenXoan;
      case 'nen_nho':
        return candleTypeNenNho;
      case 'khong_nen':
        return candleTypeKhongNen;
      default:
        return value ?? '';
    }
  }

  static const orderCreated = 'Đã tạo đơn hàng';
  // Time slots
  static const timeSlotMorning = 'Sáng';
  static const timeSlotAfternoon = 'Chiều';
  static const timeSlotEvening = 'Tối';

  // Order photos
  static const orderPhotos = 'Ảnh đơn hàng';
  static const addOrderPhoto = 'Thêm ảnh';
  static const noOrderPhotos = 'Chưa có ảnh';
  static const deleteOrderPhotoConfirm = 'Xóa ảnh này khỏi đơn?';
  static const orderPhotoDeleted = 'Đã xóa ảnh';
  static const orderPhotoAdded = 'Đã thêm ảnh';
  static const editPhotoTags = 'Chọn nhãn ảnh';
  static const photoTagsUpdated = 'Đã cập nhật nhãn';
  static const pendingPhotosLabel = 'Ảnh đính kèm';
  static const uploadingPhotos = 'Đang tải ảnh lên...';
  static const itemPrice = 'Đơn giá';

  // ── Photo upload progress (shared UploadProgressIndicator) ──────────────
  /// "X/N đã tải lên" — success-only count summary shown beneath per-photo
  /// rows. DG-333 Phase 1.
  // ── Markup (trưng bày) ──────────────────────────────────────────────────
  /// "Giá gốc" — the assigned price (base_price or selected chip price) shown
  /// as a non-editable reference in the POS chip picker. DG-296 Phase 3.
  static const giaGoc = 'Giá gốc';

  /// "Giá bán" — the editable selling price field (markup). DG-296 Phase 3.
  static const giaBan = 'Giá bán';

  /// Price floor warning: selling price cannot be below the assigned price.
  static const markupFloorWarning = 'Giá bán không được thấp hơn giá gốc';

  /// Helper text for the markup price field (thousands of đ).
  static const markupThousandsHint = 'Nhập nghìn đồng (VD: 250 = 250.000đ)';

  /// "Phần cộng thêm" — the markup amount (unitPrice − assignedPrice) shown
  /// on trưng bày order line items in the order detail view. DG-296 Phase 5.
  static const markupAmount = 'Phần cộng thêm';

  // Catalog gallery
  // Payment transactions
  static const txnTypeDeposit = 'Đặt cọc';
  static const txnTypePayment = 'Thanh toán';
  static const txnTypeFullPayment = 'Thanh toán đủ';
  static const txnTypeRefund = 'Hoàn tiền';
  static const txnTypeRutTien = 'Tiền rút';
  static const methodCash = 'Tiền mặt';
  static const methodTransfer = 'Chuyển khoản';
  static const methodDebt = 'Nợ';
  static const addPayment = 'Thêm thanh toán';
  static const depositSection = 'Đặt cọc ngay';
  static const depositAmount = 'Số tiền đặt cọc';
  static const paymentHistory = 'Lịch sử thanh toán';
  static const paymentRecorded = 'Đã ghi thanh toán';
  static const paymentUpdated = 'Đã cập nhật giao dịch';
  static const paymentFee = 'Trả phí';
  static const paymentThousandsHint = 'Nhập nghìn đồng (VD: 200 = 200.000đ)';
  static const editPayment = 'Sửa giao dịch';
  static const txnDetails = 'Chi tiết giao dịch';
  static const txnNoteLabel = 'Ghi chú';
  static const noPaymentHistory = 'Chưa có giao dịch';
  static const paymentMethod = 'Hình thức';
  static const paymentNotes = 'Ghi chú (tùy chọn)';
  static const paymentAmountLabel = 'Số tiền';
  static const txnType = 'Loại thanh toán';

  // Payment transaction invalidation (DG-196)
  static const txnInvalidatedBadge = 'Đã hủy';
  static const txnInvalidatedAtLabel = 'Ngày hủy';
  static const txnInvalidatedByLabel = 'Người hủy';
  static const invalidatePayment = 'Hủy giao dịch';
  static const restorePayment = 'Khôi phục giao dịch';
  static const invalidateConfirmTitle = 'Hủy giao dịch?';
  static const invalidateConfirmMessage =
      'Giao dịch sẽ bị hủy và không tính vào tổng thanh toán. '
      'Bút toán kế toán sẽ được đảo.';
  static const restoreConfirmTitle = 'Khôi phục giao dịch?';
  static const restoreConfirmMessage =
      'Giao dịch sẽ được khôi phục và tính lại vào tổng thanh toán.';
  static const paymentInvalidated = 'Đã hủy giao dịch';
  static const paymentRestored = 'Đã khôi phục giao dịch';
  static const invalidateReasonLabel = 'Lý do hủy (tùy chọn)';
  static const invalidateReasonHint = 'Nhập lý do hủy giao dịch...';

  // Work item statuses
  static const workItemPending = 'Chờ xử lý';
  static const workItemConfirmed = 'Đã xác nhận';
  static const workItemWorking = 'Đang làm';
  static const workItemReady = 'Sẵn sàng';
  static const workItemDelivered = 'Đã giao';
  static const workItemCancelled = 'Đã hủy';

  // Work items section
  static const workItemsSection = 'Chi tiết sản xuất';
  static const noWorkItems = 'Chưa có chi tiết sản xuất';
  static const workItemStatusChanged = 'Đã cập nhật trạng thái sản phẩm';
  static const statusReasonTitle = 'Lý do thay đổi';
  static const statusReasonLabel = 'Lý do (bắt buộc)';
  static const statusReasonHint = 'Nhập lý do...';
  static const confirmStatusChange = 'Xác nhận';
  static const autoUpdateOrderTitle = 'Cập nhật đơn hàng';
  static const autoSyncWorkItemStatus = 'Đã đồng bộ trạng thái sản phẩm';
  static const autoSyncOrderStatus = 'Đã đồng bộ trạng thái đơn hàng';

  // General tab summary overview (Phase 3 — DG-334 / FR4 / AC4)
  static const workItemSummaryTitle = 'Tóm tắt công việc';
  static const paymentStatusSummaryTitle = 'Tóm tắt thanh toán';
  static const workItemSummaryUnit = 'công việc';
  static const paymentStatusSummaryOfTotal = 'trên tổng';
  static const workItemSummaryEmpty = 'Chưa có công việc';

  /// Renders "N công việc" for the work item summary count.
  static String workItemSummaryCount(int count) =>
      '$count $workItemSummaryUnit';

  // Cake queue & cake detail
  static const cakeQueue = 'Làm bánh';
  static const deliveryTab = 'Giao hàng';
  static const orderListTab = 'Đơn hàng';
  static const cakeDetail = 'Chi tiết bánh';
  static const viewOrder = 'Xem đơn hàng';
  static const noCakeQueueItems = 'Không có sản phẩm cần làm';
  static const noDeliveryItems = 'Không có sản phẩm cần giao';
  static const includeReadyFilter = 'Bao gồm sẵn sàng';
  static const perItemPhotos = 'Ảnh sản phẩm';
  static const birthdayWithAge = 'Sinh nhật';
  static const orderPhotosSection = 'Ảnh đơn hàng (chung)';

  /// Header for the chuyen-khoan tagged photo section shown in the
  /// Transactions tab of OrderDetailScreen. DG-364 Phase 4.2.
  static const transferPhotosSection = 'Ảnh chuyển khoản';

  /// Empty-state hint shown when an order has no chuyen-khoan tagged photos
  /// in the Transactions tab. DG-364 Phase 4.2.
  static const noTransferPhotos = 'Chưa có ảnh chuyển khoản';

  /// Tooltip for the photo attachment button shown in the record-payment sheet
  /// when method = transfer. DG-364 Phase 4.3 / FR2.
  static const attachTransferPhotoTooltip = 'Đính kèm ảnh chuyển khoản';

  /// Label for the photo attachment button shown in the record-payment sheet
  /// when method = transfer. DG-364 Phase 4.3 / FR2.
  static const attachTransferPhoto = 'Ảnh chuyển khoản';

  /// Caption shown next to the selected transfer photo file name in the
  /// record-payment sheet. DG-364 Phase 4.3 / FR2.
  static const transferPhotoSelected = 'Đã chọn ảnh';

  /// SnackBar shown when the transfer photo is uploaded after the payment
  /// is recorded. DG-364 Phase 4.3 / FR3.
  static const transferPhotoUploaded = 'Đã tải lên ảnh chuyển khoản';

  /// SnackBar shown when the transfer photo upload fails after the payment
  /// is recorded. DG-364 Phase 4.3 / FR3.
  static const transferPhotoUploadFailed = 'Không tải được ảnh chuyển khoản';

  // ── Per-transaction photo (DG-410 Phase 4) ─────────────────────────────
  /// Section header above the transaction's attached photo in the detail sheet.
  static const txnPhotoSection = 'Ảnh giao dịch';

  /// Empty-state hint shown when a transaction has no attached photo.
  static const txnPhotoEmpty = 'Chưa có ảnh giao dịch';

  /// Button label for attaching a photo to a transaction (add).
  static const txnPhotoAttach = 'Đính kèm ảnh';

  /// Button label for replacing a transaction's attached photo.
  static const txnPhotoReplace = 'Đổi ảnh';

  /// Button label for removing a transaction's attached photo.
  static const txnPhotoRemove = 'Gỡ ảnh';

  /// Confirmation dialog title for removing a transaction's attached photo.
  static const txnPhotoRemoveConfirm = 'Gỡ ảnh khỏi giao dịch này?';

  /// Tooltip for the transaction photo thumbnail (tap to enlarge).
  static const txnPhotoTapToEnlarge = 'Chạm để xem ảnh lớn';

  /// SnackBar shown when a transaction photo is attached/replaced.
  static const txnPhotoSaved = 'Đã lưu ảnh giao dịch';

  /// SnackBar shown when a transaction photo is removed.
  static const txnPhotoRemoved = 'Đã gỡ ảnh giao dịch';

  /// SnackBar shown when attaching/replacing/removing a transaction photo
  /// fails.
  static const txnPhotoSaveFailed = 'Không lưu được ảnh giao dịch';

  /// SnackBar shown when the record sheet links the just-uploaded photo to
  /// the new transaction. DG-410 Phase 4 / FR2 / AC1.
  static const txnPhotoLinked = 'Đã gắn ảnh vào giao dịch';

  /// SnackBar shown when the record sheet fails to link the just-uploaded
  /// photo to the new transaction. The payment itself remains recorded.
  /// DG-410 Phase 4 / FR2.
  static const txnPhotoLinkFailed =
      'Đã ghi thanh toán nhưng không gắn được ảnh vào giao dịch';

  // General
  // Cash-in-cake (rut tien)
  static const rutTien = 'Rút tiền';
  static const rutTienToggle = 'Bánh rút tiền';
  static const soTienRut = 'Số tiền rút';
  static const phiRutTien = 'Phí rút tiền';
  static const rutTienSection = 'Rút tiền trong bánh';
  static const cashReceived = 'Đã nhận tiền';
  static const cashNotReceived = 'Chưa nhận tiền';
  static const daDuaTienRut = 'Đã đưa tiền rút';

  // Product display flags
  // POS / Counter Sales
  static const banHang = 'Bán hàng';
  static const thanhToan = 'Thanh toán';
  static const inHoaDon = 'In hóa đơn';
  static const inBienNhan = 'In biên nhận';
  static const xacNhanThanhToan = 'Xác nhận thanh tiền';
  static const sanPhamHetHang = 'Sản phẩm hết hàng';
  static const banAnyway = 'Sản phẩm hết hàng. Bán anyway?';
  static const xacNhan = 'Xác nhận';
  static const tienMat = 'Tiền mặt';
  static const chuyenKhoan = 'Chuyển khoản';
  static const themThongTin = 'Thêm thông tin';
  static const khachLe = 'Khách lẻ';
  static const taiTiem = 'Tại tiệm';
  static const taiTiemPOS = 'Tại tiệm - POS';
  static const quaTang = '(Quà tặng)';
  static const soLuong = 'Số lượng';
  static const donGia = 'Đơn giá';
  static const xoa = 'Xóa';
  static const thanhToanThanhCong = 'Thanh toán thành công';
  static const transferProofTitle = 'Bằng chứng chuyển khoản';
  static const transferProofPrompt = 'Chọn nguồn ảnh để xác nhận thanh toán.';
  static const skip = 'Bỏ qua';
  static const photoLibrary = '🖼️ Thư viện';
  static const clearCartTitle = 'Xóa giỏ hàng?';
  static const clearCartPrompt =
      'Bạn có chắc muốn xóa tất cả sản phẩm trong giỏ?';
  static const clear = 'Xóa';
  static const backToCart = 'Quay lại giỏ hàng';
  static const clearCart = 'Xóa giỏ';
  static const selectPaymentMethod = 'Chọn phương thức thanh toán';
  static const paymentAmount = 'Số tiền';
  static const excessPaymentWarningTitle = 'Số tiền không hợp lệ';
  static const excessPaymentWarningMessage =
      'Số tiền thanh toán vượt quá tổng tiền sản phẩm. Vui lòng điều chỉnh lại.';
  static const confirmCounterPayment = 'Xác nhận thanh toán đơn tại quầy';
  static const removeFromCartTitle = 'Xóa sản phẩm khỏi giỏ?';
  static const decreaseQuantity = 'Giảm số lượng';
  static const increaseQuantity = 'Tăng số lượng';
  static const giftSuffix = 'Quà tặng';
  static const removedFromCartPrefix = 'Đã xóa';
  static const removedFromCartSuffix = 'khỏi giỏ';
  static const loiKhongXacDinhTuMayChu = 'Lỗi không xác định từ máy chủ';
  static const loiMayChu = 'Lỗi máy chủ';
  static const taiLai = 'Tải lại';
  static const khongCoSanPham = 'Chưa có sản phẩm';
  static const trongLuong = 'Trọng lượng';
  static const inPhieu = 'In phiếu';

  // Knowledge base
  // Shipping fee & extras
  static const shippingFee = 'Phí giao hàng';
  static const shippingFree = 'Miễn phí';
  static const extras = 'Phụ kiện';
  static const noConfiguredExtras = 'Chưa có phụ kiện được cấu hình';
  static const giftBadge = 'Tặng';
  static const toggleGift = 'Tặng/Trả phí';
  static const giftToggleTooltip = 'Bấm để chuyển giữa tặng và trả phí';

  // Extras management
  static const extrasSettings = 'Phụ kiện đi kèm';
  static const addExtra = 'Thêm phụ kiện';
  static const editExtra = 'Sửa phụ kiện';
  static const extraName = 'Tên phụ kiện';
  static const extraPrice = 'Giá phụ kiện';
  static const extraNameHint = 'VD: Nến, Đĩa muỗng';
  static const extraPriceHint = 'VD: 5000';
  static const extraFormatError = 'Định dạng: Tên|Giá (VD: Nến|5000)';
  static const extraAdded = 'Đã thêm phụ kiện';
  static const extraUpdated = 'Đã cập nhật phụ kiện';
  static const extraDeleted = 'Đã xóa phụ kiện';
  static const noExtras = 'Chưa có phụ kiện';
  static const deleteExtraConfirm = 'Xóa phụ kiện này?';
  static const extrasSettingsDeprecatedTitle =
      'Đã dừng quản lý phụ kiện tại đây';
  static const extrasSettingsDeprecatedBody =
      'Phụ kiện trả phí mới được quản lý từ Danh mục sản phẩm (nhóm phu_kien). Mục này chỉ giữ lại để hướng dẫn và không còn tạo/sửa dữ liệu order_extra.';
  static const extrasSettingsDeprecatedAction =
      'Vào Danh mục sản phẩm để thêm/sửa phụ kiện và mức giá.';

}
