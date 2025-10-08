# Preset File Format Guide

## Overview

All preset files now use a **simplified format** that shows **ONLY the parameters that differ from defaults**.

This makes it easy to:
1. ✅ **See what's changed** at a glance
2. ✅ **Understand the scenario** - why each parameter was modified
3. ✅ **Compare presets** - spot differences quickly
4. ✅ **Maintain consistency** - all unspecified parameters use defaults

---

## File Structure

Each preset file follows this format:

```
;+------------------------------------------------------------------+
;| Scenario Header - What is being tested                           |
;+------------------------------------------------------------------+

;=== CHANGED FROM DEFAULTS ===

;--- Category Name
ParameterName=NewValue
; Default: OriginalValue
; Changed to: NewValue (reason for change)

;=== ALL OTHER PARAMETERS USE DEFAULTS ===
```

---

## Default Values Reference

All defaults are defined in:
- **File**: `/src/ea/RecoveryGridDirection_v3.mq5`
- **Lines**: 19-141

### Key Defaults:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `InpMagic` | 990045 | Magic number (change per preset) |
| `InpAtrTimeframe` | PERIOD_M15 (16) | ATR timeframe |
| `InpSpacingStepPips` | 25.0 | Base spacing |
| `InpGridLevels` | 5 | Grid levels per side |
| `InpLotScale` | 2.0 | Martingale multiplier |
| `InpTargetCycleUSD` | 6.0 | Profit target per cycle |
| `InpWarmLevels` | 5 | Initial pending levels |
| `InpMaxPendings` | 15 | Max pending orders |
| **Phase 0-2 Features** | **false** | All new features OFF |
| `InpLazyGridEnabled` | false | Lazy grid fill |
| `InpTrapDetectionEnabled` | false | Trap detection |
| `InpQuickExitEnabled` | false | Quick exit mode |
| `InpAutoFillBridge` | false | Gap management |

---

## Preset Comparison Matrix

| Parameter | Scenario 1<br>Range | Scenario 2<br>Uptrend | Scenario 3<br>Whipsaw | Scenario 4<br>Gap |
|-----------|---------------------|------------------------|------------------------|-------------------|
| **Symbol** | EURUSD | EURUSD | GBPUSD | XAUUSD |
| **Magic** | 990045 | 990046 | 990047 | 990048 |
| **Spacing** | 25p | 25p | **50p** | **150p** |
| **Grid Levels** | **10** | 5 | **7** | 5 |
| **Lot Scale** | **1.5** | 2.0 | 2.0 | 2.0 |
| **Target** | **$5** | **$5** | $6 | **$10** |
| **Warm Levels** | 5 | **3** | **4** | **3** |
| **Max Pendings** | 15 | **10** | **12** | **8** |
| **Spawn Enabled** | ✅ | ❌ | ❌ | ❌ |

**Bold** = Changed from default

---

## How to Use Presets

### Method 1: Load in MT5 Strategy Tester
1. Open Strategy Tester (`Ctrl+R`)
2. Select EA: `RecoveryGridDirection_v3`
3. Click **"Load"** button (folder icon)
4. Navigate to: `Experts/RECOVERY-GRID-DIRECTION_v3/presets/`
5. Select preset file (e.g., `02-Uptrend-300p-SELLTrap.set`)
6. Click **"Open"**
7. All parameters will be loaded automatically

### Method 2: Manual Copy
1. Open preset file in text editor
2. Copy parameter values
3. Paste into EA inputs manually
4. **Note**: Only listed parameters need to be changed; others stay default

---

## Understanding Parameter Changes

### Scenario 1: Range Normal
**Why these changes?**
- **10 Grid Levels**: More levels = more opportunities in ranging market
- **1.5 Lot Scale**: Less aggressive martingale (safer for baseline)
- **$5 Target**: Smaller target = faster cycle completion
- **Spawn ON**: Test baseline multi-basket behavior

### Scenario 2: Uptrend SELL Trap
**Why these changes?**
- **3 Warm Levels**: Fewer initial pendings against trend
- **10 Max Pendings**: Limit exposure (prevent deep trap)
- **Spawn OFF**: Focus on single trapped basket
- **Magic 990046**: Unique identifier for this test

### Scenario 3: Whipsaw Both Trapped
**Why these changes?**
- **50p Spacing**: GBPUSD is more volatile
- **7 Grid Levels**: Medium grid (not too many)
- **$6 Target**: Keep default (volatile pair needs buffer)
- **Spawn OFF**: Observe dual-trap scenario clearly

### Scenario 4: Gap Sideways
**Why these changes?**
- **150p Spacing**: Gold has much wider swings
- **$10 Target**: Higher target for larger moves
- **8 Max Pendings**: Very conservative (gold is expensive)
- **Spawn OFF**: Focus on gap scenario

---

## Modifying Presets

### To Create a New Preset:

1. **Copy a similar scenario** (e.g., copy `02-Uptrend-300p-SELLTrap.set`)
2. **Change header** - describe your scenario
3. **Change magic number** - use unique number (990049+)
4. **Modify only needed parameters** - remove lines for defaults
5. **Add comments** - explain why each parameter changed
6. **Test** - run in Strategy Tester

### Example: Create "Scenario 5: Downtrend BUY Trap"

```
;+------------------------------------------------------------------+
;| Scenario 5: Strong Downtrend 300+ pips - BUY Trap Test           |
;| Symbol: EURUSD                                                     |
;| Period: 2024-05-01 to 2024-07-01                                 |
;| Expected: BUY basket trapped, SELL basket profits                 |
;+------------------------------------------------------------------+

;=== CHANGED FROM DEFAULTS ===

;--- Identity
InpMagic=990049
; Changed to: 990049 (unique for Scenario 5)

;--- Spacing Engine
InpAtrTimeframe=4
; Changed to: PERIOD_M5 (4)

;--- Dynamic Grid (reduced for trending market)
InpWarmLevels=3
InpMaxPendings=10

;--- Spawn Triggers (disabled)
InpSpawnOnGridFull=false
InpSpawnOnTSL=false
InpSpawnOnJobDD=false

;=== ALL OTHER PARAMETERS USE DEFAULTS ===
```

---

## Validation Checklist

Before using a preset, verify:

- [ ] **Unique magic number** (no conflict with other tests)
- [ ] **Appropriate spacing** for symbol volatility
- [ ] **Reasonable grid levels** (3-10 recommended)
- [ ] **Target profit** matches symbol pip value
- [ ] **Date range** has historical data available
- [ ] **Comments** explain all changes clearly

---

## Troubleshooting

### "0 trades executed"
- ✅ Check date range has data
- ✅ Verify symbol matches preset
- ✅ Ensure spacing isn't too wide
- ✅ Check Journal for errors

### "Too many positions"
- ⚠️ Reduce `InpMaxPendings`
- ⚠️ Increase spacing
- ⚠️ Reduce `InpGridLevels`

### "Magic number conflict"
- ❌ Change `InpMagic` to unique value
- ❌ Don't run multiple presets with same magic simultaneously

---

## Phase Progression

### Phase 0 (Current - Baseline):
- All new features **OFF**
- Presets test **old behavior**
- Record baseline metrics (DD, P/L, win rate)

### Phase 3+ (Future - With New Features):
**Enable features by adding these lines to presets:**

```
;--- Phase 3+: Enable new features
InpLazyGridEnabled=true
InpTrapDetectionEnabled=true
InpQuickExitEnabled=true
InpAutoFillBridge=true

;--- Quick Exit Settings
InpQuickExitMode=0
; QE_FIXED (0) / QE_PERCENTAGE (1) / QE_DYNAMIC (2)

InpQuickExitLoss=-10.0
; Accept -$10 loss to exit trap quickly
```

**Then re-run same scenarios and compare results!**

---

## File Locations

```
/presets/
├── README-PRESET-FORMAT.md          ← This file (format guide)
├── README.md                         ← Scenario descriptions
├── TESTING_GUIDE.md                  ← How to run backtests
├── 01-Range-Normal.set               ← Scenario 1
├── 02-Uptrend-300p-SELLTrap.set     ← Scenario 2 (KEY TEST)
├── 03-Whipsaw-BothTrapped.set       ← Scenario 3
└── 04-Gap-Sideways-Bridge.set       ← Scenario 4
```

---

## Quick Reference: MT5 Enum Values

When you see numbers in preset files, they map to enums:

| Parameter | Value | Meaning |
|-----------|-------|---------|
| `InpAtrTimeframe` | 4 | PERIOD_M5 |
| `InpAtrTimeframe` | 16 | PERIOD_M15 |
| `InpAtrTimeframe` | 16385 | PERIOD_H4 |
| `InpSpacingMode` | 2 | Hybrid (ATR + floor) |
| `InpReseedMode` | 1 | RESEED_COOLDOWN |
| `InpQuickExitMode` | 0 | QE_FIXED |

---

**Last Updated**: 2025-01-08  
**Version**: v3.1.0 Phase 2  
**Status**: Ready for baseline testing

