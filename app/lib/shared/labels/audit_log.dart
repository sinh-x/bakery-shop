/// Audit log-domain Vietnamese labels for the bakery app (DG-029 Phase 8).
///
/// Per the VN Label Policy in CLAUDE.md and §5 of
/// docs/flutter-coding-standards.md, new user-facing copy for the audit log
/// feature lives in its own domain file rather than being appended to the
/// monolithic `VN` class.
class AuditLogLabels {
  AuditLogLabels._();

  // Screen title — mirrors the existing `VN.openAuditLog` entry used by the
  // Settings technical tab and the router placeholder.
  static const screenTitle = 'Nhật ký thay đổi';

  // Filter controls (FR24).
  static const filterUser = 'Người dùng';
  static const filterUserHint = 'Tất cả';
  static const filterEntityType = 'Loại thay đổi';
  static const filterDateFrom = 'Từ ngày';
  static const filterDateTo = 'Đến ngày';
  static const applyFilters = 'Lọc';
  static const clearFilters = 'Xóa lọc';

  // Entity type display names (FR24: config, products, checklist, categories,
  // staff). Backend `entity_type` values are lowercase singular/snake_case; we
  // map them to friendly Vietnamese labels via [entityTypeLabel].
  static const entityTypeConfig = 'Cấu hình';
  static const entityTypeProduct = 'Sản phẩm';
  static const entityTypeCategory = 'Danh mục';
  static const entityTypeChecklistTemplate = 'Checklist';
  static const entityTypeStaff = 'Nhân viên';
  static const entityTypeAll = 'Tất cả';

  // List entry fields.
  static const colUser = 'Người dùng';
  static const colAction = 'Hành động';
  static const colEntityType = 'Loại';
  static const colEntityId = 'Đối tượng';
  static const colTimestamp = 'Thời gian';
  static const colOldValue = 'Giá trị cũ';
  static const colNewValue = 'Giá trị mới';

  // Action display names (backend records lowercase action verbs).
  static const actionCreate = 'Tạo';
  static const actionUpdate = 'Cập nhật';
  static const actionDelete = 'Xóa';

  // Pagination + state copy.
  static const loadMore = 'Tải thêm';
  static const loading = 'Đang tải...';
  static const empty = 'Không có bản ghi nào.';
  static const errorLoad = 'Không thể tải nhật ký thay đổi.';
  static const retry = 'Thử lại';
  static const pageOf = 'Trang';

  /// Maps a backend `entity_type` value to a Vietnamese display label.
  static String entityTypeLabel(String entityType) {
    switch (entityType) {
      case 'config':
        return entityTypeConfig;
      case 'product':
        return entityTypeProduct;
      case 'category':
        return entityTypeCategory;
      case 'checklist_template':
        return entityTypeChecklistTemplate;
      case 'staff':
        return entityTypeStaff;
      default:
        return entityType;
    }
  }

  /// Maps a backend `action` value to a Vietnamese display label.
  static String actionLabel(String action) {
    switch (action) {
      case 'create':
        return actionCreate;
      case 'update':
        return actionUpdate;
      case 'delete':
        return actionDelete;
      default:
        return action;
    }
  }
}