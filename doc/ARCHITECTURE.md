Architecture
Modules

CLifecycleController — orchestrates both baskets (BUY/SELL), rescue decisions, flipping, and safety checks.

CGridDirection — manages one basket: grid creation, average price, PnL, group TP math, TSL behavior.

CRescueEngine — breach/DD detection, cooldown & exposure gating, opening opposite hedge with staged limits.

CSpacingEngine — computes spacing by PIPS/ATR/HYBRID with min floors.

COrderExecutor — atomic open/modify/close; consolidates broker rules and retries.

COrderValidator — stops level, freeze, min distance, max orders, slippage.

CPortfolioLedger — exposure in lots, realized/unrealized PnL, session SL; produces ExceedsLimits().

CLogger — structured events for backtest/forward logs.

Responsibilities & Data Flow

Controller.Update() pulls market price, calls A.Update(), B.Update(), chooses loser/winner.

Calls RescueEngine.ShouldRescue(); on true, asks OrderExecutor to open opposite hedge on winner.

Each basket recomputes tp_price and monitors TSL; when hit, executor closes the entire basket.

Ledger aggregates realized profits; controller reduces target_cycle_usd for the loser by hedge profits and recomputes TP.

On risk breach, controller orders flatten & halt.

This layering keeps UI-free logic pure and portable across MT5, cTrader, or Python.
