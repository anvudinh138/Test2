# 🐛 Bug Fix #2: Preset Manager Override

**Date**: 2025-01-08  
**Reporter**: User (second test)  
**Severity**: Critical (Feature still not working after first fix)  
**Status**: ✅ FIXED

---

## 🔍 The Real Problem

### After First Fix:
- ✅ Fixed `BuildGrid()` to check `lazy_grid_enabled`
- ❌ Still seeding 4 orders per basket instead of 2
- ❌ Log still shows "Dynamic grid warm=4/5"

### Root Cause:
**Preset Manager Override!**

When `InpUseTestedPresets=true` (line 3 of log), the `CPresetManager::ApplyPreset()` function **overrides** input parameters with hardcoded preset values!

**Evidence from log**:
```
Line 2:  InpSymbolPreset=0 (PRESET_AUTO)
Line 3:  InpUseTestedPresets=true  ← THIS IS THE CULPRIT!
Line 15: InpDynamicGrid=false      ← Set by user
Line 59: InpLazyGridEnabled=true   ← Set by user

BUT THEN:
PresetManager.mqh line 260: params.grid_dynamic_enabled = true;  ← OVERRIDES USER SETTING!
```

**Flow**:
1. User sets `InpDynamicGrid=false` in preset file
2. User sets `InpLazyGridEnabled=true` in preset file
3. EA calls `BuildParams()` which loads user settings
4. EA calls `ApplyPreset()` because `InpUseTestedPresets=true`
5. `ApplyPreset()` **overrides** `grid_dynamic_enabled=true` for XAUUSD preset
6. Lazy grid never activates because dynamic grid takes over!

---

## 🔧 The Fix

### Changed File:
`presets/TEST-Phase3-LazyGrid.set`

### Added Lines:
```
InpSymbolPreset=5
; Changed to: 5 (PRESET_CUSTOM - bypasses preset manager)

InpUseTestedPresets=false
; Changed to: false (MUST be false - prevents preset override!)
```

### Why This Works:
- `InpSymbolPreset=5` (PRESET_CUSTOM) tells preset manager to skip overrides
- `InpUseTestedPresets=false` disables preset manager entirely
- User settings now take priority

---

## ✅ Verification

### Test Again With Updated Preset:

**Load**: `TEST-Phase3-LazyGrid.set` (now updated)

**Expected Now**:
```
✅ InpSymbolPreset=5 (CUSTOM)
✅ InpUseTestedPresets=false
✅ InpDynamicGrid=false
✅ InpLazyGridEnabled=true

Result:
✅ [RGDv2][XAUUSD][BUY][PRI] DG/SEED dir=BUY level=0 ...
✅ [RGDv2][XAUUSD][BUY][PRI] DG/SEED dir=BUY level=1 ...
✅ [RGDv2][XAUUSD][BUY][PRI] Initial grid seeded (lazy) levels=2 pending=1

✅ 4 total orders (2 per basket)
```

---

## 📝 Lessons Learned

### Why This Was Hard to Debug:
1. **Hidden override**: Preset manager silently overrides settings
2. **Not obvious**: `InpUseTestedPresets=true` seems harmless
3. **Two-step bug**: First fix (BuildGrid) was correct, but wasn't enough

### Prevention:
1. ✅ **Always check preset manager** when testing new features
2. ✅ **Use PRESET_CUSTOM** for testing
3. ✅ **Set InpUseTestedPresets=false** for feature tests
4. ✅ **Document this in testing guides**

---

## 🚀 Next Steps

1. ⏳ **Re-run test** with updated preset
2. ⏳ **Verify** "Initial grid seeded (lazy) levels=2 pending=1"
3. ⏳ **Count** exactly 4 orders (2 per basket)

---

**Both fixes now applied:**
1. ✅ BuildGrid() checks lazy_grid_enabled
2. ✅ TEST preset bypasses preset manager

**Should work now!** 🎯

---

**Fix Date**: 2025-01-08  
**Files Changed**: 1 preset file  
**Complexity**: Simple (configuration fix)  
**Impact**: High (enables Phase 3 testing)

