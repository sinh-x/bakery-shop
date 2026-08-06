import 'package:flutter/material.dart';

class VN {
  // Navigation
  static const appName = 'Đoàn Gia - Bánh Kem';
  static const tabDashboard = 'Tổng quan';
  static const tabOrders = 'Đơn hàng';
  static const tabProducts = 'Sản phẩm';
  static const tabKnowledgeBase = 'Sổ tay';
  static const tabEvents = 'Sự kiện';
  static const tabChecklist = 'Checklist';

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
  static const actionCancel = 'Hủy';

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
  static const products = 'Sản phẩm';
  static const payment = 'Thanh toán';
  static const paid = 'Đã thanh toán';
  static const partialPaid = 'Trả một phần';
  static const unpaid = 'Chưa thanh toán';
  static const amountPaidLabel = 'Đã trả';
  static const remainingLabel = 'Còn lại';
  static const packingChecklist = 'Danh sách đóng gói';
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
  static const lamMoi = 'Làm mới';

  // Product categories
  static const catBanhMi = 'Bánh mì';
  static const catBanhKem = 'Bánh kem';
  static const catBanhNgot = 'Bánh ngọt';
  static const catCookie = 'Cookie';
  static const catKhac = 'Khác';

  // Category emojis
  static const emojiBanhMi = '🍞';
  static const emojiBanhKem = '🎂';
  static const emojiBanhNgot = '🧁';
  static const emojiCookie = '🍪';
  static const emojiKhac = '🍰';

  // Product code
  static const productCode = 'Mã sản phẩm';

  // Event types
  static const eventNote = 'Ghi chú';
  static const eventOrder = 'Đơn hàng';
  static const eventInventory = 'Kho';
  static const eventProduction = 'Sản xuất';
  static const eventDelivery = 'Giao hàng';
  static const eventExpense = 'Chi phí';

  // Event types (chips)
  static const typeEquipment = 'Đồ điện/Dụng cụ làm bánh';

  // Event log form
  static const eventPrompt = 'Chuyện gì xảy ra?';
  static const eventLogged = 'Đã ghi sự kiện';
  static const loggedBy = 'Người ghi';
  static const changeLogger = 'Đổi';
  static const setYourName = 'Nhập tên của bạn';
  static const addTag = 'Thêm';

  // Event tags
  static const tagIncident = 'Sự cố';
  static const tagKnowledgeGap = 'Thiếu thông tin';
  static const tagMaintenance = 'Bảo trì';
  static const tagEquipment = 'Thiết bị';
  static const tagPricing = 'Giá cả';
  static const tagOrdering = 'Đặt hàng';
  static const tagDecoration = 'Trang trí';
  static const tagStaff = 'Nhân viên';

  // Event history filters (Phase 5)
  static const filterToday = 'Hôm nay';
  static const filterWeek = 'Tuần này';
  static const filterMonth = 'Tháng này';
  static const filterAll = 'Tất cả';
  static const searchEvents = 'Tìm sự kiện...';
  static const noEvents = 'Chưa có sự kiện';

  // Event form
  static const eventType = 'Loại sự kiện';
  static const eventSummary = 'Mô tả sự kiện';
  static const logEvent = 'GHI SỰ KIỆN';
  static const recentEvents = 'Sự kiện gần đây';
  static const createEvent = 'Thêm sự kiện';
  static const editEvent = 'Sửa sự kiện';
  static const deleteEvent = 'Xóa sự kiện';
  static const deleteEventConfirm = 'Bạn có chắc muốn xóa sự kiện này?';
  static const eventDeleted = 'Đã xóa sự kiện';
  static const eventUpdated = 'Đã cập nhật sự kiện';
  static const addOrderIncident = 'Thêm sự cố';
  static const orderLabel = 'Đơn hàng';
  static const eventPhotos = 'Ảnh đính kèm';
  static const addEventPhoto = 'Thêm ảnh';
  static const noEventPhotos = 'Chưa có ảnh';
  static const eventPhotosUploadFailed = 'Đã lưu sự kiện nhưng không tải được ảnh';

  // Dashboard
  static const todayOrders = 'Đơn hàng hôm nay';
  static const upcomingDue = 'Sắp đến hạn';
  static const overdueOrders = 'Quá hạn';
  static const recentActivity = 'Sự kiện gần đây';

  // Packing items
  static const packCandles = 'Nến';
  static const packCutlery = 'Dao/dĩa';
  static const packBox = 'Hộp';
  static const packBase = 'Đế';
  static const packRibbon = 'Ruy-băng';

  // Search
  static const searchOrders = 'Tìm đơn hàng...';

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
  static const createProduct = 'Thêm sản phẩm';
  static const editProduct = 'Sửa sản phẩm';
  static const productName = 'Tên sản phẩm';
  static const productCategory = 'Danh mục';
  static const productPrice = 'Giá bán';
  static const productCost = 'Giá vốn';
  static const productNotes = 'Ghi chú công thức';
  static const priceChips = 'Các mức giá nhanh';
  static const addPriceChip = 'Thêm mức giá';
  static const priceChipLabel = 'Nhãn';
  static const priceChipPrice = 'Giá';
  static const priceChipLabelRequired = 'Nhãn bắt buộc';
  static const priceChipPriceInvalid = 'Giá không hợp lệ';

  // Enum attribute options editor (DG-092 Phase 4.5)
  static const enumOptionsSection = 'Tùy chọn thuộc tính';
  static const enumOptionsHintAttributeWide =
      'Áp dụng cho tất cả sản phẩm dùng thuộc tính này';
  static const addEnumOption = 'Thêm tùy chọn';
  static const enumOptionValueLabel = 'Giá trị';
  static const enumOptionValueRequired = 'Giá trị không được để trống';
  static const enumOptionDefaultLabel = 'Mặc định';
  static const enumOptionDefaultRequired = 'Phải chọn một giá trị mặc định';
  static const enumOptionRestore = 'Khôi phục';
  static const enumOptionRemoved = 'Đã đánh dấu xoá';
  static const priceFrom = 'từ';
  static const productPhoto = 'Ảnh sản phẩm';
  static const choosePhoto = 'Chọn ảnh';
  static const takePhoto = 'Chụp ảnh';
  static const fromGallery = 'Chọn từ thư viện';
  static const deleteProduct = 'Xóa sản phẩm';
  static const deleteConfirm = 'Bạn có chắc muốn xóa sản phẩm này?';
  static const productCreated = 'Đã thêm sản phẩm';
  static const productUpdated = 'Đã cập nhật sản phẩm';
  static const productDeleted = 'Đã xóa sản phẩm';
  static const fieldRequired = 'Không được để trống';
  static const invalidPrice = 'Giá không hợp lệ';
  static const loading = 'Đang tải...';
  static const errorLoading = 'Không thể tải dữ liệu';
  static const retry = 'Thử lại';
  static const noProducts = 'Không có sản phẩm';
  static const hiddenProducts = 'Sản phẩm đã ẩn';
  static const productHiddenState = 'Đang ẩn';
  static const showProduct = 'Hiện sản phẩm';
  static const apiError = 'Không thể kết nối máy chủ';
  static const apiTimeout = 'Kết nối máy chủ quá thời gian, vui lòng thử lại';

  // RBAC / UI gating
  static const accessDeniedTitle = 'Không có quyền truy cập';
  static const accessDeniedBody =
      'Chỉ quản trị viên mới được sử dụng tính năng này.';

  // Category management
  static const manageCategories = 'Quản lý danh mục';
  static const addCategory = 'Thêm danh mục';
  static const editCategory = 'Sửa danh mục';
  static const categoryName = 'Tên danh mục';
  static const codePrefix = 'Mã viết tắt';
  static const codePrefixHint = 'VD: BMI, BKS';
  static const codePrefixHelp = '2-4 ký tự in hoa, dùng tạo mã sản phẩm';
  static const categorySlug = 'Slug';
  static const deactivateCategory = 'Ẩn danh mục';
  static const reactivateCategory = 'Hiện danh mục';
  static const deactivateConfirm =
      'Ẩn danh mục? Sản phẩm vẫn còn nhưng tab sẽ bị ẩn.';
  static const hiddenCategories = 'Đã ẩn';
  static const categoryCreated = 'Đã thêm danh mục';
  static const categoryUpdated = 'Đã cập nhật danh mục';
  static const categoryDeactivated = 'Đã ẩn danh mục';
  static const categoryReactivated = 'Đã hiện danh mục';
  static const noPrefixError = 'Mã viết tắt không được để trống';
  static const prefixFormatError = 'Mã viết tắt phải 2-4 ký tự in hoa';
  static const categoryIcon = 'Biểu tượng';
  static const categoryVisibility = 'Trạng thái hiển thị';
  static const categoryVisible = 'Đang hiện';
  static const categoryHiddenState = 'Đang ẩn';
  static const orderUpdated = 'Đã cập nhật thứ tự';

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

  // Delivery types (detailed)
  static const deliveryBus = 'Giao xe khách';
  static const deliveryDoor = 'Giao tận nơi';

  // Order create form extras
  static const orderSource = 'Nguồn đặt hàng';
  static const deliveryAssignee = 'Nhân viên giao hàng';
  static const sourceTaiTiem = 'Tại Tiệm';
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

  static const useInventory = 'Dùng tồn kho';
  static const stockRemaining = 'Còn';
  static const stockUnknown = 'Chưa có số tồn';
  static const orderCreated = 'Đã tạo đơn hàng';
  static const searchProducts = 'Tìm sản phẩm...';

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
  static String uploadedPhotosCount(int done, int total) => '$done/$total đã tải lên';

  /// "X/N đã tải lên (Y lỗi)" — count summary shown when any photo has failed.
  /// DG-333 Phase 1.
  static String uploadedPhotosCountWithErrors(int done, int failed, int total) =>
      '$done/$total đã tải lên ($failed lỗi)';

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
    'pending': 'Đang chờ',
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
          int done, int failed, int total) =>
      'Đã tải lên xong — $done/$total ảnh ($failed lỗi)';

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
  static const catalogTitle = 'Bộ sưu tập';
  static const addCatalogPhoto = 'Thêm ảnh mẫu';
  static const editCatalogPhoto = 'Sửa ảnh';
  static const deleteCatalogPhoto = 'Xóa ảnh';
  static const deleteCatalogConfirm = 'Bạn có chắc muốn xóa ảnh này?';
  static const captionLabel = 'Mô tả';
  static const tagsLabel = 'Nhãn';
  static const tagsHint = 'VD: hoa, hồng, sinh nhật';
  static const noCatalogPhotos = 'Chưa có ảnh mẫu';
  static const catalogPhotoAdded = 'Đã thêm ảnh mẫu';
  static const catalogPhotoUpdated = 'Đã cập nhật ảnh';
  static const catalogPhotoDeleted = 'Đã xóa ảnh';
  static const setAsProductPhoto = 'Đặt làm ảnh sản phẩm';
  static const productPhotoSetFromCatalog = 'Đã đặt ảnh sản phẩm từ ảnh mẫu';

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
  static String workItemSummaryCount(int count) => '$count $workItemSummaryUnit';

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

  // General
  static const remove = 'Xóa';
  static const save = 'Lưu';
  static const cancel = 'Hủy';
  static const back = 'Quay lại';
  static const dong = 'Đóng';
  static const currency = 'đ';

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
  // Short labels for card/status indicators
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

  // Printer picker
  static const selectPrinter = 'Chọn máy in';
  static const scanning = 'Đang tìm...';
  static const noPrinterFound = 'Không tìm thấy máy in';
  static const printerConnectionFailed = 'Kết nối thất bại';
  static const connectingTo = 'Đang kết nối đến...';
  static const tapToRetry = 'Bấm để thử lại';
  static const noDevicesFound = 'Không có thiết bị nào';

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
  static const trungBay = 'Trưng bày';
  static const tangKem = 'Tặng kèm';

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
  static const knowledgeTitle = 'Sổ tay';
  static const knowledgeBaseEventsSubtitle = 'Ghi nhật ký hoạt động & sự cố';
  static const knowledgeBaseExpensesSubtitle =
      'Ghi chi phí vận hành theo khoản mục';
  static const knowledgeBaseChecklistSubtitle = 'Công việc mở / đóng tiệm';
  static const knowledgeBaseDocsSubtitle = 'Công thức, quy trình, nhà cung cấp';
  static const knowledgeBaseNotesSubtitle = 'Ghi chú nội bộ & thông báo';
  static const knowledgeBaseCashDrawerSubtitle = 'Quỹ tiền mặt hàng ngày & chênh lệch';
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

  // Expenses
  static const expenseTitle = 'Chi phí';
  static const expenseFormSection = 'Nhập chi phí';
  static const expenseHistorySection = 'Lịch sử chi phí';
  static const expenseAmountLabel = 'Số tiền (VND)';
  static const expenseCategoryLabel = 'Danh mục chi phí';
  static const expenseCategoryHint = 'Chọn danh mục chi phí';
  static const expensePaymentMethodLabel = 'Phương thức thanh toán';
  static const expenseVendorLabel = 'Nhà cung cấp';
  static const expenseNoteLabel = 'Ghi chú';
  static const expenseStaffNameLabel = 'Nhân viên';
  static const expensePaidByNameLabel = 'Người chi trả';
  static const expenseLoggedByLabel = 'Người ghi nhận';
  static const expenseCategoryIngredient = 'Nguyên liệu';
  static const expenseCategoryPackaging = 'Bao bì';
  static const expenseCategoryDelivery = 'Vận chuyển';
  static const expenseCategoryUtilities = 'Điện/nước';
  static const expenseCategoryTools = 'Dụng cụ';
  static const expenseCategoryRepair = 'Sửa chữa';
  static const expenseCategorySalaryAllowance = 'Lương/phụ cấp';
  static const expenseCategoryOther = 'Khác';

  // Expense subcategories (DG-302 Phase 3) — Nguyên liệu & Bao bì
  static const expenseSubcategoryEggs = 'Trứng';
  static const expenseSubcategoryCream = 'Kem';
  static const expenseSubcategoryFlour = 'Bột';
  static const expenseSubcategoryOtherAdditives = 'Phụ gia khác';
  static const expenseSubcategoryFruits = 'Trái cây';
  static const expenseSubcategoryBoxAndBase = 'Hộp & đế';
  static const expenseSubcategoryAccessories = 'Phụ kiện';
  static const expenseSubcategoryWrap = 'Bọc nilon';

  // Expense subcategory form / report labels
  static const expenseSubcategoryLabel = 'Danh mục con';
  static const expenseSubcategoryHint = 'Chọn danh mục con';
  static const expenseSubcategoryNone = '—';
  static const expenseSaveAction = 'Lưu chi phí';
  static const expenseAddAction = 'Thêm chi phí';
  static const expenseUpdateAction = 'Cập nhật chi phí';
  static const expenseCancelEditAction = 'Hủy sửa';
  static const expenseApplyFiltersAction = 'Áp dụng lọc';
  static const expenseResetFiltersAction = 'Xóa lọc';
  static const expenseSearchLabel =
      'Tìm theo nội dung, nhà cung cấp, người ghi, người trả';
  static const expenseSinceLabel = 'Từ ngày';
  static const expenseUntilLabel = 'Đến ngày';
  static const expenseDateLabel = 'Ngày chi';
  static const expenseTimeLabel = 'Giờ chi';
  static const expenseNoHistory = 'Chưa có chi phí phù hợp bộ lọc';
  static const expenseAmountValidationMessage =
      'Số tiền phải là số nguyên VND lớn hơn 0';
  static const expenseStaffNameRequiredForAdvance =
      'Tên nhân viên là bắt buộc khi chọn Nhân viên ứng trước';
  static const expensePayerConfirmTitle = 'Xác nhận người chi trả';
  static const expensePayerConfirmPrompt =
      'Bạn chưa chọn Người chi trả. Dùng tên nhân viên làm người chi trả?';
  static const expensePayerUseStaff = 'Dùng tên nhân viên';
  static const expensePayerEnterCustom = 'Nhập tên khác';
  static const expensePayerCustomHint = 'Nhập tên người chi trả';
  static const expenseEmptyStaffWarning =
      'Vui lòng cài đặt tên nhân viên trong Cài đặt trước khi nhập chi phí.';

  // Payment sources
  static const expensePaymentSourceLabel = 'Nguồn tiền chi';
  static const paymentSourceDrawerCash = 'Tiền mặt tại quầy';
  static const paymentSourceOwnerCash = 'Tiền mặt chủ sở hữu';
  static const paymentSourcePhuongVCB = 'TK Phượng VCB';
  static const paymentSourceAnVCB = 'TK Ân VCB';
  static const paymentSourceStaffAdvance = 'Nhân viên ứng trước';

  // Target bank account selector for payment transactions (DG-244 Phase 2)
  static const paymentTargetAccountLabel = 'TK đích';
  static const paymentNoAccount = 'Chưa chọn';

  // Reimbursed
  static const reimbursedYes = 'Đã hoàn lại';
  static const reimbursedNo = 'Chưa hoàn lại';

  // Expense debt status (DG-212 Phase 3)
  static const debtStatusUnpaid = 'Chưa trả';
  static const debtStatusPaid = 'Đã trả';
  static const debtStatusPartial = 'Trả một phần';
  static const expenseCreditorLabel = 'Chủ nợ';
  static const expenseVendorAutocompleteHint = 'Chọn từ nhà cung cấp đã dùng';
  static const expenseDebtVendorRequired = 'Chủ nợ là bắt buộc khi chọn phương thức Nợ';

  // Debt list / settlement screens (DG-212 Phase 4)
  static const debtListTitle = 'Danh sách công nợ';
  static const debtListEmpty = 'Chưa có công nợ nào';
  static const debtListTotalOwed = 'Tổng còn nợ';
  static const debtListFilterStatusLabel = 'Trạng thái';
  static const debtListFilterAll = 'Tất cả';
  static const debtListCreditorTotal = 'Tổng nợ';
  static const debtListDebtCount = 'Số khoản nợ';
  static const debtListItemAmount = 'Tiền nợ';
  static const debtListItemSettled = 'Đã trả';
  static const debtListItemRemaining = 'Còn lại';
  static const debtListOpenSettlement = 'Thanh toán';
  static const debtListLoadError = 'Không tải được danh sách công nợ';

  // Debt settlement screen
  static const debtSettlementTitle = 'Thanh toán công nợ';
  static const debtSettlementAmountLabel = 'Số tiền thanh toán';
  static const debtSettlementAmountHint = 'Nhập số VND cần thanh toán';
  static const debtSettlementPaymentMethodLabel = 'Phương thức thanh toán';
  static const debtSettlementPaymentSourceLabel = 'Nguồn tiền';
  static const debtSettlementNoteLabel = 'Ghi chú';
  static const debtSettlementNoteHint = 'Ghi chú thanh toán (tùy chọn)';
  static const debtSettlementSaveAction = 'Xác nhận thanh toán';
  static const debtSettlementAmountRequired = 'Vui lòng nhập số tiền thanh toán';
  static const debtSettlementAmountInvalid = 'Số tiền không hợp lệ';
  static const debtSettlementAmountExceedsRemaining =
      'Số thanh toán vượt quá nợ còn lại';
  static const debtSettlementPaymentSourceRequired = 'Nguồn tiền là bắt buộc';
  static const debtSettlementSuccess = 'Đã thanh toán công nợ';
  static const debtSettlementFailure = 'Thanh toán công nợ thất bại';
  static const debtSettlementRemainingLabel = 'Còn lại sau thanh toán';
  static const debtSettlementSummary = 'Thông tin công nợ';
  static const debtSettlementCreditor = 'Chủ nợ';
  static const debtSettlementTotalDebt = 'Tổng nợ ban đầu';
  static const debtSettlementSettledSoFar = 'Đã thanh toán';

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

  // Catalog browse
  static const browseScreenTitle = 'Duyệt ảnh mẫu';
  static const doiTuong = 'Đối tượng';
  static const dip = 'Dịp';
  static const phongCach = 'Phong cách';
  static const filterHint = 'Chọn thẻ để lọc';
  static const noBrowsePhotos = 'Chưa có ảnh mẫu';
  static const noBrowsePhotosForFilter = 'Không có ảnh phù hợp bộ lọc';
  static const xoaLoc = 'Xoá lọc';
  static const catalogFilterLoadError = 'Không tải được bộ lọc ảnh';
  static const categoryLoadError = 'Không tải được danh mục sản phẩm';

  // POS stock labels
  static const stockNotUpdated = 'Chưa cập nhật kho';
  static String stockUpdatedAt(String hhmm) => 'Cập nhật kho: $hhmm';
  static String availableStock(int qty) => 'Còn $qty';
  static String lowStock(int qty) => 'Sắp hết ($qty)';
  static String categorySectionCount(int count) => '$count mặt hàng';
  static String fingerprintMismatchStrip(String client, String server) {
    return '$fingerprintMismatchWarning ($client/$server)';
  }

  static const outOfStock = 'Hết hàng';

  // Negative stock display (DG-200 Phase 5, FR-8, AC-10)
  /// Label for products with a negative net stock position.
  /// `Âm N` reads as `Âm <N>` where N is the absolute quantity.
  static String negativeStockLabel(int qty) {
    assert(qty < 0, 'negativeStockLabel expects a negative quantity');
    return 'Âm ${qty.abs()}';
  }
  static const negativeStockLabelPrefix = 'Âm';

  // Stock management
  static const quanLyTonKho = 'Quản lý tồn kho';
  static const nhapHang = 'Nhập hàng';
  static const haoHut = 'Hao hụt';
  static const dieuChinh = 'Điều chỉnh';
  static const tonKho = 'Tồn kho';
  static const nhapHangSheet = 'Nhập hàng';
  static const haoHutSheet = 'Hao hụt';
  static const dieuChinhSheet = 'Điều chỉnh';
  static const tuyChonGia = 'Tùy chọn giá';
  static const tuyChon = 'Tùy chọn';
  static const ghiChuLabel = 'Ghi chú';
  static const ghiChuHint = 'Ghi chú (tùy chọn)';
  static const lyDoLabel = 'Lý do';
  static const lyDoHint = 'Nhập lý do...';
  static const lyDoRequired = 'Lý do không được để trống';
  static const soLuongInvalid = 'Số lượng phải lớn hơn 0';
  static const xacNhanHaoHut = 'Xác nhận hao hụt';
  static const xacNhanDieuChinh = 'Điều chỉnh';
  static const xacNhanNhapHang = 'Nhập hàng';
  static const khongCoSanPhamTonKho = 'Không có sản phẩm tồn kho';
  static const capNhatThanhCong = 'Cập nhật thành công';
  static const loiHeThong = 'Lỗi hệ thống';
  static const doiSoatTonKhoHomNay = 'Đối soát tồn kho hôm nay';
  static const showOutOfStockProducts = 'Hiển thị sản phẩm hết hàng';
  static const nhanVien = 'Nhân viên';
  static const ngayDoiSoat = 'Ngày đối soát';
  static const tonDuKien = 'Tồn dự kiến';
  static const giaCoSo = 'Giá cơ sở';
  static const tonDaDem = 'Tồn đã đếm';
  static const soLuongThieu = 'Số lượng thiếu';
  static const soLuongBan = 'Số lượng bán';
  static const soLuongHaoHut = 'Số lượng hao hụt';
  static const donGiaNhapTay = 'Đơn giá nhập tay';
  static const phuongThucThanhToan = 'Phương thức thanh toán';
  static const chonPhuongThucThanhToan = 'Vui lòng chọn phương thức thanh toán';
  static const lyDoHaoHut = 'Lý do hao hụt';
  static const guiDoiSoat = 'Gửi đối soát';
  static const dangGuiDoiSoat = 'Đang gửi đối soát...';
  static const xacNhanGuiDoiSoat = 'Xác nhận gửi đối soát';
  static const tongSoLuongBan = 'Tổng số lượng bán';
  static const tongSoLuongHaoHut = 'Tổng số lượng hao hụt';
  static const vanDeCanXuLyTruocKhiGui = 'Vấn đề cần xử lý trước khi gửi';
  static const daSanSangGuiDoiSoat = 'Dữ liệu hợp lệ. Có thể gửi đối soát.';
  static const daTatGuiDoiSoatKhiCoLoi =
      'Nút gửi tạm khóa cho đến khi xử lý hết lỗi.';
  static const doiSoatThanhCong = 'Đã lưu đối soát thành công';
  static const doiSoatThatBai = 'Gửi đối soát thất bại';
  static const khongTheTaiDuLieuDoiSoat = 'Không thể tải dữ liệu đối soát';
  static const huongDanTaiLaiDoiSoat =
      'Kiểm tra kết nối mạng rồi bấm tải lại để thử lại bản nháp.';
  static const khongCoSanPhamTrungBay =
      'Không có sản phẩm trưng bày cần đối soát';
  static const huongDanKhongCoSanPhamTrungBay =
      'Nếu hôm nay có sản phẩm, hãy tải lại để đồng bộ dữ liệu mới nhất.';
  static const chuaChonNhanVien = 'Chưa chọn nhân viên';
  static const lichSuDoiSoatTonKho = 'Lịch sử đối soát tồn kho';
  static const xemLichSu = 'Xem lịch sử';
  static const trangThai = 'Trạng thái';
  static const trangThaiOn = 'Ổn';
  static const trangThaiCoLoi = 'Có lỗi';
  static const themDongBan = 'Thêm dòng bán';
  static const soLuongChenhLech = 'Số lượng chênh lệch';
  static const sua = 'Sửa';

  // Reconciliation surplus / restock inflow (DG-200 Phase 6, FR-9, AC-11)
  /// Label for the surplus inflow quantity (counted - expected, when > 0).
  /// Reads as `Số lượng bù: +N`.
  static const soLuongBu = 'Số lượng bù';
  /// Restock indicator title shown next to a surplus option.
  static const nhapBuTonKho = 'Nhập bù tồn kho';
  /// Hint explaining that surplus will auto-create a restock inflow.
  static const nhapBuHint = 'Số dư sẽ tự nhập bù vào kho khi gửi đối soát';
  static const dongBan = 'Dòng bán';
  static const nhanChip = 'Nhãn chip';
  static const giam = 'Giảm';
  static const tang = 'Tăng';
  static const chuaCoLichSuDoiSoat = 'Chưa có lịch sử đối soát';
  static const khongTaiDuocLichSuDoiSoat = 'Không tải được lịch sử đối soát';
  static const chiTietDoiSoat = 'Chi tiết đối soát';
  static const khongTaiDuocChiTietDoiSoat = 'Không tải được chi tiết đối soát';
  static const soDong = 'Số dòng';
  static const thamChieuDonHang = 'Tham chiếu đơn hàng';
  static const thamChieuThanhToan = 'Tham chiếu thanh toán';
  static const thamChieuDongDonHang = 'Tham chiếu dòng đơn hàng';
  static const thamChieuXuatBan = 'Tham chiếu xuất bán';
  static const thamChieuXuatHaoHut = 'Tham chiếu xuất hao hụt';
  static const khongCo = 'Không có';

  // Reconciliation history detail summary card (DG-155 Phase 4.3)
  static const tongTonDuKien = 'Tổng tồn dự kiến';
  static const tongTonDaDem = 'Tổng tồn đã đếm';
  static const tongSoLuongSanPham = 'Số sản phẩm';
  static const tongSoDong = 'Tổng số dòng';
  static const tongChenhLech = 'Tổng chênh lệch';
  static const khongPhanLoai = 'Không phân loại';
  static const soDongBan = 'Số dòng bán';
  static const dongBanCu = 'Dòng bán cũ';

  // Catalog browse
  static const danhMuc = 'Danh mục';

  // Catalog photo viewer
  static const daLuuAnh = 'Đã lưu ảnh';
  static const taiAnh = 'Tải ảnh';
  static const chiaSe = 'Chia sẻ';
  static const daSaoChepNoiDung = 'Đã sao chép nội dung vào clipboard';
  static const saoChepNoiDungThatBai =
      'Không thể sao chép nội dung vào clipboard';
  static const taiMotPhanAnh = 'Đã tải một phần ảnh';
  static const taiNAnh = 'Đã tải {count} ảnh';
  static const khongTheTaiAnh = 'Không thể tải ảnh';
  static const khongTheChiaSe = 'Không thể chia sẻ';

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
  static const customerSharedPhoneHint =
      'Khách hàng khác dùng chung số này:';
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
  static const customerSearchRefineHint =
      'Nhập thêm để thu hẹp kết quả';

  // Customer form multi-phone (DG-205 Phase 5)
  static const customerAddPhone = 'Thêm số điện thoại';
  static const customerRemovePhone = 'Xóa số này';
  static const customerPrimaryPhone = 'Số chính';
  static const customerPhoneRequired = 'Cần ít nhất một số điện thoại';
  static const customerPhonePrimaryRequired = 'Chọn một số làm số chính';
  static const customerPhoneDuplicate = 'Số điện thoại bị trùng';

  // Accounting
  static const accountingTitle = 'Kế toán';
  static const accountingTabAccounts = 'Tài khoản';
  static const accountingTabJournal = 'Sổ nhật ký';
  static const accountingTabBalances = 'Số dư';
  static const accountingLockJournal = 'Khóa sổ';
  static const accountingLockConfirm = 'Khóa tất cả bút toán trong khoảng này?';
  static const accountingLockSuccess = 'Đã khóa sổ';
  static const accountingFilterSince = 'Từ ngày';
  static const accountingFilterUntil = 'Đến ngày';
  static const accountingFilterAccount = 'Tài khoản';
  static const accountingFilterSourceType = 'Loại giao dịch';
  static const accountingNoEntries = 'Không có bút toán nào';
  static const accountingDebit = 'Nợ';
  static const accountingCredit = 'Có';
  static const accountingBalance = 'Số dư';
  static const accountingOwnerCapital = 'Vốn chủ sở hữu vào';
  static const accountingOwnerDraw = 'Rút vốn';
  static const accountingStaffReimburse = 'Hoàn ứng';
  static const accountingLocked = 'Đã khóa';
  static const accountingUnlocked = 'Chưa khóa';
  static const accountingLoadMore = 'Tải thêm';
  static const accountingNoAccounts = 'Không có tài khoản';
  static const accountingNoBalances = 'Không có số dư';
  static const accountingSourceTypeAll = 'Tất cả';
  static const accountingSourceTypeExpense = 'Chi phí';
  static const accountingSourceTypePayment = 'Thanh toán';
  static const accountingSourceTypeOrder = 'Đơn hàng';
  static const accountingSourceTypeCogs = 'Giá vốn';
  static const accountingSourceTypeShippingHold = 'Ship bus giữ hộ';
  static const accountingSourceTypeShippingRelease = 'Trả ship bus';

  // Cash drawer (DG-324) — labels for the daily cash drawer feature.
  // Kept alongside the accounting source-type labels because the drawer
  // source types extend the journal source-type vocabulary below.
  static const cashDrawerTitle = 'Tiền tại quầy';
  static const cashDrawerOpen = 'Mở quầy';
  static const cashDrawerClose = 'Đóng quầy';
  static const cashDrawerCashIn = 'Cho tiền vào quầy';
  static const cashDrawerCashOut = 'Lấy tiền khỏi quầy';
  static const cashDrawerOpeningBalance = 'Số dư đầu ngày';
  // DG-347 Phase 5: closing balance surfaced on closed drawer history rows.
  static const cashDrawerClosingBalance = 'Số dư cuối ngày';
  static const cashDrawerExpectedBalance = 'Số dư dự kiến';
  static const cashDrawerCountedAmount = 'Số tiền đếm được';
  static const cashDrawerDiscrepancy = 'Chênh lệch';
  static const cashDrawerStatus = 'Trạng thái';
  static const cashDrawerStatusOpen = 'Đang mở';
  static const cashDrawerStatusClosed = 'Đã đóng';
  // DG-347 Phase 5: removed per-accumulator labels (cashDrawerCashSales,
  // cashDrawerTienRutIn/Out, cashDrawerOwnerIn/Out, cashDrawerCashExpenses)
  // — the status card no longer shows an accumulator breakdown.
  static const cashDrawerHistory = 'Lịch sử quầy';
  static const cashDrawerNoActive = 'Không có quầy tiền mặt đang mở';
  static const cashDrawerAlreadyOpen = 'Đã có quầy tiền mặt đang mở — phải đóng quầy hiện tại trước khi mở quầy mới.';
  static const cashDrawerAmountLabel = 'Số tiền (VND)';
  static const cashDrawerNoteLabel = 'Ghi chú (tùy chọn)';
  static const cashDrawerOpenSuccess = 'Đã mở quầy tiền mặt';
  static const cashDrawerCloseSuccess = 'Đã đóng quầy tiền mặt';
  static const cashDrawerCashInSuccess = 'Đã cho tiền vào quầy';
  static const cashDrawerCashOutSuccess = 'Đã lấy tiền khỏi quầy';
  static const cashDrawerSurplus = 'Thừa';
  static const cashDrawerShortage = 'Thiếu';
  static const cashDrawerExact = 'Khớp';

  /// FR9 carry-over proposal dialog labels.
  static const cashDrawerCarryOverTitle = 'Mang số dư sang hôm nay';
  static const cashDrawerCarryOverPrompt =
      'Quỹ hôm qua chưa đóng. Số dư dự kiến';
  static const cashDrawerCarryOverQuestion =
      'Bạn có muốn mang sang hôm nay không?';
  static const cashDrawerCarryOverAccept = 'Mang sang';
  static const cashDrawerCarryOverDecline = 'Không mang sang';

  /// DG-330: transfer proposal when opening balance < 1101 reference.
  static const cashDrawerTransferTitle = 'Chuyển tiền thừa vào quầy chủ';
  static const cashDrawerTransferQuestion =
      'Bạn có muốn chuyển số tiền thừa vào Tiền mặt chủ sở hữu?';
  static const cashDrawerTransferAccept = 'Chuyển';
  static const cashDrawerTransferDeclineBlocked =
      'Không thể mở quầy khi có chênh lệch âm chưa giải trình. '
      'Vui lòng chọn "Chuyển" hoặc liên hệ Kế toán.';

  /// DG-330: stock reconciliation confirmation when opening balance > 1101.
  static const cashDrawerStockReconTitle = 'Đối chiếu kho hàng';
  static const cashDrawerStockReconQuestion =
      'Bạn đã đối chiếu kho hàng POS chưa? Tiền thừa đến từ bán hàng?';
  static const cashDrawerStockReconAccept = 'Bán hàng';
  static const cashDrawerStockReconDecline = 'Chưa';
  static const cashDrawerExcessOwnerCapital = 'Chủ cho thêm vốn';

  /// DG-330: unidentified sale option after stock reconciliation.
  static const cashDrawerUnidentifiedSaleTitle = 'Doanh thu chưa xác định';
  static const cashDrawerUnidentifiedSaleQuestion =
      'Ghi nhận thành doanh thu chưa xác định với 50% giá vốn để dễ truy vết sau này?';
  static const cashDrawerUnidentifiedSaleAccept = 'Ghi nhận';
  static const cashDrawerUnidentifiedSaleDecline = 'Bỏ qua';

  /// DG-330: reference balance label in open dialog.
  static const cashDrawerReferenceBalance = 'Số dư kế toán 1101';

  /// DG-331 FR9: label for the previous close counted amount shown in the
  /// open dialog as a second reference point ("Số dư sau khi đóng quầy lần
  /// trước"). Follows the 1101 reference balance line.
  static const cashDrawerPreviousCloseBalance = 'Số dư sau khi đóng quầy lần trước';

  /// Phase 4.1 F5/F6: "current balance" helper shown in the cash-in and
  /// cash-out dialogs so the owner knows how much is already in the drawer.
  static const cashDrawerCurrentBalance = 'Số dư hiện tại';

  /// DG-331: close surplus confirmation dialog labels. Shown when closing
  /// the drawer with counted > expected and the surplus has not yet been
  /// confirmed.
  static const cashDrawerCloseSurplusTitle = 'Xác nhận chênh lệch thừa';
  static const cashDrawerCloseSurplusQuestion =
      'Số tiền đếm được lớn hơn số dư dự kiến. Chủ thêm tiền mặt hay ghi nhận doanh thu chưa xác định?';
  static const cashDrawerCloseSurplusOwnerCash = 'Chủ thêm tiền mặt';
  static const cashDrawerCloseSurplusUnidentifiedSale = 'Doanh thu chưa xác định';

  /// DG-331: close shortage confirmation dialog labels. Shown when closing
  /// the drawer with counted < expected and the shortage has not yet been
  /// confirmed.
  static const cashDrawerCloseShortageTitle = 'Xác nhận chênh lệch thiếu';
  static const cashDrawerCloseShortageQuestion =
      'Số tiền đếm được nhỏ hơn số dư dự kiến. Chủ rút tiền hay ghi nhận lỗ vốn chủ sở hữu?';
  static const cashDrawerCloseShortageOwnerWithdraw = 'Chủ rút tiền';
  static const cashDrawerCloseShortageEquityLoss = 'Lỗ vốn chủ sở hữu';

  /// DG-360 CQ-6: open-flow variants of the surplus/shortage confirmation
  /// dialogs. The close flow uses "Số dư dự kiến"/"Số tiền đếm được"; the
  /// open flow (reusing the same dialog) shows the 1101 accounting reference
  /// and the entered opening amount instead.
  static const cashDrawerOpenSurplusTitle = 'Xác nhận chênh lệch thừa khi mở quầy';
  static const cashDrawerOpenSurplusReferenceLabel = 'Số dư kế toán 1101';
  static const cashDrawerOpenSurplusOpeningLabel = 'Số tiền mở quầy';
  static const cashDrawerOpenSurplusQuestion =
      'Số tiền mở quầy lớn hơn số dư kế toán 1101. Chủ thêm tiền mặt hay ghi nhận doanh thu chưa xác định?';

  static const cashDrawerOpenShortageTitle = 'Xác nhận chênh lệch thiếu khi mở quầy';
  static const cashDrawerOpenShortageReferenceLabel = 'Số dư kế toán 1101';
  static const cashDrawerOpenShortageOpeningLabel = 'Số tiền mở quầy';
  static const cashDrawerOpenShortageQuestion =
      'Số tiền mở quầy nhỏ hơn số dư kế toán 1101. Chủ rút tiền hay ghi nhận lỗ vốn chủ sở hữu?';

  /// Cash-in source / cash-out destination dropdown labels (DG-330 Phase 8).
  static const cashDrawerSourceLabel = 'Nguồn tiền vào';
  static const cashDrawerDestinationLabel = 'Đích tiền ra';
  static const cashDrawerSourceOwner = 'Tiền mặt chủ sở hữu';
  static const cashDrawerSourceEmployee = 'Nhân viên';
  static const cashDrawerSourceEquity = 'Vốn chủ sở hữu';
  static const cashDrawerDestinationOwner = 'Tiền mặt chủ sở hữu';
  static const cashDrawerDestinationEmployee = 'Nhân viên ứng trước';
  static const cashDrawerStaffPickerLabel = 'Chọn nhân viên';
  static const cashDrawerStaffPickerHint = 'Chọn nhân viên';
  static const cashDrawerStaffRequired = 'Vui lòng chọn nhân viên';

  /// Cash-drawer journal source types (extend the accounting source-type
  /// vocabulary) — used by the journal filter and drawer movement history.
  static const accountingSourceTypeCashDrawerOpen = 'Mở quầy tiền mặt';
  static const accountingSourceTypeCashDrawerCashIn = 'Cho tiền vào quầy';
  static const accountingSourceTypeCashDrawerCashOut = 'Lấy tiền khỏi quầy';
  static const accountingSourceTypeCashDrawerCloseAdjust = 'Đóng quầy — điều chỉnh chênh lệch';

  // ── Cash-drawer transaction history tab (DG-343 Phase 3) ────────────────
  /// "Chi tiết giao dịch" — the 3rd tab on the cash drawer screen (FR3).
  /// Shows the per-transaction detail list for the active or a closed drawer.
  static const cashDrawerTransactionsTab = 'Chi tiết giao dịch';

  /// Short transaction-type labels used in the per-transaction list (AC3).
  /// These are intentionally shorter than the journal `source_type` labels
  /// because each row already carries the amount, timestamp, and note — the
  /// type label is a one-word chip, not a full sentence.
  ///
  /// Mapping (journal `source_type` → short VN label):
  ///   cash_drawer_open          → Mở quầy
  ///   cash_drawer_cash_in       → Nạp tiền
  ///   cash_drawer_cash_out      → Rút tiền
  ///   payment_transaction       → Bán hàng
  ///   expense                   → Chi phí
  ///   cash_drawer_close_adjust  → Đóng quầy
  ///
  /// `owner_capital`, `owner_draw`, and `staff_reimburse` flow through the
  /// cash-in / cash-out source types in the drawer transaction list (the
  /// backend links the underlying journal entry, not the capital/draw
  /// adjustment), so they don't need a dedicated short label here. Unknown
  /// source types fall back to the raw string so the row stays visible.
  static const cashDrawerTxnTypeOpen = 'Mở quầy';
  static const cashDrawerTxnTypeCashIn = 'Nạp tiền';
  static const cashDrawerTxnTypeCashOut = 'Rút tiền';
  static const cashDrawerTxnTypeSale = 'Bán hàng';
  static const cashDrawerTxnTypeExpense = 'Chi phí';
  static const cashDrawerTxnTypeClose = 'Đóng quầy';
  // DG-363 Phase 3 (FR1): two new categories for the 2-group breakdown.
  /// "Hoàn tiền" — customer refund (payment_transaction with amount < 0).
  static const cashDrawerTxnTypeRefund = 'Hoàn tiền';
  /// "Phí ship bus" — bus-shipping portion split out of a payment inflow.
  static const cashDrawerTxnTypeBusShipping = 'Phí ship bus';

  // ── Cash-drawer breakdown card (DG-359 Phase 1, DG-363 Phase 3) ────────
  /// Section title for the categorized in/out breakdown shown inside the
  /// active-drawer status card. Sits directly under the opening-balance row.
  static const cashDrawerBreakdownTitle = 'Phân tích tiền vào/ra';

  // DG-363 Phase 3 (FR1): 2-group structure headers.
  /// "Tiền vào" — header for the inflow group (Bán hàng, Nạp tiền, Mở quầy).
  static const cashDrawerBreakdownInflowGroup = 'Tiền vào';
  /// "Tiền ra" — header for the outflow group (Hoàn tiền, Chi phí, Rút tiền,
  /// Phí ship bus, Đóng quầy).
  static const cashDrawerBreakdownOutflowGroup = 'Tiền ra';

  /// Total row labels — the breakdown card footer summarises the category
  /// rows. "Tổng tiền vào" sums inflows; "Tổng tiền ra" sums outflows; their
  /// difference reconciles to the expected balance (FR3/AC3).
  static const cashDrawerBreakdownTotalIn = 'Tổng tiền vào';
  static const cashDrawerBreakdownTotalOut = 'Tổng tiền ra';

  /// "Số dư dự kiến" — the reconciled inflow − outflow total shown at the
  /// bottom of the breakdown card. Should match the status card's expected
  /// balance (FR3/AC3).
  static const cashDrawerBreakdownExpected = 'Số dư dự kiến';

  /// Count column header for the per-category transaction count.
  static const cashDrawerBreakdownCount = 'SL';

  /// DG-363 Phase 4 / FR7: placeholder shown in place of the breakdown card
  /// for closed drawers that have no persisted snapshot (e.g. drawers closed
  /// before the v097 migration backfilled snapshots). The requirements doc
  /// specifies an "N/A" / "Dữ liệu không có sẵn" display for this case.
  static const cashDrawerBreakdownSnapshotNa = 'Dữ liệu không có sẵn';

  /// Map a cash-drawer transaction `type` (journal `source_type`) to the
  /// short Vietnamese label used in the transaction list rows (AC3).
  ///
  /// Falls back to [accountingSourceTypeLabel] (and then the raw
  /// `sourceType`) so unknown source types remain visible rather than
  /// blank. Kept separate from [accountingSourceTypeLabel] because the
  /// transaction list uses the short chip-style labels above while the
  /// journal filter uses the longer accounting-style labels.
  static String cashDrawerTxnTypeLabel(String sourceType) {
    switch (sourceType) {
      case 'cash_drawer_open':
        return cashDrawerTxnTypeOpen;
      case 'cash_drawer_cash_in':
        return cashDrawerTxnTypeCashIn;
      case 'cash_drawer_cash_out':
        return cashDrawerTxnTypeCashOut;
      case 'payment_transaction':
        return cashDrawerTxnTypeSale;
      case 'expense':
        return cashDrawerTxnTypeExpense;
      case 'cash_drawer_close_adjust':
        return cashDrawerTxnTypeClose;
      default:
        return accountingSourceTypeLabel(sourceType);
    }
  }

  /// Map a journal entry ``sourceType`` to a Vietnamese label.
  ///
  /// Falls back to the raw ``sourceType`` when no mapping exists so unknown
  /// source types remain visible rather than blank.
  static String accountingSourceTypeLabel(String sourceType) {
    switch (sourceType) {
      case 'expense':
        return accountingSourceTypeExpense;
      case 'payment_transaction':
        return accountingSourceTypePayment;
      case 'order':
        return accountingSourceTypeOrder;
      case 'order_cogs':
        return accountingSourceTypeCogs;
      case 'order_shipping_hold':
        return accountingSourceTypeShippingHold;
      case 'order_shipping_release':
        return accountingSourceTypeShippingRelease;
      case 'owner_capital':
        return accountingOwnerCapital;
      case 'owner_draw':
        return accountingOwnerDraw;
      case 'staff_reimburse':
        return accountingStaffReimburse;
      case 'cash_drawer_open':
        return accountingSourceTypeCashDrawerOpen;
      case 'cash_drawer_cash_in':
        return accountingSourceTypeCashDrawerCashIn;
      case 'cash_drawer_cash_out':
        return accountingSourceTypeCashDrawerCashOut;
      case 'cash_drawer_close_adjust':
        return accountingSourceTypeCashDrawerCloseAdjust;
      default:
        return sourceType;
    }
  }

  // Account type labels (account_type_helper.dart)
  static const accountingTypeAsset = 'Tài sản';
  static const accountingTypeLiability = 'Nợ phải trả';
  static const accountingTypeEquity = 'Vốn chủ sở hữu';
  static const accountingTypeIncome = 'Doanh thu';
  static const accountingTypeExpense = 'Chi phí';

  static String accountingLockResult(int count) =>
      'Đã khóa $count bút toán';

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

  // Catalog tag vocabulary (DG-096 Phase 4.2)
  static const catalogTagEditor = 'Thẻ ảnh';
  static const addCatalogTag = 'Thêm thẻ';
  static const editCatalogTag = 'Sửa thẻ';
  static const tagCategory = 'Danh mục';
  static const tagKey = 'Khoá';
  static const tagLabel = 'Nhãn';
  static const tagKeyHint = 'vd: sinh-nhat, 8-3';
  static const tagKeyInvalid = 'Khoá chỉ dùng chữ thường, số và dấu gạch nối';
  static const tagLabelEmpty = 'Nhập nhãn hiển thị';
  static const tagLabelTooLong = 'Nhãn không được vượt quá 40 ký tự';
  static const tagLabelNoColon = 'Nhãn không được chứa dấu hai chấm';
  static const tagCannotDelete = 'Không thể xoá';
  static String tagInUse(int n) => 'Thẻ này đang được dùng bởi $n ảnh. Hãy gỡ thẻ khỏi các ảnh đó trước.';
  static String tagDeleteConfirm(String label) => 'Xoá thẻ "$label"?';
  static const tagAdded = 'Đã thêm thẻ';
  static const tagUpdated = 'Đã cập nhật thẻ';
  static const tagDeleted = 'Đã xoá thẻ';
  static const tagGenericError = 'Lỗi: ';
  static const tagUsageCheckError = 'Lỗi kiểm tra sử dụng thẻ: ';
  static const noTagsInCategory = 'Chưa có thẻ';
  static const tagCategoriesDoiTuong = 'audience';
  static const tagCategoriesDip = 'occasion';
  static const tagCategoriesPhongCach = 'style';
  static const tagKeyRegexPattern = r'^[a-z0-9][a-z0-9-]*$';
}

// Category mapping (new slugs)
const categoryMap = {
  'banh_mi': VN.catBanhMi,
  'banh_kem': VN.catBanhKem,
  'banh_ngot': VN.catBanhNgot,
  'cookie': VN.catCookie,
  'khac': VN.catKhac,
};

// Category emoji mapping (new slugs)
const categoryEmojiMap = {
  'banh_mi': VN.emojiBanhMi,
  'banh_kem': VN.emojiBanhKem,
  'banh_ngot': VN.emojiBanhNgot,
  'cookie': VN.emojiCookie,
  'khac': VN.emojiKhac,
};

// Status mapping
const statusMap = {
  'new': VN.statusNew,
  'confirmed': VN.statusConfirmed,
  'in_progress': VN.statusInProgress,
  'ready': VN.statusReady,
  'delivered': VN.statusDelivered,
  'completed': VN.statusCompleted,
  'cancelled': VN.statusCancelled,
};

// Valid transitions (from CLI validate_transition logic)
const validTransitions = {
  'new': ['confirmed', 'cancelled'],
  'confirmed': ['in_progress', 'cancelled'],
  'in_progress': ['ready', 'cancelled'],
  'ready': ['delivered', 'completed', 'cancelled'],
  'delivered': ['completed'],
  'completed': <String>[],
  'cancelled': <String>[],
};

/// Returns the button label for transitioning to [targetStatus].
String statusActionLabel(String targetStatus) {
  switch (targetStatus) {
    case 'confirmed':
      return VN.actionConfirm;
    case 'in_progress':
      return VN.actionStart;
    case 'ready':
      return VN.actionReady;
    case 'delivered':
      return VN.actionDeliver;
    case 'completed':
      return VN.actionComplete;
    case 'cancelled':
      return VN.actionCancel;
    default:
      return targetStatus;
  }
}

String txnTypeLabel(String type) {
  switch (type) {
    case 'deposit':
      return VN.txnTypeDeposit;
    case 'payment':
      return VN.txnTypePayment;
    case 'full_payment':
      return VN.txnTypeFullPayment;
    case 'refund':
      return VN.txnTypeRefund;
    case 'tien_rut':
      return VN.txnTypeRutTien;
    default:
      return type;
  }
}

String paymentMethodLabel(String method) {
  switch (method) {
    case 'cash':
      return VN.methodCash;
    case 'transfer':
      return VN.methodTransfer;
    case 'debt':
      return VN.methodDebt;
    default:
      return method;
  }
}

/// Optional target bank account options for payment transactions (DG-244).
/// Empty default is represented by `null`/empty string at the call boundary;
/// this list holds only the selectable VCB accounts (FR2).
const paymentTargetAccounts = <String>[
  VN.paymentSourcePhuongVCB,
  VN.paymentSourceAnVCB,
];

// Work item status mapping
const workItemStatusMap = {
  'pending': VN.workItemPending,
  'confirmed': VN.workItemConfirmed,
  'working': VN.workItemWorking,
  'ready': VN.workItemReady,
  'delivered': VN.workItemDelivered,
  'cancelled': VN.workItemCancelled,
};

String workItemStatusLabel(String status) =>
    workItemStatusMap[status] ?? status;

// Work item status colors
const workItemStatusColors = {
  'pending': Colors.grey,
  'confirmed': Colors.blue,
  'working': Colors.orange,
  'ready': Colors.green,
  'delivered': Colors.teal,
  'cancelled': Colors.red,
};

// Valid work item transitions
const workItemValidTransitions = {
  'pending': ['confirmed', 'working', 'cancelled'],
  'confirmed': ['working', 'cancelled'],
  'working': ['ready', 'cancelled'],
  'ready': ['delivered', 'cancelled'],
  'delivered': ['cancelled'],
  'cancelled': <String>[],
};

/// Shows a SnackBar anchored to the top of the screen.
void showTopSnackBar(
  BuildContext context,
  String message, {
  Color? backgroundColor,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: backgroundColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );
}

/// Format VND: 150000.0 → "150.000đ"
String formatVND(double amount) {
  final formatted = amount.toInt().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  return '$formatted${VN.currency}';
}
