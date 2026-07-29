export 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Product-domain Vietnamese labels for the bakery app.
///
/// Per the VN Label Policy in CLAUDE.md and §5 of
/// docs/flutter-coding-standards.md, new user-facing copy for the products
/// feature lives in its own domain file rather than being appended to the
/// monolithic `VN` class. Consumers import this file and use
/// `ProductsLabels.*` for new labels or `VN.*` for legacy labels re-exported
/// above.
class ProductsLabels {
  ProductsLabels._();

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

  // Product display flags
  static const trungBay = 'Trưng bày';
  static const tangKem = 'Tặng kèm';

  // Product CRUD messages
  static const deleteProduct = 'Xóa sản phẩm';
  static const deleteConfirm = 'Bạn có chắc muốn xóa sản phẩm này?';
  static const productCreated = 'Đã thêm sản phẩm';
  static const productUpdated = 'Đã cập nhật sản phẩm';
  static const productDeleted = 'Đã xóa sản phẩm';
  static const noProducts = 'Không có sản phẩm';
  static const hiddenProducts = 'Sản phẩm đã ẩn';
  static const productHiddenState = 'Đang ẩn';
  static const showProduct = 'Hiện sản phẩm';

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

  // Catalog gallery
  static const catalogTitle = 'Bộ sưu tập';
  static const addCatalogPhoto = 'Thêm ảnh mẫu';
  static const editCatalogPhoto = 'Sửa ảnh';
  static const deleteCatalogPhoto = 'Xóa ảnh';
  static const deleteCatalogConfirm = 'Bạn có chắc muốn xóa ảnh này?';
  static const captionLabel = 'Mô tả';
  static const tagsLabel = 'Nhãn';
  static const tagsHint = 'VD: hoa, hồng, sinh nhật';
  static const noCatalogPhotos = 'Chưa có ảnh mẫu';
  static const catalogPhotoAdded = 'Đã thêm ảnh mẫu';
  static const catalogPhotoUpdated = 'Đã cập nhật ảnh';
  static const catalogPhotoDeleted = 'Đã xóa ảnh';
  static const setAsProductPhoto = 'Đặt làm ảnh sản phẩm';
  static const productPhotoSetFromCatalog = 'Đã đặt ảnh sản phẩm từ ảnh mẫu';

  // Catalog browse
  static const browseScreenTitle = 'Duyệt ảnh mẫu';
  static const doiTuong = 'Đối tượng';
  static const dip = 'Dịp';
  static const phongCach = 'Phong cách';
  static const filterHint = 'Chọn thẻ để lọc';
  static const noBrowsePhotos = 'Chưa có ảnh mẫu';
  static const noBrowsePhotosForFilter = 'Không có ảnh phù hợp bộ lọc';
  static const xoaLoc = 'Xoá lọc';
  static const catalogFilterLoadError = 'Không tải được bộ lọc ảnh';
  static const categoryLoadError = 'Không tải được danh mục sản phẩm';
  static const danhMuc = 'Danh mục';

  // Catalog photo viewer
  static const daLuuAnh = 'Đã lưu ảnh';
  static const taiAnh = 'Tải ảnh';
  static const chiaSe = 'Chia sẻ';
  static const daSaoChepNoiDung = 'Đã sao chép nội dung vào clipboard';
  static const saoChepNoiDungThatBai =
      'Không thể sao chép nội dung vào clipboard';
  static const taiMotPhanAnh = 'Đã tải một phần ảnh';
  static const taiNAnh = 'Đã tải {count} ảnh';
  static const khongTheTaiAnh = 'Không thể tải ảnh';
  static const khongTheChiaSe = 'Không thể chia sẻ';

  // Catalog tag vocabulary (DG-096 Phase 4.2)
  static const catalogTagEditor = 'Thẻ ảnh';
  static const addCatalogTag = 'Thêm thẻ';
  static const editCatalogTag = 'Sửa thẻ';
  static const tagCategory = 'Danh mục';
  static const tagKey = 'Khoá';
  static const tagLabel = 'Nhãn';
  static const tagKeyHint = 'vd: sinh-nhat, 8-3';
  static const tagKeyInvalid = 'Khoá chỉ dùng chữ thường, số và dấu gạch nối';
  static const tagLabelEmpty = 'Nhập nhãn hiển thị';
  static const tagLabelTooLong = 'Nhãn không được vượt quá 40 ký tự';
  static const tagLabelNoColon = 'Nhãn không được chứa dấu hai chấm';
  static const tagCannotDelete = 'Không thể xoá';
  static String tagInUse(int n) =>
      'Thẻ này đang được dùng bởi $n ảnh. Hãy gỡ thẻ khỏi các ảnh đó trước.';
  static String tagDeleteConfirm(String label) => 'Xoá thẻ "$label"?';
  static const tagAdded = 'Đã thêm thẻ';
  static const tagUpdated = 'Đã cập nhật thẻ';
  static const tagDeleted = 'Đã xoá thẻ';
  static const tagGenericError = 'Lỗi: ';
  static const tagUsageCheckError = 'Lỗi kiểm tra sử dụng thẻ: ';
  static const noTagsInCategory = 'Chưa có thẻ';
  static const tagCategoriesDoiTuong = 'audience';
  static const tagCategoriesDip = 'occasion';
  static const tagCategoriesPhongCach = 'style';
  static const tagKeyRegexPattern = r'^[a-z0-9][a-z0-9-]*$';

  // Photo actions (shared with product form)
  static const choosePhoto = 'Chọn ảnh';
  static const takePhoto = 'Chụp ảnh';
  static const fromGallery = 'Chọn từ thư viện';
  static const addPhoto = 'Thêm ảnh';

  // Stock management
  static const quanLyTonKho = 'Quản lý tồn kho';
  static const nhapHang = 'Nhập hàng';
  static const haoHut = 'Hao hụt';
  static const dieuChinh = 'Điều chỉnh';
  static const tonKho = 'Tồn kho';
  static const nhapHangSheet = 'Nhập hàng';
  static const haoHutSheet = 'Hao hụt';
  static const dieuChinhSheet = 'Điều chỉnh';
  static const tuyChonGia = 'Tùy chọn giá';
  static const tuyChon = 'Tùy chọn';
  static const ghiChuLabel = 'Ghi chú';
  static const ghiChuHint = 'Ghi chú (tùy chọn)';
  static const lyDoLabel = 'Lý do';
  static const lyDoHint = 'Nhập lý do...';
  static const lyDoRequired = 'Lý do không được để trống';
  static const soLuongInvalid = 'Số lượng phải lớn hơn 0';
  static const xacNhanHaoHut = 'Xác nhận hao hụt';
  static const xacNhanDieuChinh = 'Điều chỉnh';
  static const xacNhanNhapHang = 'Nhập hàng';
  static const khongCoSanPhamTonKho = 'Không có sản phẩm tồn kho';
  static const capNhatThanhCong = 'Cập nhật thành công';
  static const loiHeThong = 'Lỗi hệ thống';
  static const outOfStock = 'Hết hàng';

  // Negative stock display (DG-200 Phase 5, FR-8, AC-10)
  static String negativeStockLabel(int qty) {
    assert(qty < 0, 'negativeStockLabel expects a negative quantity');
    return 'Âm ${qty.abs()}';
  }

  static const negativeStockLabelPrefix = 'Âm';

  // Stock availability
  static const stockNotUpdated = 'Chưa cập nhật kho';
  static String stockUpdatedAt(String hhmm) => 'Cập nhật kho: $hhmm';
  static String availableStock(int qty) => 'Còn $qty';
  static String lowStock(int qty) => 'Sắp hết ($qty)';
  static String categorySectionCount(int count) => '$count mặt hàng';

  // Reconciliation labels
  static const doiSoatTonKhoHomNay = 'Đối soát tồn kho hôm nay';
  static const showOutOfStockProducts = 'Hiển thị sản phẩm hết hàng';
  static const nhanVien = 'Nhân viên';
  static const ngayDoiSoat = 'Ngày đối soát';
  static const tonDuKien = 'Tồn dự kiến';
  static const giaCoSo = 'Giá cơ sở';
  static const tonDaDem = 'Tồn đã đếm';
  static const soLuongThieu = 'Số lượng thiếu';
  static const soLuongBan = 'Số lượng bán';
  static const soLuongHaoHut = 'Số lượng hao hụt';
  static const donGiaNhapTay = 'Đơn giá nhập tay';
  static const phuongThucThanhToan = 'Phương thức thanh toán';
  static const chonPhuongThucThanhToan =
      'Vui lòng chọn phương thức thanh toán';
  static const lyDoHaoHut = 'Lý do hao hụt';
  static const guiDoiSoat = 'Gửi đối soát';
  static const dangGuiDoiSoat = 'Đang gửi đối soát...';
  static const xacNhanGuiDoiSoat = 'Xác nhận gửi đối soát';
  static const tongSoLuongBan = 'Tổng số lượng bán';
  static const tongSoLuongHaoHut = 'Tổng số lượng hao hụt';
  static const vanDeCanXuLyTruocKhiGui = 'Vấn đề cần xử lý trước khi gửi';
  static const daSanSangGuiDoiSoat = 'Dữ liệu hợp lệ. Có thể gửi đối soát.';
  static const daTatGuiDoiSoatKhiCoLoi =
      'Nút gửi tạm khóa cho đến khi xử lý hết lỗi.';
  static const doiSoatThanhCong = 'Đã lưu đối soát thành công';
  static const doiSoatThatBai = 'Gửi đối soát thất bại';
  static const khongTheTaiDuLieuDoiSoat = 'Không thể tải dữ liệu đối soát';
  static const huongDanTaiLaiDoiSoat =
      'Kiểm tra kết nối mạng rồi bấm tải lại để thử lại bản nháp.';
  static const khongCoSanPhamTrungBay =
      'Không có sản phẩm trưng bày cần đối soát';
  static const huongDanKhongCoSanPhamTrungBay =
      'Nếu hôm nay có sản phẩm, hãy tải lại để đồng bộ dữ liệu mới nhất.';
  static const chuaChonNhanVien = 'Chưa chọn nhân viên';
  static const lichSuDoiSoatTonKho = 'Lịch sử đối soát tồn kho';
  static const xemLichSu = 'Xem lịch sử';
  static const trangThai = 'Trạng thái';
  static const trangThaiOn = 'Ổn';
  static const trangThaiCoLoi = 'Có lỗi';
  static const themDongBan = 'Thêm dòng bán';
  static const soLuongChenhLech = 'Số lượng chênh lệch';
  static const sua = 'Sửa';

  // Reconciliation surplus / restock inflow
  static const soLuongBu = 'Số lượng bù';
  static const nhapBuTonKho = 'Nhập bù tồn kho';
  static const nhapBuHint = 'Số dư sẽ tự nhập bù vào kho khi gửi đối soát';
  static const dongBan = 'Dòng bán';
  static const nhanChip = 'Nhãn chip';
  static const giam = 'Giảm';
  static const tang = 'Tăng';
  static const chuaCoLichSuDoiSoat = 'Chưa có lịch sử đối soát';
  static const khongTaiDuocLichSuDoiSoat = 'Không tải được lịch sử đối soát';
  static const chiTietDoiSoat = 'Chi tiết đối soát';
  static const khongTaiDuocChiTietDoiSoat = 'Không tải được chi tiết đối soát';
  static const soDong = 'Số dòng';
  static const thamChieuDonHang = 'Tham chiếu đơn hàng';
  static const thamChieuThanhToan = 'Tham chiếu thanh toán';
  static const thamChieuDongDonHang = 'Tham chiếu dòng đơn hàng';
  static const thamChieuXuatBan = 'Tham chiếu xuất bán';
  static const thamChieuXuatHaoHut = 'Tham chiếu xuất hao hụt';
  static const khongCo = 'Không có';

  // Reconciliation history detail summary card
  static const tongTonDuKien = 'Tổng tồn dự kiến';
  static const tongTonDaDem = 'Tổng tồn đã đếm';
  static const tongSoLuongSanPham = 'Số sản phẩm';
  static const tongSoDong = 'Tổng số dòng';
  static const tongChenhLech = 'Tổng chênh lệch';
  static const khongPhanLoai = 'Không phân loại';
  static const soDongBan = 'Số dòng bán';
  static const dongBanCu = 'Dòng bán cũ';

  // Markup (trưng bày)
  static const giaGoc = 'Giá gốc';
  static const giaBan = 'Giá bán';
  static const markupFloorWarning = 'Giá bán không được thấp hơn giá gốc';
  static const markupThousandsHint = 'Nhập nghìn đồng (VD: 250 = 250.000đ)';
  static const markupAmount = 'Phần cộng thêm';

  // Extras management
  static const extrasSettings = 'Phụ kiện đi kèm';
  static const addExtra = 'Thêm phụ kiện';
  static const editExtra = 'Sửa phụ kiện';
  static const extraName = 'Tên phụ kiện';
  static const extraPrice = 'Giá phụ kiện';
  static const extraNameHint = 'VD: Nến, Đĩa muỗng';
  static const extraPriceHint = 'VD: 5000';
  static const extraFormatError = 'Định dạng: Tên|Giá (VD: Nến|5000)';
  static const extraAdded = 'Đã thêm phụ kiện';
  static const extraUpdated = 'Đã cập nhật phụ kiện';
  static const extraDeleted = 'Đã xóa phụ kiện';
  static const noExtras = 'Chưa có phụ kiện';
  static const deleteExtraConfirm = 'Xóa phụ kiện này?';
  static const extrasSettingsDeprecatedTitle =
      'Đã dừng quản lý phụ kiện tại đây';
  static const extrasSettingsDeprecatedBody =
      'Phụ kiện trả phí mới được quản lý từ Danh mục sản phẩm (nhóm phu_kien). Mục này chỉ giữ lại để hướng dẫn và không còn tạo/sửa dữ liệu order_extra.';
  static const extrasSettingsDeprecatedAction =
      'Vào Danh mục sản phẩm để thêm/sửa phụ kiện và mức giá.';

  // POS stock labels
  static const khongCoSanPham = 'Chưa có sản phẩm';
  static const trongLuong = 'Trọng lượng';
  static const inPhieu = 'In phiếu';
}