# Strong Trend Protection Solutions

**Date**: 2025-10-06
**Problem**: EA blow-up during strong directional trends (XAU bull market)
**Status**: Research & Design Phase

---

## Problem Analysis

### Observed Failures (2024-2025 XAU Backtest)

**3 Major Drawdowns:**
1. **Early 2025-01**: -$2,400 → recovered
2. **Mid 2025-04**: -$1,800 → recovered
3. **Late 2025-09**: -$7,100 → backtest ended before recovery

**Root Cause:**
- Price trends strongly upward (XAU bull market)
- BUY basket profitable, SELL basket accumulates losses
- Grid fills with SELL positions far from current price
- Massive unrealized loss, waiting for reversal
- If reversal doesn't come → blow-up

---

## Proposed Solutions

### 🎯 Selected for Implementation (Priority Order)

#### 1. **Trend Filter** (Prevention)
**Goal**: Prevent new positions against strong trend
**Priority**: HIGH
**Implementation Complexity**: Medium

**Design:**
- Detect trend direction using EMA 200 (H4 timeframe)
- If Price > EMA200 + buffer → Strong uptrend
  - Allow BUY basket to trade normally
  - Block SELL basket from adding new positions
  - Close SELL pending orders
- If Price < EMA200 - buffer → Strong downtrend
  - Allow SELL basket to trade normally
  - Block BUY basket from adding new positions
  - Close BUY pending orders

**Parameters:**
```cpp
InpTrendFilterEnabled = true        // Enable trend filter
InpTrendEMA_Period = 200           // EMA period for trend detection
InpTrendEMA_Timeframe = PERIOD_H4  // EMA timeframe
InpTrendBufferPips = 200           // Distance from EMA to confirm strong trend
```

**Pros:**
- Prevent accumulating positions against strong trend
- Reduce exposure to blow-up scenarios
- Still allows profitable side to trade

**Cons:**
- Miss counter-trend recovery opportunities
- Need good trend detection (EMA might lag)
- Might stop too early in ranging market

**Code Location:**
- New file: `src/core/TrendFilter.mqh`
- Integration: `GridBasket.mqh` - check before placing orders
- Integration: `LifecycleController.mqh` - cancel pendings when trend detected

---

#### 2. **Emergency DD Stop** (Safety)
**Goal**: Hard stop when account DD reaches critical level
**Priority**: HIGH
**Implementation Complexity**: Low

**Design:**
- Monitor account unrealized P&L continuously
- Calculate DD% = (unrealized_pnl / account_balance) * 100
- When DD% <= -15% (configurable):
  - Log emergency stop event
  - Close ALL positions (BUY + SELL baskets)
  - Cancel ALL pending orders
  - Enter cooldown mode (e.g., 60 minutes)
  - Block new trading until cooldown expires or manual reset

**Parameters:**
```cpp
InpEmergencyDDLimit = 15.0      // Emergency stop DD threshold (%)
InpEmergencyCooldown = 60       // Cooldown after emergency stop (minutes)
InpEmergencyEnabled = true      // Enable emergency stop
```

**Pros:**
- Prevent account blow-up
- Clear risk limit
- Easy to implement and test

**Cons:**
- Lose all recovery opportunities
- Might trigger during normal volatility
- Need good DD threshold (too tight = frequent stops)

**Code Location:**
- Add to: `LifecycleController.mqh` - `Update()` method
- New method: `CheckEmergencyStop()`
- New state: `m_in_emergency_stop`, `m_emergency_stop_time`

---

#### 3. **Partial Close Strategy** (Recovery + Safety)
**Goal**: Gradually reduce exposure as DD increases
**Priority**: MEDIUM
**Implementation Complexity**: Medium-High

**Design:**
- Define DD thresholds with corresponding close ratios
- Example:
  - DD >= 10% → Close 20% of worst positions (furthest from current price)
  - DD >= 15% → Close additional 30% (total 50% closed)
  - DD >= 20% → Close all remaining positions

**Sorting Logic:**
- Sort losing positions by distance from current price (furthest = worst)
- Close top X% of sorted list
- Track which positions already closed to avoid double-closing

**Parameters:**
```cpp
InpPartialCloseEnabled = true
InpPartialClose_DD1 = 10.0     // First threshold (%)
InpPartialClose_Ratio1 = 20.0  // Close 20% at first threshold
InpPartialClose_DD2 = 15.0     // Second threshold (%)
InpPartialClose_Ratio2 = 30.0  // Close additional 30%
InpPartialClose_DD3 = 20.0     // Third threshold (%)
InpPartialClose_Ratio3 = 100.0 // Close all remaining
```

**Pros:**
- Gradual loss reduction
- Keep some positions for recovery opportunity
- More sophisticated risk management

**Cons:**
- Complex implementation (tracking closed %, sorting positions)
- Might close best recovery candidates
- Multiple thresholds to tune

**Code Location:**
- Add to: `GridBasket.mqh` - new method `PartialClose(double close_ratio)`
- Add to: `LifecycleController.mqh` - `CheckPartialClose()`
- Need position sorting by distance from current price

---

#### 4. **Time-Based Exit** (Prevention)
**Goal**: Close positions underwater for too long
**Priority**: LOW
**Implementation Complexity**: Medium

**Design:**
- Track each position's age and P&L history
- If position unrealized P&L < 0 for > X days:
  - Log stale position warning
  - Close position
  - Rationale: If no recovery after X days → trend too strong, cut loss

**Parameters:**
```cpp
InpTimeBasedExitEnabled = true
InpMaxUnderwaterDays = 7       // Close if losing for > 7 days
InpCheckIntervalHours = 24     // Check every 24 hours
```

**Pros:**
- Prevent eternal floating positions
- Automatic cleanup of stuck trades
- Works well with trend-following markets

**Cons:**
- Arbitrary time threshold
- Might exit right before reversal
- Need persistent position tracking (survive EA restart)

**Code Location:**
- Add to: `GridBasket.mqh` - track position open time
- Add to: `LifecycleController.mqh` - `CheckStalePositions()`
- Need position age calculation

---

## Other Solutions (Not Selected)

### ❌ Option 2: Adaptive Grid Spacing
**Why not selected:**
- High complexity (need good trend strength detector)
- Doesn't prevent blow-up, just delays it
- Wider spacing = miss recovery opportunities
- Current ATR-based spacing already adaptive

### ❌ Option 4: Hedge Lock
**Why not selected:**
- Very complex implementation
- Requires additional margin
- Can get stuck in locked state for long time
- Not suitable for grid recovery strategy
- Better to close and re-enter at better price

---

## Implementation Plan (Phase 3)

### Phase 3.1: Trend Filter (Week 1)
1. Create `TrendFilter.mqh` class
2. Integrate with `GridBasket` - check before orders
3. Integrate with `LifecycleController` - cancel pendings
4. Add input parameters
5. Backtest on 2024 XAU with trend filter enabled
6. Compare results vs baseline

### Phase 3.2: Emergency DD Stop (Week 1)
1. Add emergency stop logic to `LifecycleController`
2. Add DD monitoring and calculation
3. Add cooldown state management
4. Add input parameters
5. Test with small DD threshold (5%) to verify triggering
6. Backtest with realistic threshold (15%)

### Phase 3.3: Partial Close Strategy (Week 2)
1. Add position sorting by distance in `GridBasket`
2. Implement `PartialClose()` method
3. Add DD threshold tracking
4. Integrate with `LifecycleController`
5. Backtest with multi-threshold configuration
6. Optimize thresholds and ratios

### Phase 3.4: Time-Based Exit (Week 2 - Optional)
1. Add position age tracking
2. Implement stale position detection
3. Add time-based close logic
4. Backtest and evaluate effectiveness

---

## Expected Results

### Baseline (Current)
- Final Balance: $10,000 → varies widely
- Max DD: -70% (blow-up scenarios)
- Recovery Rate: High (if given time)

### With Trend Filter + Emergency Stop
- Final Balance: More stable
- Max DD: Capped at -15% (emergency limit)
- Recovery Rate: Lower (early exits)
- Blow-up Prevention: HIGH

### With All 4 Solutions Combined
- Final Balance: Modest gains, stable
- Max DD: -10% to -15% (partial close triggers)
- Recovery Rate: Medium (keep some positions)
- Blow-up Prevention: VERY HIGH
- Trade-off: Lower profit ceiling, higher safety floor

---

## Risk & Trade-offs

### Prevention vs Recovery
- **Prevention (Trend Filter)**: Avoid bad trades, miss recovery
- **Recovery (Partial Close)**: Keep some positions, limited loss
- **Safety (Emergency Stop)**: Hard limit, zero recovery

**User Preference**: Prevention → Recovery → Safety

### Risk Tolerance
- **Backtest**: Unlimited (test aggressive settings)
- **Live/Demo**: Conservative (DD <= 10-15% max)
- **Psychological Factor**: Real money = tighter stops needed

---

## Testing Strategy

### Test 1: Trend Filter Only
**Settings:**
- InpTrendFilterEnabled = true
- InpEmergencyEnabled = false
- InpPartialCloseEnabled = false

**Goal**: Measure prevention effectiveness

### Test 2: Emergency Stop Only
**Settings:**
- InpTrendFilterEnabled = false
- InpEmergencyEnabled = true
- InpEmergencyDDLimit = 15.0

**Goal**: Measure safety net effectiveness

### Test 3: Trend Filter + Partial Close
**Settings:**
- InpTrendFilterEnabled = true
- InpPartialCloseEnabled = true
- InpEmergencyEnabled = false

**Goal**: Measure prevention + recovery balance

### Test 4: Full Stack (All 3)
**Settings:**
- InpTrendFilterEnabled = true
- InpPartialCloseEnabled = true
- InpEmergencyEnabled = true
- InpEmergencyDDLimit = 20.0 (fallback only)

**Goal**: Measure complete solution effectiveness

---

## Success Criteria

Phase 3 complete when:

1. ✅ Trend filter prevents counter-trend position accumulation
2. ✅ Emergency stop triggers at correct DD threshold
3. ✅ Partial close reduces exposure gradually
4. ✅ Backtest max DD <= -15% (vs baseline -70%)
5. ✅ EA survives 2024 XAU bull market without blow-up
6. ✅ Final balance positive or small loss (vs massive DD)
7. ✅ All solutions work together without conflicts

---

## Notes

- Multi-job system **abandoned** - proved worse than single lifecycle
- Focus on **stable version** with strong trend protection
- User priority: **Prevention > Recovery > Safety**
- Test threshold: Aggressive (unlimited DD)
- Live threshold: Conservative (10-15% DD max)

---

**Next Action**: Fix demo account bug (duplicate lot sizing issue) before implementing Phase 3.

