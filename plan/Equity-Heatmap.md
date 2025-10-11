Equity Heatmap / Replay Dashboard (Feature backlog)

## Mục tiêu
- Tái hiện lại đường equity theo ngày/phiên, đánh dấu các sự kiện quan trọng (kill-switch, partial close, siphon, guard).
- Giúp trader review nhanh hiệu quả từng module và ra quyết định ưu tiên cải tiến.
- Hỗ trợ “replay” session để xem EA xử lý tình huống như thế nào.

## Dữ liệu cần thu thập
- Timestamp, equity, balance (mỗi 1 phút hoặc theo event).
- Event log: `KILL_SWITCH_ON/OFF`, `SIPHON_TRIGGER`, `PARTIAL_CLOSE`, `NO_REFILL`, `GUARD_ON`.
- Metrics per session: PnL, DD, số lệnh, số lần guard, amount siphon.
- Option: screenshot chart, nhưng giai đoạn đầu chỉ cần số.

## Cấu trúc file/log
- `equity-log.csv`: `timestamp,equity,balance,freeMargin`.
- `event-log.csv`: `timestamp,event,type,value,comment`.
- `session-metrics.csv`: `session_date,session_type,pnl,drawdown,kill_switch_count,siphon_usd`.

## Dashboard ý tưởng
- Heatmap dạng calendar: màu theo PnL session.
- Timeline interactive (HTML/JS hoặc Excel pivot) hiển thị event overlay trên equity curve.
- Filter theo symbol, preset, regime.

## Thực hiện
- Bước 1: đảm bảo mọi module ghi log thống nhất (CSV + timezone).
- Bước 2: viết script Python/Node để build dashboard (không cần realtime).
- Bước 3: triển khai UI (web nhẹ hoặc Google Data Studio).

## Trạng thái
- Để trong backlog cho phase sau khi core EA ổn định.
