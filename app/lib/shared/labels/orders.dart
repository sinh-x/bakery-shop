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

  // Stage 3
  static const deliveryPhone = 'SĐT nhận hàng';

  // Stage 4
  static const reviewSummary = 'Tóm tắt đơn hàng';
  static const reviewCreateOrder = 'Tạo đơn hàng';

  // Stage summary cards (DG-211 Phase 4)
  static const previousStagesSummary = 'Tóm tắt bước trước';

  // Order source options (DG-211 review cycle 1 — CQ-1)
  static const sourceTaiTiem = 'Tại tiệm';
  static const sourceOnline = 'Online';
  static const sourceDienThoai = 'Điện thoại';

  // Generic placeholder for unselected values (DG-211 review cycle 1 — CQ-3)
  static const notSelected = 'Chưa chọn';

  // Validation messages (DG-211 review cycle 1 — CQ-4)
  static const validationSelectAtLeastOneProduct =
      'Vui lòng chọn ít nhất một sản phẩm';

  // Product/extras count strings (DG-211 review cycle 1 — CQ-2)
  static String productCount(int count) => '$count sản phẩm';
  static String extraCount(int count) => '$count phụ kiện';
}
