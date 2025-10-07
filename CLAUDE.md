# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Dual-Grid Trading EA** for MetaTrader 5 (MQL5), implementing a grid trading strategy with **Lazy Grid Fill, Trap Detection, and Quick Exit** features (v3.3).

**Core Strategy**: Maintain two independent baskets (BUY and SELL) that trade simultaneously. Grid expands lazily (on-demand) with trend protection. When trapped, accept small loss to escape quickly.

## Recent Major Update (v3.3.0 - Lazy Grid Fill)

### What Changed

**Problem Solved:**
- Old system: Dynamic grid pre-filled 5-10 levels → trapped during strong trends → massive DD
- New system: Lazy grid fill (1-2 levels) + trap detection → quick exit → minimal DD

**New Features:**
1. **Lazy Grid Fill**: Only 1-2 pending levels at a time, expand on-demand after trend checks
2. **Trap Detector**: Multi-condition algorithm (gap + trend + DD + movement + time)
3. **Quick Exit Mode**: Accept -$10 to -$20 loss to escape trap fast (vs waiting for break-even)
4. **Gap Management**: Bridge fill or close far positions when gap forms

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
│   └── RecoveryGridDirection_v3.mq5    # Main EA entry point (UPDATED v3.3)
└── core/                                # Modular components
    ├── Types.mqh                        # Enums and structs (UPDATED v3.3)
    ├── Params.mqh                       # Strategy parameters struct (UPDATED v3.3)
    ├── LifecycleController.mqh         # Orchestrates both baskets (UPDATED v3.3)
    ├── GridBasket.mqh                   # Manages one directional basket (MAJOR UPDATE v3.3)
    ├── TrapDetector.mqh                 # NEW v3.3: Multi-condition trap detection
    ├── SpacingEngine.mqh                # Grid spacing (PIPS/ATR/HYBRID)
    ├── OrderExecutor.mqh                # Atomic order operations
    ├── OrderValidator.mqh               # Broker constraints validation
    ├── NewsFilter.mqh                   # Economic calendar news filter
    ├── TrendFilter.mqh                  # Strong trend protection (Phase 1.1)
    ├── JobManager.mqh                   # Multi-job system manager (Phase 2)
    ├── PresetManager.mqh                # Symbol-specific presets
    ├── Logger.mqh                       # Event logging (UPDATED v3.3)
    └── MathHelpers.mqh                  # Math utilities
```

### Architecture Changes (v3.3)

**New Files:**
- `src/core/TrapDetector.mqh` - Multi-condition trap detection

**Modified Files:**
- `src/core/GridBasket.mqh` - MAJOR: Lazy fill, quick exit, gap management
- `src/core/LifecycleController.mqh` - Global risk monitoring, profit sharing x2 for quick exit
- `src/core/Types.mqh` - New enums (ENUM_GRID_STATE, ENUM_TRAP_CONDITION, ENUM_QUICK_EXIT_MODE)
- `src/core/Params.mqh` - New input parameters (20+ new inputs)
- `src/core/Logger.mqh` - New log events

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

5. **CNewsFilter** (`NewsFilter.mqh`)
   - Fetches economic calendar from ForexFactory API
   - Pauses trading during high-impact news events
   - Configurable buffer window (before/after news)
   - Retry logic with exponential backoff (max 5 attempts)
   - Rate-limited error logging to prevent spam

6. **CTrendFilter** (`TrendFilter.mqh`) - Phase 1.1 Strong Trend Protection
   - Detects strong trends using EMA + ADX indicators
   - Blocks counter-trend positions during strong trends
   - Three action modes: NONE (block new only), CLOSE_ALL (flatten counter-trend), NO_REFILL (stop adding levels)
   - Hysteresis logic prevents rapid state changes (3-minute cooldown)
   - Configurable EMA timeframe, ADX threshold, and buffer distance

7. **CJobManager** (`JobManager.mqh`) - Phase 2 Multi-Job System (EXPERIMENTAL)
   - Manages multiple independent lifecycle instances with unique magic numbers
   - Auto-spawns new jobs based on triggers (grid full, TSL active, DD threshold)
   - Per-job stop loss and global DD limits for risk management
   - Job lifecycle: ACTIVE → STOPPED/ABANDONED
   - Spawn cooldown and max spawn limits to prevent over-trading

8. **CPresetManager** (`PresetManager.mqh`)
   - Symbol-specific preset configurations
   - Tested presets for EURUSD, XAUUSD, GBPUSD, USDJPY
   - Volatility-based presets (LOW_VOL, MEDIUM_VOL, HIGH_VOL)
   - Auto-detection based on symbol name
   - Adjusts spacing, grid levels, targets per symbol characteristics

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

**Symbol Presets** (Simplifies configuration):
- `InpSymbolPreset`: PRESET_AUTO (auto-detect), LOW_VOL, MEDIUM_VOL, HIGH_VOL, CUSTOM
- `InpUseTestedPresets`: Use tested presets for EUR, XAU, GBP, JPY (overrides volatility preset)

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

**Grid Protection** (Anti-Blow-Up):
- `InpGridProtection`: Enable auto-close when grid full (prevents runaway exposure)
- `InpCooldownMinutes`: Cooldown period after grid full before reseeding (default: 30 minutes)

**News Filter** (Pause trading during news):
- `InpNewsFilterEnabled`: Enable/disable news filter (default: true)
- `InpNewsImpactFilter`: Filter level - "High", "Medium+", or "All" (default: "High")
- `InpNewsBufferMinutes`: Minutes to pause before/after news event (default: 30)

**Trend Filter** (Phase 1.1 - Strong Trend Protection):
- `InpTrendFilterEnabled`: Enable/disable trend filter (default: false - TEST FIRST!)
- `InpTrendAction`: TREND_ACTION_NONE (block new only), CLOSE_ALL (flatten counter-trend), NO_REFILL (stop adding levels)
- `InpTrendEMA_Timeframe`: EMA timeframe for trend detection (default: H4)
- `InpTrendEMA_Period`: EMA period (default: 200)
- `InpTrendADX_Period`: ADX period (default: 14)
- `InpTrendADX_Threshold`: ADX threshold for strong trend (default: 30.0)
- `InpTrendBufferPips`: Distance buffer from EMA in pips (default: 100.0)

**Multi-Job System** (Phase 2 - EXPERIMENTAL):
- `InpMultiJobEnabled`: Enable multi-job system (default: false - OFF by default)
- `InpMaxJobs`: Max concurrent jobs (5-10 recommended)
- `InpJobSL_USD`: Stop loss per job in USD (0=disabled)
- `InpJobDDThreshold`: Abandon job if DD >= this % (e.g., 30%)
- `InpGlobalDDLimit`: Stop spawning if global DD >= this % (e.g., 50%)
- `InpMagicOffset`: Magic number offset between jobs (e.g., 421)
- `InpSpawnOnGridFull`: Spawn new job when grid full
- `InpSpawnOnTSL`: Spawn new job when TSL active
- `InpSpawnOnJobDD`: Spawn new job when job DD >= threshold
- `InpSpawnCooldownSec`: Cooldown between spawns (seconds)
- `InpMaxSpawns`: Max spawns per session

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

## Key Concepts (v3.3)

### 1. Lazy Grid Fill

**Old Way:**
```
Start: 1 market + 5 pending = 6 orders ready
→ Strong trend → all 6 fill → trapped
```

**New Way:**
```
Start: 1 market + 1 pending = 2 orders
Level 1 fills → Check trend → OK → Place level 2
Level 2 fills → Check trend → COUNTER! → HALT
→ Only 2 positions trapped (vs 6)
```

**Guards Before Each Expansion:**
1. Trend filter: counter-trend? → HALT
2. DD threshold: < -20%? → HALT
3. Max levels: reached limit? → GRID_FULL
4. Distance: next level > 500 pips? → Skip

### 2. Trap Detection (5 Conditions)

Requires 3 out of 5 conditions to trigger:

| Condition | Check | Threshold |
|-----------|-------|-----------|
| **Gap** | Max distance between positions | > 200 pips |
| **Counter-Trend** | TrendFilter.IsCounterTrend() | Strong trend opposite direction |
| **Heavy DD** | Basket DD% | < -20% |
| **Moving Away** | Price distance from average | Increasing > 10% |
| **Stuck** | Oldest position age | > 30 min with DD < -15% |

**Example:**
```
SELL basket:
✅ Gap: 250 pips (L0-L1 gap to current)
✅ Counter-trend: Strong uptrend detected
✅ DD: -22%
❌ Moving away: No (stable)
❌ Stuck: Only 20 min
Result: 3/5 → TRAP DETECTED! → Quick exit activated
```

### 3. Quick Exit Mode

**Purpose:** Accept small loss (-$10 to -$20) to escape trap FAST

**Old TP Calculation:**
```
Average: 1.1025
Target: +$5 profit
TP: 1.0995 (avg - 30 pips)
Current: 1.1300
Distance: 305 pips ← MAY NEVER REACH!
```

**Quick Exit TP:**
```
Average: 1.1025
Target: -$10 loss (ACCEPT LOSS!)
TP: 1.1015 (avg - 10 pips)
Current: 1.1300
Distance: 285 pips ← EASIER TO REACH
```

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

**Option 1: Use Symbol Presets (RECOMMENDED - Easiest)**
```
InpSymbolPreset: PRESET_AUTO (auto-detects symbol and applies tested settings)
InpUseTestedPresets: true (uses EUR/XAU/GBP/JPY presets if available)
InpMagic: 990045 (CHANGE THIS for each instance!)
InpLotBase: 0.01-0.10 (adjust for account size)
InpLotScale: 1.0-2.0 (1.0 = flat, 2.0 = martingale - START WITH 1.0!)
```

**Option 2: Manual Configuration (Advanced Users)**
```
InpSymbolPreset: PRESET_CUSTOM (disables presets, use manual settings)
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

Grid Protection:
InpGridProtection: true
InpCooldownMinutes: 30

Execution:
InpOrderCooldownSec: 5
InpSlippagePips: 1
InpRespectStops: false (for backtest)
InpCommissionPerLot: 7.0 (adjust to your broker)
```

### ⚠️ Critical Warnings
- **USE SYMBOL PRESETS** - Recommended to use `PRESET_AUTO` for tested symbols (EUR/XAU/GBP/JPY)
- **PRESET_AUTO is safer** - Automatically applies validated spacing/grid settings per symbol
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

### 🧪 Experimental Features (Phase 1.1 & Phase 2)

**⚠️ IMPORTANT**: These features are EXPERIMENTAL and OFF by default. Test thoroughly on demo before enabling.

#### Trend Filter (Phase 1.1 - Strong Trend Protection)

**Purpose**: Prevents counter-trend positions during strong trends (e.g., blocks SELL during strong uptrend)

**How it works**:
- Uses EMA + ADX to detect strong trends
- Three action modes:
  - `TREND_ACTION_NONE`: Block opening new counter-trend baskets (safest)
  - `TREND_ACTION_CLOSE_ALL`: Flatten all counter-trend positions (aggressive)
  - `TREND_ACTION_NO_REFILL`: Allow existing positions but stop adding levels (moderate)
- Hysteresis logic (3-minute cooldown) prevents rapid state changes

**Recommended Settings** (for testing):
```
InpTrendFilterEnabled   = true
InpTrendAction          = TREND_ACTION_NONE  // Start with safest mode
InpTrendEMA_Timeframe   = PERIOD_H4
InpTrendEMA_Period      = 200
InpTrendADX_Threshold   = 30.0  // Higher = stricter (fewer false signals)
InpTrendBufferPips      = 100.0
```

**⚠️ Warnings**:
- May reduce trading opportunities (blocks counter-trend trades)
- Test on different symbols/timeframes - effectiveness varies
- Start with `TREND_ACTION_NONE` before trying `CLOSE_ALL` or `NO_REFILL`

#### Multi-Job System (Phase 2 - EXPERIMENTAL)

**Purpose**: Manages multiple independent trading instances with auto-spawn triggers

**How it works**:
- Each "job" is an independent lifecycle controller with unique magic number
- Auto-spawns new jobs based on triggers (grid full, TSL active, DD threshold)
- Per-job stop loss and global DD limits for risk management
- Jobs can be ACTIVE, STOPPED, or ABANDONED

**Recommended Settings** (for testing):
```
InpMultiJobEnabled      = true
InpMaxJobs              = 5      // Start small (3-5 jobs max)
InpJobSL_USD            = 50.0   // Per-job stop loss
InpJobDDThreshold       = 30.0   // Abandon job at 30% DD
InpGlobalDDLimit        = 50.0   // Stop spawning at 50% global DD
InpMagicOffset          = 421    // Magic number spacing between jobs
InpSpawnOnGridFull      = true
InpSpawnOnTSL           = false  // Disable until TSL is re-implemented
InpSpawnOnJobDD         = false  // Start with grid-full trigger only
InpSpawnCooldownSec     = 30
InpMaxSpawns            = 10
```

**⚠️ CRITICAL Warnings**:
- **HIGH RISK**: Can spawn multiple jobs rapidly, multiplying exposure
- **ACCOUNT BLOW-UP RISK**: Test on demo with small lot sizes first
- **NOT RECOMMENDED for live trading** until extensively tested
- Monitor account equity closely - each job adds exposure
- Spawning too many jobs = exponential lot size growth
- Start with ONLY `InpSpawnOnGridFull = true`, disable other triggers

#### Symbol Preset System

**Purpose**: Simplifies configuration with tested settings per symbol

**Tested Presets** (validated with backtests):
- **EURUSD**: 25 pips spacing, 10 levels, conservative
- **XAUUSD**: 150 pips spacing, 5 levels, wide (tested: +472%)
- **GBPUSD**: 50 pips spacing, 7 levels, medium volatility
- **USDJPY**: 40 pips spacing, 8 levels, stable trends

**Volatility-Based Presets** (for untested symbols):
- `LOW_VOL`: 25 pips, 10 levels (EURUSD-like)
- `MEDIUM_LOW_VOL`: 35 pips, 9 levels
- `MEDIUM_VOL`: 45 pips, 8 levels
- `MEDIUM_HIGH_VOL`: 60 pips, 6 levels
- `HIGH_VOL`: 150 pips, 5 levels (XAUUSD-like)

**Usage**:
```
InpSymbolPreset: PRESET_AUTO  // Auto-detects and applies best preset
InpUseTestedPresets: true     // Prefer tested presets over volatility-based
```

## Development Best Practices

- **New features**: Always create feature branches with enable/disable flags to avoid breaking stable version
- **Testing**: Use MT5 Strategy Tester for backtesting (do NOT test .mq5/.mqh files with other tools)
- **Experimental features**: Keep OFF by default, require explicit opt-in
- **Documentation**: Update relevant docs (STRATEGY_SPEC.md, ARCHITECTURE.md) when adding features