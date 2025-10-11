Asymmetric Grid theo trend ✅ (ưu tiên #4)

## Mục tiêu
- Tăng khả năng sống sót khi đi ngược trend bằng cách giảm tốc độ “đè lệnh” ở phía rủi ro.
- Vẫn tận dụng tốt trend thuận bằng spacing chuẩn và volume tối ưu.
- Phối hợp với Dynamic Spacing & NO_REFILL để tránh trap grid khi thị trường kéo dài.

## Khái niệm
- “Thuận trend”: hướng trùng với tín hiệu trend filter (MA slope, ADX, RSI, v.v.).
- “Ngược trend”: hướng đối nghịch với trend filter.
- Grid spacing và lot size được điều chỉnh bất đối xứng theo hướng này.

## Tham số cấu hình
- `InpAsymGrid_Enable` (bool, default true).
- `InpTrendFilter_Mode` (enum: MA, ADX, RSI, Composite) – chọn nguồn trend (dùng chung với module khác).
- `InpTrendLookback` (int, default 200) – số nến để đánh giá trend.
- `InpAsymSpacingMult_Bear` (double, default 1.8) – multiplier spacing khi sell ngược trend.
- `InpAsymSpacingMult_Bull` (double, default 1.8) – multiplier spacing khi buy ngược trend.
- `InpAsymLotMult_Bear` (double, default 0.5) – multiplier lot khi sell ngược.
- `InpAsymLotMult_Bull` (double, default 0.5) – multiplier lot khi buy ngược.
- `InpAsymMinSpacing`/`MaxSpacing` – optional giới hạn spacing để không vượt rule chung.
- `InpAsymMinLot` – optional để tránh volume quá nhỏ (theo step lot).

## Luồng xử lý
1. Xác định trend direction:
   - Sử dụng Trend Analyzer (MA slope, ADX) trả về `trendDir` (LONG, SHORT, NEUTRAL).
   - Lưu `trendStrength` (0–1) để scale multiplier mượt hơn (optional).
2. Khi chuẩn bị seed/refill order:
   - Nếu `trendDir == NEUTRAL` ⇒ dùng spacing/lot mặc định hoặc dynamic spacing hiện tại.
   - Nếu order cùng hướng `trendDir` (thuận) ⇒ spacing/lot = baseline (hoặc baseline * nhẹ <1).
   - Nếu order ngược hướng ⇒ spacing = baseSpacing * asymMult, lot = baseLot * asymLotMult.
   - Có thể scale theo strength: spacing = baseSpacing * (1 + strength*(asymMult-1)).
3. Khi partial close hoặc kill-switch reset ⇒ state spacing trở về baseline cho phiên mới.

## Tích hợp với các module khác
- **Dynamic Spacing**: Asymmetric multiplier áp dụng lên spacing đã tính theo biến động (VD baseSpacing đã bao gồm ATR). Bảo đảm spacing không thấp hơn `InpMinSpacing`.
- **NO_REFILL trend/ADX**: Nếu trend quá mạnh, module này có thể chặn refill hoàn toàn; asym grid nên check module NO_REFILL trước.
- **Partial Close**: Giảm lot phía ngược trend ⇒ partial close ít volume hơn; cần đảm bảo `CloseBasketPortion` xử lý lot nhỏ.
- **Kill-Switch**: Khi kill-switch kích hoạt, tất cả multiplier reset.
- **Trailing-Profit**: Không ảnh hưởng trực tiếp, nhưng trailing thấy volume nhỏ hơn ở phía ngược trend ⇒ TP điều chỉnh tương ứng.

## Logging & Telemetry
- Log khi multiplier khác 1: `ASYM dir=SHORT spacing=1.8 lot=0.50 baseSpacing=20 baseLot=0.2`.
- Dashboard hiển thị: trendDir, strength, spacing hiện tại từng hướng, lot multiplier.
- Cảnh báo nếu multiplier áp dụng liên tục > X giờ (để xem trend kéo dài).

## Kiểm thử
- Backtest trend mạnh (BUY vs SELL) để xác nhận spacing ngược trend dãn ra, drawdown giảm.
- Backtest sideways: trend filter ≈ neutral ⇒ spacing/lot quay về baseline.
- Stress test: trend đảo chiều nhanh ⇒ kiểm tra multiplier cập nhật kịp thời, không hạ spacing quá chậm.
- Kiểm tra min/max spacing khi ATR tăng cao.

## Vận hành & tối ưu
- Điều chỉnh multipliers theo cặp (ví dụ XAUUSD cần asym mạnh hơn EURUSD).
- Xem xét adaptive multiplier: dựa trên ADX (trendStrength), multiplier tăng khi trendStrength cao.
- Kết hợp với Equity-Curve filter: khi equity xấu, asym multiplier có thể mạnh hơn để phòng thủ.
- Theo dõi metric: số lệnh mở phía ngược trend, trung bình spacing, drawdown tối đa; dùng để fine-tune.
