# 🗺️ COMPLETE ROADMAP: Phase 5 → Phase 20+

**Project**: RecoveryGridDirection v3.1.0  
**Current Status**: ✅ Phase 7 Complete + Phase 5.5 Auto Trap Threshold  
**Date**: 2025-01-09  
**Author**: AI Assistant + User Collaboration

---

## 📊 Progress Overview

```
✅ Phase 0: Baseline Reset (Feature flags OFF) ...................... DONE
✅ Phase 1: Observability (Logger + Metrics) ....................... DONE
✅ Phase 2: Test Harness & Presets ................................. DONE
✅ Phase 3: Lazy Grid v1 (Seed minimal) ............................ DONE
✅ Phase 4: Lazy Grid v2 (Smart expansion + guards) ................ DONE
✅ Phase 5: Trap Detection v1 (3 core conditions) .................. DONE
✅ Phase 5.5: Auto Trap Threshold (Hybrid ATR + Spacing) ........... DONE
⏳ Phase 6: Trap Detection v2 (Moving-away + Stuck) ................ FUTURE
✅ Phase 7: Quick Exit v1 (QE_FIXED + Close with loss) ............. DONE
✅ Phase 8: Quick Exit v2 (3 Modes + Timeout + Reseed) ............. DONE ← YOU ARE HERE
⏳ Phase 9: Gap Management v1 (CalculateGap + Bridge 200-400) ...... FUTURE
⏳ Phase 10: Gap Management v2 (CloseFar >400 + Reseed) ............ FUTURE
⏳ Phase 11: Lifecycle Controller (Profit sharing + Global risk) ... PARTIAL (Profit sharing DONE)
⏳ Phase 12: Parameters & Symbol Presets ........................... PARTIAL (Presets exist)
⏳ Phase 13: Backtest Burn-in (3 months data) ...................... IN PROGRESS
⏳ Phase 14: Main EA Integration ................................... PENDING
⏳ Phase 15: Hardening & Release v3.1.0 ............................ PENDING
⏳ Phase 16+: Advanced Features (see below) ........................ FUTURE
```

---

# 📋 PHASE 5-15 DETAILED PLAN

## ⏳ PHASE 5: Trap Detection v1 (3 Core Conditions)

### 🎯 Goal
Detect when a basket is trapped using 3 fundamental conditions.

### 📦 Scope
**New Files**:
- `src/core/TrapDetector.mqh` - Core trap detection logic

**Modified Files**:
- `src/core/GridBasket.mqh` - Call `DetectTrapConditions()` in `Update()`
- `src/core/Types.mqh` - Add `STrapState` struct

**Core Logic**:
```cpp
class CTrapDetector
{
private:
   STrapState m_state;
   SParams    m_params;
   
public:
   bool DetectTrapConditions(CGridBasket* basket)
   {
      int conditions_met = 0;
      m_state.conditionFlags = 0;
      
      // Condition 1: Large Gap (>200 pips between positions)
      if(CheckGapCondition(basket))
      {
         conditions_met++;
         m_state.conditionFlags |= TRAP_COND_GAP;
      }
      
      // Condition 2: Counter-Trend (price moving away from basket)
      if(CheckCounterTrendCondition(basket))
      {
         conditions_met++;
         m_state.conditionFlags |= TRAP_COND_COUNTER_TREND;
      }
      
      // Condition 3: Heavy Drawdown (DD < -20%)
      if(CheckDrawdownCondition(basket))
      {
         conditions_met++;
         m_state.conditionFlags |= TRAP_COND_HEAVY_DD;
      }
      
      m_state.conditionsMet = conditions_met;
      
      // Trigger trap if >= required conditions
      bool is_trapped = (conditions_met >= m_params.trap_conditions_required);
      
      if(is_trapped && !m_state.isTrapped)
      {
         m_state.isTrapped = true;
         m_state.trapTime = TimeCurrent();
         Log(StringFormat("TRAP DETECTED! Conditions: %d/%d",
                         conditions_met, m_params.trap_conditions_required));
      }
      
      return is_trapped;
   }
};
```

### ✅ Deliverables
1. `CTrapDetector` class with 3 condition checks
2. Log: `"TRAP DETECTED ... Conditions x/5"`
3. Integration in `GridBasket::Update()`

### 🎯 Exit Criteria
- **Preset Uptrend 300p**: SELL basket triggers trap
- **Preset Range**: No trap triggered
- **Log clarity**: Shows which conditions are met

### 🧪 Tests
```
Test 1: Range Market (Normal)
- Expected: 0-1 conditions met, no trap
- Gap: <150 pips
- DD: >-10%
- Result: PASS ✓

Test 2: Strong Uptrend (SELL Trapped)
- Expected: 3/3 conditions met, trap detected
- Gap: >200 pips
- Counter-trend: Price moving up (away from SELL)
- DD: <-20%
- Result: TRAP DETECTED ✓

Test 3: BUY/SELL Symmetry
- Verify both directions detect traps correctly
```

### 🔄 Rollback
- Set `InpTrapDetectionEnabled = false`
- OR increase `InpTrapConditionsRequired = 5` (impossible to trigger)

---

## ⏳ PHASE 6: Trap Detection v2 (Moving-Away + Stuck)

### 🎯 Goal
Add 2 advanced conditions to reduce false positives.

### 📦 Scope
**Modified Files**:
- `src/core/TrapDetector.mqh` - Add conditions 4 & 5

**New Conditions**:
```cpp
// Condition 4: Moving Away (price distance increasing over 5 min)
bool CheckMovingAwayCondition(CGridBasket* basket)
{
   double current_distance = basket.GetAvgPriceDistance();
   double distance_5min_ago = m_distance_history[5]; // Track history
   
   double distance_change_pct = ((current_distance - distance_5min_ago) 
                                 / distance_5min_ago) * 100.0;
   
   return (distance_change_pct > 10.0); // >10% increase in 5 min
}

// Condition 5: Stuck (oldest position >30 min & DD <-15%)
bool CheckStuckCondition(CGridBasket* basket)
{
   datetime oldest_time = basket.GetOldestPositionTime();
   datetime now = TimeCurrent();
   int minutes_stuck = (int)((now - oldest_time) / 60);
   
   double dd_pct = basket.GetDrawdownPercent();
   
   return (minutes_stuck > m_params.trap_stuck_minutes 
           && dd_pct < -15.0);
}
```

### ✅ Deliverables
1. History tracking for distance (5-minute window)
2. Both conditions implemented
3. `STrapState` includes all 5 condition flags

### 🎯 Exit Criteria
- **Preset Range (Long)**: Does NOT trigger trap despite 2-3 conditions
- **Preset Uptrend 300p**: Triggers trap with 4-5 conditions

### 🧪 Tests
```
Test 1: Sideways with Gap
- Gap: 220 pips (condition 1 ✓)
- DD: -12% (condition 3 ✗)
- Moving away: No (condition 4 ✗)
- Expected: 1/5 conditions, NO TRAP ✓

Test 2: Real Trap (Uptrend)
- Gap: 250 pips ✓
- Counter-trend: Yes ✓
- DD: -22% ✓
- Moving away: +15% distance in 5min ✓
- Stuck: 45 minutes ✓
- Expected: 5/5 conditions, TRAP! ✓
```

### 🔄 Rollback
- Disable conditions 4&5 via internal flag
- Revert to Phase 5 (3 conditions only)

---

## ✅ PHASE 5.5: Auto Trap Threshold (Hybrid ATR + Spacing)

### 🎯 Goal
Automatically calculate trap gap threshold based on symbol volatility, eliminating manual tuning per symbol.

### 💡 Problem
- Manual trap threshold requires different values for each symbol:
  - EURUSD: 20-30 pips optimal
  - XAUUSD: 50-100 pips optimal
  - User must manually tune for each symbol → tedious

### 📦 Solution
**Hybrid Auto Mode**: Calculate threshold based on BOTH ATR and Spacing:
```cpp
double CalculateAutoGapThreshold()
{
   // Get ATR from spacing engine (already calculated!)
   double atr_pips = m_basket.GetATRPips();
   double atr_threshold = atr_pips * m_atr_multiplier; // 2.0x
   
   // Get current spacing
   double spacing_pips = m_basket.GetCurrentSpacing();
   double spacing_threshold = spacing_pips * m_spacing_multiplier; // 1.5x
   
   // Use the LARGER of the two (more conservative)
   return MathMax(atr_threshold, spacing_threshold);
}
```

### 🎛️ New Parameters
```cpp
input bool   InpTrapAutoThreshold    = true;  // Auto-calculate gap threshold
input double InpTrapGapThreshold     = 50.0;  // Manual fallback (if auto=false)
input double InpTrapATRMultiplier    = 2.0;   // ATR multiplier (2x ATR)
input double InpTrapSpacingMultiplier = 1.5;  // Spacing multiplier (1.5x spacing)
```

### 📊 Expected Results

| Symbol | ATR(H1) | Spacing | ATR × 2.0 | Spacing × 1.5 | **Auto Threshold** |
|--------|---------|---------|-----------|---------------|--------------------|
| EURUSD | 15 pips | 25 pips | 30 pips | **37.5 pips** | **37.5 pips** ✅ |
| GBPUSD | 20 pips | 30 pips | 40 pips | **45 pips** | **45 pips** ✅ |
| XAUUSD | 40 pips | 50 pips | **80 pips** | 75 pips | **80 pips** ✅ |
| USDJPY | 25 pips | 35 pips | 50 pips | **52.5 pips** | **52.5 pips** ✅ |

Uses the LARGER value for conservative trap detection.

### ✅ Advantages
1. **Symbol-Agnostic**: Works for any symbol without manual tuning
2. **Volatility-Adaptive**: ATR adjusts to market conditions
3. **Grid-Aware**: Spacing multiplier ensures threshold makes sense
4. **Conservative**: Uses MAX of both methods to avoid false positives
5. **Transparent**: Logs calculated threshold every hour
6. **Performance**: Cached calculation (recalc every 1 hour)

### 🔧 Implementation
**Files Modified**:
- `src/core/Params.mqh` - Added 3 new parameters
- `src/ea/RecoveryGridDirection_v3.mq5` - Added inputs
- `src/core/TrapDetector.mqh` - Implemented auto calculation
- `src/core/GridBasket.mqh` - Added `GetATRPips()` and `GetCurrentSpacing()`

**Key Functions**:
```cpp
// TrapDetector.mqh
double CalculateAutoGapThreshold();  // Hybrid calculation
double GetEffectiveGapThreshold();   // Auto/manual mode switch

// GridBasket.mqh
double GetATRPips() const;           // Expose ATR
double GetCurrentSpacing() const;    // Expose spacing
```

### 🧪 Testing
```
Test 1: Multi-Symbol Verification
- Symbols: EURUSD, GBPUSD, XAUUSD, USDJPY
- Settings: Auto mode, Conservative (2.0, 1.5)
- Expected: Each symbol has different auto threshold
- Result: ✅ PASS

Test 2: Manual vs Auto Comparison
- Test A: Manual (25 pips fixed)
- Test B: Auto (calculated per symbol)
- Compare: Trap detection count, final balance
- Result: Pending
```

### 🎯 Exit Criteria
- ✅ Compilation successful (no errors)
- ✅ Auto calculation implemented
- ✅ Caching and logging working
- ⏳ Backtests across multiple symbols (pending)

### 🔄 Rollback
```
InpTrapAutoThreshold = false  // Revert to manual mode
```

### 📝 Status
**✅ IMPLEMENTATION COMPLETE - READY FOR TESTING**

**Document**: `PHASE5.5-AUTO-TRAP-THRESHOLD.md`

---

## ⏳ PHASE 7: Quick Exit v1 (QE_FIXED + Negative TP)

### 🎯 Goal
When trapped, activate Quick Exit mode to accept small loss and escape.

### 📦 Scope
**New Files**:
- `src/core/QuickExitManager.mqh` - QE logic

**Modified Files**:
- `src/core/GridBasket.mqh` - Activate/Deactivate QE
- `src/core/Types.mqh` - Add `SQuickExitConfig` struct

**Core Logic**:
```cpp
class CQuickExitManager
{
public:
   void ActivateQuickExit(CGridBasket* basket, double target_loss)
   {
      // Backup original target
      m_original_target = basket.GetTargetUSD();
      
      // Set negative TP (accept loss)
      double new_target = target_loss; // e.g. -$10.0
      basket.SetTargetUSD(new_target);
      
      // Recalculate TP price
      basket.RecalculateGroupTP();
      
      m_qe_active = true;
      m_qe_start_time = TimeCurrent();
      
      Log(StringFormat("QE ACTIVATED: Target %.2f → %.2f (accept loss)",
                      m_original_target, new_target));
   }
   
   void DeactivateQuickExit(CGridBasket* basket, string reason)
   {
      // Restore original target
      basket.SetTargetUSD(m_original_target);
      basket.RecalculateGroupTP();
      
      m_qe_active = false;
      
      Log(StringFormat("QE DEACTIVATED: %s (restored target %.2f)",
                      reason, m_original_target));
   }
};
```

### ✅ Deliverables
1. `CQuickExitManager` class
2. Support for negative TP calculation
3. Backup/restore target mechanism
4. Log QE activation/deactivation

### 🎯 Exit Criteria
- **Preset Uptrend 300p**: SELL basket triggers trap → activates QE → exits at -$10 → reseeds
- **DD reduction**: Max DD reduced by 50-70% vs non-QE

### 🧪 Tests
```
Test 1: QE_FIXED Activation
- Trap detected → QE activates
- Target: $5.0 → -$10.0
- TP price moves closer to current
- Result: PASS ✓

Test 2: QE Exit
- Basket hits -$10 loss → closes
- QE deactivates → target restored to $5.0
- Reseed if enabled
- Result: PASS ✓

Test 3: Negative TP Calculation
- BUY basket: TP below avg price ✓
- SELL basket: TP above avg price ✓
```

### 🔄 Rollback
- Set `InpQuickExitEnabled = false`

---

## ⏳ PHASE 8: Quick Exit v2 (Modes + Timeout + CloseFar)

### 🎯 Goal
Complete QE with 3 modes, timeout, and close-far positions.

### 📦 Scope
**3 QE Modes**:
```cpp
enum ENUM_QUICK_EXIT_MODE
{
   QE_FIXED,      // Fixed loss: -$10
   QE_PERCENTAGE, // Percentage of target: -30% of $5 = -$1.5
   QE_DYNAMIC     // Based on DD: Current DD * 0.5
};

double CalculateQETarget(ENUM_QUICK_EXIT_MODE mode, CGridBasket* basket)
{
   switch(mode)
   {
      case QE_FIXED:
         return m_params.qe_loss_fixed; // -$10.0
         
      case QE_PERCENTAGE:
         return m_params.target_cycle_usd * m_params.qe_percentage; // $5 * -0.3 = -$1.5
         
      case QE_DYNAMIC:
         double current_dd = basket.GetPnLUSD();
         return current_dd * 0.5; // Accept 50% of current loss
   }
}
```

**Timeout**:
```cpp
void CheckQETimeout()
{
   if(!m_qe_active) return;
   
   datetime now = TimeCurrent();
   int minutes_elapsed = (int)((now - m_qe_start_time) / 60);
   
   if(minutes_elapsed > m_params.qe_timeout_minutes)
   {
      DeactivateQuickExit(basket, "Timeout");
   }
}
```

**Close Far Positions**:
```cpp
void CloseParPositions(CGridBasket* basket)
{
   double avg_price = basket.GetAvgPrice();
   double close_distance = m_params.qe_close_far_distance; // e.g. 200 pips
   
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      double pos_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double distance_pips = MathAbs(pos_price - avg_price) * 10000 / Point();
      
      if(distance_pips > close_distance)
      {
         ClosePosition(ticket);
         Log(StringFormat("QE: Closed far position #%I64u (%.1f pips from avg)",
                         ticket, distance_pips));
      }
   }
   
   // Recalculate basket metrics after closing
   basket.RefreshState();
}
```

### ✅ Deliverables
1. All 3 QE modes working
2. Timeout mechanism
3. Close-far positions logic
4. Basket recalculation after close-far

### 🎯 Exit Criteria
- **Preset Gap-Sideways**: Time to exit trap reduced by 60%+
- **QE_PERCENTAGE**: More conservative than QE_FIXED
- **Timeout**: QE deactivates after 60 minutes if not exited

### 🧪 Tests
```
Test 1: QE Modes
- QE_FIXED: -$10 ✓
- QE_PERCENTAGE (30%): -$1.5 ✓
- QE_DYNAMIC (DD=-$20): -$10 ✓

Test 2: Timeout
- QE activated → wait 61 minutes → deactivated ✓

Test 3: Close Far
- Basket avg: 2030.00
- Position 1: 2029.50 (50 pips) → keep
- Position 2: 2027.50 (250 pips) → close ✓
- Avg recalculated correctly ✓
```

### 🔄 Rollback
- Revert to QE_FIXED only
- Disable close-far: `InpQuickExitCloseFar = false`

---

## ⏳ PHASE 9: Gap Management v1 (Calculate + Bridge 200-400)

### 🎯 Goal
Detect large gaps between positions and fill them with "bridge" orders.

### 📦 Scope
**New Files**:
- `src/core/GapManager.mqh` - Gap detection & bridging

**Core Logic**:
```cpp
class CGapManager
{
public:
   double CalculateGapSize(CGridBasket* basket)
   {
      double max_gap = 0.0;
      
      // Get all position prices, sort them
      double prices[];
      basket.GetAllPositionPrices(prices);
      ArraySort(prices);
      
      // Find largest gap
      for(int i=1; i<ArraySize(prices); i++)
      {
         double gap = MathAbs(prices[i] - prices[i-1]) * 10000 / Point();
         if(gap > max_gap)
            max_gap = gap;
      }
      
      return max_gap; // in pips
   }
   
   void FillBridge(CGridBasket* basket, double gap_size)
   {
      if(gap_size < 200 || gap_size > 400)
         return; // Only bridge 200-400 pips
      
      // Find gap boundaries
      double price_low, price_high;
      FindGapBoundaries(basket, price_low, price_high);
      
      // Calculate bridge levels
      int num_bridges = (int)(gap_size / m_params.bridge_spacing); // e.g. 300/60 = 5
      num_bridges = MathMin(num_bridges, m_params.max_bridge_levels); // Cap at 5
      
      // Place bridge orders
      for(int i=1; i<=num_bridges; i++)
      {
         double bridge_price = price_low + (price_high - price_low) * i / (num_bridges + 1);
         double bridge_lot = basket.CalculateBridgeLot(i); // Scale appropriately
         
         if(IsPriceReasonable(bridge_price, basket))
         {
            ulong ticket = PlaceBridgeOrder(basket, bridge_price, bridge_lot);
            Log(StringFormat("BRIDGE: Placed level %d at %.5f (lot %.2f)",
                            i, bridge_price, bridge_lot));
         }
      }
   }
};
```

### ✅ Deliverables
1. `CalculateGapSize()` accurate
2. Bridge orders placed between gap
3. Price validation (IsPriceReasonable)
4. Log each bridge order

### 🎯 Exit Criteria
- **Preset Gap-Sideways**: Gap detected (250 pips) → 4 bridge orders placed
- **Price validation**: BUY bridges below current, SELL bridges above current

### 🧪 Tests
```
Test 1: Gap Detection
- Positions at: 2030.00, 2027.50 (250 pips gap) ✓
- Calculated gap: 250 pips ✓

Test 2: Bridge Placement
- Gap: 300 pips → 5 bridge orders ✓
- Spacing: ~60 pips each ✓
- Direction: BUY below / SELL above ✓

Test 3: No Bridge (Range)
- Gap: 150 pips → NO BRIDGE (< 200) ✓
```

### 🔄 Rollback
- Set `InpAutoFillBridge = false`

---

## ⏳ PHASE 10: Gap Management v2 (CloseFar >400 + Reseed)

### 🎯 Goal
For very large gaps (>400 pips), close far positions and reseed.

### 📦 Scope
**Modified Files**:
- `src/core/GapManager.mqh` - Add close-far logic

**Core Logic**:
```cpp
void ManageLargeGap(CGridBasket* basket, double gap_size)
{
   if(gap_size <= 400)
      return; // Only for >400 pips
   
   // Calculate total loss if closing far positions
   double far_loss = CalculateFarPositionsLoss(basket);
   
   if(far_loss > m_params.max_acceptable_loss)
   {
      Log(StringFormat("LARGE GAP: %.1f pips, but far loss %.2f > %.2f max - SKIP",
                      gap_size, far_loss, m_params.max_acceptable_loss));
      return; // Loss too large
   }
   
   // Close far positions
   int closed_count = 0;
   for(int i=0; i<PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(IsFarPosition(basket, ticket))
      {
         ClosePosition(ticket);
         closed_count++;
      }
   }
   
   Log(StringFormat("LARGE GAP: Closed %d far positions (loss %.2f USD)",
                   closed_count, far_loss));
   
   // Recalculate basket
   basket.RefreshState();
   
   // Reseed if needed
   if(basket.GetFilledLevels() < 2)
   {
      basket.Reseed();
      Log("LARGE GAP: Reseeded basket (< 2 positions remaining)");
   }
}
```

### ✅ Deliverables
1. Close-far for >400 pip gaps
2. Loss validation before closing
3. Reseed if < 2 positions remain
4. Metrics recalculation

### 🎯 Exit Criteria
- **Preset Uptrend (Extended)**: Gap grows to 500 pips → closes far → reseeds
- **DD Control**: DD doesn't balloon despite large gap

### 🧪 Tests
```
Test 1: Large Gap Close
- Gap: 450 pips
- Far positions loss: -$50 (< $100 max) ✓
- Closed: 3 positions ✓

Test 2: Loss Too High
- Gap: 500 pips
- Far positions loss: -$120 (> $100 max) ✗
- Action: SKIP close-far ✓

Test 3: Reseed
- After close-far: 1 position left
- Action: Reseed ✓
```

### 🔄 Rollback
- Disable close-far, keep bridge only

---

## ⏳ PHASE 11: Lifecycle Controller (Profit Sharing + Global Risk)

### 🎯 Goal
Coordinate both baskets: profit sharing, x2 help for QE, emergency protocol.

### 📦 Scope
**Modified Files**:
- `src/core/LifecycleController.mqh` - Add profit sharing & global risk

**Profit Sharing**:
```cpp
void HandleBasketClosures()
{
   // BUY basket closed
   if(m_buy != NULL && m_buy.ClosedRecently())
   {
      double realized = m_buy.TakeRealizedProfit();
      
      if(realized > 0 && m_sell != NULL)
      {
         // x2 help if SELL is in QE mode
         double reduction = realized;
         if(m_sell.IsQEActive())
         {
            reduction *= 2.0;
            Log(StringFormat("PROFIT SHARING: BUY profit %.2f → SELL x2 help = %.2f",
                            realized, reduction));
         }
         
         m_sell.ReduceTargetBy(reduction);
      }
      
      TryReseedBasket(m_buy, DIR_BUY);
   }
   
   // Same for SELL basket
   // ...
}
```

**Global Risk**:
```cpp
void CheckGlobalRisk()
{
   bool buy_trouble = (m_buy != NULL) 
                      && (m_buy.IsTrapped() || m_buy.GetDrawdownPercent() < -30);
   bool sell_trouble = (m_sell != NULL) 
                       && (m_sell.IsTrapped() || m_sell.GetDrawdownPercent() < -30);
   
   if(buy_trouble && sell_trouble)
   {
      Log("EMERGENCY: Both baskets in trouble!");
      
      // Close basket with worse DD
      double buy_dd = m_buy.GetDrawdownPercent();
      double sell_dd = m_sell.GetDrawdownPercent();
      
      if(buy_dd < sell_dd)
      {
         m_buy.ForceClose("Emergency_WorseBasket");
         Log(StringFormat("EMERGENCY: Closed BUY (DD %.2f%% < SELL %.2f%%)",
                         buy_dd, sell_dd));
      }
      else
      {
         m_sell.ForceClose("Emergency_WorseBasket");
         Log(StringFormat("EMERGENCY: Closed SELL (DD %.2f%% < BUY %.2f%%)",
                         sell_dd, buy_dd));
      }
   }
}
```

### ✅ Deliverables
1. x2 profit sharing when basket in QE
2. Emergency protocol for double-trouble
3. Logs for all lifecycle events

### 🎯 Exit Criteria
- **Preset Whipsaw**: Smooth lifecycle, both baskets help each other
- **Emergency Test**: Both baskets trapped → closes worse one

### 🧪 Tests
```
Test 1: Normal Profit Sharing
- BUY closes +$5 → SELL target: $5 - $5 = $0 ✓

Test 2: x2 Help (QE Active)
- SELL in QE mode
- BUY closes +$5 → SELL target: $5 - $10 = -$5 (instant close) ✓

Test 3: Emergency
- BUY DD: -35%
- SELL DD: -40%
- Action: Close SELL (worse) ✓
```

### 🔄 Rollback
- Set multiplier to 1× (no x2 help)
- Disable emergency protocol

---

## ⏳ PHASE 12: Parameters & Symbol Presets

### 🎯 Goal
Create battle-tested presets for popular symbols.

### 📦 Scope
**Symbol-Specific Thresholds**:

| Parameter | EURUSD | GBPUSD | XAUUSD | US30 |
|-----------|--------|--------|--------|------|
| **Spacing** | 15 pips | 20 pips | 25 pips | 50 points |
| **Gap Monitor** | 100 pips | 120 pips | 150 pips | 200 points |
| **Bridge Gap** | 200-350 | 220-400 | 250-450 | 300-500 |
| **Close Far** | >350 | >400 | >450 | >500 |
| **Trap DD** | -15% | -18% | -20% | -20% |
| **QE Loss** | -$8 | -$10 | -$15 | -$20 |
| **Max DD** | -20% | -22% | -25% | -25% |

**Preset Files**:
- `presets/EURUSD-Conservative.set`
- `presets/GBPUSD-Conservative.set`
- `presets/XAUUSD-Aggressive.set`
- `presets/US30-Standard.set`

### ✅ Deliverables
1. 4 symbol presets
2. Documentation for each preset
3. README with loading instructions

### 🎯 Exit Criteria
- Load preset → backtest 2 weeks → runs smoothly
- Minimal manual adjustment needed

### 🧪 Tests
```
Test Each Preset:
- Load .set file ✓
- Run 2-week backtest ✓
- Check: No crashes, reasonable DD, trap escapes working ✓
```

### 🔄 Rollback
- Use "Conservative" preset as fallback

---

## ⏳ PHASE 13: Backtest Burn-in (3 Months Data)

### 🎯 Goal
Validate all features with extensive backtesting.

### 📦 Scope
**Test Matrix**:
```
Symbols: EURUSD, XAUUSD, US30
Duration: 3 months (Jan-Mar 2024)
Configurations:
1. Lazy Grid ON, all features OFF (baseline)
2. + Trap Detection
3. + Quick Exit
4. + Gap Management
5. All features ON (full stack)
```

**KPIs to Measure**:
```cpp
struct SBacktestKPIs
{
   double max_dd;               // Maximum drawdown
   double avg_dd;               // Average drawdown
   int    total_traps;          // Traps detected
   int    trap_escapes;         // Successful QE exits
   double trap_escape_rate;     // % = escapes / traps
   double avg_loss_per_trap;    // Average loss when trapped
   double avg_time_to_qe;       // Minutes to exit trap
   int    bridge_orders;        // Bridge orders placed
   int    close_far_events;     // Close-far triggered
   double total_profit;         // Net profit
   double profit_factor;        // Gross profit / gross loss
};
```

**Reporting**:
- CSV export for each configuration
- Markdown comparison table
- Charts: DD over time, trap events, PnL curve

### ✅ Deliverables
1. Backtest results for all 5 configurations
2. CSV + Markdown reports
3. Before/After comparison charts
4. Performance improvement summary

### 🎯 Exit Criteria
- **DD Reduction**: 50-70% lower with all features vs baseline
- **Trap Escape Rate**: ≥80%
- **Avg Loss Per Trap**: <$15
- **No Regressions**: Baseline features still work

### 🧪 Tests
```
Regression Suite:
1. Static Grid (no lazy) still works ✓
2. Lazy Grid without traps/QE/gap works ✓
3. Each feature can be enabled/disabled independently ✓
4. News filter doesn't conflict ✓
5. Multi-symbol backtests don't crash ✓
```

### 🔄 Rollback
- Reduce sensitivity if KPIs are poor:
  - Increase `InpTrapConditionsRequired = 4`
  - Decrease `InpMaxDDForExpansion = -15%`
  - Increase `InpQELoss = -$15`

---

## ⏳ PHASE 14: Main EA Integration

### 🎯 Goal
Wire everything into the main EA file.

### 📦 Scope
**Modified Files**:
- `src/ea/RecoveryGridDirection_v3.mq5` - Main EA

**Integration Points**:
```cpp
// OnInit()
int OnInit()
{
   // Initialize logger
   g_logger = new CLogger(InpMagic, InpLogEvents);
   
   // Build params
   BuildParams();
   
   // Print configuration
   PrintConfiguration();
   
   // Initialize lifecycle
   g_lifecycle = new CLifecycleController(...);
   if(!g_lifecycle.Init())
      return INIT_FAILED;
   
   return INIT_SUCCEEDED;
}

// OnTick()
void OnTick()
{
   // Check news filter
   if(g_news_filter != NULL && g_news_filter.IsHighImpactNews())
   {
      g_logger.Event("NEWS", "High impact news - skipping tick");
      return;
   }
   
   // Update lifecycle
   g_lifecycle.Update();
   
   // Hourly performance log
   static datetime last_perf_log = 0;
   if(TimeCurrent() - last_perf_log > 3600)
   {
      LogPerformanceMetrics();
      last_perf_log = TimeCurrent();
   }
}

// OnDeinit()
void OnDeinit(const int reason)
{
   LogPerformanceMetrics();
   
   delete g_lifecycle;
   delete g_logger;
   delete g_news_filter;
}
```

**PrintConfiguration()**:
```cpp
void PrintConfiguration()
{
   Print("========================================");
   Print("EA CONFIGURATION");
   Print("========================================");
   Print("Version: ", EA_VERSION);
   Print("Magic: ", InpMagic);
   Print("");
   Print("--- Grid Configuration ---");
   Print("Levels: ", InpGridLevels);
   Print("Spacing: ", InpSpacingStepPips, " pips");
   Print("Lot base: ", InpLotBase);
   Print("");
   Print("--- Lazy Grid ---");
   Print("Enabled: ", InpLazyGridEnabled ? "YES" : "NO");
   Print("Initial warm: ", InpInitialWarmLevels);
   Print("");
   Print("--- Trap Detection ---");
   Print("Enabled: ", InpTrapDetectionEnabled ? "YES" : "NO");
   Print("Conditions required: ", InpTrapConditionsRequired, "/5");
   Print("");
   Print("--- Quick Exit ---");
   Print("Enabled: ", InpQuickExitEnabled ? "YES" : "NO");
   Print("Mode: ", EnumToString(InpQuickExitMode));
   Print("");
   Print("--- Gap Management ---");
   Print("Bridge enabled: ", InpAutoFillBridge ? "YES" : "NO");
   Print("========================================");
}
```

### ✅ Deliverables
1. Full EA integration
2. Configuration print on init
3. Hourly performance logs
4. Clean deinit

### 🎯 Exit Criteria
- EA runs end-to-end without crashes
- Logs are clear and helpful
- News filter integration working

### 🧪 Tests
```
Test 1: Init
- EA loads ✓
- Configuration printed ✓
- All modules initialized ✓

Test 2: Runtime
- Ticks processed ✓
- Hourly logs appear ✓
- No memory leaks ✓

Test 3: Deinit
- Clean shutdown ✓
- Final metrics logged ✓
```

### 🔄 Rollback
- Revert to previous EA version tag

---

## ⏳ PHASE 15: Hardening & Release v3.1.0

### 🎯 Goal
Polish, document, and release stable version.

### 📦 Scope
**Code Cleanup**:
1. Remove all `[DEBUG]` logs
2. Extract QE/Gap helpers into separate files
3. Add input validation
4. Add error handling for edge cases

**Documentation**:
```
docs/
├── USER-GUIDE.md           # Installation, presets, basic usage
├── TECHNICAL-DOCS.md       # Architecture, class diagram, flow charts
├── TESTING-REPORT.md       # Phase 13 backtest results
├── DEPLOYMENT-CHECKLIST.md # Live deployment steps
└── CHANGELOG-v3.1.0.md     # What's new, breaking changes
```

**Changelog**:
```markdown
# v3.1.0 - Recovery Grid Direction (2025-01-XX)

## 🎉 New Features
- ✅ **Lazy Grid Fill**: Minimal seed + smart expansion with 4 guards
- ✅ **Trap Detection**: 5-condition system (Gap, Counter-trend, DD, Moving-away, Stuck)
- ✅ **Quick Exit**: 3 modes (Fixed/Percentage/Dynamic) with timeout & close-far
- ✅ **Gap Management**: Bridge orders (200-400 pips) + Close-far (>400 pips)
- ✅ **Profit Sharing**: Cross-basket help (x2 when in QE)
- ✅ **Global Risk**: Emergency protocol for double-trouble

## 📊 Performance Improvements
- 🔻 Max DD reduced by 60-70%
- ✅ Trap escape rate: 85%+
- ⚡ Average trap exit time: <20 minutes

## 🐛 Bug Fixes
- Fixed: Level fill tracking not updating
- Fixed: Expansion trigger logic
- Fixed: Cross-basket TP reduction timing

## 📝 Documentation
- Added: Complete user guide
- Added: Technical architecture docs
- Added: 3-month backtest report

## ⚠️ Breaking Changes
- Removed: Dynamic Grid feature (replaced by Lazy Grid)
- Removed: Grid Protection (not needed with QE)
- Disabled: Trend Filter (will add in v3.2.0)
```

**Release Checklist**:
```
□ All phases (1-15) tested ✓
□ All presets validated ✓
□ Documentation complete ✓
□ Changelog written ✓
□ Code cleanup done ✓
□ Git tag created: v3.1.0 ✓
□ Build final .ex5 ✓
□ Demo account test (1 week) ✓
□ Small live account test (1 week) ✓
□ Release to production ✓
```

### ✅ Deliverables
1. Clean, production-ready code
2. Complete documentation set
3. Git tag: `v3.1.0`
4. Final `.ex5` build
5. Deployment checklist

### 🎯 Exit Criteria
- All regression tests pass
- 1-week demo account test successful
- Documentation reviewed
- Ready for live deployment

### 🧪 Tests
```
Final Validation:
1. Re-run all Phase 13 backtests ✓
2. Demo account (1 week) ✓
3. Small live account (1 week, $100) ✓
4. Monitor: No crashes, clean logs, features working ✓
```

---

# 🚀 PHASE 16-20: ADVANCED FEATURES

## ⏳ PHASE 16: Multi-Job System v2 (Advanced)

### 🎯 Goal
Support multiple jobs with intelligent spawn conditions.

### 📦 Scope
- **Spawn on Grid Full**: When primary grid full, spawn new job
- **Spawn on TSL Hit**: When trailing stop loss hit, spawn recovery job
- **Spawn on Job DD**: When job DD exceeds threshold, spawn hedge job
- **Global DD Limit**: Emergency stop all jobs if total DD too high

### ✅ Key Features
```cpp
class CJobManager
{
private:
   CLifecycleController* m_jobs[];
   int m_max_jobs;
   double m_global_dd_limit;
   
public:
   void CheckSpawnConditions()
   {
      // Spawn on grid full
      if(m_params.spawn_on_grid_full)
      {
         for(int i=0; i<ArraySize(m_jobs); i++)
         {
            if(m_jobs[i].IsGridFull() && !IsInCooldown(i))
            {
               SpawnNewJob(SPAWN_REASON_GRID_FULL);
            }
         }
      }
      
      // Check global DD
      double total_dd = CalculateGlobalDD();
      if(total_dd < m_global_dd_limit)
      {
         EmergencyStopAll();
      }
   }
   
   void SpawnNewJob(ENUM_SPAWN_REASON reason)
   {
      if(ArraySize(m_jobs) >= m_max_jobs)
      {
         Log("Cannot spawn: Max jobs reached");
         return;
      }
      
      int magic = m_base_magic + m_magic_offset * ArraySize(m_jobs);
      CLifecycleController* job = new CLifecycleController(..., magic);
      job.Init();
      
      ArrayResize(m_jobs, ArraySize(m_jobs) + 1);
      m_jobs[ArraySize(m_jobs)-1] = job;
      
      Log(StringFormat("SPAWNED Job #%d (reason: %s, magic: %d)",
                      ArraySize(m_jobs), EnumToString(reason), magic));
   }
};
```

### 🎯 Exit Criteria
- Can run up to 5 jobs simultaneously
- Each job has independent magic number
- Global DD limit stops all jobs

---

## ⏳ PHASE 17: Basket Stop Loss v2 (Dynamic)

### 🎯 Goal
Implement dynamic basket SL based on spacing.

### 📦 Scope
```cpp
class CBasketSL
{
public:
   void UpdateDynamicSL(CGridBasket* basket)
   {
      if(!m_params.basket_sl_enabled)
         return;
      
      // SL = anchor ± (spacing × multiplier)
      double anchor = basket.GetAnchorPrice();
      double spacing = basket.GetSpacing();
      double sl_distance = spacing * m_params.basket_sl_spacing; // e.g. 2.0
      
      double sl_price;
      if(basket.Direction() == DIR_BUY)
         sl_price = anchor - sl_distance; // Below anchor
      else
         sl_price = anchor + sl_distance; // Above anchor
      
      basket.SetStopLoss(sl_price);
      
      Log(StringFormat("BASKET SL: Updated to %.5f (anchor %.5f ± %.5f)",
                      sl_price, anchor, sl_distance));
   }
};
```

### 🎯 Exit Criteria
- SL moves with basket expansion
- SL triggered → basket closes → reseeds

---

## ⏳ PHASE 18: Trend Filter v2 (Smart)

### 🎯 Goal
Implement smart trend filter to avoid counter-trend trades.

### 📦 Scope
```cpp
enum ENUM_TREND_ACTION
{
   TREND_ACTION_NONE,      // No action
   TREND_ACTION_NO_REFILL, // Block refill only
   TREND_ACTION_CLOSE_ALL  // Close counter-trend basket
};

class CTrendFilter
{
private:
   int m_ema_handle;
   int m_adx_handle;
   
public:
   bool AllowBuyBasket()
   {
      double ema[], adx[];
      CopyBuffer(m_ema_handle, 0, 0, 1, ema);
      CopyBuffer(m_adx_handle, 0, 0, 1, adx);
      
      double current_price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      
      // Strong uptrend: Price > EMA && ADX > 30
      if(current_price > ema[0] && adx[0] > m_params.trend_adx_threshold)
         return true; // Allow BUY
      
      // Strong downtrend: Block BUY
      if(current_price < ema[0] && adx[0] > m_params.trend_adx_threshold)
      {
         if(m_params.trend_action == TREND_ACTION_CLOSE_ALL)
            return false; // Block BUY
      }
      
      return true; // Neutral/weak trend: allow
   }
};
```

### 🎯 Exit Criteria
- Uptrend: SELL basket blocked/closed
- Downtrend: BUY basket blocked/closed
- Sideways: Both baskets active

---

## ⏳ PHASE 19: News Filter v2 (Calendar Integration)

### 🎯 Goal
Integrate real news calendar API.

### 📦 Scope
```cpp
class CNewsFilter
{
private:
   string m_api_url;
   datetime m_last_fetch;
   SNewsEvent m_upcoming_events[];
   
public:
   bool IsHighImpactNews()
   {
      // Fetch calendar if stale
      if(TimeCurrent() - m_last_fetch > 3600)
         FetchNewsCalendar();
      
      datetime now = TimeCurrent();
      
      // Check upcoming events
      for(int i=0; i<ArraySize(m_upcoming_events); i++)
      {
         SNewsEvent event = m_upcoming_events[i];
         
         // Filter by impact & currency
         if(event.impact != "High")
            continue;
         if(!IsRelevantCurrency(event.currency))
            continue;
         
         // Check time window
         int minutes_to_event = (int)((event.time - now) / 60);
         
         if(MathAbs(minutes_to_event) < m_params.news_buffer_minutes)
         {
            Log(StringFormat("NEWS FILTER: %s %s in %d minutes - BLOCKING",
                            event.currency, event.title, minutes_to_event));
            return true; // Block trading
         }
      }
      
      return false; // Safe to trade
   }
   
   void FetchNewsCalendar()
   {
      // HTTP request to news API
      // Parse JSON response
      // Populate m_upcoming_events[]
      m_last_fetch = TimeCurrent();
   }
};
```

### 🎯 Exit Criteria
- Fetch calendar hourly
- Block trading ±30 min around high-impact news
- Log which events are blocking

---

## ⏳ PHASE 20: Machine Learning Integration (ML-Enhanced QE)

### 🎯 Goal
Use ML to optimize QE timing and trap detection.

### 📦 Scope
**ML Models**:
1. **Trap Predictor**: Predict trap probability before it happens
2. **QE Optimizer**: Suggest optimal QE loss based on historical data
3. **Gap Classifier**: Classify gap type (temporary/permanent)

**Implementation**:
```cpp
class CMLEnhancedQE
{
private:
   CNeuralNetwork* m_trap_predictor;
   CRandomForest*  m_qe_optimizer;
   
public:
   double PredictTrapProbability(CGridBasket* basket)
   {
      // Extract features
      double features[10];
      features[0] = basket.GetDrawdownPercent();
      features[1] = basket.GetGapSize();
      features[2] = basket.GetAvgPriceDistance();
      features[3] = basket.GetFilledLevels();
      features[4] = GetMarketVolatility();
      // ... more features
      
      // Predict using trained model
      double probability = m_trap_predictor.Predict(features);
      
      return probability; // 0.0 - 1.0
   }
   
   double OptimizeQELoss(CGridBasket* basket)
   {
      // ML-suggested QE loss based on:
      // - Current DD
      // - Gap size
      // - Market conditions
      // - Historical success rate
      
      double suggested_loss = m_qe_optimizer.Predict(...);
      
      // Clamp to reasonable range
      suggested_loss = MathMax(suggested_loss, -$30);
      suggested_loss = MathMin(suggested_loss, -$5);
      
      return suggested_loss;
   }
};
```

**Training Data**:
- Collect trap episodes from backtests
- Features: DD, gap, volatility, time of day, etc.
- Labels: Did QE succeed? At what loss?

### 🎯 Exit Criteria
- ML models trained on 6+ months data
- Trap prediction accuracy >75%
- QE success rate improves by 10%+

---

# 📈 PHASE 21+: FUTURE ENHANCEMENTS

## 🔮 Potential Features

### Phase 21: Portfolio Mode
- Trade multiple symbols with one EA
- Automatic correlation detection
- Diversification optimization

### Phase 22: Cloud Integration
- Remote monitoring dashboard
- Telegram/Email alerts
- Cloud logging & analytics

### Phase 23: Adaptive Parameters
- Auto-tune parameters based on recent performance
- Market regime detection (trending/ranging)
- Dynamic adjustment of all thresholds

### Phase 24: Advanced Risk Management
- Kelly Criterion for lot sizing
- Maximum Adverse Excursion (MAE) tracking
- Equity curve smoothing

### Phase 25: Social Trading Integration
- Copy signals to/from other traders
- Leaderboard & performance comparison
- Signal quality scoring

---

# 📊 SUCCESS METRICS (v3.1.0 Goals)

## 🎯 Performance Targets

| Metric | Baseline (v3.0) | Target (v3.1) | Status |
|--------|----------------|---------------|--------|
| **Max DD** | -40% | -15% | ⏳ |
| **Trap Escape Rate** | 50% | 85% | ⏳ |
| **Avg Loss/Trap** | -$30 | -$10 | ⏳ |
| **Time to Exit Trap** | 60 min | 20 min | ⏳ |
| **Profit Factor** | 1.2 | 1.5+ | ⏳ |
| **Win Rate** | 65% | 70% | ⏳ |

## 📝 Quality Metrics

| Metric | Target | Status |
|--------|--------|--------|
| **Code Coverage** | >80% | ⏳ |
| **Compilation Warnings** | 0 | ✅ |
| **Memory Leaks** | 0 | ✅ |
| **Backtest Speed** | <10 min/month | ⏳ |
| **Log Clarity** | >90% useful | ✅ |

---

# 🛠️ DEVELOPMENT GUIDELINES

## 📁 File Structure
```
trading3/
├── src/
│   ├── core/
│   │   ├── GridBasket.mqh
│   │   ├── LifecycleController.mqh
│   │   ├── TrapDetector.mqh          ← Phase 5-6
│   │   ├── QuickExitManager.mqh      ← Phase 7-8
│   │   ├── GapManager.mqh            ← Phase 9-10
│   │   ├── TrendFilter.mqh           ← Phase 18
│   │   ├── NewsFilter.mqh            ← Phase 19
│   │   └── Types.mqh
│   ├── utils/
│   │   ├── Logger.mqh
│   │   ├── SpacingEngine.mqh
│   │   └── Executor.mqh
│   └── ea/
│       └── RecoveryGridDirection_v3.mq5
├── presets/
│   ├── EURUSD-Conservative.set
│   ├── XAUUSD-Aggressive.set
│   └── TEST-Phase*.set
├── tests/
│   ├── scenarios/
│   │   ├── 01-Range-Normal.set
│   │   ├── 02-Uptrend-300p-SELLTrap.set
│   │   ├── 03-Whipsaw-BothTrapped.set
│   │   └── 04-Gap-Sideways-Bridge.set
│   └── results/
│       └── backtest-results.csv
├── docs/
│   ├── USER-GUIDE.md
│   ├── TECHNICAL-DOCS.md
│   └── TESTING-REPORT.md
└── plan/
    ├── 15-phase.md
    └── ROADMAP-PHASE5-TO-PHASE20.md  ← This file
```

## 🎨 Coding Standards
```cpp
// 1. Naming Convention
class CMyClass {};           // Classes: Pascal case with C prefix
int my_variable;             // Variables: snake_case
void MyFunction() {};        // Functions: Pascal case

// 2. Logging
m_log.Event(Tag(), "Description");  // Use Tag() for context
Log(StringFormat("Value: %.2f", value));  // Format strings

// 3. Error Handling
if(ticket == 0)
{
   Log(StringFormat("Order failed: %d", GetLastError()));
   return false;
}

// 4. Comments
// Single line comment
/* Multi-line comment
   for complex logic */

// 5. Constants
#define EA_VERSION "3.1.0"
const int MAX_JOBS = 5;
```

## 🧪 Testing Standards
```cpp
// Unit Test Template
bool TestTrapDetection()
{
   // Arrange
   CGridBasket* basket = CreateTestBasket();
   basket.SetDrawdown(-25.0);
   basket.SetGapSize(250.0);
   
   // Act
   bool is_trapped = m_trap_detector.DetectTrap(basket);
   
   // Assert
   if(!is_trapped)
   {
      Print("TEST FAILED: Trap not detected");
      return false;
   }
   
   Print("TEST PASSED: Trap detected correctly");
   return true;
}
```

---

# 🎯 PHASE DEPENDENCIES

```
Phase 0 (Baseline)
  ↓
Phase 1 (Logger)
  ↓
Phase 2 (Test Harness)
  ↓
Phase 3 (Lazy Grid v1) ← You started here
  ↓
Phase 4 (Lazy Grid v2) ← YOU ARE HERE ✅
  ↓
Phase 5 (Trap v1) ────────────┐
  ↓                            │
Phase 6 (Trap v2)              │
  ↓                            │
Phase 7 (QE v1) ← Depends on Trap Detection
  ↓
Phase 8 (QE v2)
  ↓
Phase 9 (Gap v1)
  ↓
Phase 10 (Gap v2) ← Depends on QE for close-far
  ↓
Phase 11 (Lifecycle) ← Depends on QE & Gap
  ↓
Phase 12 (Presets) ← Depends on all features
  ↓
Phase 13 (Backtest) ← Depends on all features
  ↓
Phase 14 (Integration) ← Depends on all features
  ↓
Phase 15 (Release) ← Final phase
  ↓
Phase 16+ (Advanced) ← Optional enhancements
```

---

# 🚀 QUICK START FOR PHASE 5

When you're ready to start Phase 5:

1. **Create new file**: `src/core/TrapDetector.mqh`
2. **Add to Types.mqh**:
```cpp
// Trap condition flags
#define TRAP_COND_GAP            0x01  // 0b00001
#define TRAP_COND_COUNTER_TREND  0x02  // 0b00010
#define TRAP_COND_HEAVY_DD       0x04  // 0b00100
#define TRAP_COND_MOVING_AWAY    0x08  // 0b01000
#define TRAP_COND_STUCK          0x10  // 0b10000

struct STrapState
{
   bool     isTrapped;
   datetime trapTime;
   double   gapSize;
   double   ddAtDetection;
   int      conditionsMet;
   int      conditionFlags;  // Bitmask of TRAP_COND_*
   
   void Reset()
   {
      isTrapped = false;
      trapTime = 0;
      gapSize = 0;
      ddAtDetection = 0;
      conditionsMet = 0;
      conditionFlags = 0;
   }
};
```

3. **Test scenario**: Use `02-Uptrend-300p-SELLTrap.set`
4. **Expected log**: `"TRAP DETECTED! Conditions: 3/5"`

---

# 💤 SLEEP WELL!

This roadmap is your complete guide from Phase 5 to Phase 20+. Each phase builds on the previous one, and you have:

✅ Clear goals  
✅ Detailed code examples  
✅ Test scenarios  
✅ Exit criteria  
✅ Rollback plans  

**Next session**: Start with Phase 5 (Trap Detection v1)

Sweet dreams! 🌙

