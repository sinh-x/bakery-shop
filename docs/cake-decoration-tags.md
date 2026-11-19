# Mẫu tag trang trí bánh

## Bản in 20–11 hiện tại

Bản hiện tại dùng **nữ giáo viên chibi mặc áo dài, không đeo kính**:
giáo viên áo hồng cầm sách và hoa cho cô Nhiệt; giáo viên áo tím cầm sách và
thước chỉ cho cô Nỡ. Hai tag nằm trên **một tờ A6 ngang, 148 × 105 mm**:

1. Chúc cô Nhiệt 20 - 11 vui vẻ
2. Chúc cô Nỡ 20 - 11 vui vẻ. Cảm ơn cô nhiều

- [PDF để in — giáo viên chibi](../designs/cake-tags/teachers-day/exports/cake-tags-teacher-chibi-20-11-a6.pdf)
- [PNG 300 DPI — giáo viên chibi](../designs/cake-tags/teachers-day/exports/cake-tags-teacher-chibi-20-11-a6.png)

Bản nhân vật bé gái trước đó vẫn được giữ nguyên:
[PDF cũ](../designs/cake-tags/teachers-day/exports/cake-tags-20-11-a6.pdf) và
[PNG cũ](../designs/cake-tags/teachers-day/exports/cake-tags-20-11-a6.png).

Chọn giấy **A6**, hướng **ngang**, tỷ lệ **100% / Actual size**. Tắt tùy chọn
“Fit to page”. Cắt theo viền hồng lượn sóng; không cắt theo đường chỉ hồng
nét đứt phía trong. Có lề trắng quanh trang và khoảng cách giữa hai tag.
Ảnh PNG có kích thước 1748 × 1240 px; kích thước PDF được làm tròn theo
độ phân giải 300 DPI, sai khác với A6 dưới 0,02 mm.

## Tài nguyên thiết kế cục bộ

Thư mục chính: [`designs/cake-tags/teachers-day/`](../designs/cake-tags/teachers-day/).

| Đường dẫn | Nội dung |
| --- | --- |
| `references/` | Năm ảnh tham khảo gốc, không chỉnh sửa; `sources.json` ghi sáu tên nguồn và SHA-256, gồm một bản trùng. |
| `templates/teacher-chibi-blank.png` | Mẫu hiện tại: hai nữ giáo viên áo dài không đeo kính, không chữ, tạo từ ảnh tham khảo bằng `gpt-image-2`. |
| `templates/chibi-pink-generated.png` | Nền bé gái chibi gốc, được giữ lại cho các lần dùng sau. |
| `templates/chibi-pink-blank.png` | Mẫu bé gái chibi không chữ, đã làm trắng nền ngoài tag để dùng lại. |
| `fonts/DancingScript-Bold.ttf` | Phông chữ viết tay hỗ trợ tiếng Việt, đi kèm giấy phép `OFL.txt`. |
| `messages.json` | Các dòng lời chúc và phần tên tô hồng. |
| `render-cake-tags.py` | Dàn chữ chính xác, không tạo lại hình minh họa. |
| `exports/` | PNG và PDF hoàn chỉnh. |

Hai ảnh Signal có giờ `09-43-51` và `09-44-50` giống hệt nhau theo SHA-256,
nên chỉ lưu một bản và ghi nhận cả hai tên nguồn trong `sources.json`.
Hai sheet `teacher-chibi-collection-01.webp` và `teacher-chibi-collection-02.webp`
được lưu nguyên bản làm tham khảo cho hình giáo viên; không ghép 12 tag có sẵn
trong hai sheet vào bản in. Chỉ hai lời chúc gốc được xuất thành tag cá nhân hóa.
Những ảnh tham khảo này chỉ phục vụ thiết kế tag, không được đưa vào thư viện quảng cáo.
Git chỉ theo dõi `render-cake-tags.py` trong thư mục thiết kế này.
Ảnh PNG/WebP, PDF, phông chữ, `messages.json` và các tài nguyên hỗ trợ được
`.gitignore` loại bỏ nhưng vẫn giữ nguyên trên máy. Khi clone repo mới, cần
cung cấp lại các tài nguyên cục bộ này trước khi chạy script; chúng không
được tải về cùng mã nguồn.

## Sửa tên hoặc lời chúc cho lần sau

Cần Python 3 và Pillow: `python -m pip install Pillow` nếu môi trường chưa có.
Phông chữ nằm trong thư mục thiết kế cục bộ; khi đã có đủ tài nguyên,
không cần cài phông hệ thống, đăng nhập hay gọi AI để xuất lại bản in.

1. Sửa `messages.json`: mỗi tag có hai hoặc ba dòng trong `lines`.
2. Sửa `highlight` thành tên muốn tô hồng, hoặc để chuỗi rỗng.
3. Chạy từ thư mục gốc repo:

```sh
python designs/cake-tags/teachers-day/render-cake-tags.py
```

Lệnh dùng mẫu giáo viên không đeo kính và ghi lại hai file
`cake-tags-teacher-chibi-20-11-a6.png` / `.pdf` trong `exports/`.
Nếu muốn giữ bản hiện tại, dùng tên khác:

```sh
python designs/cake-tags/teachers-day/render-cake-tags.py \
  --messages /path/to/new-messages.json \
  --output-name cake-tags-new-message-a6
```

Có thể thêm `--output-dir /path/to/output` để đổi nơi lưu. Dùng
`--template designs/cake-tags/teachers-day/templates/chibi-pink-blank.png` nếu
muốn quay lại mẫu bé gái trước đó; nên đi kèm tên xuất khác để không ghi đè
bản giáo viên. Chữ được tự thu nhỏ
trong giới hạn bố cục; nếu một dòng quá dài, chương trình báo lỗi thay vì tràn
lên nhân vật hoặc hoa. Hãy chia lại dòng hoặc rút gọn lời chúc khi gặp lỗi này.

Phông Dancing Script được phân phối theo SIL Open Font License 1.1.
[Nguồn giấy phép](https://raw.githubusercontent.com/google/fonts/main/ofl/dancingscript/OFL.txt).
