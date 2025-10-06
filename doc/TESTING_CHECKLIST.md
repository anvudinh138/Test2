Testing & Acceptance Checklist
Functional

 Seeds both BUY & SELL baskets with correct grid spacing and limits.

 Detects loser basket and opens opposite hedge when (breach or DD) and guards hold.

 Hedge basket enables TSL after tsl_start_points, trails by tsl_step_points.

 Realized hedge profits reduce target_cycle_usd for loser and move group TP closer.

 When price touches group TP, close all orders in that basket atomically.

 Role flip occurs correctly; new hedge may be opened against the new loser.

 Limits are rebuilt when filled or invalidated by gaps to maintain grid_levels.

 Risk caps enforced: exposure_cap_lots, session_sl_usd.

Scenarios

 Strong trend up (little pullback).

 Strong trend down.

 Range/whipsaw (frequent reversals).

 Gap open through several levels.

 High spread / low liquidity.

Logging

 Open/close reasons with tags: BREACH, DD, TSL, TP, HALT.

 Cycle id, basket dir, total lot, avg, tp_price, realized pnl.

 Exposure after each action; cumulative session PnL.

Acceptance

 Over 1000+ trades, average cycle profit positive with configured risk caps.

 No rule violations (broker limits) in the logs.

 Halt on breach behaves deterministically.