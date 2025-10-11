NO_REFILL khi trend/ADX cao ✅ (ưu tiên #6)

## Mục tiêu
- Khi thị trường đang trend mạnh (ADX cao) hoặc có xung lực rõ, tránh nạp thêm lệnh ngược trend để không “bắt dao rơi”.
- Giữ nguyên các vị thế hiện tại, chờ tín hiệu yếu đi mới refill để giảm tốc độ nở grid.
- Kết hợp với Asymmetric Grid & Spread Guard để tạo lớp bảo vệ đa tầng.

## Chuẩn trend/xung lực
- Sử dụng ADX (Default 14) + DI+ / DI− hoặc Momentum/RSI để xác định hướng và cường độ.
- Tham chiếu trend analyzer chung: `trendStrength` từ 0–1 (0 neutral, 1 mạnh).
- Hỗ trợ override manual (flag trên panel) nếu trader muốn tắt guard tạm thời.

## Tham số cấu hình
- `InpNoRefill_Enable` (bool, default true).
- `InpNoRefill_ADX_Threshold` (double, default 28) – ngưỡng ADX kích hoạt guard.
- `InpNoRefill_Delta` (double, default 5) – hysteresis để tránh bật/tắt liên tục (chỉ tắt khi ADX < threshold - delta).
- `InpNoRefill_MinBars` (int, default 3) – yêu cầu trend mạnh liên tục X bar trước khi guard.
- `InpNoRefill_Direction` (enum: OppositeOnly, Both, Custom) – guard refill ngược trend hay cả hai hướng.
- `InpNoRefill_Cooldown_Min` (int, default 10) – thời gian tối thiểu duy trì guard sau khi kích hoạt.
- `InpNoRefill_WaitForPullback_Pips` (optional) – cho phép refill lại khi giá hồi tối thiểu X pips về phía thuận.

## Luồng xử lý
1. Cập nhật trend metrics mỗi `OnTick` hoặc `OnTimer`:
   - `adx = iADX(_Symbol, _Period, InpADXPeriod, PRICE_CLOSE, MODE_MAIN)`.
   - `dir = (DI+ > DI−)` ⇒ trend LONG, ngược lại SHORT.
   - Tính `trendStrength = NormalizeTrend(adx, threshold)`.
2. Kiểm tra điều kiện guard:
   - Nếu `adx ≥ threshold` trong `InpNoRefill_MinBars` bar gần nhất ⇒ `guardDir = trendDir`.
   - Nếu `InpNoRefill_Direction == OppositeOnly` ⇒ chặn refill ngược trend (`dir` = SHORT → chặn BUY refill).
   - Nếu `Both` ⇒ chặn cả hai chiều (ngưng nạp grid hoàn toàn).
3. Khi guard bật:
   - Đặt `noRefillUntil = TimeCurrent() + InpNoRefill_Cooldown_Min*60`.
   - Trong logic seed/refill:
     - Nếu `orderDir` thuộc hướng bị guard ⇒ skip với lý do `NO_REFILL Trend`.
     - Cho phép partial close, trailing, kill-switch.
4. Tắt guard:
   - Khi `adx < threshold - delta` **và** `TimeCurrent() > noRefillUntil`.
   - Optional: yêu cầu giá hồi `InpNoRefill_WaitForPullback_Pips` so với swingHigh/Low trước khi refill lại.

## Tích hợp
- **Asymmetric Grid**: guard layer hoạt động trước khi tính spacing/lot; nếu guard skip refill ngược trend, asym grid không cần handle.
- **Spread Guard**: Spread guard có mức ưu tiên cao hơn (nếu spread xấu → chặn cả hai).
- **Kill-Switch**: nếu kill-switch active ⇒ guard reset.
- **Partial Close / Trailing**: vẫn cho phép để giảm risk trong trend mạnh.
- **Profit Ledger**: khi guard kích hoạt lâu ⇒ log “NO_REFILL” để trader biết lý do lãi/không lãi.

## Logging & UI
- Log on/off: `NO_REFILL_ON dir=SHORT adx=32` | `NO_REFILL_OFF adx=24`.
- Dashboard hiển thị: trạng thái guard, ADX hiện tại, thời gian còn lại trước khi refill lại, hướng bị chặn.
- Alert nếu guard > X giờ liên tục (có thể cần review threshold).

## Kiểm thử
- Backtest thị trường trending: đảm bảo guard chặn nạp ngược trend, grid không phình quá nhanh.
- Backtest thị trường sideway: ADX thấp ⇒ guard không kích hoạt, refill bình thường.
- Test hysteresis: ADX dao động quanh threshold ⇒ guard không bật/tắt quá thường xuyên.
- Scenario: guard bật, partial close xảy ra, sau đó ADX giảm  → đảm bảo guard tắt đúng thời điểm.
- Restart test: guard state lưu qua GlobalVariable (`EA.NOREFILL_UNTIL`, `EA.NOREFILL_DIR`).

## Vận hành & tối ưu
- Tinh chỉnh threshold per-symbol (vàng/cặp mạnh cần threshold cao hơn).
- Kết hợp indicator khác (ATR slope, RSI) để xác định trend bền vững.
- Param `InpNoRefill_Direction = Both` dùng trong phiên news lớn (tắt refill hoàn toàn).
- Theo dõi metric: số lần guard, thời lượng guard, PnL trung bình trong guard vs không guard.
