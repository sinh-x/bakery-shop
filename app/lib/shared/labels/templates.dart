export 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Message-template domain labels (DG-375 Phase 4.3 / NFR4).
///
/// All user-facing copy for the template picker modal and integration points
/// lives here per the VN Label Policy in CLAUDE.md and §5 of
/// docs/flutter-coding-standards.md. Consumers import this file and use
/// `TemplatesLabels.*` for template-domain strings, or `VN.*` for legacy
/// labels re-exported above.
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