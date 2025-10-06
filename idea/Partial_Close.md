# Partial Close Specification

## Goals
- Thu nhỏ rổ thua trong nhịp retest để giảm TP distance và giải phóng margin.
- Giữ cấu trúc hedge chính xác: đóng chọn lọc các vị thế gần giá và làm mới pending hợp lý.
- Đảm bảo không bị "kẹt" khi thị trường sideway sau retest (tránh đóng xong lại mở ngay ở cùng vùng).
- Ghi log và thống kê để điều chỉnh tham số qua backtest.

## Activation Conditions
Partial close được xét khi **tất cả** tiêu chí sau thỏa mãn:

1. **Basket loser đang hoạt động**: `loser != NULL`, `loser.TotalLot() > 0`, `loser.BasketPnL() < 0`.
2. **Có retest thuận lợi**: Giá đã di chuyển ngược chiều trend ít nhất `pc_retest_atr` × ATR kể từ extreme gần nhất. Để tính:
   - Lưu `loser.MaxAdversePrice()` (giá xa nhất theo hướng thua) sau mỗi lần fill grid mới.
   - `distance_retest = |loser.MaxAdversePrice() - price_current|`.
   - Yêu cầu `distance_retest ≥ pc_retest_atr × ATRPoints()`.
3. **Momentum yếu dần**: `TrendSlopeValue()` giảm dưới `trend_slope_threshold - pc_slope_hysteresis` hoặc giá nằm dưới EMA nhanh (đối với SELL) / trên EMA nhanh (đối với BUY).
4. **PnL cục bộ khả thi**: Có tối thiểu `pc_min_winning_tickets` lệnh SELL/B UY đang có lời (price vượt entry theo hướng có lợi) hoặc tổng PnL của những ticket gần giá ≥ `pc_min_profit_usd`.
5. **Cooldown**: `m_pc_last_close` cách hiện tại ≥ `pc_cooldown_bars` bar.
6. **Giữ lại core lot**: Sau khi đóng dự kiến vẫn còn `loser.TotalLot() - close_volume ≥ lock_min_lots` (không làm rỗng basket).

## Behaviour khi kích hoạt
- **Chọn lệnh đóng**: thu thập danh sách position của loser, sắp xếp theo khoảng cách đến giá hiện tại (gần nhất trước). Cắt nhiều nhất `pc_max_tickets` hoặc đủ để đóng `pc_close_fraction` tổng lot.
- **Đóng lệnh**: sử dụng `COrderExecutor.PositionClose` (hoặc `CloseFraction` trong basket). Lưu ý: nếu lệnh đóng sớm đang lỗ nhưng sát hòa vốn, vẫn chấp nhận để kéo average.
- **Điều chỉnh target**: gọi `loser.ReduceTargetBy(realized_profit)` để giảm TP distance.
- **Dọn pending**: sau partial close, reset grid trên phần đã bị đóng:
  - `CancelPendingNear(price_current ± spacing_px * pc_pending_guard)` để tránh mở lại ngay.
  - Đặt cờ `m_pc_guard_bars` nhằm trì hoãn reseed trong vùng ức chế.
- **Logging**: `[PartialClose] volume=..., tickets=..., profit=..., distance_retest=..., slope=...`.

## Exit/Cooldown Logic
- Lưu `m_pc_last_close_bar = bars_total` hoặc timestamp để throttle.
- Trong thời gian guard (`pc_guard_bars`), controller skip `TryReseedBasket` cho các level đã đóng để tránh tái DCA ở chính vùng đó.
- Khi guard hết hạn và giá đi xa hơn `pc_guard_exit_atr` × ATR theo hướng bất kỳ, cho phép rebuild grid.

## Parameters
| Input | Default | Ghi chú |
| --- | --- | --- |
| `InpPcRetestAtr` | 0.8 | Hệ số ATR để xác định retest đủ sâu. |
| `InpPcSlopeHysteresis` | 0.0002 | Hysteresis slope khi đánh giá momentum yếu dần. |
| `InpPcMinProfitUsd` | 1.5 | PnL tối thiểu từ nhóm ticket định đóng. |
| `InpPcCloseFraction` | 0.30 | Tỷ lệ tối đa của tổng lot loser được đóng mỗi lần. |
| `InpPcMaxTickets` | 3 | Số ticket tối đa đóng trong một lần partial. |
| `InpPcCooldownBars` | 10 | Số bar tối thiểu giữa hai lần partial close. |
| `InpPcGuardBars` | 6 | Bar phải chờ trước khi cho phép reseed vùng vừa đóng. |
| `InpPcPendingGuardMult` | 0.5 | Nhân spacing để xác định vùng cancel pending tạm thời. |
| `InpPcGuardExitAtr` | 0.6 | Hệ số ATR yêu cầu để bỏ guard (giá thoát khỏi vùng). |
| `InpPcMinLotsRemain` | 0.20 | Lot tối thiểu phải còn lại sau partial close. |

Map sang `SParams`: `pc_retest_atr`, `pc_slope_hysteresis`, `pc_min_profit_usd`, `pc_close_fraction`, `pc_max_tickets`, `pc_cooldown_bars`, `pc_guard_bars`, `pc_pending_guard_mult`, `pc_guard_exit_atr`, `pc_min_lots_remain`.

## Flowchart
```mermaid
flowchart TD
    A[OnTick] --> B[Identify loser]
    B --> C{CanPartialClose?}
    C -- No --> H[Skip partial; continue normal flow]
    C -- Yes --> D[Select tickets near price]
    D --> E[Close subset (<= max tickets, <= fraction)]
    E --> F[Reduce target by realized]
    F --> G[Apply guard: cancel pending near price, set cooldown]
    G --> H[Resume normal flow (rescue, reseed, safety)]
```

## Pseudo-code
```pseudo
bool CLifecycleController::CanPartialClose(CGridBasket *loser,
                                           double price,
                                           double atr_points,
                                           double slope)
{
    if(loser == NULL || !loser.IsActive()) return false;
    if(loser.BasketPnL() >= 0) return false;

    if(m_pc_guard_active && !GuardExpired(price, atr_points))
        return false;

    double total_lot = loser.TotalLot();
    if(total_lot <= params.pc_min_lots_remain) return false;

    if(BarsSince(m_pc_last_close_bar) < params.pc_cooldown_bars)
        return false;

    double distance_retest = fabs(loser.MaxAdversePrice() - price);
    if(atr_points <= 0) atr_points = m_spacing.ToPrice(m_spacing.SpacingPips());
    if(distance_retest < params.pc_retest_atr * atr_points)
        return false;

    if(slope > params.trend_slope_threshold - params.pc_slope_hysteresis)
        return false;

    if(!loser.HasProfitableTickets(params.pc_min_profit_usd,
                                   params.pc_max_tickets,
                                   price))
        return false;

    return true;
}
```

```pseudo
void CLifecycleController::ExecutePartialClose(CGridBasket *loser,
                                               double price,
                                               double spacing_px)
{
    double target_volume = loser.TotalLot() * params.pc_close_fraction;
    target_volume = MathMax(target_volume, params.pc_min_lots_remain);

    int closed = loser.CloseNearestTickets(target_volume,
                                           params.pc_max_tickets,
                                           params.pc_min_profit_usd,
                                           price);

    if(closed > 0)
    {
        double realized = loser.TakePartialCloseProfit();
        if(realized > 0)
            loser.ReduceTargetBy(realized);

        CancelPendingAround(price, spacing_px * params.pc_pending_guard_mult);
        ActivatePcGuard(price);
        m_pc_last_close_bar = CurrentBarIndex();

        if(m_log)
            m_log.Event(Tag(), StringFormat("[PartialClose] tickets=%d profit=%.2f price=%.5f",
                                            closed, realized, price));
    }
}
```

```pseudo
void CLifecycleController::CancelPendingAround(double price,
                                               double offset_px)
{
    if(offset_px <= 0) return;
    if(m_executor == NULL) return;

    double lower = price - offset_px;
    double upper = price + offset_px;

    m_executor.CancelPendingByDirectionRange(loser.Direction(), m_magic,
                                             lower, upper);
}
```

```pseudo
class CGridBasket
{
    double m_max_adverse_price;
    double m_partial_realized;
    int    m_pc_guard_bars_left;

    void UpdateAdversePrice(double price)
    {
        if(m_direction == DIR_SELL)
            m_max_adverse_price = MathMax(m_max_adverse_price, price);
        else
            m_max_adverse_price = MathMin(m_max_adverse_price, price);
    }

    bool HasProfitableTickets(double min_profit,
                              int max_tickets,
                              double ref_price)
    {
        // iterate positions for this basket, compute unrealized per ticket.
        // count tickets within `max_tickets` closest to ref_price that have net >= 0.
    }

    int CloseNearestTickets(double target_volume,
                            int max_tickets,
                            double min_profit,
                            double ref_price)
    {
        // gather tickets (volume, entry price, current pnl)
        // sort by distance to ref_price ascending, filter pnl >= -min_profit tolerance
        // close until reached target_volume or max_tickets
        // accumulate realized into m_partial_realized
    }

    double TakePartialCloseProfit()
    {
        double val = m_partial_realized;
        m_partial_realized = 0.0;
        return val;
    }
};
```

```pseudo
bool CLifecycleController::GuardExpired(double price, double atr_points)
{
    if(!m_pc_guard_active) return true;
    if(BarsSince(m_pc_guard_start) >= params.pc_guard_bars)
        return true;
    double distance = fabs(price - m_pc_guard_price);
    if(distance >= params.pc_guard_exit_atr * atr_points)
        return true;
    return false;
}
```

## Testing Checklist
1. **Trend mạnh với retest ngắn**: xác nhận partial close không kích hoạt quá sớm; khi kích hoạt, log đúng, lot giảm và TP kéo gần.
2. **Sideway rộng**: đảm bảo guard giữ cho bot không liên tục đóng/mở ở cùng vùng; observe log guard expire.
3. **Backtest dài**: kiểm tra cooldown tránh spam partial close (Interval ≥ `pc_cooldown_bars`).
4. **Stress test**: partial close khi spread lớn hoặc ít ticket → xác minh vẫn giữ lại tối thiểu `pc_min_lots_remain`.
5. **Kết hợp Trend Lockdown**: nếu lockdown đang active, partial close vẫn có thể chạy (optional) hoặc bị disable tùy chính sách – xác nhận theo quyết định cuối.
