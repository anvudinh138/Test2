# 🚀 Phase 4: Lazy Grid v2 - Smart Expansion

**Goal**: Nở level sau fill và qua guards (DD, distance, max-levels, counter-trend)  
**Status**: 🟡 In Progress

---

## 📋 Requirements (from `15-phase.md`)

**P4 — Lazy Grid v2**: Chỉ nở khi fill + Guards

**Scope**:
- `OnLevelFilled()` → `ShouldExpandGrid()`
- Expansion guards:
  - Counter-trend check
  - DD threshold (`InpMaxDDForExpansion`)
  - Max levels limit (`InpGridLevels`)
  - Distance check (`InpMaxLevelDistance`)
- Price validation: `IsPriceReasonable()` (chặn pending sai phía/xa quá)
- State tracking: `ACTIVE` / `HALTED` / `GRID_FULL`

**Deliverables**:
- State transitions logged
- Log expansion reason/blocking reason
- Preset Uptrend 300p: SELL stops expanding early

**Exit Criteria**:
- Grid expands 1 level at a time when conditions met
- Guards properly block unsafe expansion
- State changes logged clearly

---

## 🎯 Implementation Plan

### 1. Review Current State ✅

**What we have** (from Phase 3 v1):
```cpp
struct SGridState
{
   int      lastFilledLevel;
   double   lastFilledPrice;
   datetime lastFilledTime;
   int      currentMaxLevel;
   int      pendingCount;
};
```

**Current behavior**:
- Seeds 1 market + 1 pending (level 0-1)
- `RefillBatch()` returns early if lazy grid enabled
- No expansion logic

### 2. Design Expansion Logic

#### Core Flow:
```
OnTick() / Update()
  → Detect level filled
  → ShouldExpandGrid() checks guards
     ✓ DD < InpMaxDDForExpansion
     ✓ currentMaxLevel < InpGridLevels - 1
     ✓ Price distance < InpMaxLevelDistance
     ✓ Price is reasonable (direction check)
  → If OK: ExpandOneLevel()
  → Update SGridState
```

#### Expansion Trigger:
- When a pending order fills
- Check if we should place the NEXT level

#### Guards (Priority Order):
1. **Max Levels**: `currentMaxLevel >= InpGridLevels - 1` → GRID_FULL
2. **DD Threshold**: Basket DD% < `InpMaxDDForExpansion` (-20%) → HALTED
3. **Distance Check**: Next level price > `InpMaxLevelDistance` pips from seed → HALTED
4. **Counter-trend**: Price moving wrong direction (optional, can defer to later)

---

## 🔧 Implementation Steps

### Step 1: Add Helper Methods to `GridBasket`

#### A. `ShouldExpandGrid()` - Check all guards
```cpp
bool ShouldExpandGrid()
{
   // Guard 1: Max levels reached?
   if(m_grid_state.currentMaxLevel >= m_max_levels - 1)
      return false;
   
   // Guard 2: DD too deep?
   double dd_pct = (m_basket_pl / AccountBalance()) * 100.0;
   if(dd_pct < m_params.lazy_max_dd_expansion)
      return false;
   
   // Guard 3: Distance too far?
   double next_level_price = CalculateNextLevelPrice();
   double distance_pips = PriceToDistance(next_level_price, m_levels[0].price);
   if(distance_pips > m_params.lazy_max_level_distance)
      return false;
   
   // Guard 4: Price reasonable? (direction check)
   if(!IsPriceReasonable(next_level_price))
      return false;
   
   return true;
}
```

#### B. `ExpandOneLevel()` - Place next pending order
```cpp
void ExpandOneLevel()
{
   int next_level = m_grid_state.currentMaxLevel + 1;
   
   double spacing_px = m_spacing.ToPrice(m_initial_spacing_pips);
   double anchor = m_levels[0].price;
   
   double price = anchor;
   if(m_direction == DIR_BUY)
      price -= (spacing_px * next_level);
   else
      price += (spacing_px * next_level);
   
   double lot = LevelLot(next_level);
   
   ulong ticket = (m_direction == DIR_BUY) 
      ? m_executor.Limit(DIR_BUY, price, lot, "RGDv2_LazyExpand")
      : m_executor.Limit(DIR_SELL, price, lot, "RGDv2_LazyExpand");
   
   if(ticket > 0)
   {
      m_levels[next_level].price = price;
      m_levels[next_level].lot = lot;
      m_levels[next_level].ticket = ticket;
      m_levels[next_level].filled = false;
      
      m_levels_placed++;
      m_pending_count++;
      m_grid_state.currentMaxLevel = next_level;
      m_grid_state.pendingCount = m_pending_count;
      
      LogDynamic("EXPAND", next_level, price);
      
      if(m_log != NULL)
         m_log.Event(Tag(), StringFormat("Lazy grid expanded to level %d, pending=%d", 
                                         next_level, m_pending_count));
   }
}
```

#### C. `IsPriceReasonable()` - Direction validation
```cpp
bool IsPriceReasonable(double price)
{
   double current = SymbolInfoDouble(m_symbol, 
                    (m_direction == DIR_BUY) ? SYMBOL_ASK : SYMBOL_BID);
   
   // BUY: pending must be BELOW current
   if(m_direction == DIR_BUY && price >= current)
      return false;
   
   // SELL: pending must be ABOVE current
   if(m_direction == DIR_SELL && price <= current)
      return false;
   
   return true;
}
```

#### D. `CalculateNextLevelPrice()` - Helper
```cpp
double CalculateNextLevelPrice()
{
   int next_level = m_grid_state.currentMaxLevel + 1;
   double spacing_px = m_spacing.ToPrice(m_initial_spacing_pips);
   double anchor = m_levels[0].price;
   
   if(m_direction == DIR_BUY)
      return anchor - (spacing_px * next_level);
   else
      return anchor + (spacing_px * next_level);
}
```

#### E. `PriceToDistance()` - Convert price to pips
```cpp
double PriceToDistance(double price1, double price2)
{
   double diff = MathAbs(price1 - price2);
   return diff / SymbolInfoDouble(m_symbol, SYMBOL_POINT) / 10.0;
}
```

### Step 2: Update `RefillBatch()` for Lazy Grid

**Current** (blocks all refill):
```cpp
void RefillBatch()
{
   if(m_params.lazy_grid_enabled)
      return;  // Phase 3 v1: No expansion
   ...
}
```

**New** (smart expansion):
```cpp
void RefillBatch()
{
   if(m_params.lazy_grid_enabled)
   {
      // Phase 4: Check if we should expand
      if(ShouldExpandGrid())
         ExpandOneLevel();
      return;
   }
   
   // Old dynamic grid logic
   if(!m_params.grid_dynamic_enabled)
      return;
   ...
}
```

### Step 3: Trigger Expansion on Level Fill

**Option A**: Check in `Update()` after position tracking
```cpp
void Update()
{
   // ... existing position/pending tracking ...
   
   // Phase 4: Check for lazy grid expansion
   if(m_params.lazy_grid_enabled && m_pending_count < m_params.grid_warm_levels)
   {
      RefillBatch();  // This will call ExpandOneLevel if conditions OK
   }
}
```

**Option B**: Explicit check after detecting fill
```cpp
// In Update(), after detecting a pending became position
if(m_params.lazy_grid_enabled)
{
   m_grid_state.lastFilledLevel = level_index;
   m_grid_state.lastFilledPrice = m_levels[level_index].price;
   m_grid_state.lastFilledTime = TimeCurrent();
   
   // Try to expand
   RefillBatch();
}
```

### Step 4: Add State Logging

**In `ShouldExpandGrid()`**:
```cpp
if(m_grid_state.currentMaxLevel >= m_max_levels - 1)
{
   if(m_log != NULL)
      m_log.Event(Tag(), "Expansion blocked: GRID_FULL");
   return false;
}

if(dd_pct < m_params.lazy_max_dd_expansion)
{
   if(m_log != NULL)
      m_log.Event(Tag(), StringFormat("Expansion blocked: DD too deep %.2f%% < %.2f%%",
                                      dd_pct, m_params.lazy_max_dd_expansion));
   return false;
}
// ... etc
```

---

## 🧪 Testing Strategy

### Test 1: Basic Expansion
**Setup**: Lazy grid enabled, price moves slowly against position
**Expected**:
- Seeds level 0-1
- When level 1 fills → expands to level 2
- When level 2 fills → expands to level 3
- Continues until max levels reached

### Test 2: DD Guard
**Setup**: Set `InpMaxDDForExpansion=-10%`, let DD grow
**Expected**:
- Expansion stops when DD < -10%
- Log: "Expansion blocked: DD too deep"

### Test 3: Distance Guard
**Setup**: Set `InpMaxLevelDistance=100`, large spacing
**Expected**:
- Expansion stops when next level > 100 pips from seed
- Log: "Expansion blocked: Distance too far"

### Test 4: Max Levels
**Setup**: `InpGridLevels=5`
**Expected**:
- Stops at level 4 (0-indexed = 5 levels total)
- Log: "Expansion blocked: GRID_FULL"

### Test 5: Price Validation
**Setup**: Price moves back toward profitable
**Expected**:
- `IsPriceReasonable()` rejects pending on wrong side
- No invalid orders placed

---

## 📊 Success Criteria

- ✅ Grid expands 1 level at a time
- ✅ Expansion stops at each guard condition
- ✅ All guards logged with reason
- ✅ No invalid prices (BUY above market, SELL below market)
- ✅ `SGridState` updated correctly
- ✅ Works for both BUY and SELL baskets
- ✅ Preset Uptrend 300p: SELL basket halts expansion early

---

## 🎯 Phase 4 Deliverables

1. ✅ `ShouldExpandGrid()` method
2. ✅ `ExpandOneLevel()` method
3. ✅ `IsPriceReasonable()` helper
4. ✅ Updated `RefillBatch()` with smart logic
5. ✅ Guard logging (DD, distance, max levels)
6. ✅ Test preset for expansion testing
7. ✅ Documentation

---

## 🚀 Let's Start!

**First Step**: Implement helper methods in `GridBasket.mqh`

Ready to code? 🔥

