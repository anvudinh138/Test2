Session Risk Budget (Feature backlog)

## Mục tiêu
- Phân bổ “ngân sách rủi ro” riêng cho từng phiên (Á/Âu/Mỹ) để tránh dồn drawdown vào một thời điểm.
- Khi một phiên tiêu hao quá 70% ngân sách, giảm quy mô trade hoặc nghỉ hoàn toàn tới phiên sau.
- Gắn liền với chiến lược kill-switch và profit siphon để quản lý dòng tiền.

## Khái niệm
- `RiskBudget[session]` = USD tối đa có thể thua trong phiên (ví dụ 200 USD cho NY).
- `RiskUsed[session]` = tổng lỗ thực tế (closed + floating?).
- `BudgetUsage` = `RiskUsed / RiskBudget`.
- `Session` xác định bằng khung giờ server (ví dụ Asia 00:00–07:59, EU 08:00–15:59, US 16:00–23:59).

## Tham số
- `InpSessionBudget_Enable`.
- `InpSessionBudget_Asia/EU/US` (USD).
- `InpSessionBudget_WarnPct` (default 0.7).
- `InpSessionBudget_StopPct` (default 1.0).
- `InpSessionBudget_ResetMode` (time-based reset at session start).

## Luồng xử lý
1. Khi vào phiên mới ⇒ reset `RiskUsed = 0`.
2. Mỗi khi lệnh đóng lỗ hoặc floating drawdown tăng:
   - Update `RiskUsed`.
   - Nếu `BudgetUsage >= WarnPct` ⇒ cảnh báo Telegram, giảm lot (nếu override).
   - Nếu `BudgetUsage >= StopPct` ⇒ chặn seed/refill đến hết phiên.
3. Nếu profit lớn làm `RiskUsed` < 0 ⇒ option cho phép tăng “buffer” (bonus để phiên sau).

## Logging & Tích hợp
- `session-budget.csv`: `date,session,riskUsed,budget,usage`.
- Telegram: `⚠️ US session risk usage 72% (140/200). Giảm quy mô!`.
- Khi kill-switch trigger ⇒ mark session consumed 100%.
- Profit siphon có thể ghi chú: “+X USD chuyển sang ví earn từ session NY”.

## Kiểm thử
- Replay dữ liệu: simulate lỗ dần trong phiên → guard kích hoạt lúc 70%, stop khi 100%.
- Restart EA giữa phiên: state `RiskUsed` restore từ GV `EA.SESSION_BUDGET.<session>`.
- Giai đoạn đầu có thể manual log trong CSV nếu chưa auto.
