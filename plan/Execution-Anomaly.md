Giám sát anomaly khớp lệnh & slippage ✅ (ưu tiên #Y)

## Mục tiêu
- Theo dõi chất lượng khớp lệnh theo thời gian thực để phát hiện nhanh khi broker/thanh khoản có vấn đề.
- Khi slippage, tỷ lệ fill, hoặc chi phí giao dịch tăng bất thường ⇒ chuyển symbol sang trạng thái “quan sát” (tạm dừng seed/refill) và cảnh báo Telegram.
- Lưu số liệu để phân tích dài hạn, phục vụ quyết định đổi broker hoặc điều chỉnh chiến lược.

## Metrics cần theo dõi
- `AvgSlippagePoints` (theo chiều buy/sell, rolling n deals gần nhất).
- `MaxSlippagePoints` và `SlippageSpikeCount`.
- `FillRatio` = số lệnh khớp / số lệnh gửi (nếu có dữ liệu refusal).
- `ExecutionTimeMs` (nếu đo được).
- `SpreadAvg`, `SpreadMax` trong cùng window.
- `CommissionPerLot`, `SwapPerLot` (phát hiện tăng phí).
- `NetPnL_per_session` per symbol (để xem anomaly có ảnh hưởng PnL).

## Ngưỡng & điều kiện anomaly
- `SlipThreshold = baseSlipAvg * 2` (hoặc ngưỡng tuyệt đối, ví dụ 30 points).
- `FillThreshold` (ví dụ < 90%).
- `SpreadThreshold` (ví dụ > 2× median 1h).
- `CostThreshold`: commission tăng > 20% so baseline.
- Sử dụng rolling window (ví dụ 30 phút hoặc 10 deals) để tính baseline.
- Kết hợp ít nhất 2 metric để tránh false positive (ví dụ slip tăng + spread tăng).

## Trạng thái & hành vi
- `SymbolHealthState` cho mỗi symbol:
  - `status` ∈ {`Healthy`, `Warning`, `Anomaly`}.
  - `since` timestamp.
  - `reason` (list metrics vượt ngưỡng).
- Khi `status = Anomaly`:
  - Đặt flag `AllowTrading=false` cho symbol đó (seed/refill/modify disable).
  - Cho phép close và partial nếu cần xả vị thế.
  - Gửi Telegram: `🚨 Symbol X anomaly: slippage=35pts (>15), spread=40pts. Tạm dừng giao dịch.`
- Khi anomaly hết (metrics về bình thường trong `RecoveryWindow`) ⇒ set `Healthy`, gửi thông báo resume.

## Lưu trữ & logging
- CSV/SQLite `execution-metrics.csv`: `timestamp,symbol,slip,spread,fill,commission,status`.
- GV: `EA.EXE_STATE.<symbol>` để giữ trạng thái sau restart.
- Log event `ANOMALY_ON`, `ANOMALY_OFF`, `ANOMALY_WARN`.
- Dashboard: bảng theo dõi metrics hiện tại vs baseline, trạng thái per symbol.

## Tích hợp với module khác
- **Spread Guard**: anomaly module có thể reuse spread metric nhưng hoạt động độc lập (spread guard tức thời, anomaly = trend dài).
- **Market Regime**: khi vol cao (Volatile regime) có thể nới threshold.
- **Profit Siphon / Partial**: khi anomaly, cho phép đóng profit/partial để giảm exposure.
- **Kill-Switch**: nếu kill-switch bắt đầu kích hoạt thường xuyên sau anomaly, log chung để phân tích.

## Thu thập dữ liệu thực hiện
- Mỗi lần lệnh khớp (`OnTradeTransaction`):
  - `slipPoints = (deal_price - requested_price)/Point` (theo hướng).
  - `executionMs` nếu đo bằng `GetMicrosecondCount()` (không bắt buộc).
  - Append vào buffer per symbol, update rolling stats.
- Định kỳ (OnTimer 1 phút):
  - Update baseline (EMA hoặc median) cho slip/spread/fill.
  - So sánh metric hiện tại với baseline → quyết định trạng thái.

## Kiểm thử
- Backtest/simulator: ép dữ liệu slippage tăng → verify state từ Healthy → Warning → Anomaly.
- Test scenario: slip cao nhưng chwil, guard cooldown 5 phút, đảm bảo hysteresis tránh toggle liên tục.
- Restart: state & baseline load lại, anomaly không reset bất ngờ.
- Evaluate multiple symbols: XAUUSD anomaly chỉ nên ảnh hưởng XAUUSD, không chặn cặp khác.

## Vận hành & tối ưu
- Export báo cáo tuần: thời lượng anomaly theo symbol, ảnh hưởng PnL.
- Nếu anomaly xảy ra liên tục một khung giờ → cân nhắc shutdown auto trade giờ đó.
- Tích hợp UI cho phép trader “force resume” hoặc “force observe”.
- Kết hợp web dashboard/Telegram command `/status` để xem metrics live.
