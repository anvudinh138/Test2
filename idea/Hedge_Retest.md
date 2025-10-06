# Hedge Retest Activation Specification

## Problem
Trong logic hiện tại, khi basket thắng (hedge) đóng TP/TSL xong và được reseed ngay, đôi khi giá vẫn chạy cùng xu hướng → hedge mới khớp liên tục nhưng hiệu quả thấp, hoặc mở quá sớm khi chưa có retest rõ ràng.

## Idea
Sau khi basket hedge hoàn thành một chu kỳ, tạm “trống” và chỉ tái kích hoạt khi xuất hiện tín hiệu retest cụ thể (ví dụ giá quay lại vùng ATR xác định). Điều này giúp hedge vào đúng nhịp pullback, tránh tiêu tốn margin lúc trend vẫn tiếp diễn mạnh.

## Goals
- Giữ basket hedge ở trạng thái idle sau khi đóng, chờ retest rồi mới seed lại grid.
- Đảm bảo basket loser vẫn được bảo vệ (lockdown/partial close) trong thời gian hedge chờ.
- Cho phép định nghĩa rõ ràng tiêu chí retest (ATR distance, price structure).

## Retest Criteria (đề xuất)
1. **Price distance**: Sau khi hedge đóng ở giá `close_price`, chờ giá di chuyển thêm `hedge_wait_distance` × ATR theo hướng trend hiện tại. Ví dụ BUY hedge đóng ở `p_close`; nếu trend lên tiếp, yêu cầu giá tăng thêm `d_up`; sau đó khi giá retest về `p_close - hedge_retest_atr × ATR`, mới seed hedge.
2. **Time delay**: đảm bảo ít nhất `hedge_wait_bars` bar trôi qua trước khi xét retest.
3. **Momentum deceleration**: slope EMA giảm dưới `hedge_slope_threshold` hoặc RSI < ngưỡng (optional) để chắc chắn pullback bắt đầu.
4. **Confirmation**: nến đóng ngược hướng trend (ví dụ bearish close với trend up) ở vùng retest.

## Parameters
| Input | Default | Ghi chú |
| --- | --- | --- |
| `InpHedgeRetestEnable` | true | Bật/tắt chế độ chờ retest. |
| `InpHedgeWaitBars` | 3 | Số bar tối thiểu sau khi hedge đóng trước khi xét retest. |
| `InpHedgeWaitAtr` | 0.8 | Khoảng cách giá cần di chuyển thêm theo xu hướng trước khi chờ quay lại (đảm bảo trend tiếp tục). |
| `InpHedgeRetestAtr` | 0.6 | Khoảng cách từ đỉnh/đáy mới về vùng close để coi là retest. |
| `InpHedgeRetestEmaSlope` | 0.0003 | Slope EMA nhỏ hơn ngưỡng này coi là momentum giảm. |
| `InpHedgeRetestConfirmBars` | 2 | Số bar đóng ngược hướng cần thiết để xác nhận retest. |

Mapping sang `SParams`: `hedge_retest_enable`, `hedge_wait_bars`, `hedge_wait_atr`, `hedge_retest_atr`, `hedge_retest_slope`, `hedge_retest_confirm_bars`.

## State Tracking
- `CHedgeState` trong `CLifecycleController`:
  - `bool waiting_for_retest;`
  - `double close_price;`
  - `datetime closed_at;`
  - `double extreme_price;` (giá extreme sau khi hedge đóng).
  - `int confirm_counter;`

## Flow
```mermaid
flowchart TD
    A[Hedge basket closes] --> B[Record close price/time]
    B --> C[Disable immediate reseed]
    C --> D[Monitor price movement]
    D --> E{Price moved trendwards ≥ wait_atr?}
    E -- No --> D
    E -- Yes --> F[Set extreme_price]
    F --> G{Price retests towards close by retest_atr?}
    G -- No --> D
    G -- Yes --> H{Momentum confirm? (slope/confirm bars)}
    H -- No --> D
    H -- Yes --> I[Reseed hedge basket]
```

## Pseudo-code
```pseudo
struct SHedgeRetestState
{
    bool waiting;
    double close_price;
    double extreme_price;
    datetime closed_at;
    int confirm_count;
};

void CLifecycleController::OnHedgeClosed(CGridBasket *hedge)
{
    if(!params.hedge_retest_enable)
        return;
    m_hedge_retest.waiting = true;
    m_hedge_retest.close_price = CurrentPrice(hedge.Direction());
    m_hedge_retest.extreme_price = m_hedge_retest.close_price;
    m_hedge_retest.closed_at = TimeCurrent();
    m_hedge_retest.confirm_count = 0;
}
```

```pseudo
bool CLifecycleController::HedgeReadyForReseed(CGridBasket *hedge,
                                               double price,
                                               double atr_points,
                                               double slope)
{
    if(!m_hedge_retest.waiting)
        return true; // normal flow

    if(BarsSince(m_hedge_retest.closed_at) < params.hedge_wait_bars)
        return false;

    // Track extreme price in direction of prior trend
    if(hedge.Direction() == DIR_BUY)
        m_hedge_retest.extreme_price = MathMax(m_hedge_retest.extreme_price, price);
    else
        m_hedge_retest.extreme_price = MathMin(m_hedge_retest.extreme_price, price);

    double distance_trend = fabs(m_hedge_retest.extreme_price - m_hedge_retest.close_price);
    if(distance_trend < params.hedge_wait_atr * atr_points)
        return false; // wait for trend continuation first

    double distance_retest = fabs(price - m_hedge_retest.close_price);
    if(distance_retest > params.hedge_retest_atr * atr_points)
        return false; // not yet retest zone

    if(slope > params.hedge_retest_slope)
        return false; // momentum still high

    // optionally check candle direction (pseudo)
    if(CandleOppositeDirection())
        m_hedge_retest.confirm_count++;
    else
        m_hedge_retest.confirm_count = 0;

    if(m_hedge_retest.confirm_count >= params.hedge_retest_confirm_bars)
    {
        m_hedge_retest.waiting = false;
        return true;
    }

    return false;
}
```

- Trong `TryReseedBasket` gọi `HedgeReadyForReseed` để quyết định có seed lại hay chưa.

## Integration Notes
- Khi retest chưa đạt, `TryReseedBasket` trả false → hedge basket không được init.
- Có thể log `[HedgeRetest] waiting distance=...` để theo dõi.
- Khi `loser` vẫn âm sâu, partial close/adaptive spacing hoạt động bình thường.
- Nếu lifecycle shutdown (FlattenAll) → reset state.

## Testing Checklist
1. **Trend continuation**: sau hedge đóng, giá tiếp tục trend → verify không seed vội; khi retest đúng sâu → hinge seed -> log.
2. **Sideway**: nếu giá không đạt điều kiện trend distance, hedge sẽ sớm reseed (nếu slope giảm, ATR retest). Xem log confirm.
3. **False trigger**: check slope & confirm bars ngăn seed khi mới rung nhẹ.
4. **Edge**: ATR nhỏ → ensure retest distance >= min spacing; tune `hedge_wait_atr`.
5. **Interaction**: test song song với Trend Lockdown (lockdown true -> prisoner). Make sure Hedge retest respects lockdown (if locked, still wait?).
