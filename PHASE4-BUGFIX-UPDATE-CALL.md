# 🐛 Phase 4 Bug Fix: RefillBatch() Not Called

**Date**: 2025-10-08  
**Issue**: Lazy grid never expands because `RefillBatch()` not called in `Update()`

---

## 🔍 Problem Analysis

### User Report:
> "luôn luôn là 2 cái market và limit, ko thấy tự refill thêm grid thứ 3 trong 1 basket"

### Root Cause:

**Code in `GridBasket.mqh` line 824**:
```cpp
// Dynamic grid refill
if(m_params.grid_dynamic_enabled)  // ← ONLY checks dynamic grid!
{
   // Update pending count
   ...
   RefillBatch();  // ← Never called for lazy grid!
}
```

**Preset Configuration**:
```
InpDynamicGrid=false           ← Dynamic grid DISABLED
InpLazyGridEnabled=true        ← Lazy grid ENABLED
```

**Result**: 
- `grid_dynamic_enabled = false`
- Condition fails → `RefillBatch()` never called
- Lazy grid can't expand!

---

## 📊 Log Evidence

```
Line 96:  [RGDv2][XAUUSD][BUY][PRI] Initial grid seeded (lazy) levels=2 pending=1
Line 156: order [#3 buy limit 0.02 XAUUSD at 2030.140] triggered  ← Level 1 fills
Line 160: [RGDv2][XAUUSD][SELL][PRI] Basket closed: GroupTP      ← Closes immediately
Line 174: [RGDv2][XAUUSD][SELL][PRI] DG/SEED ...                 ← Reseed from scratch
```

**No expansion messages** between line 156-160!  
**Expected**: `"Lazy grid expanded to level 2"`

---

## ✅ Fix Applied

### Changed Line 824:

**Before**:
```cpp
if(m_params.grid_dynamic_enabled)
{
   // Update pending count
   ...
   RefillBatch();
}
```

**After**:
```cpp
if(m_params.grid_dynamic_enabled || m_params.lazy_grid_enabled)
{
   // Update pending count by direction
   ...
   RefillBatch();  // This will call ExpandOneLevel() for lazy grid
}
```

### Why This Works:

1. **Lazy grid enabled** → condition passes
2. **Pending count updated** each tick
3. **`RefillBatch()` called** each tick
4. **Inside `RefillBatch()`** (line 739-746):
   ```cpp
   if(m_params.lazy_grid_enabled)
   {
      if(ShouldExpandGrid())
         ExpandOneLevel();
      return;
   }
   ```
5. **Guards check** → expand if safe

---

## 🧪 Expected Behavior After Fix

### Seed Phase:
```
[RGDv2][XAUUSD][BUY][PRI] Initial grid seeded (lazy) levels=2 pending=1
```
**State**: Level 0 (market filled), Level 1 (pending)

### Expansion Phase 1:
```
order [#3 buy limit] triggered  ← Level 1 fills
[RGDv2][XAUUSD][BUY][PRI] DG/EXPAND dir=BUY level=2 price=2029.890 pendings=1
[RGDv2][XAUUSD][BUY][PRI] Lazy grid expanded to level 2, pending=1/5
```
**State**: Level 0-1 (filled), Level 2 (pending)

### Expansion Phase 2:
```
order [#X buy limit] triggered  ← Level 2 fills
[RGDv2][XAUUSD][BUY][PRI] DG/EXPAND dir=BUY level=3 price=2029.640 pendings=1
[RGDv2][XAUUSD][BUY][PRI] Lazy grid expanded to level 3, pending=1/5
```
**State**: Level 0-2 (filled), Level 3 (pending)

### Continues Until:
- Max levels reached: `"Expansion blocked: GRID_FULL"`
- DD too deep: `"Expansion blocked: DD too deep -21.0% < -20.0%"`
- Distance exceeded: `"Expansion blocked: Distance 520 pips > 500 max"`
- OR basket hits TP and closes

---

## 🎯 Testing Checklist

### Test 1: Basic Expansion ✅ To Test
**Setup**: Run with fixed code  
**Expected**: 
- ✅ Seed 2 orders
- ✅ Expand to level 2 when level 1 fills
- ✅ Expand to level 3 when level 2 fills
- ✅ Continue until GRID_FULL or TP

### Test 2: Guard Verification ✅ To Test
**Setup**: Let grid expand to level 4  
**Expected**: 
- ✅ "Expansion blocked: GRID_FULL" at level 4
- ❌ No level 5 placed

### Test 3: DD Guard ✅ To Test
**Setup**: Price moves against, DD grows  
**Expected**: 
- ✅ Expansion stops if DD < -20%
- ✅ Log: "Expansion blocked: DD too deep"

---

## 📝 Changes Summary

**File**: `src/core/GridBasket.mqh`  
**Line**: 824  
**Change**: Added `|| m_params.lazy_grid_enabled` to condition  
**Impact**: `RefillBatch()` now called for lazy grid, enabling expansion

---

## 🚀 Ready for Re-Test

**Action Items**:
1. ✅ Fix applied
2. ⏳ Compile EA
3. ⏳ Run backtest with `TEST-Phase4-SmartExpansion.set`
4. ⏳ Verify expansion messages in log
5. ⏳ Confirm guards working

---

**Status**: 🟢 Fixed - Ready for Testing  
**Next**: Run backtest to verify expansion works correctly

