# Trend Lockdown Specification

## Goals
- Nhận diện khi basket thua bị kéo xa theo một chiều với slope lớn.
- Tạm dừng DCA/rescue chiều thua để chặn drawdown runaway.
- Siết hành vi basket hedge để lợi nhuận hiện có giúp bù khi trend hạ nhiệt.
- Log đầy đủ để quan sát hành vi qua backtest.

## Activation Conditions
Lockdown kích hoạt khi **đồng thời** thỏa các điều kiện sau (đánh giá mỗi tick):

1. `distance_price = |price_current - loser.AveragePrice()|` ≥ `trend_k_atr` × `ATRPoints()` (đang có trong code).
2. `TrendSlopeValue()` ≥ `trend_slope_threshold` (độ dốc EMA 200).
3. (Tuỳ chọn trong tương lai) EMA nhanh (ví dụ EMA 21) cùng phía EMA 200 với khoảng cách tối thiểu `ema_fast_gap_points`.
4. `loser.TotalLot()` ≥ `lock_min_lots` (tham số mới) **và** `|loser.GroupTPPrice() - price_current|` ≥ `tp_distance_z_atr` × ATR.

Nếu đạt → set `m_lockdown_active = true` và lưu `m_lockdown_since` + `m_lockdown_bars = 0`.

## Behaviour while Lockdown Active
- **Chặn rescue/DCA**: ngoài filter sẵn (`TrendBlocksRescue`), gọi `CancelFarPending(loser)` để xóa pending sâu hơn `loser.AveragePrice() ± spacing_px * lock_cancel_mult`.
- **Siết hedge**: nếu basket thắng đang có lãi, thắt TSL lại (ví dụ `winner.SetTrailOverride(spacing_px/2)`) hoặc đóng một phần (`winner.CloseFraction(lockdown_close_pct)`). Nếu `lockdown_close_pct <= 0`, chỉ điều chỉnh trailing.
- **Logging**: ghi log một lần khi bật với slope, ATR multiple, tổng lot, khoảng cách TP.
- **Timer**: mỗi lần tick tăng `m_lockdown_bars`. Yêu cầu tối thiểu `lock_min_bars` trước khi xét unlock.

## Exit Conditions
Lockdown tắt khi:
- `distance_price` < (`trend_k_atr` − `lock_hysteresis_atr`) × ATR **và** `TrendSlopeValue()` < (`trend_slope_threshold` − `lock_hysteresis_slope`), **và** `m_lockdown_bars ≥ lock_min_bars`;
- Hoặc vượt `lock_max_bars` (failsafe) và basket loser không còn âm sâu (`loser.BasketPnL() > −tp_distance_z_atr * ATRPoints() * pnl_per_point`).

Thoát → log event, gọi `ExitLockdown()` để bật lại `TryReseedBasket`, reset trail override, `m_lockdown_active=false`.

## Parameters
| Input | Default | Mục đích |
| --- | --- | --- |
| `InpLockMinLots` | 0.50 | Tối thiểu tổng lot loser trước khi lockdown hợp lệ. |
| `InpLockMinBars` | 3 | Số bar tối thiểu phải ở trạng thái lockdown trước khi xét unlock. |
| `InpLockMaxBars` | 30 | Failsafe buộc thoát lockdown sau X bar. |
| `InpLockCancelMultiplier` | 0.5 | Khoảng cách (theo spacing) để quyết định pending bị hủy. |
| `InpLockHysteresisATR` | 0.5 | Hysteresis ATR để tránh bật/tắt liên tục. |
| `InpLockHysteresisSlope` | 0.0002 | Hysteresis slope EMA để tránh jitter. |
| `InpLockHedgeClosePct` | 0.20 | Phần trăm hedge đóng ngay khi lockdown (0 = không đóng). |

Mapping sang `SParams`: `lock_min_lots`, `lock_min_bars`, `lock_max_bars`, `lock_cancel_mult`, `lock_hyst_atr`, `lock_hyst_slope`, `lock_hedge_close_pct`.

## Flowchart
```mermaid
flowchart TD
    A[OnTick] --> B[Refresh BUY/SELL baskets]
    B --> C{Determine loser & winner}
    C --> D[Compute ATR, slope]
    D --> E{Lockdown active?}

    E -- No --> F{ShouldLockdown?}
    F -- Yes --> G[EnterLockdown()
- set flags
- cancel far pending
- tighten hedge]
    F -- No --> H[Proceed with rescue logic]

    E -- Yes --> I[UpdateLockdownBars]
    I --> J{CanExitLockdown?}
    J -- Yes --> K[ExitLockdown()
- reset trail
- allow reseed]
    J -- No --> L[Skip rescue
Maintain tightened hedge]

    H --> M[Rescue decision]
    L --> N[Continue basket updates]
    K --> N
    M --> N
    N --> O[Post-cycle tasks
(reseed, reduce targets, safety checks)]
    O --> P[End Tick]
```

## Pseudo-code
```pseudo
method Update():
    refresh baskets
    spacing_px = m_spacing.ToPrice(m_spacing.SpacingPips())
    atr_points = m_spacing.AtrPoints()
    loser, winner = IdentifyLoserWinner()
    price_loser = CurrentPrice(loser.Direction())
    slope = TrendSlopeValue()
    distance = abs(price_loser - loser.AveragePrice())

    if (!m_lockdown_active):
        if ShouldLockdown(loser, distance, slope, atr_points):
            EnterLockdown(loser, winner, spacing_px, distance, slope)
    else:
        m_lockdown_bars++
        if CanExitLockdown(loser, distance, slope, atr_points):
            ExitLockdown(loser, winner)
        else:
            // while locked skip rescue but still manage baskets
            goto AfterRescue

    // Rescue logic only when not locked
    if (loser && winner):
        handle rescue as hiện tại

AfterRescue:
    handle basket closed/resets như cũ
```

```pseudo
method ShouldLockdown(loser, distance, slope, atr_points):
    if loser == NULL: return false
    if atr_points <= 0: atr_points = spacing_px
    if distance < params.trend_k_atr * atr_points: return false
    if slope < params.trend_slope_threshold: return false
    if loser.TotalLot() < params.lock_min_lots: return false
    if abs(loser.GroupTPPrice() - price_loser) < params.tp_distance_z_atr * atr_points: return false
    return true
```

```pseudo
method EnterLockdown(loser, winner, spacing_px, distance, slope):
    m_lockdown_active = true
    m_lockdown_since = TimeCurrent()
    m_lockdown_bars = 0
    CancelFarPending(loser, spacing_px * params.lock_cancel_mult)
    if winner && params.lock_hedge_close_pct > 0:
        winner.CloseFraction(params.lock_hedge_close_pct)
    if winner:
        winner.SetTrailOverride(spacing_px / 2)
    log "[Lockdown Enter]" với distance, slope
```

```pseudo
method CancelFarPending(basket, offset_px):
    limit_price = basket.AveragePrice() ± offset_px (theo direction)
    basket.CancelPendingBeyond(limit_price)
```

```pseudo
method CanExitLockdown(loser, distance, slope, atr_points):
    if m_lockdown_bars < params.lock_min_bars: return false
    cond1 = distance < (params.trend_k_atr - params.lock_hyst_atr) * atr_points
    cond2 = slope < (params.trend_slope_threshold - params.lock_hyst_slope)
    cond3 = m_lockdown_bars >= params.lock_max_bars
    if (cond1 && cond2) or cond3:
        return true
    return false
```

```pseudo
method ExitLockdown(loser, winner):
    m_lockdown_active = false
    m_lockdown_since = 0
    if winner:
        winner.ResetTrailOverride()
    log "[Lockdown Exit]"
```

```pseudo
class CGridBasket:
    method CloseFraction(pct):
        if pct <= 0: return
        target_volume = TotalLot() * pct
        iterate positions matching direction & magic, closing until reached

    method CancelPendingBeyond(limit_price):
        iterate pending orders; delete nếu giá vượt limit tùy hướng

    method SetTrailOverride(step_points):
        m_trail_override = step_points; ManageTrailing dùng override nếu > 0

    method ResetTrailOverride():
        m_trail_override = 0
```

## Testing Checklist
1. Backtest trend tăng/giảm mạnh: log enter, không còn pending chiều thua mới, hedge trail siết lại.
2. Backtest range: lockdown hiếm kích hoạt; nếu có thì thời gian ngắn và exit đúng.
3. Edge case: lockdown đang bật khi cửa sổ giao dịch đóng → đảm bảo reset khi phiên mới mở.
4. Kiểm tra lot trước/sau partial close (nếu bật) để tránh đóng quá tay.
5. Theo dõi `m_lockdown_bars` trong log để chắc chắn hysteresis hoạt động.
