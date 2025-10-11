# Phase 12: Trend-Aware Reseed (Smart Reseed Direction Filter)

**Date**: 2025-01-10
**Status**: 🚧 PLANNED (Not Yet Implemented)
**Priority**: 🔴 HIGH (Fixes critical issue in Basket SL + Reseed)
**Branch**: feature/lazy-grid-fill-smart-trap-detection-2

---

## 🎯 **Problem Statement**

**User Feedback from Backtest**:
> "giá đi 1 chiều là gần như ko cách nào cứu dc grid ta"

### **Critical Issue Discovered**:

Basket SL + Reseed creates **no-win situation** in strong trends:

| Reseed Mode | Result | Problem |
|-------------|--------|---------|
| **IMMEDIATE** | -22.8% loss, 36% DD | Reseed vào counter-trend → SL loop → Catastrophic losses |
| **COOLDOWN** | -1.04% loss, flat equity | No reseed → Miss opportunities → EA stops trading |

**Fundamental Problem**: Grid trading không phù hợp với strong trend 1 chiều!

---

## ✅ **Solution: Trend-Aware Reseed**

### **Core Concept**:

**Don't reseed into counter-trend direction after Basket SL!**

```
Basket SL triggered
↓
Check current market trend
↓
If STRONG TREND detected:
  → ✅ Allow with-trend basket to continue
  → ❌ Block counter-trend basket reseed
↓
If NO strong trend (range):
  → ✅ Allow both baskets (normal grid operation)
```

### **Example Scenario**:

**Strong Uptrend (XAUUSD 2000 → 2500)**:
```
Time    Event                          Action                         Result
──────  ────────────────────────────  ─────────────────────────────  ──────────────
10:00   SELL basket opens at 2050      Normal grid operation          -
11:00   Price rises to 2425            SELL basket underwater         -$112
11:30   SELL Basket SL triggers        Check trend → UPTREND          -
11:31   Trend Filter: Strong UP        ❌ Block SELL reseed            Prevent re-entry
11:32   BUY basket continues           ✅ With-trend trading          Profit from trend
14:00   Trend exhausts, range starts   Trend Filter: NO TREND         -
14:05   SELL basket reseeds            ✅ Allow reseed in range       Resume grid
```

**Result**:
- Prevented: SL → Reseed SELL → SL loop (would lose -22.8%)
- Allowed: BUY basket profit from uptrend
- Total: Small loss from initial SELL SL, recovered by BUY profits

---

## 📐 **Design Specification**

### **1. New Enum: EReseedMode**

Add to `Types.mqh`:

```cpp
enum EReseedMode
{
   RESEED_IMMEDIATE,      // Reseed ngay lập tức (nguy hiểm trong trend!)
   RESEED_COOLDOWN,       // Reseed sau cooldown (có thể miss opportunities)
   RESEED_TREND_AWARE,    // NEW: Reseed only with-trend direction
   RESEED_MANUAL          // NEW: No auto-reseed (manual restart required)
};
```

### **2. New Parameters**

Add to `Params.mqh`:

```cpp
// Phase 12: Trend-Aware Reseed
EReseedMode reseed_mode;              // Reseed strategy
int         reseed_cooldown_min;      // Cooldown per direction (minutes)
bool        reseed_with_trend_only;   // Enable trend filter for reseed
```

### **3. New Member Variables**

Add to `LifecycleController.mqh`:

```cpp
private:
   datetime m_buy_reseed_cooldown;    // BUY reseed allowed after this time
   datetime m_sell_reseed_cooldown;   // SELL reseed allowed after this time
   int      m_buy_sl_count;           // Track BUY SL hits (for analysis)
   int      m_sell_sl_count;          // Track SELL SL hits (for analysis)
```

### **4. Core Logic: HandleBasketSLClosure()**

Implement in `LifecycleController.mqh`:

```cpp
//+------------------------------------------------------------------+
//| Handle basket closure due to SL (with trend-aware reseed)        |
//+------------------------------------------------------------------+
void HandleBasketSLClosure(EDirection closed_direction)
{
   // Track SL hits
   if(closed_direction == DIR_BUY)
      m_buy_sl_count++;
   else
      m_sell_sl_count++;

   if(m_log != NULL)
      m_log.Event("[LC]", StringFormat("%s basket SL recorded (#%d)",
                                       (closed_direction == DIR_BUY) ? "BUY" : "SELL",
                                       (closed_direction == DIR_BUY) ? m_buy_sl_count : m_sell_sl_count));

   // Mode: MANUAL - No auto reseed
   if(m_params.reseed_mode == RESEED_MANUAL)
   {
      if(m_log != NULL)
         m_log.Warn("[LC]", "Reseed mode: MANUAL - EA will stop trading. Restart manually when ready.");
      return; // Don't reseed
   }

   // Mode: TREND_AWARE - Check trend before reseed
   if(m_params.reseed_mode == RESEED_TREND_AWARE && m_params.reseed_with_trend_only)
   {
      if(m_trend_filter != NULL)
      {
         ETrendState trend = m_trend_filter.GetTrendState();

         // Strong uptrend → Block SELL reseed (counter-trend)
         if(trend == TREND_STRONG_UP && closed_direction == DIR_SELL)
         {
            if(m_log != NULL)
               m_log.Warn("[LC]", "⚠️  SELL reseed BLOCKED: Strong uptrend detected (counter-trend would lose)");
            m_sell_reseed_cooldown = TimeCurrent() + (m_params.reseed_cooldown_min * 60);
            return; // Don't reseed SELL in uptrend
         }

         // Strong downtrend → Block BUY reseed (counter-trend)
         if(trend == TREND_STRONG_DOWN && closed_direction == DIR_BUY)
         {
            if(m_log != NULL)
               m_log.Warn("[LC]", "⚠️  BUY reseed BLOCKED: Strong downtrend detected (counter-trend would lose)");
            m_buy_reseed_cooldown = TimeCurrent() + (m_params.reseed_cooldown_min * 60);
            return; // Don't reseed BUY in downtrend
         }

         // No strong trend → Allow reseed (normal grid operation)
         if(m_log != NULL)
            m_log.Event("[LC]", StringFormat("✅ %s reseed ALLOWED: No strong trend (range/weak trend)",
                                            (closed_direction == DIR_BUY) ? "BUY" : "SELL"));
      }
   }

   // Check per-direction cooldown
   datetime now = TimeCurrent();
   if(closed_direction == DIR_SELL && now < m_sell_reseed_cooldown)
   {
      int remaining = (int)((m_sell_reseed_cooldown - now) / 60);
      if(m_log != NULL)
         m_log.Event("[LC]", StringFormat("SELL reseed on cooldown: %d minutes remaining", remaining));
      return;
   }
   if(closed_direction == DIR_BUY && now < m_buy_reseed_cooldown)
   {
      int remaining = (int)((m_buy_reseed_cooldown - now) / 60);
      if(m_log != NULL)
         m_log.Event("[LC]", StringFormat("BUY reseed on cooldown: %d minutes remaining", remaining));
      return;
   }

   // Mode: COOLDOWN - Wait specified time
   if(m_params.reseed_mode == RESEED_COOLDOWN)
   {
      // Set cooldown
      if(closed_direction == DIR_SELL)
         m_sell_reseed_cooldown = now + (m_params.reseed_cooldown_min * 60);
      else
         m_buy_reseed_cooldown = now + (m_params.reseed_cooldown_min * 60);

      if(m_log != NULL)
         m_log.Event("[LC]", StringFormat("%s reseed scheduled after %d min cooldown",
                                         (closed_direction == DIR_BUY) ? "BUY" : "SELL",
                                         m_params.reseed_cooldown_min));
   }

   // Proceed with reseed
   ReseedBasket(closed_direction);

   // Set cooldown for IMMEDIATE and TREND_AWARE modes (prevent rapid re-trigger)
   if(m_params.reseed_mode == RESEED_IMMEDIATE || m_params.reseed_mode == RESEED_TREND_AWARE)
   {
      int cooldown_sec = 300; // 5 minutes minimum between same-direction reseeds
      if(closed_direction == DIR_SELL)
         m_sell_reseed_cooldown = now + cooldown_sec;
      else
         m_buy_reseed_cooldown = now + cooldown_sec;
   }
}
```

### **5. Update LifecycleController.Update()**

Modify basket closure handling:

```cpp
void Update()
{
   // ... existing code ...

   // Check for basket closure due to SL
   if(m_buy.ClosedRecently() && m_buy.GetCloseReason() == "BasketSL")
   {
      HandleBasketSLClosure(DIR_BUY);
   }

   if(m_sell.ClosedRecently() && m_sell.GetCloseReason() == "BasketSL")
   {
      HandleBasketSLClosure(DIR_SELL);
   }

   // ... rest of existing code ...
}
```

### **6. New Input Parameters**

Add to `RecoveryGridDirection_v3.mq5`:

```cpp
input group             "=== Phase 12: Trend-Aware Reseed ==="
input EReseedMode       InpReseedMode           = RESEED_TREND_AWARE;  // Reseed strategy
input int               InpReseedCooldownMin    = 30;                   // Cooldown per direction (minutes)
input bool              InpReseedWithTrendOnly  = true;                 // Enable trend filter for reseed

// Map to params
g_params.reseed_mode            = InpReseedMode;
g_params.reseed_cooldown_min    = InpReseedCooldownMin;
g_params.reseed_with_trend_only = InpReseedWithTrendOnly;
```

---

## 🎛️ **Preset Configuration**

### **EURUSD (Low Volatility)**:
```
InpReseedMode = RESEED_TREND_AWARE
InpReseedCooldownMin = 30
InpReseedWithTrendOnly = true
InpBasketSL_Enabled = false     ; Still disabled (test on demo first)
InpBasketSL_Spacing = 3.0
```

### **GBPUSD (Medium Volatility)**:
```
InpReseedMode = RESEED_TREND_AWARE
InpReseedCooldownMin = 30
InpReseedWithTrendOnly = true
InpBasketSL_Enabled = false     ; Still disabled (test on demo first)
InpBasketSL_Spacing = 3.0
```

### **XAUUSD (High Volatility)**:
```
InpReseedMode = RESEED_TREND_AWARE
InpReseedCooldownMin = 30
InpReseedWithTrendOnly = true
InpBasketSL_Enabled = true      ; ENABLED for XAUUSD (critical!)
InpBasketSL_Spacing = 2.5
```

---

## 🔄 **Interaction with Existing Features**

### **Feature Priority Order**:

```
1. Quick Exit TP          → Trap escape with negative TP
2. Trap Detection         → Detect trap conditions
3. Gap Management         → Bridge/CloseFar
4. Basket Stop Loss       → Hard SL triggers
   ↓
5. HandleBasketSLClosure  → NEW: Trend-aware reseed decision
   ↓
6. Lazy Grid Expansion    → Normal grid refill
7. Group TP Check         → Normal basket closure
```

### **Trend Filter Integration**:

**Phase 1.1 (Trend Filter)** is used for:
1. Block opening new counter-trend baskets (existing)
2. **NEW**: Block reseeding counter-trend baskets after SL

**Synergy**: Same trend detection logic serves dual purpose!

---

## 📊 **Expected Results**

### **Before Phase 12** (Current - RESEED_IMMEDIATE):
```
Test Period: 10 days XAUUSD strong trend
Result: -$2,494 loss (-22.8%), 36% DD
Cause: SELL SL → Reseed SELL → SL loop → Catastrophic losses
```

### **After Phase 12** (RESEED_TREND_AWARE):
```
Test Period: Same 10 days XAUUSD strong trend
Expected Result: -$500 to $0 (-5% to 0%), <15% DD

Breakdown:
- SELL basket SL: -$112 (one-time loss)
- SELL reseed blocked: $0 (no repeated losses)
- BUY basket profits: +$200-300 (with-trend trading)
- Net: Small loss or break-even

Range period recovery: +$500-1000 (both baskets trade normally)
Overall: Profitable across mixed market conditions
```

### **Expected Improvement**:
- ✅ Max DD: 36% → **<15%** (60% improvement)
- ✅ Net Loss: -22.8% → **0% to +5%** (profitable)
- ✅ SL Loop: Prevented (no counter-trend reseed)
- ✅ Range Profits: Maintained (both baskets work in range)

---

## 🧪 **Testing Plan**

### **Scenario 1: Strong Uptrend (XAUUSD 2000 → 2500)**
**Expected**:
- SELL basket hits SL at 2425 (375 pips)
- Trend filter: UPTREND detected
- SELL reseed BLOCKED
- BUY basket continues trading → Profits from trend
- After trend ends: SELL reseed allowed

**Verify**:
- Log: "SELL reseed BLOCKED: Strong uptrend detected"
- No repeated SELL SL hits
- BUY basket profitable

### **Scenario 2: Range Market (EURUSD 1.0800 - 1.0900)**
**Expected**:
- Both baskets trade normally
- Trend filter: NO TREND
- If Basket SL hits (rare in range): Reseed allowed immediately
- Normal grid operation

**Verify**:
- Log: "Reseed ALLOWED: No strong trend"
- Both baskets active
- Profitable in range

### **Scenario 3: Mixed Conditions (Trend + Range)**
**Expected**:
- Trend period: One basket blocked, one continues
- Range period: Both baskets active
- Overall: Positive net profit

**Success Criteria**:
- ✅ Range profits > Trend losses
- ✅ Max DD < 20%
- ✅ No SL loops
- ✅ Net profit positive

---

## ⚠️ **Potential Side Effects**

### **1. One Basket Trading Only During Trends**:
- **Effect**: Only with-trend basket trades (lower activity)
- **Mitigation**: Acceptable trade-off (prevents losses)
- **Benefit**: Focus on profitable direction

### **2. Cooldown May Miss Opportunities**:
- **Effect**: 30-minute cooldown may miss range entry
- **Mitigation**: Trend filter checks on every Update() → Will reseed when range starts
- **Benefit**: Prevents premature re-entry

### **3. Depends on Trend Filter Accuracy**:
- **Effect**: False trend signals may block profitable reseed
- **Mitigation**: Use proven indicators (EMA 200 + ADX 30)
- **Benefit**: Better safe than sorry (prevent large losses)

---

## 📁 **Files to Modify**

1. ✅ **`src/core/Types.mqh`**: Add EReseedMode enum
2. ✅ **`src/core/Params.mqh`**: Add Phase 12 parameters
3. ✅ **`src/core/LifecycleController.mqh`**: Implement HandleBasketSLClosure()
4. ✅ **`src/ea/RecoveryGridDirection_v3.mq5`**: Add input parameters
5. ✅ **`presets/EURUSD-TESTED.set`**: Add Phase 12 settings
6. ✅ **`presets/GBPUSD-TESTED.set`**: Add Phase 12 settings
7. ✅ **`presets/XAUUSD-TESTED.set`**: Add Phase 12 settings

---

## ✅ **Completion Checklist**

- [ ] Add EReseedMode enum to Types.mqh
- [ ] Add Phase 12 parameters to Params.mqh
- [ ] Add member variables to LifecycleController.mqh
- [ ] Implement HandleBasketSLClosure() method
- [ ] Update LifecycleController.Update() to call HandleBasketSLClosure()
- [ ] Add input parameters to RecoveryGridDirection_v3.mq5
- [ ] Update EURUSD preset with Phase 12 settings
- [ ] Update GBPUSD preset with Phase 12 settings
- [ ] Update XAUUSD preset with Phase 12 settings
- [ ] Compile and test: No errors
- [ ] Backtest: Strong trend scenario (XAUUSD)
- [ ] Backtest: Range scenario (EURUSD)
- [ ] Backtest: Mixed scenario (3 months)
- [ ] Verify: No SL loops
- [ ] Verify: With-trend basket continues
- [ ] Verify: Counter-trend reseed blocked
- [ ] Demo testing: 2 weeks minimum
- [ ] Production deployment decision

---

## 🎉 **Summary**

**Phase 12: Trend-Aware Reseed** solves critical issue discovered in Basket SL testing:

**Problem**: Grid trading fails in strong trends
- IMMEDIATE reseed → SL loop → Catastrophic losses (-22.8%)
- COOLDOWN reseed → No trading → Miss opportunities (-1.04%)

**Solution**: Trend-aware reseed direction filtering
- Block counter-trend reseed after Basket SL
- Allow with-trend basket to continue profiting
- Resume both baskets when range returns

**Expected Impact**:
- Max DD: 36% → **<15%** (60% improvement)
- Net Result: -22.8% → **0% to +5%** (profitable)
- Prevents SL loops while maintaining range profitability

**Key Innovation**: Uses existing Trend Filter (Phase 1.1) for dual purpose:
1. Block opening counter-trend baskets (existing)
2. **Block reseeding counter-trend baskets** (new)

---

**🤖 Generated with Claude Code**
**Author**: AI Assistant
**Date**: 2025-01-10
**Priority**: 🔴 HIGH
**Status**: 🚧 PLANNED (Awaiting User Approval for Implementation)
