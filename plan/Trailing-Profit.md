Trailing-Profit ở cấp Basket ✅ (ưu tiên #2)

## Mục tiêu
- Đảm bảo basket đang lời không trả lại toàn bộ profit khi thị trường đảo chiều.
- Khóa một phần lợi nhuận đạt được và dời TP nhóm theo hướng có lợi, chỉ nhích lên không bao giờ hạ xuống.
- Cho phép tiếp tục “let profit run” nhưng có chốt từng phần để nạp lãi sang ví earn.

## Tham số cấu hình
- `InpBasketTrail_Enable` (bool, default true) – bật/tắt toàn bộ module.
- `InpTrailTrigger_USD` (double, default 10) – ngưỡng floating PnL để kích hoạt trail.
- `InpTrailStep_USD` (double, default 10) – increment tối thiểu so với đỉnh trước để nhích TP.
- `InpLockPct` (double, default 0.5) – tỷ lệ profit được “khóa” (50% → TP ở BE + 50% profit).
- `InpTrailCooldown_Sec` (int, default 30) – khoảng nghỉ giữa hai lần chỉnh TP.
- tuỳ chọn: `InpTrailATR_Mult` (double, default 1.5) – cần PnL ≥ ATR-based buffer mới trail để lọc nhiễu.

## Trạng thái & cấu trúc dữ liệu
- `BasketState` cho mỗi chiều (LONG/SHORT):
  - `double highUsd` – đỉnh PnL đã ghi nhận.
  - `datetime lastTrailTs` – lần cuối chỉnh group TP.
  - `double lockedUsd` (optional) – số USD đã khóa, phục vụ dashboard/report.
- Cần lưu `BasketState` bền qua restart: hoặc dùng `GlobalVariable` (`EA.BASKET_HIGH_<dir>`, `EA.BASKET_LAST_TS_<dir>`) hoặc serialize file JSON nhẹ.

## Luồng xử lý
1. OnTick (khi module enable và basket đang mở):
   - Đọc `pnl = GetBasketFloatingUsd(dir)`.
   - Nếu `pnl < InpTrailTrigger_USD` ⇒ reset `highUsd` về max(pnl, 0) và return.
   - Nếu đang cooldown (`TimeCurrent() - lastTrailTs < InpTrailCooldown_Sec`) ⇒ bỏ qua.
2. Khi `pnl >= highUsd + InpTrailStep_USD`:
   - Cập nhật `highUsd = pnl`.
   - `lockedUsd = highUsd * InpLockPct`.
   - `target = BasketBreakEvenUsd(dir) + lockedUsd`.
   - `tpPrice = CalcGroupTPFromUsd(dir, target)`; cần hàm chuyển đổi USD sang giá dựa trên tổng volume + commissions.
   - Gọi `ModifyBasketTP(dir, tpPrice)` (điều chỉnh từng order trong nhóm, bảo toàn TP cá nhân cùng mức).
   - Update `lastTrailTs = TimeCurrent()` và ghi log.
3. Không được giảm `tpPrice` khi pnl giảm. Chỉ reset `highUsd/lockedUsd` khi basket đóng hết hoặc kill-switch flat.

## Tích hợp với hệ thống hiện tại
- Khi `IsHalted()` (kill-switch) ⇒ tạm bỏ qua trail để khỏi spam modify.
- Interaction với `Partial-Close`: sau khi chốt từng phần, phải cập nhật lại break-even, volume và giữ `lockedUsd` theo lợi nhuận còn lại.
- Đảm bảo `ModifyBasketTP` phối hợp với `GridRecovery` (không nên override TP trong cùng tick).
- Cần emit event cho Profit Siphon (nếu TP hit vì trailing) để log dòng tiền vào ví earn.

## Logging & quan sát
- Log chuẩn: `TRAIL dir=LONG pnl=25.4 lock=12.7 tp=1.12345`.
- Dashboard hiển thị: PnL hiện tại, highUsd, lockedUsd, TP giá hiện tại, thời gian còn lại đến hết cooldown.
- Alert khi trail cập nhật > X lần trong 1h (cảnh báo nhiễu).

## Công việc triển khai
- [ ] Thêm input và `BasketState` (struct + GV helper).
- [ ] Viết `GetBasketFloatingUsd`, `BasketBreakEvenUsd`, `CalcGroupTPFromUsd` nếu chưa có.
- [ ] Viết `TrailBasket(dir)` và gọi từ OnTick sau khi cập nhật PnL.
- [ ] Đồng bộ với module partial close + kill-switch (xử lý reset state khi basket đóng).
- [ ] Bổ sung logging + telemetry (CSV/Prometheus).

## Kiểm thử
- Backtest control: thị trường trending ⇒ basket lời > trigger, kiểm tra lệnh TP dời theo step.
- Backtest reversal: PnL đạt đỉnh rồi đảo ⇒ TP giữ ở mức khóa, basket đóng với lợi nhuận đã lock.
- Scenario partial close: sau khi giảm khối lượng, trail tiếp tục hoạt động đúng với volume còn lại.
- Restart test: kill EA giữa lúc trail active, bật lại ⇒ state được load chính xác, không nhảy TP xuống.
- Stress test: PnL dao động quanh trigger ⇒ cooldown giúp tránh spam modify.

## Vận hành & tối ưu
- Theo dõi số lần trail và tổng USD khóa được mỗi phiên để đánh giá hiệu quả.
- Tinh chỉnh `InpLockPct` dựa trên biến động: có thể 0.3 cho thị trường nhiễu, 0.7 khi trend mạnh.
- Kết hợp Time-of-Day filter: chỉ trail trong khung thanh khoản cao để tránh slip.
- Mở rộng: hỗ trợ trail theo ATR hoặc tỷ lệ % thay vì USD cố định, tùy cặp tiền.
