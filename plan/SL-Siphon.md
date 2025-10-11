SL-Siphon (Low Wallet Alert) ✅ (ưu tiên #8)

## Mục tiêu
- Giám sát số dư ví “cháy” (tài khoản chuyên gánh lỗ) và cảnh báo khi vốn xuống dưới ngưỡng tối thiểu.
- Nhắc trader nạp thêm tiền từ ví earn (đã siphon) để duy trì khả năng chịu đựng drawdown và hỗ trợ kill-switch.
- Kết nối với Profit Siphon Tracker để đề xuất lượng nạp tương ứng với lãi đã tích lũy.

## Phạm vi
- Theo dõi `AccountBalance()` hoặc số dư ví riêng (nếu sử dụng đa tài khoản).
- Nếu balance < `minBalanceUsd` ⇒ phát thông báo (Telegram, log, dashboard).
- Có thể đề xuất số tiền nạp = `minTopupUsd` hoặc matching với ledger siphon.

## Tham số cấu hình
- `InpSLSiphon_Enable` (bool, default true).
- `InpMinWalletBalance_USD` (double, default 500) – ngưỡng tối thiểu mong muốn.
- `InpCriticalWalletBalance_USD` (double, default 300) – ngưỡng cảnh báo đỏ.
- `InpTopupSuggestion_USD` (double, default 200) – số tiền đề xuất nạp mỗi lần.
- `InpWalletCheck_PeriodMin` (int, default 5) – chu kỳ kiểm tra (phút).
- `InpSLSiphonNotify_Telegram` (bool) – bật tắt thông báo TG.
- `InpSLSiphonRepeatHours` (double, default 4) – khoảng thời gian lặp lại nhắc nếu chưa nạp.

## Luồng xử lý
1. OnTimer mỗi `InpWalletCheck_PeriodMin` phút:
   - `balance = AccountBalance()` hoặc query API số dư ví liên quan.
   - Nếu `balance >= minBalance` ⇒ trạng thái OK, reset thời gian cảnh báo.
   - Nếu `minBalance > balance >= criticalBalance` ⇒ cảnh báo vàng.
   - Nếu `balance < criticalBalance` ⇒ cảnh báo đỏ (ưu tiên cao).
2. Khi cảnh báo:
   - Ghi log: `SLSIPHON_WARN balance=320 min=500 critical=300`.
   - Gửi telegram (nếu enable):
     ```
     ⚠️ <b>Wallet low</b>: Balance=320 USD (min=500). Đề nghị nạp 200 USD từ ví earn.
     ```
   - Đề xuất số tiền nạp = `max(minTopup, minBalance - balance)` hoặc `TakeFromSiphonLedger()`.
3. Debounce/lặp lại:
   - Lưu `lastAlertTs` (GlobalVariable `EA.SLSIPHON_LAST_ALERT`).
   - Chỉ nhắc lại sau `InpSLSiphonRepeatHours`, trừ khi trạng thái xấu hơn (vàng → đỏ).
4. Sau khi nạp:
   - Trader dùng script/manual để nạp; EA có thể detect balance tăng.
   - Khi balance > minBalance ⇒ gửi thông báo “wallet restored”.

## Tích hợp
- **Profit Siphon Tracker**: 
  - Sử dụng `EA.SIPHON_TOTAL` để gợi ý: “Total siphoned available: X USD”.
  - Có thể tự động subtract ledger khi nạp (manual update).
- **Kill-Switch**:
  - Nếu kill-switch kích hoạt nhiều lần và balance giảm nhanh ⇒ guard send alert sớm.
- **Telegram notifications**: dùng helper `TgSend` từ `noti-telegram.md`.
- **Dashboard**: hiển thị balance hiện tại, minBalance, minTopup, thời gian cảnh báo cuối.

## Logging & Ledger
- Append `wallet-alert.csv`: `timestamp, balance, minBalance, level, suggestedTopup`.
- Journal messages: `WALLET_ALERT level=yellow balance=430`.
- Optional: ghi event `WALLET_TOPUP` khi trader xác nhận đã nạp (manual input).

## Kiểm thử
- Test manual: giảm balance demo xuống < critical ⇒ nhận alert.
- Restart EA sau khi alert ⇒ đảm bảo timer & GV preserve state (không spam ngay lập tức).
- Test repeat: balance vẫn thấp sau 4h ⇒ nhận alert lặp.
- Test recovery: nạp tiền lên > min ⇒ alert “restored” và reset timer.

## Vận hành & tối ưu
- Có thể tự động lấy balance từ nhiều account (nếu multi-account) thông qua API hoặc bridging.
- Gắn thêm metric “Kill-switch count since last top-up” để phân tích vì sao ví giảm.
- Trong tương lai: auto-triage – nếu siphon ledger >= topup suggestion ⇒ bot đề nghị chuyển đúng số tiền.
