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

  // Stage 3 pickup options (DG-267 Phase 3)
  static const pickupNow = 'Giao ngay';
  static const pickupLater = 'Giao hàng sau';
  static const pickupTitle = 'Nhận bánh';
  static const pickupSubtitle = 'Vui lòng chọn hình thức nhận bánh';

  // Delivery filter labels (DG-261 Phase 1)
  static const deliveryFilterToday = 'Hôm nay';
  static const deliveryFilterAll = 'Tất cả';
  static const deliveryNoDueDate = 'Chưa có ngày';
  static const deliveryEmptyToday = 'Không có đơn giao hàng hôm nay';
  static const deliveryEmptyAll = 'Không có đơn giao hàng';

  // Delivery tab with count (DG-261 review CQ-2)
  static String deliveryTabWithCount(int count) => 'Giao hàng ($count)';
}
