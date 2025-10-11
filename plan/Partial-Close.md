Partial-Close bậc thang ✅ (ưu tiên #3)

## Mục tiêu
- Thu hồi một phần lợi nhuận đã đạt được ở các mốc USD cố định để nạp sang ví earn, giảm thiểu trả lại profit.
- Giữ phần vị thế còn lại để tiếp tục chạy với Basket Trailing-Profit, tận dụng trend.
- Phối hợp với strategy kill-switch và profit ledger để thống kê dòng tiền giữa ví cháy ↔ ví earn.

## Nguyên tắc chung
- Hoạt động khi basket floating profit đạt các mốc USD tăng dần (ví dụ $30, $60, $100...).
- Mỗi lần chạm mốc ⇒ đóng `closePct` khối lượng còn mở (thường 30–50%).
- Sau partial close ⇒ cập nhật break-even, khối lượng còn lại, và sync với module trailing.
- Không partial nếu:
  - Basket chưa đạt BE (floating âm hoặc quá nhỏ).
  - Đang trong cooldown (vừa partial xong).
  - Kill-switch đang active (do kill-switch đã đóng sạch).
- Khi partial close thành công ⇒ ghi nhận lợi nhuận vào Profit Siphon log.

## Tham số cấu hình
- `InpPartialClose_Enable` (bool, default true).
- `InpPartialCloseLevels` (string, default `"30,60,100,150"` USD) – danh sách mốc.
- `InpPartialClosePct` (double, default 0.4) – phần trăm volume đóng khi đạt mốc.
- `InpPartialCooldown_Sec` (int, default 60) – thời gian nghỉ giữa hai partial để tránh spam.
- `InpPartialMinLot` (double, optional) – không partial nếu khối lượng còn lại nhỏ hơn min lot.
- `InpPartialMinDistance_Pips` (optional) – yêu cầu giá chạy đủ xa BE để tránh partial quá sát.
- `InpPartialLockToSiphon` (bool) – nếu true, auto log `SIPHON` khi partial.

## Trạng thái & cấu trúc dữ liệu
- `PartialState[dir]` lưu cho LONG/SHORT:
  - `int nextLevelIdx` – index kế tiếp trong danh sách mốc.
  - `datetime lastPartialTs` – thời điểm partial gần nhất.
  - `double realizedUsd` – tổng USD đã thu từ partial (hiển thị dashboard).
- Cần lưu `GlobalVariable` hoặc file để survive restart: `EA.PARTIAL_NEXT_<dir>`, `EA.PARTIAL_LAST_TS_<dir>`, `EA.PARTIAL_REALIZED_<dir>`.
- Tích hợp với Profit Ledger để ghi `REALIZED_PARTIAL dir=... usd=...`.

## Thuật toán
1. Trong OnTick (sau khi cập nhật basket PnL):
   - Nếu module disable hoặc `IsHalted()` ⇒ return.
   - Lấy `pnl = GetBasketFloatingUsd(dir)`; nếu `pnl <= 0` ⇒ reset về level đầu, return.
   - Nếu `TimeCurrent() - lastPartialTs < InpPartialCooldown_Sec` ⇒ return.
   - Xác định `targetUsd = levels[nextLevelIdx]`.
   - Nếu `pnl < targetUsd` ⇒ return.
2. Partial close:
   - Tính `volumeClose = BasketVolume(dir) * InpPartialClosePct`, làm tròn xuống theo step lot.
   - Nếu `volumeClose < InpPartialMinLot` ⇒ skip và log warning.
   - Gọi `CloseBasketPortion(dir, volumeClose)` – đóng đều trên các orders của basket (ưu tiên lệnh xa nhất BE).
   - Nếu đóng thành công:
     - Cập nhật `lastPartialTs = TimeCurrent()`.
     - `realized = ComputeClosedProfit(volumeClose)`; add vào `realizedUsd`.
     - `nextLevelIdx++` (khóa mốc đã đạt).
     - Emit log & alert.
     - Trigger Profit Siphon: ghi ledger, đánh dấu cần chuyển lãi sang ví earn.
   - Nếu thất bại (partial đóng không trọn):
     - Retry từng order; nếu vẫn fail ⇒ log error, giữ level hiện tại (không tăng).
3. Reset logic:
   - Khi basket flat ⇒ reset `nextLevelIdx = 0`, `lastPartialTs = 0`, `realizedUsd = 0` (optional giữ để report).
   - Khi kill-switch đóng toàn bộ ⇒ reset như trên.

## Tích hợp với các module khác
- **Basket Trailing**: Sau partial, cần re-calc break-even & highUsd vì volume giảm.
- **Profit Siphon Tracker**: Partial close = event “lãi chuyển ví earn”; update ledger & dashboard.
- **Kill-Switch**: Khi kill-switch trigger, partial phải dừng, state reset.
- **Dynamic Spacing/Refill**: Nếu partial giảm volume đáng kể, cho phép seed/refill trở lại theo rule (optional).
- **Time-Exit**: Partial không nên cản trở logic Time-Exit; có thể khiến Time-Exit đóng phần còn lại sớm hơn.

## Logging & Telemetry
- Log event: `PARTIAL dir=LONG level=60usd closed=0.24 lots realized=+25.3`.
- Telemetry: số partial/day, tổng USD thu được, % volume trung bình giữ lại.
- Alert nếu partial fail > N lần liên tiếp hoặc volume còn lại dưới min lot nhưng vẫn chưa đạt TP (để cân nhắc đóng hết).

## Kiểm thử
- Backtest trending strong: Basket tăng qua nhiều mốc ⇒ kiểm tra partial diễn ra đúng, trailing giữ phần còn lại và TP cuối cùng khớp.
- Backtest chop: PnL dao động quanh một mốc ⇒ cooldown ngăn partial lặp liên tục.
- Test partial + kill-switch: kill-switch kích hoạt giữa lúc partial; đảm bảo state reset.
- Restart test: partial đã chạy 1–2 level, restart EA ⇒ level index tiếp tục chính xác.
- Manual test: sử dụng script ép giá để kiểm tra `CloseBasketPortion` khi volume lẻ nhỏ.

## Vận hành & tối ưu
- Điều chỉnh danh sách mốc theo cặp tiền/lot size (có thể dynamic dựa trên ATR).
- Nghiên cứu adaptive `closePct` (giảm dần khi lên mốc cao để giữ phần chạy).
- Sử dụng dashboard để hiển thị: level kế tiếp, realized partial, thời gian từ partial gần nhất.
- Sau khi triển khai, theo dõi: tỷ lệ partial hit vs full TP, ảnh hưởng đến drawdown & volatility của equity curve.
