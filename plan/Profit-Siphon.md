Profit Siphon Tracker ✅ (ưu tiên #7)

## Mục tiêu
- Theo dõi và ghi nhận chính xác phần lợi nhuận đã “rút” sang ví earn, phù hợp chiến lược cháy ví vs ví lãi.
- Tạo ledger bền vững (log file + GlobalVariables) để audit được dòng tiền, kể cả khi EA restart.
- Tự động phát tín hiệu thông báo (Telegram) mỗi khi đạt mốc +$100 closed PnL và kích hoạt quy trình chuyển lãi.

## Khái niệm
- “Lãi đã rút”: tổng closed PnL kể từ lần siphon gần nhất. Khi vượt ngưỡng `threshold` (ví dụ 100 USD) ⇒ ghi nhận “Siphon Event”, reset bộ đếm.
- Hỗ trợ nhiều mốc lũy tiến (ví dụ 100, 200, 500) hoặc mốc cố định reset mỗi lần.
- Liên kết với Partial-Close & Basket TP để cập nhật ledger ngay khi lệnh đóng.

## Tham số cấu hình
- `InpSiphon_Enable` (bool, default true).
- `InpSiphonThreshold_USD` (double, default 100) – mức closed PnL cần đạt để ghi event.
- `InpSiphonStepDynamic` (bool) – nếu true, threshold tăng theo equity (ví dụ 1% balance).
- `InpSiphonLogFile` (string, default `"siphon-ledger.csv"`).
- `InpSiphonResetDaily` (bool) – reset bộ đếm vào đầu ngày mới.
- `InpSiphonNotify_Telegram` (bool) – gửi telegram khi siphon.
- `InpSiphonNotifyFormat` (enum: Plain, HTML) – định dạng tin nhắn.

## Dữ liệu & trạng thái bền
- GlobalVariables:
  - `EA.SIPHON_ACCUM` – tổng closed PnL đã dồn từ lần siphon cuối.
  - `EA.SIPHON_LAST_TS` – thời điểm lần siphon gần nhất.
  - `EA.SIPHON_TOTAL` – tổng USD đã siphon kể từ khi bật module.
- Ledger file `files/siphon-ledger.csv` (append):
  - Cột gợi ý: `timestamp, ticket, type, usd, balance_after, comment`.
  - Event `SIPHON_TRIGGER` ghi USD chuyển, cumulative total, equity lúc đó.
- Sử dụng event-driven: khi lệnh đóng (`OnTradeTransaction`), cập nhật accum. Nếu accum >= threshold ⇒ tạo event.

## Luồng xử lý
1. Khi nhận `TRADE_TRANSACTION_DEAL_ADD` và `profit > 0`:
   - `accum += profit - commissions - swaps`.
   - Append log `DEAL_CLOSED`.
   - Nếu `accum >= threshold` ⇒ gọi `TriggerSiphon()`.
2. `TriggerSiphon()`:
   - Ghi log `SIPHON_TRIGGER` vào ledger (timestamp, usd=accum, balance).
   - Reset `accum = 0` hoặc `accum -= threshold` tùy `thresholdMode`.
   - Cập nhật `EA.SIPHON_TOTAL += siphonUsd`.
   - Gửi Telegram nếu enable:
     ```
     TgSend(StringFormat("💰 <b>Profit Siphon</b>: +%.2f USD chuyển sang ví earn. Total siphon=%.2f USD.", siphonUsd, total));
     ```
   - Optional: phát sự kiện nội bộ để bot thực hiện chuyển tiền (manual confirmation).
3. Reset hàng ngày:
   - Nếu `InpSiphonResetDaily` và sang ngày mới ⇒ ghi event `RESET_DAILY`, set `accum=0`.
4. Tích hợp với Partial-Close:
   - Partial close → lệnh đóng → profit đi vào accum.
   - Có thể đánh dấu log comment `"partial"` để phân tích tỷ trọng partial vs TP.
5. Tích hợp với Kill-Switch:
   - Khi kill-switch activate ⇒ ghi log `HARD_SL`; accum có thể âm, không siphon. Reset accum nếu cần.

## UI & Monitoring
- Panel hiển thị:
  - `Siphon Accumulated: $X`.
  - `Next Threshold: $Y`.
  - `Total Siphoned: $Z`.
  - Thời gian lần siphon cuối.
- Telegram notifications:
  - Khi siphon: highlight emoji, kèm link sổ ledger (nếu có).
  - Khi accum > threshold*2 (quá lâu chưa chuyển) ⇒ cảnh báo review.

## Logging
- Append CSV với timezone chuẩn UTC.
- In journal: `SIPHON accum=85.3 threshold=100`, `SIPHON_TRIGGER usd=105.5 total=305.5`.
- Provide helper `WriteLedgerRow(string type,double usd,string comment="")`.

## Kiểm thử
- Backtest scenario: Partial close nhiều nhỏ ⇒ accum vượt 100 → trigger.
- Backtest scenario: lệnh lãi lớn một lần ⇒ accum > threshold*3 → test logic subtract vs reset.
- Forward test: restart EA sau khi accum=80 ⇒ ensure state restored.
- Negative profit: verify accum không giảm <0 (chỉ tính profit dương). Nếu want net → allow subtract.
- Telegram sandbox: check WebRequest, confirm message format OK.

## Vận hành & tối ưu
- Có thể nâng cấp ledger sang SQLite hoặc Google Sheets API (future).
- Tùy biến threshold theo ngày trong tuần/volatility.
- Thêm module “Auto withdraw”: xuất danh sách yêu cầu chuyển tiền sang ví earn.
- Kết hợp dashboard (Grafana/Prometheus) hiển thị cumulative siphon vs. kill-switch times.
