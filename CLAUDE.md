# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Dual-Grid Trading EA** for MetaTrader 5 (MQL5), implementing a simplified grid trading strategy. The system maintains two independent grids (BUY and SELL) that trade simultaneously.

**Core Strategy**: Maintain two independent baskets (BUY and SELL) with dynamic grid levels. When one basket closes at its group take-profit (TP), use the realized profit to reduce the other basket's TP requirement (pulling it closer to break-even). Each basket automatically reopens with a fresh grid after closing.

## Development Commands

### Compilation
```bash
# MetaEditor command line compilation (if available)
# Otherwise compile through MetaEditor GUI: File -> Compile
```

### Testing
- **Strategy Tester**: Use MT5 Strategy Tester in MetaEditor or MT5 terminal
- **Demo Testing**: Deploy to demo account first (see `TESTING_CHECKLIST.md`)
- **Backtest Scenarios**: Test all scenarios in `doc/TESTING_CHECKLIST.md`

### File Structure
```
src/
├── ea/
│   └── RecoveryGridDirection_v3.mq5    # Main EA entry point
└── core/                                # Modular components
    ├── Types.mqh                        # Enums and structs
    ├── Params.mqh                       # Strategy parameters struct
    ├── LifecycleController.mqh         # Orchestrates both baskets
    ├── GridBasket.mqh                   # Manages one directional basket
    ├── SpacingEngine.mqh                # Grid spacing (PIPS/ATR/HYBRID)
    ├── OrderExecutor.mqh                # Atomic order operations
    ├── OrderValidator.mqh               # Broker constraints validation
    ├── NewsFilter.mqh                   # Economic calendar news filter
    ├── Logger.mqh                       # Event logging
    └── MathHelpers.mqh                  # Math utilities
```

## Architecture

### Module Responsibilities

1. **CLifecycleController** (`LifecycleController.mqh`)
   - Orchestrates BUY and SELL baskets independently
   - Monitors basket closures and handles profit redistribution
   - Automatically reseeds closed baskets with fresh grids
   - Simple two-basket manager (no rescue/hedge logic)

2. **CGridBasket** (`GridBasket.mqh`)
   - Manages one directional basket (BUY or SELL)
   - Tracks grid levels, average price, floating PnL
   - Computes group TP price (break-even + target profit)
   - Supports **Dynamic Grid**: maintains warm pending levels, auto-refills when levels fill
   - Handles target reduction when opposite basket closes with profit

3. **CSpacingEngine** (`SpacingEngine.mqh`)
   - Computes grid spacing: PIPS (fixed), ATR (adaptive), or HYBRID (ATR with floor)
   - Provides adaptive spacing based on market volatility

4. **COrderExecutor** (`OrderExecutor.mqh`)
   - Atomic open/modify/close with retry logic
   - Handles broker-specific constraints

5. **CNewsFilter** (`NewsFilter.mqh`) - NEW FEATURE
   - Fetches economic calendar from ForexFactory API
   - Pauses trading during high-impact news events
   - Configurable buffer window (before/after news)
   - Retry logic with exponential backoff (max 5 attempts)
   - Rate-limited error logging to prevent spam

### Data Flow (Simplified)

1. `OnTick()` → `LifecycleController.Update()`
2. Controller updates both baskets: `m_buy.Update()`, `m_sell.Update()`
3. Each basket refreshes PnL, average price, checks if TP hit
4. When basket closes:
   - Realizes profit
   - Reduces opposite basket's TP requirement by realized profit
   - Automatically reseeds the closed basket with fresh grid
5. Both baskets continue trading independently

## Key Concepts

### Input Parameters (Reorganized for Clarity)

**Identity**:
- `InpMagic`: Magic number for order identification (CHANGE THIS FIRST when running multiple instances!)

**Spacing Engine**:
- `InpSpacingMode`: PIPS (fixed), ATR (adaptive), HYBRID (ATR with min floor)
- `InpSpacingStepPips`: Base spacing in pips (used in PIPS mode)
- `InpSpacingAtrMult`: ATR multiplier (used in ATR/HYBRID modes)
- `InpMinSpacingPips`: Minimum spacing floor for HYBRID mode
- `InpAtrTimeframe`, `InpAtrPeriod`: ATR calculation parameters

**Grid Configuration**:
- `InpGridLevels`: Number of levels per side (including market seed)
- `InpLotBase`: Base lot size for first level
- `InpLotScale`: Lot size multiplier for deeper levels (1.0 = flat, 2.0 = martingale)

**Dynamic Grid** (Auto-refill pending levels):
- `InpDynamicGrid`: Enable/disable auto-refill
- `InpWarmLevels`: Initial number of pending levels to place
- `InpRefillThreshold`: Refill when pending count drops to this value
- `InpRefillBatch`: Number of levels to add per refill
- `InpMaxPendings`: Maximum allowed pending orders (safety limit)

**Profit Target**:
- `InpTargetCycleUSD`: Profit target when basket closes (break-even + this amount)

**Risk Management** (For monitoring):
- `InpSessionSL_USD`: Session stop loss reference (USD) - for monitoring only, not enforced by system

**News Filter** (Pause trading during news - NEW):
- `InpNewsFilterEnabled`: Enable/disable news filter (default: false)
- `InpNewsImpactFilter`: Filter level - "High", "Medium+", or "All" (default: "High")
- `InpNewsBufferMinutes`: Minutes to pause before/after news event (default: 30)

**Execution**:
- `InpOrderCooldownSec`: Minimum seconds between order operations (anti-spam protection)
- `InpSlippagePips`: Maximum allowed slippage in pips
- `InpRespectStops`: Respect broker stops level (set false for backtesting)
- `InpCommissionPerLot`: Commission per lot for PnL calculation (backtest only, does NOT affect live trading)

### Math

**Average Price**: `avg = Σ(lot_i × price_i) / Σ(lot_i)`

**Basket PnL**:
- BUY: `(Bid - avg) × point_value × total_lot - fees`
- SELL: `(avg - Ask) × point_value × total_lot - fees`

**Group TP Solve**: Find `tp_price` where `PnL_at(tp_price) = target_cycle_usd`

**Pulling TP**: When hedge closes profit `H`, reduce loser's `target_cycle_usd` by `H` → recomputes `tp_price` closer to current price

## Testing Requirements

### Functional Tests (from `TESTING_CHECKLIST.md`)
- ✓ Seeds both BUY & SELL baskets with correct grid spacing
- ✓ Detects loser, opens opposite hedge on breach/DD with guards
- ✓ TSL activates and trails correctly on hedge basket
- ✓ Hedge profits reduce loser's target, move group TP closer
- ✓ Group TP hit closes entire basket atomically
- ✓ Role flip and cycle continuation work correctly
- ✓ Dynamic grid refills maintain level count
- ✓ Risk caps enforced (exposure, session SL)

### Scenario Coverage
- Strong trend up (minimal pullback)
- Strong trend down
- Range/whipsaw (frequent reversals)
- Gap open through multiple levels
- High spread / low liquidity

### Logging Requirements
- Open/close reasons: BREACH, DD, TSL, TP, HALT
- Cycle ID, basket direction, total lot, avg price, TP price
- Realized PnL per cycle
- Exposure after each action

## Important Notes

### MQL5 Include Paths
- Main EA includes use: `#include <RECOVERY-GRID-DIRECTION_v3/core/FileName.mqh>`
- Place this folder in MT5's `Include/` directory or adjust paths accordingly

### ⚠️ Simplified Architecture (Major Refactor)

This EA has been significantly simplified from the original design:

**Removed Features**:
1. **TSL (Trailing Stop Loss)** - Removed entirely (was not working correctly)
2. **Recovery/Rescue System** - Removed RescueEngine.mqh (including hedge deployment, breach detection, cooldown logic)
3. **Exposure & Risk Caps** - Removed PortfolioLedger.mqh (InpExposureCapLots, InpMaxCyclesPerSide, InpCooldownBars removed)
4. **Rescue Triggers** - Removed InpDDOpenUSD, InpOffsetRatio parameters
5. **Basket Roles** - No more PRIMARY/HEDGE distinction - both baskets are equal

**Current Behavior**:
- Two independent grids (BUY + SELL) trade simultaneously
- Each basket closes when it hits its group TP
- Realized profit from one basket reduces the other basket's TP requirement
- Closed basket automatically reopens with fresh grid
- No rescue intervention, no exposure caps enforced by code
- Session SL parameter exists but is NOT enforced (monitoring only)

### Broker Constraints
- `InpRespectStops`: Set `false` for backtesting (bypasses broker freeze/stops distance)
- `InpSlippagePips`: Execution tolerance
- `InpOrderCooldownSec`: Minimum seconds between order operations (prevents spam)

### Dynamic Grid Behavior
When `InpDynamicGrid = true`:
- System starts with `InpWarmLevels` pending orders beyond market seed
- As levels fill, maintains count by adding `InpRefillBatch` levels when pendings ≤ `InpRefillThreshold`
- Never exceeds `InpMaxPendings` safety limit
- Logged as `DG/PLACE`, `DG/REFILL` events

### Safety Considerations
**No Automated Risk Limits**: The current simplified version does NOT enforce:
- Exposure caps
- Session stop loss (parameter exists but not enforced)
- Maximum cycles per side

**Manual Monitoring Required**: Users must monitor account manually or use broker-level stop-outs

### Key Parameter Explanations
- **InpOrderCooldownSec**: Minimum seconds between consecutive order operations - prevents broker rejection due to spam
- **InpCommissionPerLot**: Used ONLY for backtest PnL calculation - does NOT affect live trading (broker handles real commission)
- **InpSessionSL_USD**: Monitoring reference only - NOT enforced by code

## Reference Documentation

- `doc/STRATEGY_SPEC.md` — Full specification with parameters and math
- `doc/ARCHITECTURE.md` — Module responsibilities and data flow
- `doc/PSEUDOCODE.md` — Complete pseudocode implementation
- `doc/FLOWCHARTS.md` — Mermaid flowcharts for visual understanding
- `doc/CONFIG_EXAMPLE.yaml` — Safe baseline parameters for testing
- `doc/TESTING_CHECKLIST.md` — Acceptance criteria and test scenarios
- `doc/GLOSSARY.md` — UI/term mapping
- **`doc/NEWS_FILTER.md`** — **NEW**: News filter setup, API integration, troubleshooting

## Parameter Tuning

### Conservative Starting Values (Recommended for Testing)
```
InpMagic: 990045 (CHANGE THIS for each instance!)

Spacing:
InpSpacingMode: Hybrid
InpSpacingStepPips: 25.0
InpSpacingAtrMult: 0.6
InpMinSpacingPips: 12.0

Grid:
InpGridLevels: 6-10
InpLotBase: 0.01-0.10
InpLotScale: 1.0-2.0 (1.0 = flat, 2.0 = martingale - START WITH 1.0!)

Dynamic Grid:
InpDynamicGrid: true
InpWarmLevels: 5
InpRefillThreshold: 2
InpRefillBatch: 3
InpMaxPendings: 15

Profit & Risk:
InpTargetCycleUSD: 3.0-6.0 (small profit targets)
InpSessionSL_USD: 10000 (reference only - NOT enforced)

Execution:
InpOrderCooldownSec: 5
InpSlippagePips: 1
InpRespectStops: false (for backtest)
InpCommissionPerLot: 7.0 (adjust to your broker)
```

### ⚠️ Critical Warnings
- **ALWAYS change `InpMagic` first** when running multiple instances
- **NO AUTOMATED STOP LOSS** - System does NOT enforce exposure caps or session SL
- **MONITOR MANUALLY** - Watch account equity and close positions manually if needed
- Test on demo with 1000+ trades before live deployment
- Start with `InpLotScale = 1.0` (flat lot) to avoid aggressive martingale
- Use small `InpLotBase` (0.01-0.02) for initial testing
- Both grids run simultaneously - total exposure = sum of both baskets

### 🆕 News Filter Setup (Optional)

**Enable WebRequest Permission** (Required for news filter):
1. Tools → Options → Expert Advisors
2. Check "Allow WebRequest for listed URL"
3. Add: `https://nfs.faireconomy.media`

**Recommended Settings**:
```
InpNewsFilterEnabled   = true
InpNewsImpactFilter    = "High"      // Only major events (NFP, FOMC, CPI)
InpNewsBufferMinutes   = 30          // Pause 30 min before/after
```

See `doc/NEWS_FILTER.md` for detailed documentation
