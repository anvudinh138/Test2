# Glossary - Recovery Grid Direction v3.1.0

## Core Terms

**Basket** - A group of positions in one direction (BUY or SELL). Each basket operates independently with its own grid levels, average price, and profit target.

**Grid** - A series of pending orders placed at fixed intervals above/below the current price. The EA maintains two grids simultaneously (BUY and SELL).

**Grid Level** - A specific price point where a pending order is placed. Each level has a configured lot size based on the scaling factor.

**Group TP** - The take-profit price for an entire basket, calculated as break-even + target profit. When price reaches this level, all positions in the basket close together.

## Features (Always Enabled)

**Lazy Grid Fill** - Instead of placing all grid levels at once, the EA starts with 1-2 pending orders and expands the grid as needed. This reduces initial exposure and adapts to market movement.

**Dynamic Spacing** - Grid spacing automatically widens during strong trends (up to 3x normal spacing). This reduces the number of positions opened during unfavorable conditions.

**Time-Based Exit** - Positions stuck underwater for more than 24 hours are closed if the loss is acceptable (≤ $100). This prevents prolonged drawdown periods.

## Trading Mechanics

**Average Price** - The weighted average entry price of all positions in a basket, calculated as: Σ(lot × price) / Σ(lot)

**Floating P&L** - The unrealized profit/loss of open positions in a basket, calculated based on current market price vs average price.

**Profit Redistribution** - When one basket closes with profit, that profit is used to reduce the opposite basket's target requirement, pulling its TP closer to current price.

**Reseed** - After a basket closes, it automatically reopens with a fresh grid starting from the current market price.

## Market Analysis

**Trend Strength** - Analyzed using EMA, ADX, and ATR indicators to determine market state (RANGE, WEAK_TREND, STRONG_TREND, EXTREME_TREND).

**Spacing Multiplier** - Dynamic adjustment factor applied to base spacing:
- RANGE: 1.0x (normal spacing)
- WEAK_TREND: 1.5x
- STRONG_TREND: 2.0x
- EXTREME_TREND: 3.0x

## Configuration Terms

**Magic Number** - Unique identifier for the EA's orders. Must be different for each EA instance running on the same account.

**Symbol Preset** - Pre-configured settings optimized for specific symbols (EURUSD, XAUUSD, GBPUSD, USDJPY) or volatility levels.

**Lot Scale** - Multiplier for lot sizes at deeper grid levels:
- 1.0 = Flat (same lot all levels)
- 2.0 = Martingale (doubling)
- 1.5 = Moderate progression

## Risk Management

**Session SL** - Reference value for maximum acceptable loss per session. Note: This is for monitoring only and NOT automatically enforced by the EA.

**Drawdown (DD)** - The current floating loss as a percentage of account balance. The EA monitors DD to make decisions about grid expansion.

**Time Underwater** - Duration since the first position in a basket was opened. Used for time-based exit decisions.

## Optional Features

**Trap Detection** - (Experimental) Algorithm to detect when a basket is stuck in an unfavorable position with little chance of recovery.

**Quick Exit** - (Experimental) Mode to accept small controlled losses to escape from trapped positions quickly.

**News Filter** - Pauses trading during high-impact economic news events to avoid volatility spikes.

## Removed Terms (No Longer Used)

~~**TSL (Trailing Stop Loss)**~~ - Removed in v3.1.0
~~**Hedge/Rescue System**~~ - Removed in v3.1.0
~~**Multi-Job System**~~ - Removed in v3.1.0
~~**Basket Stop Loss**~~ - Removed in v3.1.0
~~**Gap Management**~~ - Removed in v3.1.0
~~**Breach Detection**~~ - Removed in v3.1.0
~~**Portfolio Ledger**~~ - Removed in v3.1.0

---

*Last Updated: October 2024*