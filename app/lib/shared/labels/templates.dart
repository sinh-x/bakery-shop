/// Message-template domain labels (DG-375 Phase 4.3 / NFR4).
///
/// All user-facing copy for the template picker modal and integration points
/// lives here per the VN Label Policy in CLAUDE.md and §5 of
/// docs/flutter-coding-standards.md. Consumers import this file and use
/// `TemplatesLabels.*` for template-domain strings.
class TemplatesLabels {
  TemplatesLabels._();

  // Overflow menu item (order detail / create / edit).
  static const overflowMenuOpenPicker = 'Mẫu tin nhắn';

  // Modal header + hints.
  static const pickerTitle = 'Chọn mẫu tin nhắn';
  static const pickerHint = 'Chọn mẫu để điền thông tin đơn và sao chép.';

  // Scenario group headers (match backend scenario slugs).
  static const scenarioAskInfo = 'Hỏi thông tin';
  static const scenarioConfirmOrder = 'Xác nhận đơn';
  static const scenarioFinalMessage = 'Bánh sẵn sàng / Giao bánh';
  static const scenarioFollowUp = 'Cảm ơn & Hỏi thăm';
  static const scenarioStatusUpdate = 'Cập nhật trạng thái';
  static const scenarioPaymentRequest = 'Yêu cầu thanh toán';

  // Personal vs system template tag.
  static const systemTag = 'Hệ thống';
  static const personalTag = 'Cá nhân';

  // Inactive template marker shown next to a template name in the
  // management list when the template's `active` flag is off.
  static const inactiveTag = '(tắt)';

  // String used in place of an empty field value when resolving template
  // placeholders. Matches requirements doc §11 Risk mitigation.
  static const emptyFieldPlaceholder = '(trống)';

  // Empty state.
  static const emptyTitle = 'Chưa có mẫu nào';
  static const emptyBody = 'Quản lý thêm mẫu ở trang quản lý mẫu tin nhắn.';

  // Preview + copy actions.
  static const copyButton = 'Sao chép';
  static const copiedSnack = 'Đã sao chép vào bộ nhớ tạm';
  static const previewLabel = 'Xem trước';
  static const closeLabel = 'Đóng';

  // Review-stage button label (create / edit wizard stage 4).
  static const reviewStageButton = 'Mẫu tin nhắn';

  // ── Phase 4 — Template management + editor ────────────────────────────
  // Management screen (FR6, FR7, FR10 / AC6, AC7).
  static const managementTitle = 'Quản lý mẫu tin nhắn';
  static const managementSystemTab = 'Hệ thống';
  static const managementPersonalTab = 'Cá nhân';
  static const managementSystemTabHint = 'Mẫu dùng chung cho toàn bộ nhân viên';
  static const managementPersonalTabHint = 'Mẫu của riêng bạn';
  static const managementAddButton = 'Thêm mẫu';
  static const managementEditTooltip = 'Sửa mẫu';
  static const managementDeleteTooltip = 'Xoá mẫu';
  static const managementDeleteConfirmTitle = 'Xoá mẫu tin nhắn';
  static const managementDeleteConfirmBody = 'Bạn có chắc muốn xoá mẫu "{name}"?';
  static const managementDeleteConfirmAction = 'Xoá';
  static const managementEmpty = 'Chưa có mẫu nào. Bấm "Thêm mẫu" để tạo.';
  static const managementAdminOnlyHint =
      'Tab Hệ thống chỉ quản trị viên mới được phép sửa.';
  static const managementCreatedSnack = 'Đã tạo mẫu "{name}".';
  static const managementUpdatedSnack = 'Đã cập nhật mẫu "{name}".';
  static const managementDeletedSnack = 'Đã xoá mẫu "{name}".';
  static const manageTemplatesButton = 'Quản lý mẫu';

  // Editor screen (FR8 / AC8).
  static const editorCreateTitle = 'Tạo mẫu tin nhắn';
  static const editorEditTitle = 'Sửa mẫu tin nhắn';
  static const editorNameLabel = 'Tên mẫu';
  static const editorNameHint = 'VD: Xác nhận đơn — Pickup';
  static const editorNameRequired = 'Vui lòng nhập tên mẫu';
  static const editorScenarioLabel = 'Kịch bản';
  static const editorBodyLabel = 'Nội dung mẫu';
  static const editorBodyHint = 'Soạn nội dung mẫu. Dùng nút "Chèn trường" để thêm biến.';
  static const editorBodyRequired = 'Vui lòng nhập nội dung mẫu';
  static const editorInsertFieldButton = 'Chèn trường';
  static const editorInsertFieldTitle = 'Chèn trường đơn hàng';
  static const editorInsertFieldHint =
      'Chạm một trường để chèn vào vị trí con trỏ trong nội dung mẫu.';
  static const editorActiveLabel = 'Đang sử dụng';
  static const editorActiveHint = 'Tắt để ẩn mẫu khỏi danh sách mà không xoá.';
  static const editorIsSystemLabel = 'Mẫu hệ thống (toàn bộ nhân viên)';
  static const editorIsSystemHint =
      'Chỉ quản trị viên mới được tạo mẫu hệ thống.';
  static const editorSavedSnack = 'Đã lưu mẫu "{name}".';
  static const editorSaveError = 'Không lưu được mẫu. Thử lại sau.';

  /// Available placeholders for the "insert order field" helper (FR8).
  /// Key = placeholder slug (used in the body text as `{slug}`),
  /// value = VN description shown in the picker list.
  static const Map<String, String> orderFieldPlaceholders = {
    'customer_name': 'Tên khách hàng',
    'customer_phone': 'Số điện thoại khách',
    'order_code': 'Mã đơn nội bộ',
    'public_order_code': 'Mã đơn hiển thị',
    'due_date': 'Ngày nhận bánh',
    'due_time': 'Giờ nhận bánh',
    'total_price': 'Tổng tiền',
    'items_list': 'Danh sách bánh',
    'delivery_type': 'Hình thức nhận',
    'delivery_address': 'Địa chỉ giao',
    'shipping_fee': 'Phí giao hàng',
    'notes': 'Ghi chú đơn',
    'source': 'Nguồn đơn',
    'created_by': 'Nhân viên tạo',
  };

  /// Maps a backend scenario slug to a Vietnamese display label.
  static String scenarioLabel(String scenario) {
    switch (scenario) {
      case 'ask_info':
        return scenarioAskInfo;
      case 'confirm_order':
        return scenarioConfirmOrder;
      case 'final_message':
        return scenarioFinalMessage;
      case 'follow_up':
        return scenarioFollowUp;
      case 'status_update':
        return scenarioStatusUpdate;
      case 'payment_request':
        return scenarioPaymentRequest;
      default:
        return scenario;
    }
  }
}