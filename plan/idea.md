Các ý tưởng tăng profit & quản trị rủi ro (triển khai dần, đã tách thành plan riêng khi cần)

**Kill-Switch Hard SL phiên** (`plan/Kill-Switch.md`)
- Hard stop −$200/phiên, cooldown 30 phút, tự động CloseAll và halt.
- Dùng GlobalVariables để sống sót qua restart, tránh trap grid bị cháy ví.
- Khi kill-switch bật, log + alert để kích hoạt quy trình nạp lãi sang ví cháy.

**Basket Trailing-Profit** (`plan/Trailing-Profit.md`)
- Khi basket lời vượt trigger, khóa % profit và nhích group TP theo đỉnh PnL mới.
- Giúp “let profit run” nhưng vẫn siphon được một phần lợi nhuận.

**Time-Exit Layer**
- Bật mặc định với `maxHolding ≈ 24h`, `capLoss ≈ -$100`, `TrendOnly = true`.
- Cắt drawdown kéo dài, xoay vòng vốn nhanh hơn.

**Dynamic Spacing theo biến động (đã có)**
- Cho phép giãn spacing tới 3× khi trend mạnh để giảm số lệnh đè.

**Equity-Curve Filter** (`plan/Equity-Curve-Filter.md`)
- Nếu PnL 8h < 0 hoặc chuỗi thua ≥ N ⇒ NO_TRADE 2–4h để “cool down”.

**Session Take-Profit + Daily Trailing**
- Target ngày (ví dụ +$150). Đạt target ⇒ khóa 50–70%.
- Nếu equity rơi >30–40% từ đỉnh ngày ⇒ flat & nghỉ.

**Phân loại Regime & đổi preset** (`plan/Market-Regime.md`)
- Dùng MA slope + ADX + biến động để tag Trend/Range/Volatile rồi bật preset phù hợp.

**Asymmetric Grid theo trend** (`plan/Asymmetric-Grid.md`)
- Ngược trend: spacing rộng, lot nhỏ; thuận trend: spacing chuẩn.

**NO_REFILL khi trend/ADX cao** (`plan/No-Refill-Trend.md`)
- Giữ vị thế hiện tại, không nạp thêm phía ngược trend trong đoạn biến động mạnh.

**Spread/Slippage Guard** (`plan/Spread-Guard.md`)
- Chặn seed/refill khi spread > X hoặc slip > Y, nhất là trước giờ tin.

**Partial-Close bậc thang** (`plan/Partial-Close.md`)
- Chốt 30–50% ở các mốc USD lớn, phần còn lại chạy theo trailing (kết nối Profit Siphon).

**Profit Siphon Tracker** (`plan/Profit-Siphon.md`)
- Mỗi +$100 closed PnL ⇒ log “rút lãi sang ví earn”, phục vụ chiến lược ví cháy/ví earn.

**SL-Siphon (Low Wallet Alert)** (`plan/SL-Siphon.md`)
- Khi ví “cháy” < min USD ⇒ cảnh báo cần nạp từ ví earn; gợi ý số tiền nạp theo ledger.

**Giám sát anomaly khớp lệnh** (`plan/Execution-Anomaly.md`)
- Theo dõi slippage/fill/spread; khi bất thường ⇒ chuyển symbol sang chế độ quan sát & cảnh báo.

**Time-of-Day & News Windows**
- Ưu tiên LDN/NY overlap, giảm hoạt động trước tin “đỏ”.

**Equity Heatmap / Replay Dashboard** (*Feature backlog*)
- Lưu lại mái chèo (kill-switch, siphon, partial) để review theo ngày/phiên, hỗ trợ phân tích chiến thuật.

**Session Risk Budget** (*Feature backlog*)
- Đặt ngân sách rủi ro cho từng phiên; nếu tiêu 70% ⇒ giảm quy mô hoặc nghỉ đến phiên khác.

**Sắp xếp thứ tự triển khai đề xuất**
1. Kill-Switch Hard SL (đã có plan chi tiết).
2. Spread/Slippage Guard + NO_REFILL trend (giảm rủi ro mở lệnh xấu).
3. Basket Trailing-Profit + Partial-Close (tăng hiệu suất hút lãi).
4. Profit Siphon Tracker + SL-Siphon alert (quản lý dòng tiền ví earn/ cháy).
5. Equity-Curve Filter + Time-Exit (cooldown tự động theo PnL).
6. Market Regime presets + Asymmetric Grid (tối ưu theo trạng thái thị trường).
7. Execution Anomaly monitor (giám sát broker/thanh khoản).
8. Feature backlog: Equity Heatmap, Session Risk Budget.
