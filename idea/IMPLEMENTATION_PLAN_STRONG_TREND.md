# Implementation Plan: Strong Trend Protection System

**Date**: 2025-10-06
**Goal**: Prevent blow-up during strong directional trends (XAUUSD 2024 problem)
**Approach**: Hybrid (ChatGPT 4-layer + Claude best practices)

---

## Selected Features (Priority Order)

### 🔥 Phase 1: Core Protection (Week 1) - CRITICAL

#### Feature 1.1: Trend Filter (Prevention Layer)
**What**: Block counter-trend positions when strong trend detected
**Why**: Prevents 80% of blow-ups by not fighting strong trends
**How**: EMA200 + ADX indicator

**Inputs**:
```cpp
InpTrendFilterEnabled = true        // Enable trend filter
InpTrendEMA_Period = 200           // EMA period (H4 timeframe)
InpTrendADX_Period = 14            // ADX period
InpTrendADX_Threshold = 25.0       // ADX > 25 = strong trend
InpTrendBufferPips = 200           // Distance from EMA to confirm trend
```

**Logic**:
```cpp
// Before placing orders in GridBasket:
bool IsStrongUptrend() {
   double ema200 = iMA(PERIOD_H4, 200);
   double adx = iADX(14);
   double ask = SymbolInfoDouble(SYMBOL_ASK);

   return (adx > InpTrendADX_Threshold &&
           ask > ema200 + InpTrendBufferPips * _Point);
}

bool IsStrongDowntrend() {
   double ema200 = iMA(PERIOD_H4, 200);
   double adx = iADX(14);
   double bid = SymbolInfoDouble(SYMBOL_BID);

   return (adx > InpTrendADX_Threshold &&
           bid < ema200 - InpTrendBufferPips * _Point);
}

// In LifecycleController.Update():
if (IsStrongUptrend()) {
   m_sell.SetTradingEnabled(false);  // Block SELL basket
   m_buy.SetTradingEnabled(true);    // Allow BUY basket
}
else if (IsStrongDowntrend()) {
   m_buy.SetTradingEnabled(false);   // Block BUY basket
   m_sell.SetTradingEnabled(true);   // Allow SELL basket
}
else {
   m_buy.SetTradingEnabled(true);    // Allow both
   m_sell.SetTradingEnabled(true);
}
```

**Files to create**:
- `src/core/TrendFilter.mqh` (new)

**Files to modify**:
- `src/core/GridBasket.mqh` - Add m_trading_enabled flag
- `src/core/LifecycleController.mqh` - Add trend check in Update()
- `src/core/Params.mqh` - Add trend filter params

**Success Criteria**:
- ✅ SELL basket stops adding when price > EMA200 + 200 pips
- ✅ BUY basket stops adding when price < EMA200 - 200 pips
- ✅ Log shows "[TrendFilter] SELL disabled - strong uptrend detected"

---

#### Feature 1.2: Emergency DD Stop (Kill-Switch Layer)
**What**: Hard stop when account DD reaches critical threshold
**Why**: Last line of defense to prevent account blow-up
**How**: Monitor equity vs balance, close all if DD >= threshold

**Inputs**:
```cpp
InpEmergencyDDEnabled = true       // Enable emergency stop
InpEmergencyDDLimit = 15.0         // Stop if DD >= 15%
InpEmergencyCooldown = 60          // Cooldown after stop (minutes)
```

**Logic**:
```cpp
// In LifecycleController.Update() - FIRST check:
void CheckEmergencyStop() {
   if (!InpEmergencyDDEnabled) return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dd_pct = ((balance - equity) / balance) * 100.0;

   if (dd_pct >= InpEmergencyDDLimit) {
      m_log.Event(Tag(), StringFormat("EMERGENCY STOP: DD %.1f%% >= %.1f%%",
                                      dd_pct, InpEmergencyDDLimit));

      // Close ALL positions
      FlattenAll("Emergency DD stop");

      // Enter cooldown
      m_emergency_stop_time = TimeCurrent();
      m_in_emergency_stop = true;
   }
}
```

**Files to modify**:
- `src/core/LifecycleController.mqh` - Add CheckEmergencyStop()
- `src/core/Params.mqh` - Add emergency stop params

**Success Criteria**:
- ✅ EA closes all positions when DD reaches 15%
- ✅ EA enters cooldown for 60 minutes
- ✅ Log shows "EMERGENCY STOP: DD 15.2% >= 15.0%"

---

### 🟡 Phase 2: Stop-Adding Logic (Week 2) - HIGH PRIORITY

#### Feature 2.1: Stop-Adding by DD
**What**: Stop refilling grid when basket loss exceeds threshold
**Why**: Limits exposure growth during adverse price movement
**How**: Check basket unrealized PnL before RefillBatch()

**Inputs**:
```cpp
InpStopAddEnabled = true           // Enable stop-adding logic
InpStopAddDD_USD = 500.0          // Stop refill if basket loss >= $500
InpStopAddDistance_ATR = 6.0      // Stop if distance >= 6×ATR
```

**Logic**:
```cpp
// In GridBasket.RefillBatch() - BEFORE placing orders:
void RefillBatch() {
   // Check stop-adding conditions
   if (InpStopAddEnabled) {
      // Condition 1: DD threshold
      double basket_loss = m_pnl_usd;
      if (basket_loss <= -InpStopAddDD_USD) {
         if (m_log) m_log.Event(Tag(), StringFormat(
            "Stop-adding: Loss %.2f >= %.2f",
            -basket_loss, InpStopAddDD_USD));
         return;
      }

      // Condition 2: Distance threshold
      double distance_atr = GetDistanceFromAvgInATR();
      if (distance_atr >= InpStopAddDistance_ATR) {
         if (m_log) m_log.Event(Tag(), StringFormat(
            "Stop-adding: Distance %.1f ATR >= %.1f",
            distance_atr, InpStopAddDistance_ATR));
         return;
      }
   }

   // Proceed with normal refill...
}

double GetDistanceFromAvgInATR() {
   double current_price = (m_direction == DIR_BUY) ?
                          SymbolInfoDouble(SYMBOL_BID) :
                          SymbolInfoDouble(SYMBOL_ASK);
   double distance_px = MathAbs(current_price - m_avg_price);
   double atr = m_spacing.GetATR();
   return (atr > 0) ? (distance_px / atr) : 0.0;
}
```

**Files to modify**:
- `src/core/GridBasket.mqh` - Add stop-adding checks
- `src/core/Params.mqh` - Add stop-adding params

**Success Criteria**:
- ✅ Grid stops refilling when basket loss >= $500
- ✅ Grid stops refilling when distance >= 6×ATR
- ✅ Log shows "Stop-adding: Loss 520.00 >= 500.00"

---

#### Feature 2.2: Exposure Cap
**What**: Hard limit on total lot size per basket
**Why**: Prevents over-leveraging and margin call
**How**: Check TotalLots() before placing any order

**Inputs**:
```cpp
InpExposureCapEnabled = true       // Enable exposure cap
InpMaxExposureLots = 1.0          // Max total lots per basket
```

**Logic**:
```cpp
// In GridBasket - Before ALL order placement:
bool CanPlaceOrder(double lot_size) {
   if (!InpExposureCapEnabled) return true;

   double total_after = m_total_lot + lot_size;
   if (total_after > InpMaxExposureLots) {
      if (m_log) m_log.Event(Tag(), StringFormat(
         "Exposure cap: Total %.2f + %.2f > %.2f",
         m_total_lot, lot_size, InpMaxExposureLots));
      return false;
   }
   return true;
}

// Before Market():
if (!CanPlaceOrder(seed_lot)) return;

// Before Limit():
if (!CanPlaceOrder(lot)) return;
```

**Files to modify**:
- `src/core/GridBasket.mqh` - Add CanPlaceOrder() check
- `src/core/Params.mqh` - Add exposure cap params

**Success Criteria**:
- ✅ No more orders placed when total lots >= 1.0
- ✅ Log shows "Exposure cap: Total 0.95 + 0.16 > 1.0"

---

### 🟢 Phase 3: Recovery Mechanism (Week 3) - MEDIUM PRIORITY

#### Feature 3.1: Simple Hedge (Recovery Layer)
**What**: Open trend-following hedge when basket in trouble
**Why**: Generates profit to reduce losing basket's target
**How**: Detect breach → open hedge with TS → profit reduces target

**Inputs**:
```cpp
InpHedgeEnabled = true             // Enable simple hedge
InpHedgeTriggerATR = 5.0          // Trigger when distance >= 5×ATR
InpHedgeLotRatio = 0.5            // Hedge size = 50% of basket lot
InpHedgeSL_ATR = 1.5              // SL = 1.5×ATR
InpHedgeTS_ATR = 2.0              // Trailing stop = 2×ATR
```

**Logic**:
```cpp
// In LifecycleController.Update() - After basket updates:
void CheckHedgeOpportunity() {
   if (!InpHedgeEnabled) return;

   // Check BUY basket (if losing)
   if (m_buy && m_buy.BasketPnL() < 0) {
      double distance = m_buy.GetDistanceFromAvgInATR();
      if (distance >= InpHedgeTriggerATR && !m_buy_hedge_active) {
         OpenHedge(DIR_SELL, m_buy.TotalLot() * InpHedgeLotRatio);
      }
   }

   // Check SELL basket (if losing)
   if (m_sell && m_sell.BasketPnL() < 0) {
      double distance = m_sell.GetDistanceFromAvgInATR();
      if (distance >= InpHedgeTriggerATR && !m_sell_hedge_active) {
         OpenHedge(DIR_BUY, m_sell.TotalLot() * InpHedgeLotRatio);
      }
   }
}

void OpenHedge(EDirection dir, double lot_size) {
   double atr = m_spacing.GetATR();
   double sl_px = atr * InpHedgeSL_ATR;
   double ts_px = atr * InpHedgeTS_ATR;

   // Open hedge order with TS
   // Track hedge ticket
   // Monitor hedge profit → reduce basket target
}
```

**Files to create**:
- `src/core/HedgeManager.mqh` (new) - Simple hedge logic

**Files to modify**:
- `src/core/LifecycleController.mqh` - Add hedge checks
- `src/core/Params.mqh` - Add hedge params

**Success Criteria**:
- ✅ Hedge opens when losing basket distance >= 5×ATR
- ✅ Hedge has trailing stop
- ✅ Hedge profit reduces basket target
- ✅ Log shows "Hedge opened: SELL 0.50 lot (BUY basket distance: 5.2 ATR)"

---

## Testing Strategy

### Test 1: Trend Filter Only
**Setup**: Enable only trend filter, disable others
**Data**: XAUUSD 2024-01-01 to 2024-12-31 (full year)
**Expected**:
- No SELL positions during strong uptrends
- Max DD reduced by ~50%

### Test 2: Trend Filter + Emergency Stop
**Setup**: Enable both, InpEmergencyDDLimit = 15%
**Expected**:
- EA stops trading when DD = 15%
- Account preserved at -15% instead of -70%

### Test 3: Trend Filter + Stop-Adding
**Setup**: Enable trend filter + stop-adding logic
**Expected**:
- Grid stops growing when basket loss >= $500
- Prevents exponential loss growth

### Test 4: Full Stack (All Features)
**Setup**: Enable all 5 features
**Expected**:
- Max DD: -10% to -15% (vs baseline -70%)
- Survives 2024 XAU bull run
- Final balance positive or small loss

---

## Implementation Schedule

### Week 1: Core Protection
- **Day 1-2**: Implement TrendFilter.mqh
- **Day 3-4**: Integrate trend filter into LifecycleController
- **Day 5**: Implement Emergency DD Stop
- **Day 6-7**: Test Phase 1, document results

### Week 2: Stop-Adding Logic
- **Day 1-2**: Implement stop-adding by DD
- **Day 3**: Implement exposure cap
- **Day 4-5**: Test Phase 2, document results
- **Day 6-7**: Optimize thresholds

### Week 3: Recovery Mechanism
- **Day 1-3**: Port HedgeManager from old project
- **Day 4-5**: Integrate hedge logic
- **Day 6-7**: Test Phase 3, document results

---

## Success Metrics

| Metric | Baseline (Current) | Target (After Fix) |
|--------|-------------------|-------------------|
| Max DD | -70% | -15% to -20% |
| Blow-up Rate | 100% (strong trends) | <10% |
| Recovery Rate | 0% (after blow-up) | 70-80% |
| Final Balance | Varies wildly | Consistent small gains or losses |

---

## Risk Assessment

| Feature | Risk | Mitigation |
|---------|------|------------|
| Trend Filter | False positives (miss trades) | Use high ADX threshold (25+) |
| Emergency Stop | Stop too early | Set threshold at 15-20% (generous) |
| Stop-Adding | Grid can't recover | Hedge provides recovery path |
| Exposure Cap | Limits profit potential | Set cap at reasonable level (1.0 lot) |
| Hedge | Complex logic | Port proven code from old project |

---

## Next Steps

1. **Create branch**: `feature/strong-trend-protection`
2. **Start Phase 1**: Implement TrendFilter.mqh
3. **Test incrementally**: Don't merge all at once
4. **Document results**: Update this file with backtest data
5. **Get user approval**: Before moving to next phase

---

**Status**: 📋 Planning Complete - Ready to Implement
**Branch**: feature/strong-trend-protection (to be created)
**ETA**: 3 weeks (conservative estimate)

