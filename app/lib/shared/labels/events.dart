/// Events-domain Vietnamese labels for the bakery app.
///
/// Per the VN Label Policy in CLAUDE.md and §5 of
/// docs/flutter-coding-standards.md, user-facing copy for the events feature
/// lives in its own domain file rather than being appended to the monolithic
/// `VN` class. Consumers import this file and use `EventsLabels.*` for
/// events-domain strings.
class EventsLabels {
  EventsLabels._();

  // Navigation
  static const tabEvents = 'Sự kiện';
  static const knowledgeBaseEventsSubtitle = 'Ghi nhật ký hoạt động & sự cố';

  // Event types
  static const eventNote = 'Ghi chú';
  static const eventOrder = 'Đơn hàng';
  static const eventInventory = 'Kho';
  static const eventProduction = 'Sản xuất';
  static const eventDelivery = 'Giao hàng';
  static const eventExpense = 'Chi phí';

  // Event types (chips)
  static const typeEquipment = 'Đồ điện/Dụng cụ làm bánh';

  // Event log form
  static const eventPrompt = 'Chuyện gì xảy ra?';
  static const eventLogged = 'Đã ghi sự kiện';
  static const loggedBy = 'Người ghi';
  static const changeLogger = 'Đổi';
  static const setYourName = 'Nhập tên của bạn';
  static const addTag = 'Thêm';

  // Event tags
  static const tagIncident = 'Sự cố';
  static const tagKnowledgeGap = 'Thiếu thông tin';
  static const tagMaintenance = 'Bảo trì';
  static const tagEquipment = 'Thiết bị';
  static const tagPricing = 'Giá cả';
  static const tagOrdering = 'Đặt hàng';
  static const tagDecoration = 'Trang trí';
  static const tagStaff = 'Nhân viên';

  // Event history filters (Phase 5)
  static const filterToday = 'Hôm nay';
  static const filterWeek = 'Tuần này';
  static const filterMonth = 'Tháng này';
  static const filterAll = 'Tất cả';
  static const searchEvents = 'Tìm sự kiện...';
  static const noEvents = 'Chưa có sự kiện';

  // Event form
  static const eventType = 'Loại sự kiện';
  static const eventSummary = 'Mô tả sự kiện';
  static const logEvent = 'GHI SỰ KIỆN';
  static const recentEvents = 'Sự kiện gần đây';
  static const createEvent = 'Thêm sự kiện';
  static const editEvent = 'Sửa sự kiện';
  static const deleteEvent = 'Xóa sự kiện';
  static const deleteEventConfirm = 'Bạn có chắc muốn xóa sự kiện này?';
  static const eventDeleted = 'Đã xóa sự kiện';
  static const eventUpdated = 'Đã cập nhật sự kiện';
  static const addOrderIncident = 'Thêm sự cố';
  static const orderLabel = 'Đơn hàng';
  static const eventPhotos = 'Ảnh đính kèm';
  static const addEventPhoto = 'Thêm ảnh';
  static const noEventPhotos = 'Chưa có ảnh';
  static const eventPhotosUploadFailed =
      'Đã lưu sự kiện nhưng không tải được ảnh';
}