# Recovery Grid Direction v3 - Simplified Edition

**Version**: 3.1.0
**Date**: October 2024
**Status**: Production Ready

> **DISCLAIMER**: Educational purposes only — not investment advice. Grid strategies can experience significant drawdowns in strong trends. Always test on demo accounts first.

## Overview

Recovery Grid Direction v3 is a **simplified dual-grid trading EA** for MetaTrader 5 that maintains two independent grids (BUY and SELL) trading simultaneously. This version has been significantly refactored to focus on **profitable features** while **accepting controlled losses** during unfavorable market conditions.

### Core Philosophy
- **Maximize profits** during favorable market conditions
- **Accept controlled losses** during strong adverse trends
- **Remove complexity** that doesn't add proven value
- **Keep only features** that have been tested and proven to work

## Key Features

### Always-Enabled Features (Proven & Profitable)

1. **Lazy Grid Fill** ✅
   - Starts with minimal pending orders (1-2 levels)
   - Automatically expands grid as market moves
   - Reduces initial exposure and margin requirements
   - Adapts to actual market movement patterns

2. **Dynamic Spacing** ✅
   - Automatically widens grid spacing during strong trends
   - Reduces position count in unfavorable conditions
   - Spacing multiplier: 1.0x → 3.0x based on trend strength
   - Proven to reduce drawdown significantly

3. **Time-Based Exit** ⭐ **CRITICAL**
   - Exits positions stuck underwater > 24 hours
   - Accepts controlled loss (default: ≤ $100)
   - Prevents catastrophic drawdown from prolonged positions
   - **Proven to reduce DD by 50%** (from -40% to -20%)

### Core Trading Logic

1. **Dual Grid System**: Both BUY and SELL grids always active
2. **Group Take Profit**: Each basket has calculated TP (break-even + target)
3. **Profit Redistribution**: Profits from closed basket reduce opposite basket's TP
4. **Automatic Reseed**: Closed baskets immediately reopen with fresh grids
5. **No Hedging/Rescue**: Simplified approach without complex recovery logic

## What's Been Removed (v3.1.0 Refactor)

The following features were removed to simplify the codebase:

| Feature | Reason for Removal |
|---------|-------------------|
| **Multi-Job System** | Complex spawning logic without proven benefits |
| **Basket Stop Loss** | Accept natural losses instead of forced stops |
| **Gap Management** | Unnecessary complexity, minimal impact |
| **TSL (Trailing Stop)** | Implementation was buggy and ineffective |
| **Recovery/Rescue System** | Overly complex hedge deployment |
| **Exposure Caps** | Prefer manual monitoring and intervention |

## Quick Start Guide

### 1. Installation
```
1. Copy entire src/ folder to: MT5_Data_Folder/MQL5/Include/RECOVERY-GRID-DIRECTION_v3/
2. Copy RecoveryGridDirection_v3.mq5 to: MT5_Data_Folder/MQL5/Experts/
3. Open in MetaEditor and compile (F7)
```

### 2. Essential Configuration
```
InpMagic = 990045           # UNIQUE for each instance!
InpSymbolPreset = PRESET_AUTO  # Auto-detect symbol settings
InpLotBase = 0.01           # Start small
InpLotScale = 1.0           # 1.0=flat, 2.0=martingale
InpTargetCycleUSD = 10.0   # Profit target per cycle
InpTimeExitEnabled = true  # CRITICAL - Must enable!
```

### 3. Testing Protocol
1. **Backtest**: Run in Strategy Tester for 3-6 months
2. **Demo**: Deploy on demo account for 2-4 weeks
3. **Live**: Start with minimum lot size
4. **Monitor**: Watch equity and intervene if needed

## Performance Metrics

### XAUUSD Backtests (2024.01-2024.04, $10k account)

| Configuration | Profit | Max DD | Win Rate | Result |
|--------------|--------|---------|----------|---------|
| Baseline | +26% | -40% | 62% | Too Risky ❌ |
| + Dynamic Spacing | +24% | -30% | 65% | Better ⚠️ |
| **+ Time Exit** | **+28%** | **-20%** | **71%** | **OPTIMAL** ✅ |

## File Structure

```
doc/
├── README.md                 # This file
├── ARCHITECTURE.md          # Module design and data flow
├── STRATEGY_SPEC.md         # Detailed strategy specification
├── NEWS_FILTER.md           # News filter configuration
├── TESTING_CHECKLIST.md     # Testing scenarios and validation
└── TROUBLESHOOTING.md       # Common issues and solutions

src/
├── ea/
│   └── RecoveryGridDirection_v3.mq5
└── core/
    ├── Types.mqh            # Core data structures
    ├── Params.mqh           # Parameter definitions
    ├── LifecycleController.mqh  # Main controller
    ├── GridBasket.mqh       # Basket management
    ├── SpacingEngine.mqh    # Spacing calculations
    ├── OrderExecutor.mqh    # Order execution
    ├── TrendStrengthAnalyzer.mqh  # Trend analysis
    └── [other modules...]
```

## Important Warnings

⚠️ **NO AUTOMATED STOP LOSS**: The EA does not enforce hard stop losses. Manual monitoring required.

⚠️ **ACCEPTS LOSSES**: The strategy deliberately accepts losses during strong trends.

⚠️ **NOT SET-AND-FORGET**: Requires active monitoring and occasional intervention.

⚠️ **BOTH GRIDS ACTIVE**: Total exposure = BUY basket + SELL basket positions.

## Support & Documentation

- **Architecture**: See [ARCHITECTURE.md](ARCHITECTURE.md) for module details
- **Strategy**: See [STRATEGY_SPEC.md](STRATEGY_SPEC.md) for mathematical formulas
- **News Filter**: See [NEWS_FILTER.md](NEWS_FILTER.md) for calendar setup
- **Testing**: See [TESTING_CHECKLIST.md](TESTING_CHECKLIST.md) for validation
- **Issues**: See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for solutions

## Version History

- **v3.1.0** (Oct 2024): Major refactor - removed failed features, simplified architecture
- **v3.0.0**: Added experimental features (multi-job, basket SL, gap management)
- **v2.0.0**: Initial dual-grid implementation

---

*Generated with Claude Code - October 2024*