/// Products-domain Vietnamese labels for the bakery app.
///
/// Per the VN Label Policy in CLAUDE.md and §5 of
/// docs/flutter-coding-standards.md, user-facing copy for the products feature
/// lives in its own domain file rather than being appended to the monolithic
/// `VN` class. Consumers import this file and use `ProductsLabels.*` for new
/// labels or `VN.*` for legacy labels still re-exported via
/// `vietnamese_labels.dart`.
class ProductsLabels {
  ProductsLabels._();

  // Navigation
  static const tabProducts = 'Sản phẩm';

  // Product categories
  static const catBanhMi = 'Bánh mì';
  static const catBanhKem = 'Bánh kem';
  static const catBanhNgot = 'Bánh ngọt';
  static const catCookie = 'Cookie';
  static const catKhac = 'Khác';

  // Category emojis
  static const emojiBanhMi = '🍞';
  static const emojiBanhKem = '🎂';
  static const emojiBanhNgot = '🧁';
  static const emojiCookie = '🍪';
  static const emojiKhac = '🍰';

  // Product code
  static const productCode = 'Mã sản phẩm';

  // Product form
  static const createProduct = 'Thêm sản phẩm';
  static const editProduct = 'Sửa sản phẩm';
  static const productName = 'Tên sản phẩm';
  static const productCategory = 'Danh mục';
  static const productPrice = 'Giá bán';
  static const productCost = 'Giá vốn';
  static const productNotes = 'Ghi chú công thức';
  static const priceChips = 'Các mức giá nhanh';
  static const addPriceChip = 'Thêm mức giá';
  static const priceChipLabel = 'Nhãn';
  static const priceChipPrice = 'Giá';
  static const priceChipLabelRequired = 'Nhãn bắt buộc';
  static const priceChipPriceInvalid = 'Giá không hợp lệ';

  // Enum attribute options editor (DG-092 Phase 4.5)
  static const enumOptionsSection = 'Tùy chọn thuộc tính';
  static const enumOptionsHintAttributeWide =
      'Áp dụng cho tất cả sản phẩm dùng thuộc tính này';
  static const addEnumOption = 'Thêm tùy chọn';
  static const enumOptionValueLabel = 'Giá trị';
  static const enumOptionValueRequired = 'Giá trị không được để trống';
  static const enumOptionDefaultLabel = 'Mặc định';
  static const enumOptionDefaultRequired = 'Phải chọn một giá trị mặc định';
  static const enumOptionRestore = 'Khôi phục';
  static const enumOptionRemoved = 'Đã đánh dấu xoá';
  static const priceFrom = 'từ';
  static const productPhoto = 'Ảnh sản phẩm';
  static const choosePhoto = 'Chọn ảnh';
  static const takePhoto = 'Chụp ảnh';
  static const fromGallery = 'Chọn từ thư viện';
  static const deleteProduct = 'Xóa sản phẩm';
  static const deleteConfirm = 'Bạn có chắc muốn xóa sản phẩm này?';
  static const productCreated = 'Đã thêm sản phẩm';
  static const productUpdated = 'Đã cập nhật sản phẩm';
  static const productDeleted = 'Đã xóa sản phẩm';
  static const noProducts = 'Không có sản phẩm';
  static const hiddenProducts = 'Sản phẩm đã ẩn';
  static const productHiddenState = 'Đang ẩn';
  static const showProduct = 'Hiện sản phẩm';
  static const searchProducts = 'Tìm sản phẩm...';

  // Category management
  static const manageCategories = 'Quản lý danh mục';
  static const addCategory = 'Thêm danh mục';
  static const editCategory = 'Sửa danh mục';
  static const categoryName = 'Tên danh mục';
  static const codePrefix = 'Mã viết tắt';
  static const codePrefixHint = 'VD: BMI, BKS';
  static const codePrefixHelp = '2-4 ký tự in hoa, dùng tạo mã sản phẩm';
  static const categorySlug = 'Slug';
  static const deactivateCategory = 'Ẩn danh mục';
  static const reactivateCategory = 'Hiện danh mục';
  static const deactivateConfirm =
      'Ẩn danh mục? Sản phẩm vẫn còn nhưng tab sẽ bị ẩn.';
  static const hiddenCategories = 'Đã ẩn';
  static const categoryCreated = 'Đã thêm danh mục';
  static const categoryUpdated = 'Đã cập nhật danh mục';
  static const categoryDeactivated = 'Đã ẩn danh mục';
  static const categoryReactivated = 'Đã hiện danh mục';
  static const noPrefixError = 'Mã viết tắt không được để trống';
  static const prefixFormatError = 'Mã viết tắt phải 2-4 ký tự in hoa';
  static const categoryIcon = 'Biểu tượng';
  static const categoryVisibility = 'Trạng thái hiển thị';
  static const categoryVisible = 'Đang hiện';
  static const categoryHiddenState = 'Đang ẩn';
  static const orderUpdated = 'Đã cập nhật thứ tự';

  // Product display flags
  static const trungBay = 'Trưng bày';
  static const tangKem = 'Tặng kèm';
}