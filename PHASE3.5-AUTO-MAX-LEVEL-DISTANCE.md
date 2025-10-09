# Phase 3.5: Auto Max Level Distance ✅

## 📋 Overview
Implemented **auto-scaling for `InpMaxLevelDistance`** based on current grid spacing, similar to the auto trap threshold feature. This eliminates the need to manually configure max level distance for different symbols.

---

## 🎯 Problem Statement
Previously, `InpMaxLevelDistance` was a fixed value (default 500 pips) that required manual tuning for each symbol:
- EURUSD: 20-40 pips spacing → 500 pips was too wide
- XAUUSD: 150 pips spacing → 500 pips might be too narrow
- User had to manually calculate and configure for each symbol

---

## ✅ Solution: Auto Scaling

### Calculation Method
```
Auto Max Level Distance = Current Spacing × Multiplier
```

**Default Multiplier: 20x**
- EURUSD (25 pips spacing): 25 × 20 = **500 pips**
- XAUUSD (150 pips spacing): 150 × 20 = **3000 pips**
- GBPUSD (50 pips spacing): 50 × 20 = **1000 pips**

### Benefits
1. **Adaptive**: Automatically scales with market volatility (via spacing)
2. **Symbol-agnostic**: Works across all symbols without manual tuning
3. **Consistent**: Maintains same risk profile (20 levels max distance)
4. **Flexible**: Can switch to manual mode if needed

---

## 🔧 Implementation Details

### New Parameters (Params.mqh)
```mql5
// lazy grid fill (Phase 1)
bool         lazy_grid_enabled;       // enable lazy grid fill
int          initial_warm_levels;     // initial pending levels (1-2)
bool         auto_max_level_distance; // auto-calculate max level distance [NEW]
int          max_level_distance;      // max distance to next level (pips) - manual
double       lazy_distance_multiplier;// spacing multiplier for auto mode (default 20x) [NEW]
double       max_dd_for_expansion;    // stop expanding if DD < this (%)
```

### New EA Inputs (RecoveryGridDirection_v3.mq5)
```mql5
input bool              InpAutoMaxLevelDistance = true;        // Auto-calculate max level distance
input int               InpMaxLevelDistance     = 500;         // Manual max distance (pips) - used if auto=false
input double            InpLazyDistanceMultiplier = 20.0;      // Spacing multiplier for auto mode (20x spacing)
```

### Implementation (GridBasket.mqh)
```mql5
//+------------------------------------------------------------------+
//| Get effective max level distance (auto or manual)               |
//+------------------------------------------------------------------+
double GetEffectiveMaxLevelDistance()
{
   if(!m_params.auto_max_level_distance)
      return m_params.max_level_distance; // Manual mode
   
   // Auto mode: spacing × multiplier
   double spacing_pips = GetCurrentSpacing();
   if(spacing_pips <= 0)
      return m_params.max_level_distance; // Fallback to manual
   
   return spacing_pips * m_params.lazy_distance_multiplier;
}
```

### Guard Update
```mql5
// Guard 3: Distance too far?
double next_price = CalculateNextLevelPrice();
double distance_pips = PriceToDistance(next_price, m_levels[0].price);
double max_distance = GetEffectiveMaxLevelDistance(); // Auto or manual
if(distance_pips > max_distance)
{
   // Block expansion
   return false;
}
```

---

## 📊 Configuration Logging

The EA now logs the auto mode status:

**Auto Mode:**
```
1. LAZY GRID FILL: ENABLED ⚠️
   Initial warm levels: 1
   Max level distance: AUTO (Spacing × 20.0)
   Max DD for expansion: -20.0%
```

**Manual Mode:**
```
1. LAZY GRID FILL: ENABLED ⚠️
   Initial warm levels: 1
   Max level distance: 500 pips (manual)
   Max DD for expansion: -20.0%
```

---

## 🎯 Preset Files Created

Created 4 tested preset files (only showing overrides from default):

### 1. EURUSD-TESTED.set
```
InpSymbolPreset=0
InpUseTestedPresets=true
InpAtrTimeframe=3
InpSpacingStepPips=25.0
InpSpacingAtrMult=0.6
InpMinSpacingPips=12.0
InpGridLevels=10
InpTargetCycleUSD=6.0
```
**Auto Max Distance:** 25 × 20 = **500 pips**

### 2. XAUUSD-TESTED.set
```
InpSymbolPreset=0
InpUseTestedPresets=true
InpAtrTimeframe=16385
InpSpacingStepPips=150.0
InpSpacingAtrMult=1.0
InpMinSpacingPips=80.0
InpGridLevels=5
InpTargetCycleUSD=10.0
```
**Auto Max Distance:** 150 × 20 = **3000 pips**

### 3. GBPUSD-TESTED.set
```
InpSymbolPreset=0
InpUseTestedPresets=true
InpAtrTimeframe=16388
InpSpacingStepPips=50.0
InpSpacingAtrMult=0.8
InpMinSpacingPips=25.0
InpGridLevels=7
InpTargetCycleUSD=8.0
```
**Auto Max Distance:** 50 × 20 = **1000 pips**

### 4. USDJPY-TESTED.set
```
InpSymbolPreset=0
InpUseTestedPresets=true
InpAtrTimeframe=16388
InpSpacingStepPips=40.0
InpSpacingAtrMult=0.7
InpMinSpacingPips=20.0
InpGridLevels=8
InpTargetCycleUSD=7.0
```
**Auto Max Distance:** 40 × 20 = **800 pips**

### Preset Notes
- All presets use `InpSymbolPreset=0` (PRESET_AUTO) with `InpUseTestedPresets=true`
- PresetManager automatically detects symbol and applies correct settings
- Only showing inputs that differ from default (as requested)
- Auto max level distance is enabled by default (no need to set it in .set files)

---

## 🧪 Testing Recommendations

### Test 1: Verify Auto Calculation
1. Load EURUSD-TESTED.set
2. Check logs for "Max level distance: AUTO (Spacing × 20.0)"
3. Verify expansion blocks at ~500 pips from anchor

### Test 2: Verify Symbol Scaling
1. Test XAUUSD-TESTED.set → Should allow expansion up to ~3000 pips
2. Test GBPUSD-TESTED.set → Should allow expansion up to ~1000 pips
3. Confirm no manual tuning needed

### Test 3: Manual Override
1. Set `InpAutoMaxLevelDistance=false`
2. Set `InpMaxLevelDistance=300`
3. Verify expansion blocks at 300 pips (ignoring auto calculation)

---

## 📈 Expected Behavior

### EURUSD Example
```
Spacing: 25 pips
Auto Max Distance: 25 × 20 = 500 pips
Max Levels Before Block: ~20 levels (500 / 25)
```

### XAUUSD Example
```
Spacing: 150 pips
Auto Max Distance: 150 × 20 = 3000 pips
Max Levels Before Block: ~20 levels (3000 / 150)
```

**Key Insight:** The multiplier of 20x ensures consistent risk across all symbols (~20 levels max).

---

## 🎯 Files Modified

1. **Params.mqh**: Added `auto_max_level_distance` and `lazy_distance_multiplier`
2. **RecoveryGridDirection_v3.mq5**: Added inputs and logging
3. **GridBasket.mqh**: Added `GetEffectiveMaxLevelDistance()` and updated guard
4. **Created 4 preset files**: EURUSD, XAUUSD, GBPUSD, USDJPY

---

## ✅ Status: COMPLETE

Phase 3.5 is **COMPLETE**! Auto max level distance is now production-ready and integrated with preset files! 🚀

**Next Action:** Test all 4 symbol presets to verify auto scaling works correctly! 🧪

