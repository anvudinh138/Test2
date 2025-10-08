# Compile Fix Guide

## Lỗi hiện tại

```
19 errors related to:
- trend_action (undeclared)
- SpacingPips() (undeclared)
```

## Root Cause

MT5 compiler đang cache file cũ hoặc chưa nhận diện changes.

## Fix Steps

### Option 1: Clean Compile (RECOMMENDED)
1. Close MT5 completely
2. Delete compiled files:
   ```
   Delete: MQL5/Experts/RecoveryGridDirection_v3.ex5
   Delete: MQL5/Include/RECOVERY-GRID-DIRECTION_v3/*.ex5
   ```
3. Restart MT5
4. Compile lại

### Option 2: Force Recompile
1. In MetaEditor, go to: Tools → Options → Compiler
2. Check "Delete intermediate files after compilation"
3. Clean: Tools → Clean
4. Compile: F7

### Option 3: Manual Verification

#### Check 1: Params.mqh line 73
```cpp
// Should have this line:
ETrendAction trend_action;  // trend action mode
```

#### Check 2: EA line 68
```cpp
// Should have this input:
input ETrendAction InpTrendAction = TREND_ACTION_NONE;
```

#### Check 3: EA line 363
```cpp
// Should have this mapping:
g_params.trend_action = InpTrendAction;
```

#### Check 4: GridBasket.mqh line 407
```cpp
// Should be:
double current_spacing_pips=(m_spacing!=NULL)?m_spacing.SpacingPips():m_params.spacing_pips;
// NOT GetSpacing()
```

## Verify Files Modified

Run this in terminal:
```bash
cd /Users/anvudinh/Desktop/hoiio/ea-1

# Check if trend_action exists
grep "ETrendAction trend_action" src/core/Params.mqh

# Check if InpTrendAction exists  
grep "input ETrendAction InpTrendAction" src/ea/RecoveryGridDirection_v3.mq5

# Check if SpacingPips exists
grep "SpacingPips()" src/core/GridBasket.mqh

# Check mapping
grep "g_params.trend_action" src/ea/RecoveryGridDirection_v3.mq5
```

All should return results.

## If Still Not Working

### Nuclear Option: Fresh Include
1. Copy ALL files from `src/core/` to MT5 Include folder
2. Copy `src/ea/RecoveryGridDirection_v3.mq5` to MT5 Experts folder
3. Force path refresh in MetaEditor

### MT5 Include Path
Mac:
```
~/Library/Application Support/MetaTrader 5/Bottles/{instance}/drive_c/Program Files/MetaTrader 5/MQL5/
  ├─ Experts/RecoveryGridDirection_v3.mq5
  └─ Include/RECOVERY-GRID-DIRECTION_v3/core/*.mqh
```

## Quick Test

Create a test script to verify includes work:
```cpp
// TestCompile.mq5
#include <RECOVERY-GRID-DIRECTION_v3/core/Types.mqh>
#include <RECOVERY-GRID-DIRECTION_v3/core/Params.mqh>

void OnStart()
{
   SParams p;
   p.trend_action = TREND_ACTION_NONE;  // Should compile
   Print("Test OK");
}
```

If this compiles → includes are correct, issue is elsewhere.
If this fails → include path problem.

## Last Resort

Replace the problematic lines with explicit values temporarily:

### In EA (line 363):
```cpp
// Temporary workaround
g_params.trend_action = TREND_ACTION_NONE;  // Force default
// g_params.trend_action = InpTrendAction;  // Comment out
```

This will compile but ignore user input. Use only for testing.

---

**Expected Result**: 0 errors after proper cleanup + recompile

