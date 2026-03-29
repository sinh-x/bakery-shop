import 'package:flutter/material.dart';

class VN {
  // Navigation
  static const appName = 'Đoàn Gia - Bánh Kem';
  static const tabDashboard = 'Tổng quan';
  static const tabOrders = 'Đơn hàng';
  static const tabProducts = 'Sản phẩm';
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
  static const orderEditSaved = 'Đã lưu thay đổi';

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

  // Product form
  static const createProduct = 'Thêm sản phẩm';
  static const editProduct = 'Sửa sản phẩm';
  static const productName = 'Tên sản phẩm';
  static const productCategory = 'Danh mục';
  static const productPrice = 'Giá bán';
  static const productCost = 'Giá vốn';
  static const productNotes = 'Ghi chú công thức';
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
  static const apiError = 'Không thể kết nối máy chủ';

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
  static const orderUpdated = 'Đã cập nhật thứ tự';

  // Settings
  static const settings = 'Cài đặt';
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
  static const createdBy = 'Người tạo';

  // Delivery types (detailed)
  static const deliveryBus = 'Giao xe khách';
  static const deliveryDoor = 'Giao tận nơi';

  // Order create form extras
  static const orderSource = 'Nguồn đặt hàng';
  static const dueTime = 'Giờ giao';
  static const isBirthday = 'Sinh nhật';
  static const birthdayAge = 'Tuổi khách hàng';
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

  // Payment transactions
  static const txnTypeDeposit = 'Đặt cọc';
  static const txnTypePayment = 'Thanh toán';
  static const txnTypeFullPayment = 'Thanh toán đủ';
  static const txnTypeRefund = 'Hoàn tiền';
  static const methodCash = 'Tiền mặt';
  static const methodTransfer = 'Chuyển khoản';
  static const addPayment = 'Thêm thanh toán';
  static const depositSection = 'Đặt cọc ngay';
  static const depositAmount = 'Số tiền đặt cọc';
  static const paymentHistory = 'Lịch sử thanh toán';
  static const paymentRecorded = 'Đã ghi thanh toán';
  static const paymentUpdated = 'Đã cập nhật giao dịch';
  static const editPayment = 'Sửa giao dịch';
  static const txnDetails = 'Chi tiết giao dịch';
  static const txnNoteLabel = 'Ghi chú';
  static const noPaymentHistory = 'Chưa có giao dịch';
  static const paymentMethod = 'Hình thức';
  static const paymentNotes = 'Ghi chú (tùy chọn)';
  static const paymentAmountLabel = 'Số tiền';
  static const txnType = 'Loại thanh toán';

  // Work item statuses
  static const workItemPending = 'Chờ xử lý';
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
  static const currency = 'đ';

  // Receipts
  static const printReceipt = 'In';
  static const printWorkTicket = 'Phiếu nội bộ';
  static const printCustomerReceipt = 'Hóa đơn khách hàng';
  static const printBusLabel = 'Phiếu xe khách';
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

  // Printer picker
  static const selectPrinter = 'Chọn máy in';
  static const scanning = 'Đang tìm...';
  static const noPrinterFound = 'Không tìm thấy máy in';
  static const printerConnectionFailed = 'Kết nối thất bại';
  static const connectingTo = 'Đang kết nối đến...';
  static const tapToRetry = 'Bấm để thử lại';
  static const noDevicesFound = 'Không có thiết bị nào';

  // Shipping fee & extras
  static const shippingFee = 'Phí giao hàng';
  static const extras = 'Phụ kiện';
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
    default:
      return method;
  }
}

// Work item status mapping
const workItemStatusMap = {
  'pending': VN.workItemPending,
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
  'working': Colors.orange,
  'ready': Colors.green,
  'delivered': Colors.teal,
  'cancelled': Colors.red,
};

// Valid work item transitions
const workItemValidTransitions = {
  'pending': ['working', 'cancelled'],
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
      margin: EdgeInsets.only(
        top: 16,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).size.height - 100,
      ),
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
