/// Stock-domain Vietnamese labels for the bakery app.
///
/// Per the VN Label Policy in CLAUDE.md and §5 of
/// docs/flutter-coding-standards.md, user-facing copy for the stock
/// management feature lives in its own domain file rather than being
/// appended to the monolithic `VN` class. Consumers import this file and use
/// `StockLabels.*` for new labels or `VN.*` for legacy labels still
/// re-exported via `vietnamese_labels.dart`.
class StockLabels {
  StockLabels._();

  // Stock helpers
  static const useInventory = 'Dùng tồn kho';
  static const stockRemaining = 'Còn';
  static const stockUnknown = 'Chưa có số tồn';
  static const stockNotUpdated = 'Chưa cập nhật kho';
  static String stockUpdatedAt(String hhmm) => 'Cập nhật kho: $hhmm';
  static String availableStock(int qty) => 'Còn $qty';
  static String lowStock(int qty) => 'Sắp hết ($qty)';
  static String categorySectionCount(int count) => '$count mặt hàng';
  static const outOfStock = 'Hết hàng';

  // Negative stock display (DG-200 Phase 5, FR-8, AC-10)
  /// Label for products with a negative net stock position.
  /// `Âm N` reads as `Âm <N>` where N is the absolute quantity.
  static String negativeStockLabel(int qty) {
    assert(qty < 0, 'negativeStockLabel expects a negative quantity');
    return 'Âm ${qty.abs()}';
  }

  static const negativeStockLabelPrefix = 'Âm';

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
  static const chonPhuongThucThanhToan = 'Vui lòng chọn phương thức thanh toán';
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

  // Reconciliation surplus / restock inflow (DG-200 Phase 6, FR-9, AC-11)
  /// Label for the surplus inflow quantity (counted - expected, when > 0).
  /// Reads as `Số lượng bù: +N`.
  static const soLuongBu = 'Số lượng bù';

  /// Restock indicator title shown next to a surplus option.
  static const nhapBuTonKho = 'Nhập bù tồn kho';

  /// Hint explaining that surplus will auto-create a restock inflow.
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

  // Reconciliation history detail summary card (DG-155 Phase 4.3)
  static const tongTonDuKien = 'Tổng tồn dự kiến';
  static const tongTonDaDem = 'Tổng tồn đã đếm';
  static const tongSoLuongSanPham = 'Số sản phẩm';
  static const tongSoDong = 'Tổng số dòng';
  static const tongChenhLech = 'Tổng chênh lệch';
  static const khongPhanLoai = 'Không phân loại';
  static const soDongBan = 'Số dòng bán';
  static const dongBanCu = 'Dòng bán cũ';
}