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
  // Hint shown when the category dropdown has no selection (e.g. an existing
  // blank whose stored category does not match any server Category slug).
  static const fieldCategoryHint = 'Chọn danh mục';
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
  static const actionSelectBlank = 'Chọn phôi';

  // BOM mapping field labels (FR2 / NFR4).
  static const fieldBlank = 'Phôi';
  static const fieldBomQuantity = 'Số lượng trong công thức';

  // BOM mapping messages (FR2 / NFR4).
  static const messageBomCreateSuccess = 'Thêm BOM thành công';
  static const messageBomUpdateSuccess = 'Cập nhật BOM thành công';
  static const messageBomDeleteSuccess = 'Xóa BOM thành công';
  static const messageBomDeleteBlocked = 'Không thể xóa BOM này';
  static const messageBomSelectBlank = 'Vui lòng chọn phôi';
  static const messageBomInvalidQuantity = 'Số lượng không hợp lệ';

  // BOM mapping empty states (NFR4).
  static const emptyBom = 'Chưa có phôi nào trong BOM';

  // Stock movement types (FR3 / NFR4).
  static const stockTypeProduction = 'Sản xuất';
  static const stockTypeUsage = 'Sử dụng';

  // Stock action sheet labels (FR4 / NFR4).
  static const fieldProducedDate = 'Ngày sản xuất';
  static const fieldExpiryDateOptional = 'Ngày hết hạn (tùy chọn)';
  static const messageStockRecordSuccess = 'Ghi nhận thành công';
  static const messageStockRecordFailed = 'Ghi nhận thất bại';
  static const messageStockInvalidQuantity = 'Số lượng không hợp lệ';

  // Audit log entry labels (FR5 / NFR4).
  static const fieldQuantityChange = 'Biến động';
  static const fieldEntryDate = 'Thời gian';
  static const fieldProducedDateShort = 'NSX';
  static const fieldExpiryDateShort = 'HSD';

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

  // Work item blank assignment (DG-293 FR8 / AC2).
  static const notAssigned = 'Chưa gán phôi';
}