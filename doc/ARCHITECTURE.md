# Architecture - Recovery Grid Direction v3 Simplified

## Core Modules

### CLifecycleController
**Purpose**: Orchestrates both baskets (BUY/SELL), handles profit redistribution and automatic reseeding.

**Key Responsibilities**:
- Initialize and manage both directional baskets
- Monitor basket closures and take realized profits
- Redistribute profits: reduce opposite basket's TP requirement
- Automatically reseed closed baskets with fresh grids
- Coordinate time-based exits for stuck positions

### CGridBasket
**Purpose**: Manages one directional basket with grid levels, P&L tracking, and group TP calculation.

**Key Features**:
- Grid level management (market seed + pending orders)
- Average price and floating P&L calculation
- Group TP computation (break-even + target profit)
- **Lazy grid fill** (always enabled) - starts minimal, expands as needed
- **Dynamic spacing** (always enabled) - widens in trends via CTrendStrengthAnalyzer
- Time-based exit monitoring (exits after 24h underwater)
- Optional trap detection and quick exit modes

### CSpacingEngine
**Purpose**: Computes grid spacing based on configured mode.

**Modes**:
- **PIPS**: Fixed spacing in pips
- **ATR**: Adaptive based on volatility
- **HYBRID**: ATR with minimum floor

### CTrendStrengthAnalyzer
**Purpose**: Analyzes market trend strength for dynamic spacing adjustments.

**Output**:
- Market state: RANGE, WEAK_TREND, STRONG_TREND, EXTREME_TREND
- Spacing multiplier: 1.0x → 3.0x based on trend strength
- Always active when dynamic spacing is enabled

### COrderExecutor
**Purpose**: Executes orders with retry logic and broker constraint handling.

**Features**:
- Atomic operations (open/modify/close)
- Exponential backoff retry on failures
- Respects broker stops/freeze levels
- Slippage control

### COrderValidator
**Purpose**: Validates orders against broker constraints before execution.

**Checks**:
- Stops level and freeze level
- Volume min/max/step requirements
- Sufficient margin
- Maximum order limits

### Other Supporting Modules

- **CPresetManager**: Symbol-specific configurations (EURUSD, XAUUSD, etc.)
- **CNewsFilter**: Pauses trading during high-impact news events
- **CLogger**: Structured event logging for debugging and analysis
- **MathHelpers**: Common calculations (NormalizeVolume, NormalizePrice, etc.)

## Data Flow

### Initialization
```
OnInit()
  ├── BuildParams()              // Configure from inputs
  ├── Create CLogger             // Setup logging
  ├── Create CSpacingEngine      // Setup spacing calculator
  ├── Create COrderExecutor      // Setup order execution
  ├── Create CLifecycleController
        ├── Create CGridBasket (BUY)
        └── Create CGridBasket (SELL)
```

### Tick Processing
```
OnTick()
  ├── Check market open
  ├── Check news filter
  └── LifecycleController.Update()
        ├── BUY basket.Update()
        │     ├── Refresh positions
        │     ├── Calculate P&L
        │     ├── Check time exit
        │     ├── Check group TP
        │     └── Lazy grid expansion
        ├── SELL basket.Update()
        └── Handle closures
              ├── Take realized profit
              ├── Reduce opposite TP
              └── Reseed basket
```

## Simplified Architecture Benefits

### What's Been Removed
- **Complex hedge/rescue logic** - No more RescueEngine
- **Multi-job spawning** - No more JobManager
- **Basket stop losses** - Accept natural losses instead
- **Gap management** - No more GapManager
- **Portfolio ledger** - Simplified P&L tracking

### Always-On Features
- **Lazy Grid Fill**: Reduces initial exposure, adapts to market
- **Dynamic Spacing**: Automatically widens in trends, reduces risk
- **Time-Based Exit**: Critical protection against prolonged drawdown

### Result
- **-1,553 lines of code** removed
- Cleaner, more maintainable codebase
- Focus on proven profitable features
- Easier to debug and enhance

---

*Last Updated: October 2024*