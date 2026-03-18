class VN {
  // Navigation
  static const appName = 'Đoàn Gia - Bánh Kem';
  static const tabDashboard = 'Tổng quan';
  static const tabOrders = 'Đơn hàng';
  static const tabProducts = 'Sản phẩm';
  static const tabEvents = 'Sự kiện';

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
  static const customer = 'Khách hàng';
  static const products = 'Sản phẩm';
  static const payment = 'Thanh toán';
  static const paid = 'Đã thanh toán';
  static const unpaid = 'Chưa thanh toán';
  static const packingChecklist = 'Danh sách đóng gói';
  static const actions = 'Thao tác';

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

  // Event form
  static const eventType = 'Loại sự kiện';
  static const eventSummary = 'Mô tả sự kiện';
  static const logEvent = 'GHI SỰ KIỆN';
  static const recentEvents = 'Sự kiện gần đây';

  // Dashboard
  static const todayOrders = 'Đơn hàng hôm nay';
  static const upcomingDue = 'Sắp đến hạn';
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
  static const catalogPhotoDeleted = 'Đã xóa ảnh';

  // General
  static const remove = 'Xóa';
  static const save = 'Lưu';
  static const cancel = 'Hủy';
  static const back = 'Quay lại';
  static const currency = 'đ';
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

/// Format VND: 150000.0 → "150.000đ"
String formatVND(double amount) {
  final formatted = amount.toInt().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  return '$formatted${VN.currency}';
}
