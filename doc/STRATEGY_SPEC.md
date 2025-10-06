# Strategy Specification — Two‑Sided Recovery Grid

## 1. Concepts
- **Basket**: collection of open orders in one direction (BUY *or* SELL). Basket has: total lot, average price, floating P/L, group TP price (the long red/blue bar).
- **Grid**: 1 market seed + (N−1) pending limits spaced by `spacing` on each side.
- **Group TP (TP gộp)**: price level at which **all orders in a basket** are closed together to realize **break‑even + δ**.
- **TSL START**: distance from basket average (or entry) at which **trailing stop** becomes active on the **hedge basket**.
- **Recovery layers**: staged adds or opposite hedges at distances `[1000, 2000, 3000, ...]` points to handle prolonged trends.
- **Flip roles**: after a loser basket is closed at its group TP, the remaining side becomes the new context; system may open a new hedge against it if needed.

## 2. Parameters
| Name | Type | Meaning |
|---|---:|---|
| `spacing_mode` | enum(`PIPS`,`ATR`,`HYBRID`) | How to compute grid step distance. |
| `spacing_pips` | int | Base step if `PIPS`. |
| `spacing_atr_mult` | float | Multiplier of ATR if `ATR`/`HYBRID`. |
| `min_spacing_pips` | int | Floor for hybrid spacing. |
| `grid_levels` | int | Levels per side (incl. market seed). |
| `lot_base` | float | Lot size for seed order. |
| `lot_scale` | float | Multiplier for deeper grid levels (e.g., 1.0 = fixed). |
| `target_cycle_usd` | float | Profit δ when closing loser basket (BE + δ). |
| `tsl_enabled` | bool | Enable trailing on hedge basket. |
| `tsl_start_points` | int | **TSL START** threshold. |
| `tsl_step_points` | int | Trail step. |
| `recovery_steps` | list[int] | Distances for staged rescue/hedge (e.g., `[1000, 2000, 3000]`). |
| `recovery_lot` | float | Lot for each rescue stage (opposite hedge). |
| `dd_open_usd` | float | Open hedge if basket drawdown beyond this. |
| `offset_ratio` | float | Open hedge if price breaches last grid by `ratio*spacing`. |
| `exposure_cap_lots` | float | Max combined exposure. |
| `max_cycles_per_side` | int | Limit number of rescue cycles per trend leg. |
| `session_sl_usd` | float | Hard stop for session/equity. |
| `cooldown_bars` | int | Min bars between new hedges. |
| `slippage_pips` | int | Execution allowance. |
| `commission_per_lot` | float | For realistic PnL computation. |

## 3. Math
- **Average price**: `avg = Σ(l_i * p_i) / Σ(l_i)`  
- **Basket PnL** (simplified):
  - BUY: `pnl = (Bid - avg) * point_value * Σl_i - fees`
  - SELL: `pnl = (avg - Ask) * point_value * Σl_i - fees`
- **Solve group TP**: find `tp_price` such that `PnL_at(tp_price) ≈ target_cycle_usd` (BE + δ).
- **Pulling TP**: when hedge closes profit `H`, reduce `target_cycle_usd` for the loser by `H` → recompute `tp_price` closer to current price.

## 4. Entry/Management Rules
1. **Bootstrap**: create both BUY & SELL grids (seed market + limits up/down by spacing).
2. **Identify loser** each tick:
   - `loser := argmin{ basket_pnl }` if negative; else `None`.
3. **Rescue decision** (open the opposite hedge):
   - Condition A: price **breaches last grid** of loser by `offset_ratio × spacing`.
   - Condition B: loser **drawdown ≥ dd_open_usd`**.
   - Condition C: **cooldown ok**, **exposure under cap**, **cycles under limit**.
   - If `(A or B) and C` ⇒ open **hedge basket** (1 market + optional limits), enable **TSL**.
4. **Trailing** (hedge only): once price moves in favor ≥ `tsl_start_points`, activate trailing; move SL by `tsl_step_points` increments.
5. **Close by Group TP**: if loser basket reaches its computed `tp_price` (or PnL ≥ target), close **all tickets** of that basket atomically.
6. **Flip roles**: after a close, if the other side remains in meaningful drawdown → optionally open a new opposite hedge (continue the cycle).
7. **Safety**: stop trading & flatten if `exposure_cap_lots` or `session_sl_usd` is breached.

## 5. Edge Cases
- **Low volatility** → widen `spacing` by ATR hybrid to avoid overtrading.
- **Gap through grid** → rebuilding pending limits to maintain level count.
- **Broker constraints**: `stops level`, freeze level, min distance, partial fills — guard with `OrderValidator`.
- **News filter** (optional): pause new hedges near events.

## 6. Logging
- Open/close reasons (Breach/DD/TSL/TP), cycle id, lot, avg, tp_price, realized cycle PnL, exposure after action.
