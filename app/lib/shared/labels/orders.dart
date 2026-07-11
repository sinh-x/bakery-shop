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
}
