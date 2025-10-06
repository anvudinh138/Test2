# Swap / Rollover Guard Specification

## Problem
Grid chiến lược thường giữ vị thế qua đêm, dẫn đến chi phí swap/rollover cao (đặc biệt trên CFD như US30/XAU). Nếu cuối ngày vẫn còn basket lớn, phí swap có thể đẩy drawdown tăng thêm.

## Goal
- Tự động quản lý exposure khi gần giờ rollover:
  - Tránh mở lệnh mới ngay trước thời điểm swap.
  - Thực hiện giảm lot hoặc đóng một phần đối với basket đang mở nếu vượt ngưỡng rủi ro.
  - Cho phép tùy chỉnh hành vi theo từng ngày trong tuần (ví dụ rollover thứ Tư cao hơn).

## Terminology
- **Rollover window**: khoảng thời gian (ví dụ 23:30–23:59 server time) cần áp dụng guard.
- **Cutoff policy**: chiến lược hành động trong window: block orders, partial close, full flatten.
- **Swap intensity**: hệ số swap (ví dụ triple swap Wednesday) để quyết định ngưỡng.

## Parameters
| Input | Default | Ý nghĩa |
| --- | --- | --- |
| `InpSwapGuardEnable` | true | Bật/tắt chức năng. |
| `InpSwapWindowStartHour` | 23 | Giờ bắt đầu guard. |
| `InpSwapWindowStartMinute` | 30 | Phút bắt đầu guard. |
| `InpSwapWindowDurationMin` | 45 | Độ dài window (phút). |
| `InpSwapBlockNewOrders` | true | Nếu true, không mở lệnh mới trong window. |
| `InpSwapPartialClose` | true | Cho phép đóng bớt khi vượt ngưỡng. |
| `InpSwapPartialThresholdUSD` | 10.0 | Nếu basket lỗ hơn USD này gần rollover → đóng bớt lot. |
| `InpSwapPartialFraction` | 0.25 | Phần trăm lot đóng mỗi lần. |
| `InpSwapFlattenOnTriple` | true | Ngày triple swap (thường Wed) đóng toàn bộ.
| `InpSwapTimezoneOffset` | 0 | Offset nếu muốn dùng giờ khác server. |

Mapping sang `SParams`: `swap_guard_enable`, `swap_window_start_hour`, `swap_window_start_minute`, `swap_window_duration_min`, `swap_block_new_orders`, `swap_partial_close`, `swap_partial_threshold_usd`, `swap_partial_fraction`, `swap_flatten_on_triple`, `swap_timezone_offset`.

## Logic Overview
```mermaid
flowchart TD
    A[OnTick] --> B{Swap guard enabled?}
    B -- No --> Z[Normal flow]
    B -- Yes --> C[Compute current time (server + offset)]
    C --> D{Within window?}
    D -- No --> Z
    D -- Yes --> E[Apply guard policy]
    E --> F{Triple swap day?}
    F -- Yes --> G[Flatten or aggressive reduction]
    F -- No --> H[Block new orders / partial close]
    G --> Z
    H --> Z
```

## Detailed Behaviour
1. **Window detection**
   - `datetime now = TimeCurrent();` điều chỉnh offset nếu cần.
   - `window_start = DateTimeToday(start_hour, start_minute)
   + offset`.
   - `window_end = window_start + duration` (phút).
   - Nếu `now` nằm trong window, guard active.

2. **Block new orders**
   - Trong `CLifecycleController::Update()`, nếu guard active và `swap_block_new_orders=true`: set `allow_new_orders=false` (được dùng sẵn trong logic).
   - Log `[SwapGuard] block new orders`.

3. **Partial close**
   - Nếu guard active, basket loser PnL < `-swap_partial_threshold_usd` → gọi `loser.CloseFraction(swap_partial_fraction)`.
   - Optionally close pending beyond certain distance.
   - Log `[SwapGuard] partial close lot=...`.

4. **Triple swap day**
   - Thường là Wednesday (day of week = 3). Nếu `swap_flatten_on_triple=true`, khi trong window → `FlattenAll("Triple swap")` hoặc `CloseFraction(0.5)` tùy độ rủi ro.

5. **Reset**
   - Khi window kết thúc → guard inactive, log event.
   - Ensure `allow_new_orders` quay lại `TradingWindowOpen` logic mặc định.

## Pseudo-code
```pseudo
bool CLifecycleController::SwapGuardActive()
{
    if(!m_params.swap_guard_enable)
        return false;
    datetime now = TimeCurrent() + m_params.swap_timezone_offset * 3600;
    datetime start = TodayAt(m_params.swap_window_start_hour,
                             m_params.swap_window_start_minute);
    datetime end = start + m_params.swap_window_duration_min * 60;
    return (now >= start && now <= end);
}
```

```pseudo
void CLifecycleController::ApplySwapGuard(CGridBasket *loser, CGridBasket *winner)
{
    if(!SwapGuardActive())
        return;

    m_swap_guard_active = true;
    if(m_params.swap_block_new_orders)
        m_allow_new_orders_override = false;

    int dow = TimeDayOfWeek(TimeCurrent());
    bool triple = (dow == 3); // adjust per symbol if needed

    if(triple && m_params.swap_flatten_on_triple)
    {
        FlattenAll("Triple swap guard");
        return;
    }

    if(m_params.swap_partial_close && loser != NULL)
    {
        if(loser.BasketPnL() <= -m_params.swap_partial_threshold_usd)
        {
            double lot_before = loser.TotalLot();
            loser.CloseFraction(m_params.swap_partial_fraction);
            double lot_after = loser.TotalLot();
            if(m_log)
                m_log.Event(Tag(), StringFormat("[SwapGuard] partial close %.2f -> %.2f", lot_before, lot_after));
        }
    }
}
```

- Trong `Update()`, gọi `ApplySwapGuard(loser, winner)` trước khi rescue.
- Khi window kết thúc (`SwapGuardActive()==false`), reset flag & log `[SwapGuard] ended`.

## Logging
- On enter: `[SwapGuard] active start=HH:MM duration=... block_orders=...`.
- On exit: `[SwapGuard] inactive`.
- On partial/triple: log reason, lot closed, PnL.

## Testing Checklist
1. **Daily run**: mô phỏng backtest có lệnh chạy qua 23:30 – verify new orders không mở, partial close triggered khi lỗ > threshold.
2. **Triple swap**: test Wednesday – ensure FlattenAll hoặc aggressive reduction hoạt động.
3. **Offset**: nếu broker timezone khác (e.g., GMT+2), check offset logic.
4. **Edge**: guard active khi lockdown → ensure FlattenAll ưu tiên logic rủi ro cao.
5. **Performance**: guard không spam log/hành động khi window kéo dài.

## Extension Ideas
- Param theo ngày: `swap_schedule` (mapping day -> policy) để tinh chỉnh cho symbol khác nhau.
- Tính toán swap dự kiến: `swap_cost = lot * swap_rate * multiplier` để ra quyết định partial close số lượng.
- Khi guard active nhiều ngày liên tiếp -> consider adjusting base target (trading off daily cost).
