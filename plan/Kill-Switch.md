Kill-Switch phiên ở −$200 + Cooldown 30 phút ✅ (ưu tiên #1)

## Mục tiêu
- Giới hạn drawdown phiên ở mức −200 USD rồi bật chế độ “đóng băng” 30 phút.
- Đảm bảo trạng thái dừng giao dịch sống sót qua restart/mất kết nối.
- Cho phép khởi động lại phiên một cách sạch, reseed vị thế theo cấu hình bình thường.

## Điều kiện kích hoạt
- Mỗi tick tính `session_drawdown = AccountEquity() - AccountBalance()`.
- Nếu `session_drawdown <= -InpSessionHardSL_USD` và hệ thống chưa bị halt ⇒ đóng toàn bộ vị thế, đặt thời gian cooldown.
- Khi đang trong cooldown (`TimeCurrent() < GV_HALT_UNTIL`) ⇒ bỏ qua mọi logic seed/refill/modify, chỉ cho phép lệnh quản trị tối thiểu (ví dụ update GV).

## Tham số cấu hình
- `InpSessionHardSL_USD` (double, mặc định 200) – ngưỡng hard stop cho phiên.
- `InpHaltCooldown_Minutes` (int, mặc định 30) – thời lượng cooldown.
- `InpHardSL_CloseAllRetries` (int, mặc định 5) – số lần thử đóng tất cả vị thế.

## Trạng thái bền vững (GlobalVariables)
- `EA.HALT_UNTIL` (double -> datetime) – thời điểm hết cooldown.
- `EA.SESSION_START_BAL` (double) – ghi nhận balance đầu phiên để phục vụ thống kê.

## Luồng xử lý chính
1. `IsHalted()` đọc `EA.HALT_UNTIL`; trả về true nếu `TimeCurrent()` vẫn nhỏ hơn thời điểm này.
2. `CheckHardSessionSL()`:
   - Tính drawdown.
   - Nếu vi phạm ngưỡng và chưa halt ⇒ gọi `CloseAllPositions(InpHardSL_CloseAllRetries)`.
   - Khi đóng thành công ⇒ đặt `EA.HALT_UNTIL = TimeCurrent() + cooldown_seconds`, log sự kiện, update metrics.
3. Trong vòng lặp OnTick:
   - Nếu `IsHalted()` ⇒ bỏ qua `Seed`, `Refill`, `Modify`, `GridRecovery`.
   - Nếu không bị halt và `TimeCurrent() >= GV_HALT_UNTIL` ⇒ reset `EA.SESSION_START_BAL = AccountBalance()` và cho phép logic bình thường chạy lại.

## CloseAll an toàn
- Đóng theo từng symbol để giảm rủi ro `TRADE_CONTEXT_BUSY`.
- Khi gặp lỗi busy ⇒ `Sleep(100-200 ms)` rồi retry; dừng sau `InpHardSL_CloseAllRetries`.
- Nếu không đóng hết ⇒ chuyển sang đóng từng phần nhỏ (ví dụ 25% volume).
- Xử lý trường hợp thị trường đóng/maintenance: nếu không thể khớp lệnh ⇒ cập nhật `EA.HALT_UNTIL` kéo dài thêm 30 phút sau giờ mở lại, đồng thời gửi alert (Push/Telegram).

## Công việc triển khai
- [ ] Thêm tham số input + mô tả rõ trong EA.
- [ ] Viết wrapper `GetGlobalDatetime/SetGlobalDatetime` để làm việc với `GlobalVariable` gọn.
- [ ] Cài đặt `IsHalted()` và tích hợp vào các chỗ nhánh logic (Seed, Refill, Modify, GridRecovery).
- [ ] Hoàn thiện `CloseAllPositions` với retry + partial close.
- [ ] Logging: `.csv` + alert cảnh báo khi kill-switch kích hoạt/hết cooldown.
- [ ] Cập nhật dashboard/metrics để hiển thị trạng thái halt và thời gian còn lại.

## Kiểm thử & xác nhận
- Backtest với dữ liệu tick để ép drawdown nhanh và quan sát hành vi (đặc biệt phiên cuối tuần).
- Test forward trên demo: ép drawdown thủ công bằng tay (manual trade) và xem EA phản ứng.
- Scenario test: (1) mất kết nối rồi reconnect trong thời gian cooldown, (2) EA restart giữa lúc cooldown, (3) cố gắng seed khi cooldown.
- Kiểm tra log đảm bảo không spam, trạng thái được reset đúng lúc hết cooldown.

## Vận hành & giám sát
- Thiết lập Telegram/Discord alert khi kill-switch bật/tắt.
- Trong dashboard theo dõi thời gian còn lại của cooldown và drawdown hiện tại.
- Sau khi cooldown kết thúc ⇒ log rõ “SESSION_RESET” để dễ audit.
- Đặt KPI: số lần trigger / tuần, tỷ lệ phục hồi sau kill-switch; dùng để tinh chỉnh `InpSessionHardSL_USD`.

## Việc tiếp theo (liên quan ví cháy)
- Khi kill-switch kích hoạt, flag lại để bot nạp tiền từ ví lãi sang ví cháy theo rule mới (sẽ triển khai ở module khác).
- Ghi nhận tổng lãi đã bơm vào ví cháy sau mỗi phiên để phục vụ risk report.
