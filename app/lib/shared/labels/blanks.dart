export 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Blanks-domain Vietnamese labels for the bakery app (DG-291 Phase 4.3).
///
/// Per the VN Label Policy in CLAUDE.md and §5 of docs/flutter-coding-standards.md,
/// new user-facing copy for the blanks feature lives in its own domain file
/// rather than being appended to the monolithic `VN` class. Consumers import
/// this file and use `BlanksLabels.*` for new labels or `VN.*` for legacy
/// labels re-exported above.
class BlanksLabels {
  BlanksLabels._();

  // Screen titles (FR1-FR6 / NFR4).
  static const screenManage = 'Quản lý phôi bánh';
  static const screenDetail = 'Chi tiết phôi';
  static const screenCreate = 'Tạo phôi mới';
  static const screenBomMapping = 'BOM Mapping';
  static const screenStock = 'Tồn kho phôi';
  static const screenDemand = 'Nhu cầu phôi';
  static const screenHistory = 'Lịch sử phôi';

  // Field labels (FR1-FR6 / NFR4).
  static const fieldName = 'Tên phôi';
  static const fieldCategory = 'Danh mục';
  static const fieldUnit = 'Đơn vị';
  static const fieldNote = 'Ghi chú';
  static const fieldQuantity = 'Số lượng';
  static const fieldProductionDate = 'Ngày sản xuất';
  static const fieldExpiryDate = 'Ngày hết hạn';

  // Actions (FR1-FR6 / NFR4).
  static const actionSave = 'Lưu';
  static const actionCancel = 'Hủy';
  static const actionDelete = 'Xóa';
  static const actionEdit = 'Sửa';
  static const actionAddBlank = 'Thêm phôi';
  static const actionStockIn = 'Nhập kho';
  static const actionStockOut = 'Xuất kho';
  static const actionAddBom = 'Thêm BOM';
  static const actionDeleteBom = 'Xóa BOM';

  // Stock movement types (FR3 / NFR4).
  static const stockTypeProduction = 'Sản xuất';
  static const stockTypeUsage = 'Sử dụng';

  // Demand labels (FR5 / NFR4).
  static const demand = 'Nhu cầu';
  static const demandStock = 'Tồn kho';
  static const demandShortfall = 'Thiếu';

  // Messages (FR4/FR6 / NFR4).
  static const messageCreateSuccess = 'Tạo phôi thành công';
  static const messageUpdateSuccess = 'Cập nhật thành công';
  static const messageDeleteSuccess = 'Xóa phôi thành công';
  static const messageDeleteConfirm = 'Xác nhận xóa?';
  static const messageDeleteBlocked = 'Không thể xóa phôi này';

  // Empty states (NFR4).
  static const emptyBlanks = 'Chưa có phôi nào';
  static const emptyHistory = 'Chưa có lịch sử';
  static const emptyData = 'Chưa có dữ liệu';

  // Category filter (NFR4).
  static const categoryFilterAll = 'Tất cả danh mục';
}