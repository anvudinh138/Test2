Phân loại trạng thái thị trường & đổi preset chiến lược ✅ (ưu tiên #X)

## Mục tiêu
- Phân loại nhanh thị trường vào 3 trạng thái chính (Trend, Range, Volatile) để chọn preset phù hợp (grid chặt, asymmetric, hoặc chỉ bảo toàn).
- Giảm phụ thuộc vào phản ứng muộn (kill-switch), giúp EA chủ động đổi chế độ trước khi DD lớn.
- Cho phép quan sát, log, và backtest từng chế độ riêng để tối ưu hiệu suất.

## Trạng thái & preset đề xuất
| Regime         | Điều kiện chính                                       | Preset hành động |
|----------------|-------------------------------------------------------|------------------|
| Trend          | MA slope rõ + ADX cao + Range Compression thấp        | Bật Asymmetric Grid, giảm refill ngược trend, trailing mạnh |
| Range/Sideway  | MA phẳng (slope nhỏ) + ADX thấp + Biên độ hẹp ổn định | Grid spacing chuẩn, bật partial close & siphon đều |
| Volatile/Shock | ATR spike + ADX cao + Spread/slip tăng                | Tạm NO_TRADE hoặc chỉ cho partial/close, bật guard mức cao |

## Chỉ báo & tham số
- `MA_Period` (ví dụ 89) để đánh giá độ dốc (sử dụng derivative hoặc tanh slope).
- `ADX_Period` (14) để đo cường độ trend.
- `RangeCompression` = (High-Low)/ATR (windows 8h).
- `ATR_Period` (14) để phát hiện cú spike.
- Ngưỡng gợi ý:
  - Trend: `|Slope| > slopeTrend` (ví dụ 0.0003), `ADX > 25`, `RangeCompression < 1.5`.
  - Range: `|Slope| <= slopeRange`, `ADX < 20`.
  - Volatile: `ATR > ATR_avg * 1.5` hoặc `Spread > spreadVol`, `Slippage > slipVol`.
- Hysteresis: cần liên tục `X` bar (ví dụ 5) cùng trạng thái trước khi chuyển, tránh “nhấp nháy”.

## Kiến trúc & trạng thái
- Module `RegimeDetector` chạy `OnTick` hoặc mỗi `OnTimer (30s)`:
  - Tính metric, lưu vào buffer trượt.
  - Quyết định `currentRegime` với logic hysteresis.
  - Lưu `RegimeState` vào GV: `EA.REGIME_CURRENT`, `EA.REGIME_SINCE`.
- Module `PresetManager`:
  - Map `currentRegime` → `activePreset` (cấu hình cho các module).
  - Ví dụ:
    - Trend preset: `AsymmetricMult = 1.8`, `NoRefillDirection = OppositeOnly`, `TrailLock=0.6`.
    - Range preset: `SpacingMult = 1.0`, `PartialLevels` dày hơn, `TrailLock=0.4`.
    - Volatile preset: `GuardHard = true`, `Seed=false`, `Refill=false`, `PartialOnly=true`.
- Preset apply = update biến cấu hình runtime (không cần input reset), hoặc gán flag để module đọc.

## Luồng xử lý
1. `RegimeDetector.Update()` gọi mỗi 1–5 phút.
2. Khi phát hiện regime thay đổi:
   - Log: `REGIME_CHANGE from=Range to=Trend slope=... adx=...`.
   - Gọi `PresetManager.Apply(newRegime)`.
   - Gửi Telegram (optional) thông báo preset mới.
3. Các module đọc `activePreset`:
   - `Seed/Refill`: check `Preset.AllowedActions`.
   - `Asymmetric Grid`: đọc `Preset.AsymMult`.
   - `PartialClose`: dùng set level riêng.
   - `SpreadGuard`: có thể thắt chặt threshold trong Volatile.

## Logging & Monitoring
- CSV `regime-log.csv`: `timestamp, regime, slope, adx, atr, spread`.
- Dashboard: hiển thị regime hiện tại, thời gian đã tồn tại, các preset đang bật.
- Telegram: `🔄 Regime = Trend (ADX=32, slope=0.0005). Preset: Grid asym + Trail lock 60%.`

## Kiểm thử
- Backtest dữ liệu lịch sử: tag regime mỗi 5 phút, kiểm tra tỷ lệ đúng.
- Scenario: market chuyển từ range → trend → volatile; đảm bảo preset swap đúng và không nhấp nháy.
- Restart test: load GV và preset sau khi EA khởi động lại.
- Stress test: metrics nhiễu → hysteresis/hysteretic windows đảm bảo không flip quá thường xuyên.

## Mở rộng & tối ưu
- Cho phép override manual (button “Force Trend/Range/Volatile”).
- Lưu performance per regime để tối ưu param sau (ví dụ map PnL & DD).
- Có thể thêm ML nhẹ (kNN, Naive Bayes) nếu muốn phân loại mềm (score 0–1).
- Tích hợp scheduler: trong phiên Á, threshold trend suy giảm (vì volatility thấp).
