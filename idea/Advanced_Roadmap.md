# Advanced Idea Roadmap

Tổng hợp các ý tưởng nâng cấp (ngoài Priority 1–5) để cân nhắc triển khai khi phù hợp.

## 1. Risk Layer Deep Dive
- **Dynamic Session SL**:
  - Thay `InpSessionSL_USD` cố định bằng công thức: `session_SL = max(base, equity_peak * dd_percent)` và tự điều chỉnh theo ATR hoặc biến động.
  - Thêm soft halt: khi equity giảm vượt `soft_pct`, ngừng mở rescue mới nhưng vẫn giữ lệnh hiện có.
- **Margin Buffer Monitor**:
  - Theo dõi `FreeMargin / Equity`. Khi xuống dưới `margin_buffer_threshold`, thực hiện: giảm batch refill, tắt partial close, hoặc đóng một phần hedge.
- **Swap / Rollover Guard**:
  - Lịch chặn lệnh mới trước rollover (ví dụ 23:45 server). Nếu basket còn mở → cân nhắc đóng bớt hoặc giảm lot để tránh phí swap.
- **Volatility Surge Kill-switch**:
  - Khi ATR hoặc spread tăng đột ngột (x lần so với trung bình 30 bar), dừng deploy lưới mới và log cảnh báo.

## 2. Analytics & Telemetry
- **Cycle CSV Export**:
  - Sau mỗi lần đóng basket, ghi một dòng vào CSV: thời gian, total lot, max DD, spacing hiện tại, tier adaptive, lockdown active, partial close volume.
  - Hỗ trợ review backtest nhanh, có thể plot trong Excel.
- **Event Heatmap**:
  - Log `distance_to_tp`, `ATR`, `dd_usd` khi partial close/lockdown/insurance kích hoạt để check threshold.
- **Chart Annotations**:
  - Dùng `Comment`/`ObjectCreate` vẽ label lên chart mỗi lần event quan trọng xảy ra (Lockdown, Partial, Refill, Insurance). Dễ debug trong visual mode.
- **Performance Metrics**:
  - Tính Sharpe-likeness: rolling profit / rolling DD → log để đánh giá tuning.

## 3. Execution Improvements
- **Smart Slippage Control**:
  - Thay đổi `m_executor` slippage theo spread hiện tại (ví dụ spread lớn → slippage nhỏ để tránh fill tệ).
  - Delay placing order nếu spread vượt `spread_max_pips`.
- **Order Retry Queue**:
  - Khi broker trả `TRADE_RETCODE_REQUOTE` hoặc `OFF_QUOTES`, đưa order vào queue, thử lại sau `retry_seconds` (giới hạn `retry_max_attempts`).
- **Broker Capability Probe**:
  - Lúc OnInit, gọi `SymbolInfoInteger(SYMBOL_VOLUME_MAX/MIN/STEP)` và `SYMBOL_TRADE_STOPS_LEVEL`. Nếu param user nhập < floor, tự bump lên và log warning.
- **Partial Fill Handler**:
  - Nếu vị thế khớp một phần, bổ sung logic để fill nốt hoặc adjust lot state.

## 4. UX & Tooling
- **Parameter Sanity Checker**:
  - Trước OnInit hoàn tất, chạy hàm validate: `grid_levels` quá lớn? `lock_min_lots` > `lot_base`? Nếu sai → log warning & có thể auto-adjust.
- **Scenario Simulator Script**:
  - Viết script reading config + random walk price, output expected events (lockdown, partial) để test logic mà không cần MT5.
- **Documentation Sync**:
  - Tạo README mục "Idea Roadmap" link tới từng file trong `idea/` để dễ theo dõi tiến độ và trạng thái (planned/in-progress/done).
- **In-App Dashboard**:
  - Sử dụng `Print`/`Comment` hiển thị trạng thái realtime (tier, lockdown, pending count, session DD…) ngay trên chart.

## Next Steps
- Khi sẵn sàng, chọn một idea để chi tiết hóa (viết spec riêng như các file khác).
- Ưu tiên những idea hỗ trợ testing (analytics) để bạn dễ đánh giá hiệu quả trước khi thay đổi logic lớn.
