# Bug Fix: Duplicate Positions on Timeframe Switch

**Date**: 2025-10-06
**Status**: ✅ FIXED
**Branch**: feature/tf-switch-preservation

---

## Problem

Demo account showing **duplicate lot sizes** (16 positions, only 6 unique lot sizes):
- 0.04 lot × 3 positions (DUPLICATE!)
- 0.08 lot × 3 positions (DUPLICATE!)
- 0.16 lot × 3 positions (DUPLICATE!)
- 0.32 lot × 3 positions (DUPLICATE!)

Expected: Each grid level should have ONLY ONE position with unique lot size.

---

## Root Cause

**Timeframe Switch Reinitializes Grid Without Position Recovery**

### What Happens:

1. User switches timeframe (M1 → M5 → H1, etc.)
2. MT5 calls `OnDeinit()` → `OnInit()` again
3. `LifecycleController::Init()` creates NEW baskets
4. Baskets call `PlaceInitialOrders()` → places grid again
5. **Existing positions NOT detected** → Duplicate grid at same price levels
6. Repeat 3 times → **3× duplicate positions per level**

### Log Evidence:

```
18:19:43 - EA canceling ALL pending orders (0.32 × 3, 0.16 × 3, 0.08 × 3...)
18:19:43 - EA placing NEW grid (0.01 seed, 0.02, 0.04, 0.08, 0.16, 0.32)
```

**Key Insight**: Pending orders canceled, but **filled positions left open** → accumulate duplicates.

---

## Solution

**Port Timeframe Preservation Logic from Old Project**

### Implementation:

1. **Check existing positions on Init()**
   ```cpp
   bool HasExistingPositions() const {
      // Scan PositionsTotal() for positions with our magic number
      // Return true if any found
   }
   ```

2. **Reconstruct mode vs Normal mode**
   ```cpp
   bool Init() {
      bool has_positions = HasExistingPositions();
      
      if (has_positions) {
         // Reconstruct mode: Create baskets WITHOUT seeding
         m_buy = new CGridBasket(...);
         m_sell = new CGridBasket(...);
         
         // Mark active without placing new orders
         m_buy.SetActive(true);
         m_sell.SetActive(true);
         
         // Let baskets discover their positions via Update()
         m_buy.Update();
         m_sell.Update();
      } else {
         // Normal mode: Seed new grid as usual
         m_buy.Init(ask);
         m_sell.Init(bid);
      }
   }
   ```

3. **Always enabled** (no input parameter needed)
   ```cpp
   g_params.preserve_on_tf_switch = true;  // Hardcoded
   ```

---

## Files Modified

### 1. `src/core/Params.mqh`
- Added: `bool preserve_on_tf_switch`

### 2. `src/core/GridBasket.mqh`
- Added: `void SetActive(const bool active)`

### 3. `src/core/LifecycleController.mqh`
- Added: `bool HasExistingPositions() const`
- Modified: `bool Init()` - Added TF preservation logic

### 4. `src/ea/RecoveryGridDirection_v3.mq5`
- Modified: `BuildParams()` - Set `preserve_on_tf_switch = true`

---

## Testing

### Test Scenario:
1. Start EA on M1 timeframe
2. Let EA place 5 grid levels
3. Switch to M5 timeframe
4. Check positions count

### Expected Result:
- **Before fix**: +5 duplicate positions (total 10)
- **After fix**: Same 5 positions, no duplicates ✅

### Log Output:
```
[RGDv2][EURUSD][LC] [TF-Preserve] Existing positions detected, reconstructing baskets
[RGDv2][EURUSD][LC] [TF-Preserve] Reconstruction complete: BUY:Active SELL:Active
```

---

## Impact

### Before Fix:
- Timeframe switch → duplicate grid
- 3 switches → 3× position size
- Risk multiplied unintentionally
- **Production bug** affecting live trading

### After Fix:
- Timeframe switch → positions preserved
- Grid reconstructs from existing positions
- No duplicate orders
- **Safe for live trading** ✅

---

## Related Issues

- Multi-job system abandoned (worse results than stable)
- Strong trend protection solutions documented in `idea/STRONG_TREND_SOLUTIONS.md`

---

## Credits

Solution ported from `/Users/anvudinh/Desktop/hoiio/trading/recovery-grid/` (old project) which already had `preserve_on_tf_switch` feature implemented.

---

**Status**: Ready for PR to master ✅
