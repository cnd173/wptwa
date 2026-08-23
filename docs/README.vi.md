# Poker Table Arranger cho macOS

Đây là tiện ích macOS mã nguồn mở, không chính thức, dùng để đưa cửa sổ poker client được hỗ trợ vào các slot trên màn hình. Adapter hiện tại chỉ nhận WPT Global qua bundle ID chính xác `com.wptglobal.wptg`.

## Nguyên tắc an toàn

- App luôn khởi động ở trạng thái **Đã dừng** và chỉ di chuyển cửa sổ sau khi người dùng bấm **Bắt Đầu Sắp Xếp**.
- App chỉ đọc tiêu đề, vị trí và kích thước cửa sổ qua Accessibility API.
- App không đọc bài, không chụp màn hình, không đặt cược, không chọn ghế, không hiển thị HUD và không đưa ra lời khuyên chiến thuật.
- Dữ liệu preset, cấu hình và nhật ký session chỉ nằm trong `~/Library/Application Support/PokerTableArranger/`.

## Build

Yêu cầu macOS 13 trở lên và Swift 5.9 trở lên:

```bash
cd macos/WPTTableArranger
./build_app.sh
open "Poker Table Arranger.app"
```

Lệnh `swift test` cần full Xcode trên các máy mà gói Command Line Tools độc lập không có XCTest.

Bản build mặc định dùng chữ ký ad-hoc cho phát triển. Sau mỗi lần rebuild, macOS có thể yêu cầu xóa và cấp lại quyền Accessibility. Bản phát hành cho người dùng cuối phải được ký bằng Developer ID và notarize theo [RELEASING.md](../RELEASING.md).

## Tuyên bố độc lập

Dự án không liên kết, không được bảo trợ hoặc xác nhận bởi WPT Global hay World Poker Tour. Tên và thương hiệu liên quan thuộc về chủ sở hữu tương ứng. Người dùng có trách nhiệm kiểm tra điều khoản nền tảng hiện hành trước khi sử dụng.

Xem tài liệu đầy đủ bằng tiếng Anh tại [README.md](../README.md), chính sách dữ liệu tại [PRIVACY.md](../PRIVACY.md), và giấy phép tại [LICENSE](../LICENSE).
