Equity-Curve Filter ✅ (ưu tiên #9)

## Mục tiêu
- Khi lợi nhuận gần đây tiêu cực hoặc chuỗi thua kéo dài, tạm ngưng trade để tránh “đào hố”.
- Cho phép hệ thống “cool down” 2–4 giờ, chờ thị trường ổn định trước khi mở lệnh mới.
- Phối hợp với kill-switch, spread guard, no-refill để tạo lớp quản trị rủi ro chủ động.

## Logic & tiêu chí
- Sử dụng PnL rolling window (mặc định 8 giờ) và đếm streak lệnh thua.
- Nếu `PnL_8h <= -thresholdUsd` hoặc `losingStreak >= N` ⇒ bật `NO_TRADE`.
- `NO_TRADE` có thể chặn: Seed, Refill, GridRecovery, PartialClose? (vẫn cho partial/close).
- Tắt khi hết thời gian cooldown và điều kiện cải thiện (PnL trở lại > -threshold).

## Tham số cấu hình
- `InpEqFilter_Enable` (bool, default true).
- `InpEqFilter_Lookback_Hours` (double, default 8).
- `InpEqFilter_PnL_Threshold_USD` (double, default 80) – mức lỗ dương (ví dụ -80 USD).
- `InpEqFilter_LosingStreak` (int, default 5) – số lệnh thua liên tục để trigger.
- `InpEqFilter_Cooldown_Min` (int, default 180) – 3 giờ nghỉ.
- `InpEqFilter_ResetOnProfit` (bool, default true) – reset streak khi có lệnh thắng.
- `InpEqFilter_IncludeSwaps` (bool, default true).
- `InpEqFilter_MinClosedTrades` (int, default 3) – tránh trigger khi sample quá nhỏ.
- `InpEqFilter_AlertTelegram` (bool).

## Dữ liệu & trạng thái
- Lưu lịch sử closed trades (profit, timestamp) vào cấu trúc nhớ tạm hoặc file CSV.
- Window 8h: sum profits của trades đóng trong 8h gần nhất → `pnlWindow`.
- Losing streak: increment khi trade đóng lỗ, reset nếu thắng (nếu `ResetOnProfit`).
- GlobalVariables:
  - `EA.EQFILTER_ACTIVE` (bool).
  - `EA.EQFILTER_UNTIL` (datetime) – cooldown expiry.
  - `EA.EQFILTER_LAST_PNL` (double) – PnL window khi trigger (để log).

## Luồng xử lý
1. `OnTradeTransaction` khi có `DEAL_ADD`:
   - Append trade to window list; remove items > lookback hours.
   - Update `pnlWindow`, `losingStreak`.
2. Check trigger:
   - If `pnlWindow <= -threshold` **hoặc** `losingStreak >= N` **và** sample ≥ `MinClosedTrades`.
   - Nếu filter chưa active ⇒ bật:
     - `cooldownUntil = TimeCurrent() + cooldownMin*60`.
     - Set GV `EQFILTER_ACTIVE = true`, `EQFILTER_UNTIL = cooldownUntil`.
     - Send Telegram: `🚫 Equity filter ON: 8h PnL=-95 USD, cooldown 180m.` hoặc `losingStreak=5`.
3. Khi filter active:
   - Trong OnTick, check `IsEqFilterActive()`:
     - Nếu `TimeCurrent() < EQFILTER_UNTIL` ⇒ skip seed/refill.
     - Partial close / kill-switch / trailing vẫn hoạt động.
4. Tắt filter:
   - Khi `TimeCurrent() >= EQFILTER_UNTIL` **và** `pnlWindow > -threshold` **và** `losingStreak < N`.
   - Reset GV `EQFILTER_ACTIVE=false`.
   - Log + Telegram: `✅ Equity filter OFF: cooldown done, pnl8h=-30`.
   - Optional: khi filter off, reset `pnlWindow`, `losingStreak` hoặc giảm dần.

## Tích hợp
- **Kill-Switch**: nếu kill-switch trigger, equity filter state có thể reset (hoặc kéo dài cooldown).
- **Spread/No-Refill/Asymmetric**: equity filter là layer cao, chặn trade sớm nhất.
- **Partial-Close & Profit Siphon**: vẫn hoạt động; khi partial đóng profit => có thể reset losing streak.
- **Dashboard**: hiển thị PnL 8h, losing streak, thời gian còn lại cooldown.
- **Noti Telegram**: reuse `TgSend`.

## Logging & Monitoring
- Journal: `EQFILTER_ON reason=PnL8h` | `EQFILTER_ON reason=LosingStreak`.
- CSV: `timestamp,event,reason,value,cooldown_until`.
- Metrics: % thời gian filter active, PnL trước/sau khi filter trigger, số lượng trigger/tuần.

## Kiểm thử
- Backtest 8h drawdown: ép lệnh lỗ liên tục → filter trigger, NO_TRADE trong 3h.
- Backtest winning streak sau trigger: ensure losing streak reset, filter off đúng lúc.
- Restart test: filter active, restart EA → GV restore, filter vẫn active cho đến cooldown hết.
- Edge case: trade lãi nhỏ sau filter on → verify criteria check (pnlWindow > -threshold).

## Vận hành & tối ưu
- Cho phép trader override (button “force resume”).
- Dynamic threshold: scale theo balance (1% balance).
- Dùng exponential decay thay vì window cứng (EMA equity).
- Gắn alert khi filter trigger > X lần trong ngày (cần xem lại strategy).
