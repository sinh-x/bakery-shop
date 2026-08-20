/// Shared/common Vietnamese labels for the bakery app.
///
/// Per the VN Label Policy in CLAUDE.md and §5 of
/// docs/flutter-coding-standards.md, new user-facing copy that spans multiple
/// domains lives in this file rather than being appended to the monolithic
/// `VN` class. Consumers import this file and use `SharedLabels.*` for
/// shared/common strings.
class SharedLabels {
  SharedLabels._();

  // Navigation
  static const appName = 'Đoàn Gia - Bánh Kem';
  static const tabDashboard = 'Tổng quan';
  static const tabManagement = 'Quản lý';
  static const tabOrders = 'Đơn hàng';
  static const tabProducts = 'Sản phẩm';
  static const tabKnowledgeBase = 'Sổ tay';
  static const tabEvents = 'Sự kiện';
  static const tabChecklist = 'Checklist';

  // General actions
  static const remove = 'Xóa';
  static const save = 'Lưu';
  static const cancel = 'Hủy';
  static const back = 'Quay lại';
  static const dong = 'Đóng';
  static const currency = 'đ';

  // Common error / loading messages
  static const apiError = 'Không thể kết nối máy chủ';
  static const apiTimeout = 'Kết nối máy chủ quá thời gian, vui lòng thử lại';
  static const fieldRequired = 'Không được để trống';
  static const invalidPrice = 'Giá không hợp lệ';
  static const loading = 'Đang tải...';
  static const errorLoading = 'Không thể tải dữ liệu';
  static const retry = 'Thử lại';

  // RBAC / UI gating
  static const accessDeniedTitle = 'Không có quyền truy cập';
  static const accessDeniedBody =
      'Chỉ quản trị viên mới được sử dụng tính năng này.';

  // Search
  static const searchOrders = 'Tìm đơn hàng...';

  // Refresh
  static const lamMoi = 'Làm mới';
  static const refreshFailed = 'Làm mới thất bại, dữ liệu có thể cũ';

  // Settings
  static const settings = 'Cài đặt';
  static const moreActions = 'Thao tác khác';
  static const openSettings = 'Cài đặt';
  static const openStock = 'Kho hàng';
  static const openOrderHistory = 'Lịch sử đơn hàng';
  static const openStockReconciliation = 'Đối soát tồn kho hôm nay';
  static const openStockReconciliationHistory = 'Lịch sử đối soát tồn kho';
  static const openCategoryManagement = 'Quản lý danh mục';
  static const openCatalogBrowse = 'Duyệt ảnh mẫu';
  static const openAuditLog = 'Nhật ký thay đổi';
  static const switchToKanbanView = 'Dạng Kanban';
  static const switchToListView = 'Dạng danh sách';
  static const apiUrlLabel = 'Địa chỉ máy chủ';
  static const apiUrlHint = 'http://hostname:8000';
  static const apiUrlHelp = 'Nhập địa chỉ Tailscale của máy chủ';
  static const testConnection = 'Kiểm tra kết nối';
  static const connectionSuccess = 'Kết nối thành công';
  static const connectionFailed = 'Không thể kết nối';
  static const urlSaved = 'Đã lưu địa chỉ máy chủ';
  static const urlEmpty = 'Vui lòng nhập địa chỉ';
  static const testing = 'Đang kiểm tra...';

  // Settings — staff picker
  static const generalSettings = 'Cài đặt chung';
  static const technicalSettings = 'Kỹ thuật';
  static const staffPicker = 'Nhân viên';
  static const staffPickerHint = 'Chọn nhân viên';
  static const staffNameManual = 'Tên nhân viên (thủ công)';
  static const staffNameHint = 'Nhập tên của bạn';
  static const staffSaved = 'Đã lưu tên nhân viên';
  static const appVersion = 'Phiên bản ứng dụng';
  static const serverVersion = 'Phiên bản máy chủ';
  static const serverVersionLoading = 'Đang tải...';
  static const serverVersionError = 'Không thể kết nối';
  static const fingerprintMismatchWarning =
      'Cảnh báo: mã ứng dụng khác mã máy chủ';
  static const serverFingerprintUnavailableWarning =
      'Cảnh báo: máy chủ chưa cung cấp mã phiên bản, có thể đang chạy bản cũ';
  static const dismissFingerprintWarning = 'Đóng cảnh báo phiên bản';
  static const createdBy = 'Người tạo';
  static String fingerprintMismatchStrip(String client, String server) {
    return '$fingerprintMismatchWarning ($client/$server)';
  }

  // Settings — staff-user binding (DG-259 Phase 4)
  static const staffBindingTitle = 'Gắn nhân viên';
  static const staffBindingHelp = 'Chọn nhân viên cho tài khoản này';
  static const staffBindingNone = 'Chưa gắn kết';
  static const staffBindingSaved = 'Đã cập nhật nhân viên';
  static const staffBindingSaveFailed = 'Không thể cập nhật nhân viên';
  static const staffBindingLoadError = 'Không tải được gắn kết nhân viên';

  // Printer paper mode (DG-183 Phase 2)
  static const paperModeLabel = 'Loại giấy in';
  static const paperModeHelp =
      'Cấu hình chỉ ghi nhận loại giấy — không đổi lệnh TSPL';
  static const paperModeLabelOption = 'Nhãn (có khe)';
  static const paperModeRollOption = 'Cuộn (liên tục)';
  static const paperModeLoading = 'Đang tải...';
  static const paperModeLoadError = 'Không tải được loại giấy in';
  static const paperModeSaved = 'Đã lưu loại giấy in';
  static const paperModeSaveFailed = 'Không thể lưu loại giấy in';
  static const paperModeInvalid = 'Loại giấy không hợp lệ';

  // Printer picker
  static const selectPrinter = 'Chọn máy in';
  static const scanning = 'Đang tìm...';
  static const noPrinterFound = 'Không tìm thấy máy in';
  static const printerConnectionFailed = 'Kết nối thất bại';
  static const connectingTo = 'Đang kết nối đến...';
  static const tapToRetry = 'Bấm để thử lại';
  static const noDevicesFound = 'Không có thiết bị nào';

  // Print
  static const print = 'In';
  static const printing = 'Đang in...';
  static const printSuccess = 'In thành công';
  static const printFailed = 'In thất bại';
  static const printerNotConnected = 'Máy in chưa kết nối';
  static const printerConnecting = 'Đang kết nối máy in...';

  // Print checklist dialog (Flow A)
  static const printChecklistTitle = 'In phiếu';
  static const printSkip = 'Bỏ qua';
  static const printStatusUnprinted = 'Chưa in phiếu';
  static const printStatusPrinted = 'Đã in phiếu';
  static const printStatusPrintedShort = 'Đã in';
  static const printStatusUnprintedShort = 'Chưa in';
  static const markAsPrinted = 'Đánh dấu đã in';
  static const unmarkPrinted = 'Hủy in';
  static const fetchingInternalReceipt = 'Đang tải phiếu nội bộ...';
  static const fetchingCustomerReceipt = 'Đang tải hóa đơn khách hàng...';
  static const printingInternalReceipt = 'Đang in phiếu nội bộ...';
  static const printingCustomerReceipt = 'Đang in hóa đơn khách hàng...';
  static const internalReceiptPrinted = 'Đã in phiếu nội bộ';
  static const customerReceiptPrinted = 'Đã in hóa đơn khách hàng';
  static const orderAutoConfirmed = 'Đã tự động xác nhận đơn hàng';
  static const printInternalPrompt = 'Đơn hàng chưa in phiếu nội bộ. In ngay?';

  // Receipts
  static const printReceipt = 'In';
  static const printWorkTicket = 'Phiếu nội bộ';
  static const printCustomerReceipt = 'Hóa đơn khách hàng';
  static const printBusLabel = 'Phiếu xe khách';
  static const printShopReceipt = 'Phiếu giao hàng';
  static const printDeliveryReceipt = 'Phiếu giao tận nơi';
  static const selectReceiptType = 'Chọn loại phiếu';
  static const receiptPreview = 'Xem phiếu';
  static const share = 'Chia sẻ';
  static const saveToGallery = 'Lưu ảnh';
  static const receiptSaved = 'Đã lưu ảnh phiếu';

  // Management dashboard (DG-344)
  static const dashboardSectionMetrics = 'Chỉ số hôm nay';
  static const dashboardSectionShortcuts = 'Truy cập nhanh';
  static const dashboardSectionAlerts = 'Cảnh báo';
  static const dashboardMetricOrdersToday = 'Đơn hàng hôm nay';
  static const dashboardMetricRevenueToday = 'Doanh thu hôm nay';
  static const dashboardMetricLowStock = 'Tồn kho thấp';
  static const dashboardCriticalAlertsDismiss = 'Đóng cảnh báo';
  static const dashboardShortcutStock = 'Kho hàng';
  static const dashboardShortcutCategories = 'Quản lý danh mục';
  static const dashboardShortcutCustomers = 'Quản lý khách hàng';
  static const dashboardShortcutExpenses = 'Chi phí';
  static const dashboardShortcutBlanks = 'Quản lý phôi bánh';
  static const dashboardShortcutCashDrawer = 'Tiền tại quầy';
  static String dashboardCriticalOrdersAlert(int count) =>
      'Có $count đơn hàng khẩn cấp cần xử lý';

  // Today Sales entry point (DG-374 Phase 1)
  static const dashboardMetricViewTodaySales = 'Xem doanh số hôm nay';

  // Today Sales screen — period tabs (DG-386 Phase 6 / FR1 / AC1, AC2)
  //
  // Three tabs on the summary screen: Ngày (day, current behavior), Tuần
  // (week, Monday–Sunday), Tháng (month, 1st–last day). Used as TabBar labels
  // and AppBar title prefixes for week/month navigation.
  static const todaySalesTabDay = 'Ngày';
  static const todaySalesTabWeek = 'Tuần';
  static const todaySalesTabMonth = 'Tháng';

  // Today Sales screen — period navigation (DG-386 Phase 11 / FR1 / AC1, AC2)
  //
  // Tooltips for the prev/next arrow buttons on the Tuần/Tháng tabs. Distinct
  // from `SharedLabels.back` (generic "Quay lại") so the period navigation
  // affordance is unambiguous (NFR4 — no inline VN strings).
  static const todaySalesPeriodPrevious = 'Kỳ trước';
  static const todaySalesPeriodNext = 'Kỳ sau';

  // Today Sales screen (DG-374 Phase 2)
  static const todaySalesTitle = 'Doanh số hôm nay';
  static const todaySalesRevenueSection = 'Tổng quan doanh thu';
  static const todaySalesRevenueGroup = 'Tổng doanh thu';
  static const todaySalesPaymentGroup = 'Tổng tiền nhận được';
  static const todaySalesOrderListSection = 'Đơn hàng hôm nay';
  static const todaySalesTotalRevenue = 'Tổng doanh thu';
  static const todaySalesOrderCount = 'Số đơn hàng';
  static const todaySalesCashTotal = 'Tiền mặt';
  static const todaySalesBankTransferTotal = 'Chuyển khoản';
  static const todaySalesTotalReceived = 'Tổng nhận';
  static const todaySalesEmptyOrders = 'Không có đơn hàng hôm nay';

  // Today Sales screen — cashflow breakdown (DG-374 Phase 3)
  static const todaySalesCashflowSection = 'Dòng tiền';
  static const todaySalesNoActiveDrawer = 'Chưa mở quầy hôm nay';

  // Today Sales screen — product breakdown (DG-386 Phase 7 / FR3 / AC3)
  //
  // Section title and column/row labels for the per-product revenue
  // attribution breakdown (top 10 products + a single "Khác"/Others row).
  // The "Khác" label is centralized here so no inline Vietnamese string lives
  // in widget code (NFR4 — VN Label Policy).
  static const todaySalesProductBreakdownSection = 'Phân tích sản phẩm';
  static const todaySalesProductBreakdownColumnProduct = 'Sản phẩm';
  static const todaySalesProductBreakdownColumnQuantity = 'SL';
  static const todaySalesProductBreakdownColumnRevenue = 'Doanh thu';
  static const todaySalesProductBreakdownColumnShare = 'Tỷ trọng';
  static const todaySalesProductBreakdownOthers = 'Khác';
  static const todaySalesProductBreakdownEmpty = 'Không có dữ liệu';

  // Today Sales screen — expense summary (DG-386 Phase 8 / FR4 / AC4)
  //
  // Section title, total line, category/subcategory labels, and empty state
  // for the period expense breakdown. The full parent/child category tree
  // from `expense_categories` is rendered even when a subcategory had zero
  // expenses in the period (via the backend `childrenOf` mapping). The
  // "Chưa phân loại" (uncategorized) line covers expenses whose category
  // could not be resolved.
  static const todaySalesExpenseSection = 'Chi phí';
  static const todaySalesExpenseTotal = 'Tổng chi phí';
  static const todaySalesExpenseSubcategory = 'Tiểu mục';
  static const todaySalesExpenseUncategorized = 'Chưa phân loại';
  static const todaySalesExpenseEmpty = 'Không có chi phí trong kỳ';

  // Today Sales screen — cashflow summary (DG-386 Phase 9 / FR5 / AC5)
  //
  // Section title and line labels for the operating-activities cashflow
  // summary rendered from journal entries (drawer-independent). Inflow is
  // cash received from customers; outflow is cash paid to suppliers and
  // employees. The supplier-outflow breakdown is grouped by expense
  // category with subcategory lines, mirroring the expense-summary tree.
  // An `Chưa phân loại` line covers supplier outflow whose category could
  // not be resolved. The net line is inflow minus outflow.
  static const todaySalesCashflowInflow = 'Tiền vào từ khách hàng';
  static const todaySalesCashflowOutflow = 'Tiền trả nhà cung cấp / nhân viên';
  static const todaySalesCashflowNet = 'Dòng tiền ròng';
  static const todaySalesCashflowUncategorized = 'Chưa phân loại';
  static const todaySalesCashflowEmpty = 'Không có dòng tiền trong kỳ';

  // Today Sales screen — cash-source breakdown (DG-378 Phase 3 / FR3, AC3)
  //
  // Separate from the "Tổng tiền nhận được" payment group: this breakdown
  // details the composition of cash at the drawer — sales cash (existing
  // `cashTotal`), owner/employee capital injections (`cashInTotal`), owner
  // draws (`cashOutTotal`), and the resulting net cash
  // (`cashTotal + cashInTotal - cashOutTotal`). Labels are intentionally
  // distinct from `CashDrawerLabels.cashDrawerTxnTypeCashIn`/
  // `cashDrawerTxnTypeCashOut` because the breakdown is a summary context,
  // not a per-transaction chip.
  static const todaySalesCashSourceSection = 'Nguồn tiền mặt';
  static const todaySalesCashSourceSalesCash = 'Tiền bán hàng';
  static const todaySalesCashSourceCashIn = 'Nạp vào quầy';
  static const todaySalesCashSourceCashOut = 'Rút khỏi quầy';
  static const todaySalesCashSourceNetCash = 'Tiền mặt ròng';

  // Today Sales screen — order breakdown (DG-391 Phase 3 / FR2, FR6, FR7 /
  // AC1, AC2)
  //
  // Section title, dropdown mode labels, source-row heading, column headers,
  // and empty state for the source × delivery_type order-breakdown matrix
  // shown on the Tuần/Tháng tabs. The three dropdown modes select which
  // metric is rendered in each cell: order count only, count + revenue, or
  // count + revenue + revenue share. All VN copy lives here (NFR2 — VN Label
  // Policy) so no inline Vietnamese string appears in widget code.
  static const todaySalesOrderBreakdownSection = 'Phân tích đơn hàng';
  static const todaySalesOrderBreakdownSourceHeader = 'Nguồn đặt hàng';
  static const todaySalesOrderBreakdownModeCount = 'Số đơn';
  static const todaySalesOrderBreakdownModeCountRevenue = 'Số đơn + Doanh thu';
  static const todaySalesOrderBreakdownModeCountRevenueShare =
      'Số đơn + Doanh thu + Tỷ trọng';
  static const todaySalesOrderBreakdownColumnDeliveryType = 'Kiểu giao';
  static const todaySalesOrderBreakdownColumnOrderCount = 'Số đơn';
  static const todaySalesOrderBreakdownColumnRevenue = 'Doanh thu';
  static const todaySalesOrderBreakdownColumnShare = 'Tỷ trọng';
  static const todaySalesOrderBreakdownEmpty = 'Không có dữ liệu';
  static const todaySalesOrderBreakdownTotal = 'Tổng';

  // Today Sales screen — accounts receivable (AR) line (DG-391 Phase 3 /
  // FR5 / AC4)
  //
  // AR = totalRevenue − (cashTotal + bankTransferTotal). Orange when AR > 0
  // (still owed), green when AR ≤ 0 (fully collected or prepayment surplus).
  // Displayed below the "Tổng tiền nhận được" group in [RevenueSummarySection]
  // for both the Day and Period tabs (all three inputs are already passed in).
  static const todaySalesAccountsReceivable = 'Công nợ';

  // Bulk selection
  static const chonAnh = 'Chọn';
  static const huy = 'Hủy';
  static const chon20 = 'Chọn 20';
  static const daChon = 'đã chọn';
  static const toiDa20Anh = 'Chỉ chọn tối đa 20 ảnh';
  static const dangTaiAnh = 'Đang tải ảnh...';
  static const daLuuNTrenM = 'Đã lưu n/m ảnh';
  static const khongTheTaiNTrenM = 'Không thể tải n/m ảnh';
  static const daChiaSeNAnh = 'Đã chia sẻ n ảnh';

  // Pagination load-more (cross-feature — DG-409 review-auto CQ-9).
  // Used by the product catalog grid footer and any future paginated list
  // that surfaces an explicit tap-to-load affordance.
  static const loadMore = 'Tải thêm';

  // ── Phase 4.2 migration: relocated from VN ──

  // Dashboard
  static const chonNgay = 'Chọn ngày';
  static const todayOrders = 'Đơn hàng hôm nay';
  static const upcomingDue = 'Sắp đến hạn';
  static const overdueOrders = 'Quá hạn';
  static const recentActivity = 'Sự kiện gần đây';
  // Today's order list empty state (DG-376 Phase 5 — FR6/AC6).
  static const khongCoDonHomNay = 'Không có đơn hàng hôm nay';

  // Packing items
  // ── Photo upload progress (shared UploadProgressIndicator) ──────────────
  /// "X/N đã tải lên" — success-only count summary shown beneath per-photo
  /// rows. DG-333 Phase 1.
  static String uploadedPhotosCount(int done, int total) =>
      '$done/$total đã tải lên';

  /// "X/N đã tải lên (Y lỗi)" — count summary shown when any photo has failed.
  /// DG-333 Phase 1.
  static String uploadedPhotosCountWithErrors(
    int done,
    int failed,
    int total,
  ) => '$done/$total đã tải lên ($failed lỗi)';

  /// Per-photo status line. [index] is 1-based. [statusLabel] is one of the
  /// localized status words returned by [photoUploadStatusLabel]. DG-333
  /// Phase 1.
  static String photoUploadStatus(int index, String statusLabel) =>
      'Ảnh $index: $statusLabel';

  /// Per-photo error line: "Ảnh N: Lỗi — `message`". DG-333 Phase 1.
  static String photoUploadFailed(int index, String message) =>
      'Ảnh $index: Lỗi — $message';

  /// Localized status word for a [PhotoUploadStatus]. DG-333 Phase 1.
  static const photoUploadStatusLabels = <String, String>{
    'pending': 'Đang xử lý',
    'uploading': 'Đang tải',
    'success': 'Đã xong',
    'error': 'Lỗi',
  };

  /// "Đã tải lên xong — N/N ảnh" — terminal success summary shown when every
  /// photo in the batch uploaded without errors (AC6). DG-333 Phase 6.
  static String photoUploadComplete(int total) =>
      'Đã tải lên xong — $total/$total ảnh';

  /// "Đã tải lên xong — X/N ảnh (Y lỗi)" — terminal summary shown when the
  /// batch finished but some photos failed (AC6). DG-333 Phase 6.
  static String photoUploadCompleteWithErrors(
    int done,
    int failed,
    int total,
  ) => 'Đã tải lên xong — $done/$total ảnh ($failed lỗi)';

  // ── Markup (trưng bày) ──────────────────────────────────────────────────
  /// "Giá gốc" — the assigned price (base_price or selected chip price) shown
  /// as a non-editable reference in the POS chip picker. DG-296 Phase 3.
  // Knowledge base
  static const knowledgeTitle = 'Sổ tay';
  static const knowledgeBaseDocsSubtitle = 'Công thức, quy trình, nhà cung cấp';
  static const knowledgeBaseNotesSubtitle = 'Ghi chú nội bộ & thông báo';
  static const pinnedSection = '📌 Đã ghim';
  static const pinSuccess = 'Đã ghim';
  static const unpinSuccess = 'Đã bỏ ghim';
  static const pinError = 'Lỗi khi ghim';
  static const pinAfterSave = 'Ghim sau khi lưu';
  static const knowledgeEntry = 'Mục tri thức';
  static const createKnowledge = 'Tạo mục mới';
  static const editKnowledge = 'Sửa mục';
  static const knowledgeTypes = {
    'recipe': 'Công thức',
    'procedure': 'Quy trình',
    'equipment': 'Thiết bị',
    'supplier': 'Nhà cung cấp',
    'reference': 'Tham khảo',
    'note': 'Ghi chú',
  };
  static const addPhoto = 'Thêm ảnh';
  static const noKnowledgeEntries = 'Chưa có mục nào';
  static const searchKnowledge = 'Tìm kiếm sổ tay';
  static const confirmDeleteKnowledge = 'Xóa mục này?';
  static const deleteKnowledge = 'Xóa mục';
  static const knowledgeDeleted = 'Đã xóa mục';
  static const knowledgeSaved = 'Đã lưu mục';
  static const knowledgeCreated = 'Đã tạo mục mới';
  static const knowledgeTitleField = 'Tiêu đề';
  static const knowledgeContentField = 'Nội dung';
  static const knowledgeTypeField = 'Loại';
  static const knowledgeTagsField = 'Nhãn';
  static const knowledgePhotosField = 'Ảnh';
  static const knowledgeNoPhotos = 'Chưa có ảnh';

}
