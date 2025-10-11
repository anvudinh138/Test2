Spread/Slippage Guard ✅ (ưu tiên #5)

## Mục tiêu
- Tránh mở thêm vị thế trong điều kiện thị trường bất lợi (spread nới rộng, slippage cao), giảm chi phí và nguy cơ khớp giá xấu trước giờ tin.
- Bảo vệ các module seed/refill/grid khỏi bị “đốt phí” khi thanh khoản mỏng.

## Phạm vi
- Chặn `Seed`, `Refill`, `GridRecovery` khi điều kiện không đạt.
- Cho phép đóng lệnh hoặc xử lý kill-switch ngay cả khi spread cao (không bị block).
- Cảnh báo để trader biết hệ thống đang trong trạng thái guard.

## Tham số cấu hình
- `InpSpreadGuard_Enable` (bool, default true).
- `InpMaxSpread_Points` (int, default 25) – ngưỡng spread tối đa cho phép (tính theo Point).
- `InpMaxSlippage_Points` (int, default 20) – ngưỡng slippage chấp nhận khi lệnh gần nhất khớp.
- `InpSpreadCooldown_Sec` (int, default 60) – thời gian nghỉ sau khi guard kích hoạt.
- `InpGuardNewsMinutesBefore` (int, default 10) – thời gian trước giờ tin đỏ để auto bật guard.
- `InpGuardNewsMinutesAfter` (int, default 5) – giữ guard thêm sau tin.
- `InpGuardMinVolume` (optional) – yêu cầu volume market ≥ X (nếu broker cung cấp).
- `InpGuardOverride_TimeWindow` (string, optional) – cho phép seed lại trong khung giờ cụ thể (ví dụ phiên Á).

## Thu thập dữ liệu
- Spread hiện tại = `SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * Point`.
- Slippage gần nhất: lưu `lastSlipPoints` trong module fill handler (difference giữa giá đặt và giá fill).
- Lịch tin: kết nối module News/Calendar (có thể dựa trên file hoặc input tay).

## Luồng xử lý
1. Trên mỗi tick hoặc trước khi mở lệnh:
   - `spreadPoints = GetCurrentSpreadPoints(_Symbol)`.
   - `isNewsGuard = IsWithinNewsWindow(TimeCurrent(), SymbolNewsSchedule, before, after)`.
   - `slipGuard = (UseRecentSlippage && lastSlipPoints > InpMaxSlippage_Points)`.
   - `spreadGuard = (spreadPoints > InpMaxSpread_Points)`.
   - Nếu `spreadGuard || slipGuard || isNewsGuard` ⇒ set `guardActive = true` và `guardUntil = TimeCurrent() + InpSpreadCooldown_Sec`.
2. Khi `guardActive`:
   - Bỏ qua `Seed/Refill/GridRecovery`.
   - Cho phép `CloseAll`, `PartialClose`, `KillSwitch`.
   - Log `SPREAD_GUARD active reason=spread/slip/news`.
3. Tự động reset guard khi `TimeCurrent() > guardUntil` và điều kiện bình thường trở lại (spread < threshold, slippage ok, không còn trong window news).
4. Manual override: nếu user set override window (ví dụ `23:00-01:00`) ⇒ có thể đặt guardActive = false ngay cả khi spread lớn (chỉ khi chấp nhận rủi ro).

## Tích hợp với các module khác
- **Kill-Switch**: guard không chặn logic kill-switch, và kill-switch có thể đặt guard để kéo dài cooldown.
- **Asymmetric Grid & NO_REFILL**: guard là layer ngoài cùng; nếu guard bật thì seed/refill bị chặn trước khi kiểm tra asym/NoRefill.
- **Partial-Close & Trailing**: vẫn chạy vì chỉ dính đến lệnh hiện có (TP/close).
- **Profit Siphon**: nếu guard kéo dài, ledger nên ghi chú “guard active” để lý do profit chậm.
- **Telegram/Notifications**: gửi alert khi guard bật/đã tắt + lý do (spread high, slippage high, news).

## Logging & Telemetry
- Log: `SPREAD_GUARD_ON spread=35 slip=12 news=true` | `SPREAD_GUARD_OFF spread=18`.
- Dashboard: trạng thái guard, thời gian còn lại, spread hiện tại, last slippage.
- Metric: % thời gian guard active, số lệnh bị block vì guard.

## Kiểm thử
- Backtest ngày có tin NFP: verify guard bật trước tin, không seed thêm; sau tin spread về bình thường ⇒ guard off.
- Simulation slippage: ép trượt giá lớn trên fill order ⇒ guard active cho 60s, không seed thêm.
- Edge case: spread spike trong khoảnh khắc <1 tick ⇒ guard cooldown tránh lặp on/off liên tục.
- Restart test: guardActive + guardUntil lưu trong GlobalVariable (`EA.GUARD_UNTIL`) để survive restart.

## Vận hành & tối ưu
- Điều chỉnh ngưỡng spread per-symbol (ví dụ GBP pairs cho phép spread cao hơn).
- Thêm adaptive threshold: InpMaxSpread_Points = ATR-based multiplier (ví dụ 0.5 pip + ATR*0.1).
- Sử dụng `isNewsGuard` để lock EA trước các sự kiện đã biết (CPI, FOMC).
- Theo dõi metric guard vs. missed opportunities để fine-tune (không guard quá lâu làm mất trade tốt).
