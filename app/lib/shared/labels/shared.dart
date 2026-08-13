export 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Shared/common Vietnamese labels for the bakery app.
///
/// Per the VN Label Policy in CLAUDE.md and §5 of
/// docs/flutter-coding-standards.md, new user-facing copy that spans multiple
/// domains lives in this file rather than being appended to the monolithic
/// `VN` class. Consumers import this file and use `SharedLabels.*` for new
/// labels or `VN.*` for legacy labels re-exported above.
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
  static const printInternalPrompt =
      'Đơn hàng chưa in phiếu nội bộ. In ngay?';

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

  // Today Sales screen — cash-source breakdown (DG-378 Phase 3 / FR3, AC3)
  //
  // Separate from the "Tổng tiền nhận được" payment group: this breakdown
  // details the composition of cash at the drawer — sales cash (existing
  // `cashTotal`), owner/employee capital injections (`cashInTotal`), owner
  // draws (`cashOutTotal`), and the resulting net cash
  // (`cashTotal + cashInTotal - cashOutTotal`). Labels are intentionally
  // distinct from `VN.cashDrawerTxnTypeCashIn/CashOut` because the breakdown
  // is a summary context, not a per-transaction chip.
  static const todaySalesCashSourceSection = 'Nguồn tiền mặt';
  static const todaySalesCashSourceSalesCash = 'Tiền bán hàng';
  static const todaySalesCashSourceCashIn = 'Nạp vào quầy';
  static const todaySalesCashSourceCashOut = 'Rút khỏi quầy';
  static const todaySalesCashSourceNetCash = 'Tiền mặt ròng';

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
}