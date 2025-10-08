# Phase 2 Testing Guide - Baseline Backtests

## Overview

This guide helps you run **baseline backtests** with v3.1.0 Phase 0 (all new features OFF) to establish performance benchmarks before implementing Lazy Grid Fill, Trap Detection, Quick Exit, and Gap Management.

## Pre-Test Checklist

### ✅ Compilation
1. Open `src/ea/RecoveryGridDirection_v3.mq5` in MetaEditor
2. Compile (F7)
3. Verify: **0 errors, 0 warnings**

### ✅ Preset Files
Ensure these files exist in `presets/` folder:
- `01-Range-Normal.set`
- `02-Uptrend-300p-SELLTrap.set`
- `03-Whipsaw-BothTrapped.set`
- `04-Gap-Sideways-Bridge.set`

### ✅ MT5 Strategy Tester Setup
1. Open MT5 Terminal
2. View → Strategy Tester (Ctrl+R)
3. Select Expert Advisor: **RecoveryGridDirection_v3**
4. Testing Mode: **Every tick (most accurate)**
5. Visual Mode: OFF (faster) or ON (watch behavior)

---

## Test Execution Steps

### Test 1: Range Market (Baseline)

**Purpose**: Verify normal operation in calm market conditions

1. **Load Preset**:
   - Settings → Load → Select `01-Range-Normal.set`
   
2. **Configure Tester**:
   ```
   Symbol: EURUSD
   Period: M1 (1-minute chart)
   Date Range: 2024-01-15 to 2024-01-22
   Initial Deposit: $10,000
   ```

3. **Run Test**:
   - Click "Start"
   - Wait for completion (5-10 minutes)

4. **Record Results** (see template below)

5. **Expected Outcome**:
   - ✅ Both BUY and SELL baskets open
   - ✅ Grids fill gradually
   - ✅ Both close at TP with profit
   - ✅ Max DD: 5-10%
   - ✅ No traps, no halts

---

### Test 2: Strong Uptrend (SELL Trap)

**Purpose**: Demonstrate SELL basket trap in strong rally

1. **Load Preset**:
   - Settings → Load → Select `02-Uptrend-300p-SELLTrap.set`
   
2. **Configure Tester**:
   ```
   Symbol: EURUSD
   Period: M1
   Date Range: 2024-03-10 to 2024-03-17
   Initial Deposit: $10,000
   ```

3. **Run Test**:
   - Watch SELL basket fill all levels
   - Price keeps moving up
   - SELL basket stuck in deep DD

4. **Record Results**

5. **Expected Outcome**:
   - ✅ BUY basket closes with profit
   - ❌ SELL basket trapped (DD 30-50%)
   - ❌ Recovery: Very slow or never
   - ⚠️ **THIS IS THE PROBLEM WE'RE SOLVING**

---

### Test 3: Whipsaw (Both Trapped)

**Purpose**: Show both baskets trapped simultaneously

1. **Load Preset**:
   - Settings → Load → Select `03-Whipsaw-BothTrapped.set`
   
2. **Configure Tester**:
   ```
   Symbol: GBPUSD
   Period: M1
   Date Range: 2024-02-01 to 2024-02-08
   Initial Deposit: $10,000
   ```

3. **Run Test**:
   - Observe rapid reversals
   - Both baskets struggle

4. **Record Results**

5. **Expected Outcome**:
   - ❌ BUY trapped during downswing
   - ❌ SELL trapped during upswing
   - ❌ Max DD: 40-60%
   - ⚠️ **Worst-case scenario**

---

### Test 4: Gap + Sideways (Bridge Need)

**Purpose**: Demonstrate gap trap scenario

1. **Load Preset**:
   - Settings → Load → Select `04-Gap-Sideways-Bridge.set`
   
2. **Configure Tester**:
   ```
   Symbol: XAUUSD
   Period: M1
   Date Range: 2024-04-01 to 2024-04-05
   Initial Deposit: $10,000
   ```

3. **Run Test**:
   - Look for large gap (200-400 pips)
   - Price consolidates away from entry

4. **Record Results**

5. **Expected Outcome**:
   - ❌ Gap creates large distance
   - ❌ Average price far from market
   - ❌ TP becomes unreachable
   - ⚠️ **Need bridge fill logic**

---

## Results Recording Template

### Copy this for each test:

```
========================================
TEST REPORT
========================================
Scenario: [Range/Uptrend/Whipsaw/Gap]
Preset File: ___________________
EA Version: v3.1.0 Phase 0
Test Date: ___________________

CONFIGURATION:
Symbol: ________
Period: M1
Date Range: ________ to ________
Initial Balance: $10,000

BACKTEST RESULTS:
Final Balance: $________
Net Profit/Loss: $________
Max DD: ________% ($________)
Max DD Date: ________

Total Trades: ________
Win Rate: _______%
Profit Factor: ________

Largest Win: $________
Largest Loss: $________

BASKET ANALYSIS:
BUY Basket Cycles: ________
SELL Basket Cycles: ________

BUY Avg Profit/Cycle: $________
SELL Avg Profit/Cycle: $________

TRAP OBSERVATIONS:
Trap Occurred: [YES/NO]
Which Basket: [BUY/SELL/BOTH]
Max Grid Depth: ________ levels
Time Trapped: ________ hours
Recovery: [FULL/PARTIAL/NONE]

SCREENSHOTS:
[ ] Balance curve saved
[ ] DD curve saved
[ ] Trade list exported

NOTES:
_________________________________
_________________________________
_________________________________

========================================
```

---

## KPI Comparison Table

After running all 4 tests, fill this table:

| Scenario | Net P/L | Max DD | Win Rate | Trap? | Recovery Time |
|----------|---------|--------|----------|-------|---------------|
| 1. Range | $_____ | ___% | ___% | ❌ | N/A |
| 2. Uptrend | $_____ | ___% | ___% | ✅ | ___h |
| 3. Whipsaw | $_____ | ___% | ___% | ✅ | ___h |
| 4. Gap | $_____ | ___% | ___% | ✅ | ___h |

**Average Max DD**: ______%  
**Trap Success Rate**: ______% (traps that recovered)  
**Avg Trap Loss**: $______

---

## Phase 0 Exit Criteria

Before proceeding to Phase 3 implementation, verify:

### ✅ Must Pass:
- [ ] All 4 tests complete without crash
- [ ] No new orders from lazy grid/trap/QE modules (features OFF)
- [ ] Balance curve matches legacy v3.0 behavior
- [ ] Logs show: "Lazy Grid: DISABLED ✓"
- [ ] Logs show: "Trap Detection: DISABLED ✓"

### ⚠️ Expected Failures (to be fixed later):
- [ ] Test 2: SELL basket trapped (DD 30-50%)
- [ ] Test 3: Both baskets trapped (DD 40-60%)
- [ ] Test 4: Gap trap (slow recovery)

---

## Troubleshooting

### Issue: Tester shows "No data"
**Solution**: Download historical data for symbol/period in MT5

### Issue: Preset file not loading
**Solution**: 
1. Check file path: `<MT5_DATA>/MQL5/Presets/`
2. File format must be plain text
3. Copy presets to correct directory

### Issue: Compilation errors
**Solution**: See `FIX-COMPILER-CACHE.md`

### Issue: Unexpected behavior
**Solution**: 
1. Check logs: `<MT5_DATA>/MQL5/Logs/`
2. Verify inputs match preset file
3. Ensure all new feature flags = false

---

## After Phase 3-4 Implementation

**Re-run all 4 tests** with new features enabled:

```
InpLazyGridEnabled = true
InpTrapDetectionEnabled = true
InpQuickExitEnabled = true
InpAutoFillBridge = true
```

**Expected Improvements**:
- Max DD: ↓ 50-70% reduction
- Trap recovery: <1 hour (vs days/never)
- Loss per trap: -$10 to -$30 (vs -$100+)

---

## Next Steps

1. ✅ Complete all 4 baseline tests
2. ✅ Document results in CSV/Excel
3. ⏳ Proceed to Phase 3 - Lazy Grid Fill
4. ⏳ Re-test with new features enabled
5. ⏳ Compare Phase 0 vs Phase 3+ KPIs

---

**Status**: Phase 2 Complete - Ready for Phase 0 Baseline Testing  
**Purpose**: Establish performance benchmarks before implementing new features

