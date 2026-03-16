class VN {
  // Navigation
  static const appName = 'Tiệm Bánh';
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
  static const catCake = 'Bánh kem';
  static const catCupcake = 'Cupcake';
  static const catTiramisuMousse = 'Tiramisu / Mousse';
  static const catSandwich = 'Sandwich';
  static const catBongLan = 'Bông lan trứng muối';

  // Category emojis
  static const emojiCake = '🎂';
  static const emojiCupcake = '🧁';
  static const emojiTiramisuMousse = '🍰';
  static const emojiSandwich = '🥪';
  static const emojiBongLan = '🍞';

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

  // General
  static const remove = 'Xóa';
  static const save = 'Lưu';
  static const cancel = 'Hủy';
  static const back = 'Quay lại';
  static const currency = 'đ';
}

// Category mapping
const categoryMap = {
  'cake': VN.catCake,
  'cupcake': VN.catCupcake,
  'tiramisu_mousse': VN.catTiramisuMousse,
  'sandwich': VN.catSandwich,
  'bong_lan_trung_muoi': VN.catBongLan,
};

// Category emoji mapping
const categoryEmojiMap = {
  'cake': VN.emojiCake,
  'cupcake': VN.emojiCupcake,
  'tiramisu_mousse': VN.emojiTiramisuMousse,
  'sandwich': VN.emojiSandwich,
  'bong_lan_trung_muoi': VN.emojiBongLan,
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
