# Phase 11: Basket Stop Loss (Per-Basket Hard SL)

**Date**: 2025-01-10
**Status**: 🚧 IN PROGRESS
**Branch**: feature/lazy-grid-fill-smart-trap-detection-2

---

## 🎯 **Problem Statement**

**User Feedback**: "hay là phải làm tiếp phase Basket Stop Loss cho SL cụ thể lun để drop sớm giống Quick Exit Mode mode nhưng có SL basket"

### **Current Situation**:
- **Quick Exit (Phase 7-8)**: Works well for trapped baskets with negative TP exit
- **Gap Management (Phase 9-10)**: Handles medium/large gaps with bridge/close-far
- **Missing Safety Net**: No hard stop loss when basket loss exceeds acceptable limit

### **Real-World Scenario** (from backtest):
```
SELL basket opened at 2048-2049 (March 19)
Held underwater until test end at 2245 (March 28)
Unrealized loss: ~196 pips per position
Total exposure: 0.03 lot SELL
Result: Basket never closed (no hard SL)
```

**Risk**: If market trends strongly, basket can accumulate large unrealized loss without exit mechanism.

---

## ✅ **Solution: Per-Basket Stop Loss**

### **Concept**:
Add a **hard stop loss per basket** that triggers when basket floating loss exceeds threshold:
- Independent from Quick Exit (QE handles traps, SL handles runaway losses)
- Per-basket, not global (BUY and SELL each have their own SL)
- Closes entire basket when SL hit
- Auto-reseeds after SL closure (optional)

### **Trigger Conditions** (any of these):
1. **Fixed USD Loss**: `basket_pnl <= -InpBasketSL_USD`
2. **Percentage of Balance**: `basket_pnl <= -(account_balance × InpBasketSL_Percent)`
3. **Percentage of Target**: `basket_pnl <= -(target_cycle_usd × InpBasketSL_TargetMultiplier)`

**Priority**: Check all conditions, trigger SL if ANY condition met.

---

## 📐 **Design Specification**

### **1. New Parameters** (add to `Params.mqh`):
```cpp
// Phase 11: Basket Stop Loss
bool   basket_sl_enabled;           // Enable basket SL (default: false - OFF by default)
double basket_sl_usd;               // Fixed USD loss (e.g., -100.0)
double basket_sl_percent;           // % of balance (e.g., 0.05 = 5%)
double basket_sl_target_multiplier; // Multiple of target (e.g., 3.0 = 3× target loss)
bool   basket_sl_reseed;            // Auto-reseed after SL hit (default: true)
int    basket_sl_cooldown_min;      // Cooldown before reseed (default: 10 min)
```

### **2. New Input Parameters** (add to `RecoveryGridDirection_v3.mq5`):
```cpp
input group             "=== Phase 11: Basket Stop Loss ==="
input bool              InpBasketSL_Enabled         = false;   // Enable Basket SL (OFF by default - TEST FIRST!)
input double            InpBasketSL_USD             = -100.0;   // Fixed USD loss threshold
input double            InpBasketSL_Percent         = 0.05;     // % of balance (5%)
input double            InpBasketSL_TargetMultiplier = 3.0;     // Multiple of target (3×)
input bool              InpBasketSL_Reseed          = true;     // Auto-reseed after SL
input int               InpBasketSL_CooldownMin     = 10;       // Cooldown before reseed (minutes)
```

### **3. Implementation in `GridBasket.mqh`**:

#### **A. Add Member Variables**:
```cpp
private:
   datetime m_sl_last_check;        // Last SL check time
   datetime m_sl_cooldown_until;    // Cooldown end time after SL hit
```

#### **B. Add SL Check Method**:
```cpp
bool CheckBasketSL()
{
   if(!m_params.basket_sl_enabled)
      return false;  // SL disabled

   // Cooldown check
   datetime now = TimeCurrent();
   if(now < m_sl_cooldown_until)
      return false;  // Still in cooldown

   // Rate limit: check every 5 seconds
   if(now - m_sl_last_check < 5)
      return false;
   m_sl_last_check = now;

   // Get current floating PnL
   RefreshState();
   double pnl = GetFloatPnL();

   // Get account balance for % calculation
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   // Condition 1: Fixed USD loss
   bool trigger_fixed = (pnl <= m_params.basket_sl_usd);

   // Condition 2: % of balance
   double threshold_percent = -(balance * m_params.basket_sl_percent);
   bool trigger_percent = (pnl <= threshold_percent);

   // Condition 3: Multiple of target
   double threshold_target = -(m_params.target_cycle_usd * m_params.basket_sl_target_multiplier);
   bool trigger_target = (pnl <= threshold_target);

   // Trigger if ANY condition met
   if(trigger_fixed || trigger_percent || trigger_target)
   {
      string reason = "";
      if(trigger_fixed) reason += StringFormat("USD=%.2f<=%.2f ", pnl, m_params.basket_sl_usd);
      if(trigger_percent) reason += StringFormat("%%=%.2f<=%.2f ", pnl, threshold_percent);
      if(trigger_target) reason += StringFormat("Target=%.2f<=%.2f ", pnl, threshold_target);

      if(m_log != NULL)
         m_log.Event(Tag(), StringFormat("⚠️  BASKET SL TRIGGERED! Loss=%.2f | Reasons: %s",
                                        pnl, reason));

      return true;
   }

   return false;
}
```

#### **C. Add SL Execution Method**:
```cpp
bool ExecuteBasketSL(string &out_reason)
{
   out_reason = "BasketSL";

   // Close all positions
   int closed = CloseAllPositions("BasketSL");

   if(closed == 0)
   {
      if(m_log != NULL)
         m_log.Event(Tag(), "[ERROR] Basket SL: Failed to close any positions!");
      return false;
   }

   if(m_log != NULL)
      m_log.Event(Tag(), StringFormat("✅ BASKET SL: Closed %d positions at loss", closed));

   // Set cooldown
   if(m_params.basket_sl_cooldown_min > 0)
   {
      m_sl_cooldown_until = TimeCurrent() + (m_params.basket_sl_cooldown_min * 60);
      if(m_log != NULL)
         m_log.Event(Tag(), StringFormat("Basket SL cooldown: %d minutes",
                                        m_params.basket_sl_cooldown_min));
   }

   return true;
}
```

#### **D. Integrate into `Update()` Method**:
```cpp
void Update()
{
   // ... existing code ...

   // Phase 11: Check Basket SL BEFORE Quick Exit
   if(CheckBasketSL())
   {
      string reason;
      if(ExecuteBasketSL(reason))
      {
         // Optionally reseed after SL
         if(m_params.basket_sl_reseed)
         {
            if(m_log != NULL)
               m_log.Event(Tag(), "Basket SL: Auto-reseeding...");
            // Reseed will happen in next Update() cycle
         }
         return;  // Exit after SL execution
      }
   }

   // ... rest of existing code (QE, gap management, etc.) ...
}
```

---

## 🎛️ **Configuration Examples**

### **Conservative (Recommended for Testing)**:
```cpp
InpBasketSL_Enabled         = true
InpBasketSL_USD             = -100.0   // Hard limit: $100 loss
InpBasketSL_Percent         = 0.05     // 5% of balance
InpBasketSL_TargetMultiplier = 3.0     // 3× target loss
InpBasketSL_Reseed          = true     // Auto-reseed
InpBasketSL_CooldownMin     = 10       // 10 min cooldown
```

**Example (EURUSD with $1000 balance, $6 target)**:
- Fixed: Trigger at -$100 loss
- Percent: Trigger at -$50 loss (5% × $1000)
- Target: Trigger at -$18 loss (3× $6)
- **Effective**: Whichever hits first → -$18 (most sensitive)

### **Aggressive (Tighter SL)**:
```cpp
InpBasketSL_USD             = -50.0    // Tighter hard limit
InpBasketSL_Percent         = 0.03     // 3% of balance
InpBasketSL_TargetMultiplier = 2.0     // 2× target loss
```

### **Loose (Higher tolerance)**:
```cpp
InpBasketSL_USD             = -200.0   // Higher hard limit
InpBasketSL_Percent         = 0.10     // 10% of balance
InpBasketSL_TargetMultiplier = 5.0     // 5× target loss
```

---

## 🔄 **Interaction with Existing Features**

### **Priority Order** (top = highest priority):
1. **Basket Stop Loss** (Phase 11) - Hard limit, highest priority
2. **Quick Exit** (Phase 7-8) - Trap escape with negative TP
3. **Gap Management CloseFar** (Phase 10) - Large gap handling
4. **Gap Management Bridge** (Phase 9) - Medium gap filling
5. **Lazy Grid Expansion** (Phase 1) - Normal grid refill

**Rationale**: Basket SL is checked FIRST to prevent runaway losses before any other logic.

### **When to Use Each**:
| Feature | Trigger | Action | Use Case |
|---------|---------|--------|----------|
| Basket SL | Loss > threshold | Close entire basket | Prevent catastrophic loss |
| Quick Exit | Trapped basket | Close at negative TP | Escape directional trap |
| CloseFar | Gap > 5× spacing | Close far + reseed | Large gap recovery |
| Bridge | Gap 1.5-4× spacing | Fill gap with orders | Medium gap filling |

---

## ⚠️ **Potential Side Effects**

### **1. May Close Basket Too Early**:
- **Risk**: SL triggers before basket has chance to recover
- **Mitigation**: Use conservative thresholds (3-5× target)
- **Testing**: Monitor how often SL triggers vs QE triggers

### **2. Reseed Immediately After SL**:
- **Risk**: Re-enter same losing direction
- **Mitigation**: Use cooldown period (10-30 min) before reseed
- **Alternative**: Disable reseed, require manual intervention

### **3. Conflicts with Quick Exit**:
- **Risk**: Both SL and QE may trigger on same basket
- **Mitigation**: Check Basket SL BEFORE Quick Exit in Update() order
- **Priority**: Basket SL > Quick Exit (SL is hard limit)

---

## 🧪 **Testing Plan**

### **Scenario 1: Strong Trend (XAUUSD)**
- **Setup**: Strong uptrend, SELL basket underwater
- **Expected**: Basket SL triggers at -3× target (e.g., -$45 for $15 target)
- **Verify**:
  - Basket closes at SL
  - Cooldown prevents immediate reseed
  - Log shows SL trigger reason

### **Scenario 2: Range Market (EURUSD)**
- **Setup**: Ranging market, baskets oscillate
- **Expected**: Basket SL does NOT trigger (losses stay within limits)
- **Verify**: Only GroupTP closures occur

### **Scenario 3: Multiple SL Triggers**
- **Setup**: Volatile market, multiple SL hits
- **Expected**: Cooldown prevents rapid re-entries
- **Verify**: 10-minute cooldown enforced between SL triggers

---

## 📊 **Expected Benefits**

1. ✅ **Hard Safety Net**: Prevents runaway losses beyond acceptable threshold
2. ✅ **Complement to Quick Exit**: QE handles traps, SL handles catastrophic scenarios
3. ✅ **Per-Basket Control**: Independent SL for BUY and SELL baskets
4. ✅ **Configurable**: Multiple trigger conditions (USD, %, target multiple)
5. ✅ **Auto-Recovery**: Optional reseed after SL with cooldown

---

## 📁 **Files to Modify**

1. **`src/core/Params.mqh`**: Add Phase 11 parameters (6 new fields)
2. **`src/core/GridBasket.mqh`**: Implement SL logic (3 new methods)
3. **`src/ea/RecoveryGridDirection_v3.mq5`**: Add input parameters (6 new inputs)
4. **`presets/EURUSD-TESTED.set`**: Add Basket SL settings
5. **`presets/GBPUSD-TESTED.set`**: Add Basket SL settings
6. **`presets/XAUUSD-TESTED.set`**: Add Basket SL settings (higher thresholds for volatility)

---

## ✅ **Completion Criteria**

- [ ] Phase 11 parameters added to Params.mqh
- [ ] CheckBasketSL() method implemented in GridBasket.mqh
- [ ] ExecuteBasketSL() method implemented in GridBasket.mqh
- [ ] Integrated into GridBasket.Update() (highest priority)
- [ ] Input parameters added to RecoveryGridDirection_v3.mq5
- [ ] All 3 presets updated with Basket SL settings
- [ ] Documentation created (this file)
- [ ] Code compiles without errors
- [ ] User testing on XAUUSD with strong trend scenario

---

## 🎉 **Summary**

**Phase 11: Basket Stop Loss** adds a **hard safety net** to prevent catastrophic losses when baskets move too far underwater.

**Key Features**:
- Multiple trigger conditions (USD, %, target multiple)
- Per-basket independent SL
- Auto-reseed with cooldown
- Highest priority (checked before QE/Gap Management)
- OFF by default (requires explicit opt-in)

**Use Case**: When market trends strongly against basket direction, SL closes basket at acceptable loss before it becomes catastrophic (like SELL basket at -196 pips in backtest).

**Trade-off**: May close baskets that could eventually recover → Use conservative thresholds!

---

**🤖 Generated with Claude Code**
**Author**: AI Assistant
**Date**: 2025-01-10
**Branch**: feature/lazy-grid-fill-smart-trap-detection-2
