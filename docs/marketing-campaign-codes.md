# Quy ước mã ảnh chiến dịch quảng cáo

> **Cập nhật riêng cho bộ tháng 11 (04/11/2026):** chủ tiệm yêu cầu bỏ số/mã
> hiển thị và duyệt đúng 16 ảnh trong `ads/20261101-bo-cap/processed/drafts/photos/`.
> Theo yêu cầu bổ sung 05/11/2026, bộ này xuất vuông 1080 × 1080, crop ảnh vuông
> trong khung vuông bo góc, chữ **Đoàn Gia đỏ** căn giữa phía trên bên trong khung.
> Không nhãn nháp hoặc mã hiển thị. Mã/số vẫn giữ
> trong tên file và metadata để truy vết; không đổi bảng tháng hoặc đánh số lại.
> Xem `photo-approval.json` trong thư mục chiến dịch. Ngoại lệ trình bày này không
> áp dụng cho nguồn mới, ảnh tham khảo, duyệt caption hoặc tự đăng bài. Yêu cầu
> crop/bố cục lưu trong hồ sơ duyệt, không đồng nghĩa chủ tiệm đã xem JPEG tạo lại.

## Định dạng đã thống nhất: `26-N41`

Chủ tiệm đã xác nhận bảng chữ theo tháng và chốt định dạng **`26-N41`** ngày 01/11/2026.

```text
YY-LNN
│  │└─ Số ảnh gốc, ít nhất hai chữ số
│  └── Một chữ cái đại diện tháng
└───── Hai chữ số cuối của năm
```

Ví dụ **`26-N41`**:

- **26**: năm **2026**.
- **N**: tháng **11**, đọc **en-nờ**.
- **41**: ảnh số **41** trong danh mục ảnh quảng cáo.
- Một dấu gạch ngang ASCII `-` sau năm; **không có khoảng trắng**.

Không dùng `N26-41`, `26N41`, `N41` hoặc từ như “Nắng 41” làm định dạng hiện hành.

## Bảng chữ theo tháng — giữ cố định

| Tháng | Chữ | Cách đọc |
|---|:---:|---|
| 1 | A | a |
| 2 | B | bê |
| 3 | C | xê |
| 4 | D | dê |
| 5 | E | e |
| 6 | G | giê |
| 7 | H | hát |
| 8 | K | ca |
| 9 | L | e-lờ |
| 10 | M | em-mờ |
| 11 | N | en-nờ |
| 12 | T | tê |

Đây là các chữ thuộc bảng chữ cái tiếng Việt. Không dùng F/J/W/Z; tránh I/O dễ nhầm với 1/0. Không tự đổi bảng chữ hoặc suy ra mã từ tên bánh hay chủ đề cung hoàng đạo.

## Ví dụ

| Mã | Ý nghĩa |
|---|---|
| `26-N41` | Tháng 11/2026, ảnh 41 |
| `26-N09` | Tháng 11/2026, ảnh 09 |
| `26-T41` | Tháng 12/2026, cùng ảnh 41 |
| `27-A41` | Tháng 1/2027, cùng ảnh 41 |
| `06-N41` | Tháng 11 của năm có đuôi 06; năm đầy đủ phải có trong hồ sơ/tên file |

## Giữ nguyên danh tính ảnh

- **Không đánh số lại** khi đổi tháng, năm, tên chiến dịch hoặc xuất bộ ảnh nhỏ hơn.
- Số ảnh là **index quảng cáo**, không phải ID ảnh trong database và không phải giá bánh.
- Giữ số 0 đầu của các index nhỏ: `09` thành **`26-N09`**, không rút thành `26-N9`.
- Số lớn hơn 99 giữ nguyên, ví dụ ảnh 123 thành `26-N123`.
- Không tái sử dụng số ảnh đã bị loại vĩnh viễn. Luôn tuân thủ `ads/library-exclusions.json`.
- Một ảnh đã có index từ bộ trước phải giữ index đó, không được cấp số mới chỉ vì đưa vào chiến dịch mới.

## Trình bày trên ảnh và nội dung bán hàng

- **Định dạng có mã trước đây/mặc định:** ảnh bánh thật + logo nhỏ + mã như **`26-N41`**. Riêng bộ tháng 11 hiện hành đã được yêu cầu ẩn mã theo ghi chú ở đầu tài liệu.
- Giá, kích thước tham khảo, địa chỉ, số điện thoại, giao hàng và câu inbox chỉ đặt trên **ảnh bìa hoặc caption**, không lặp lại trên từng ảnh bánh.
- Khi còn ở giai đoạn bản nháp có mã, dùng nhãn **BẢN NHÁP · CHỜ DUYỆT**. Bộ 16 ảnh tháng 11 đã duyệt bỏ nhãn này; không suy ra duyệt cho ảnh mới.
- Khi mã còn hiển thị, khách có thể gửi mã cho tiệm, ví dụ: “Cho mình hỏi mẫu **26-N41**”. Với bộ tháng 11 hiện đã ẩn mã, caption mời khách gửi ảnh mẫu thay vì mã.

## Lưu trữ và nguồn dữ liệu

- Git chỉ giữ `ads/README.md`, `ads/library-exclusions.json`, `ads/monthly-campaigns.json` và tài liệu quy ước này. Script, ảnh, file xuất và hồ sơ từng chiến dịch trong `ads/` được giữ local/ignored; cần tự sao lưu và khôi phục nếu muốn tạo lại. Các đường dẫn nguồn/manifest bên dưới không có sẵn trong bản clone mới. Không suy ra trạng thái duyệt khi thiếu hồ sơ local.

- Dữ liệu dùng chung: [`ads/monthly-campaigns.json`](../ads/monthly-campaigns.json).
- Mã hiển thị dùng năm hai chữ số; tên file và hồ sơ luôn giữ **năm đầy đủ**, ví dụ:
  `ads/20261101-bo-cap/processed/drafts/photos/2026-11-n-41.jpg`.
- Nhờ năm đầy đủ trong đường dẫn/manifest, các năm khác thế kỷ không bị gộp chỉ vì có cùng đuôi năm hai số. Không coi mã hiển thị là khóa lưu trữ toàn thời gian.
- `source-selection.json` ánh xạ số ảnh với nguồn DB hoặc upload và hash file. `manifest.json` ghi mã khách đọc, năm/tháng và file xuất.
- Bộ tháng 11 (thư mục lịch sử `20261101-bo-cap`) hiện dùng **`26-N09`**, **`26-N32`**…**`26-N46`**. Ba ảnh Đoàn Gia `IMG_3305–3307.jpg` được cấp tiếp **44–46**; bảy ảnh `IMG_3308–3314.jpg` chỉ tham khảo riêng, không cấp mã quảng cáo. Số chưa dùng tiếp theo là **47**. DB458 đã bị loại khỏi chiến dịch, DB692 không được chọn; không thay đổi ảnh gốc trong DB.
- Bộ hiện hành chỉ có các file ảnh bánh riêng và một caption chung chúc sinh nhật tháng 11, nhắc nhẹ 20/11; không dùng cung hoàng đạo, ảnh bìa hoặc tổng hợp preview. `source-selection.json` lưu cả nguồn upload ngoài DB; `external-references.json` giữ ranh giới ảnh chỉ tham khảo.

Nếu cần thay đổi quy ước, xác nhận lại với chủ tiệm rồi cập nhật đồng thời tài liệu này, JSON dùng chung, formatter, kiểm thử, caption và các bản ảnh đang sử dụng.
