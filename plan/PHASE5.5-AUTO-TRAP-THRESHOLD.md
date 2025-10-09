# Phase 5.5: Auto Trap Threshold (Hybrid ATR + Spacing)

**Status**: ✅ COMPLETE  
**Date**: 2025-01-09  
**Version**: v3.1.0 Phase 5.5  

---

## 📋 OVERVIEW

Implements automatic calculation of trap gap thresholds based on symbol volatility, eliminating the need for manual tuning per symbol.

### Problem Statement
- Manual trap threshold (`InpTrapGapThreshold`) requires different values for each symbol
- EURUSD: 20-30 pips optimal
- XAUUSD: 50-100 pips optimal  
- User must manually tune for each symbol → tedious and error-prone

### Solution
**Hybrid Auto Mode**: Calculate threshold based on BOTH ATR and Spacing:
```
auto_threshold = MAX(ATR × multiplier, Spacing × multiplier)
```

Use the LARGER value for conservative trap detection.

---

## 🎯 IMPLEMENTATION DETAILS

### 1. New Parameters (`Params.mqh`)

```cpp
// Trap detection (Phase 5)
bool   trap_detection_enabled;   // enable trap detection
bool   trap_auto_threshold;      // NEW: auto-calculate gap threshold
double trap_gap_threshold;       // manual gap threshold (pips) - fallback
double trap_atr_multiplier;      // NEW: ATR multiplier for auto mode
double trap_spacing_multiplier;  // NEW: spacing multiplier for auto mode
double trap_dd_threshold;        // DD threshold (%)
int    trap_conditions_required; // min conditions to trigger (1-5)
int    trap_stuck_minutes;       // minutes to consider "stuck"
```

### 2. EA Inputs (`RecoveryGridDirection_v3.mq5`)

```cpp
//--- Trap Detection (Phase 5)
input group             "=== Trap Detection (v3.1 - Phase 5) ==="
input bool              InpTrapDetectionEnabled = true;       // Enable trap detection
input bool              InpTrapAutoThreshold    = true;        // Auto-calculate gap threshold
input double            InpTrapGapThreshold     = 50.0;        // Manual gap threshold (pips) - used if auto=false
input double            InpTrapATRMultiplier    = 2.0;         // ATR multiplier for auto mode (2.0 = 2x ATR)
input double            InpTrapSpacingMultiplier = 1.5;        // Spacing multiplier for auto mode (1.5 = 1.5x spacing)
input double            InpTrapDDThreshold      = -15.0;       // DD threshold (%)
input int               InpTrapConditionsRequired = 1;         // Min conditions to trigger (1-5)
input int               InpTrapStuckMinutes     = 30;          // Minutes to consider "stuck"
```

### 3. TrapDetector Updates

#### New Members
```cpp
private:
   bool   m_auto_threshold;        // Auto-calculate gap threshold
   double m_gap_threshold;         // Manual gap threshold
   double m_atr_multiplier;        // ATR multiplier for auto mode
   double m_spacing_multiplier;    // Spacing multiplier for auto mode
   double m_calculated_gap_threshold; // Cached calculated threshold
```

#### New Methods
```cpp
// Calculate auto gap threshold (Hybrid: ATR + Spacing)
double CalculateAutoGapThreshold();

// Get effective gap threshold (auto or manual)
double GetEffectiveGapThreshold();
```

#### Implementation

```cpp
double CTrapDetector::CalculateAutoGapThreshold()
{
   if(m_basket == NULL)
      return m_gap_threshold; // Fallback to manual
   
   // Get ATR from spacing engine (already calculated!)
   double atr_pips = m_basket.GetATRPips();
   double atr_threshold = atr_pips * m_atr_multiplier;
   
   // Get current spacing
   double spacing_pips = m_basket.GetCurrentSpacing();
   double spacing_threshold = spacing_pips * m_spacing_multiplier;
   
   // Use the LARGER of the two (more conservative)
   double auto_threshold = MathMax(atr_threshold, spacing_threshold);
   
   // Ensure minimum threshold (at least 10 pips for safety)
   auto_threshold = MathMax(auto_threshold, 10.0);
   
   return auto_threshold;
}

double CTrapDetector::GetEffectiveGapThreshold()
{
   if(!m_auto_threshold)
      return m_gap_threshold; // Manual mode
   
   // Auto mode: Calculate once and cache (recalc every 1 hour)
   static datetime last_calc_time = 0;
   datetime now = TimeCurrent();
   
   if(m_calculated_gap_threshold <= 0 || (now - last_calc_time) >= 3600)
   {
      m_calculated_gap_threshold = CalculateAutoGapThreshold();
      last_calc_time = now;
      
      // Log the calculated threshold (once per hour)
      if(m_log != NULL)
      {
         double atr_pips = (m_basket != NULL) ? m_basket.GetATRPips() : 0;
         double spacing_pips = (m_basket != NULL) ? m_basket.GetCurrentSpacing() : 0;
         m_log.Event(Tag(), StringFormat(
            "Auto Trap Threshold: %.1f pips (ATR: %.1f × %.1f = %.1f | Spacing: %.1f × %.1f = %.1f)",
            m_calculated_gap_threshold,
            atr_pips, m_atr_multiplier, atr_pips * m_atr_multiplier,
            spacing_pips, m_spacing_multiplier, spacing_pips * m_spacing_multiplier));
      }
   }
   
   return m_calculated_gap_threshold;
}

bool CTrapDetector::CheckCondition_Gap()
{
   double gap_size = GetBasketGapSize();
   double effective_threshold = GetEffectiveGapThreshold();
   return (gap_size >= effective_threshold);
}
```

### 4. GridBasket Helper Methods

Added getter methods to expose ATR and spacing to TrapDetector:

```cpp
// Get ATR pips (for auto trap threshold calculation)
double GetATRPips() const
{
   if(m_spacing == NULL)
      return 0.0;
   return m_spacing.AtrPips();
}

// Get current spacing (for auto trap threshold calculation)
double GetCurrentSpacing() const
{
   if(m_spacing == NULL)
      return 0.0;
   return m_spacing.GetSpacing();
}
```

---

## 📊 EXPECTED RESULTS BY SYMBOL

### Conservative Settings (Default)
```
InpTrapATRMultiplier      = 2.0
InpTrapSpacingMultiplier  = 1.5
```

| Symbol | ATR(H1) | Spacing | ATR Threshold | Spacing Threshold | **Auto Threshold** |
|--------|---------|---------|---------------|-------------------|--------------------|
| EURUSD | 15 pips | 25 pips | 30 pips | **37.5 pips** | **37.5 pips** ✅ |
| GBPUSD | 20 pips | 30 pips | 40 pips | **45 pips** | **45 pips** ✅ |
| XAUUSD | 40 pips | 50 pips | **80 pips** | 75 pips | **80 pips** ✅ |
| USDJPY | 25 pips | 35 pips | 50 pips | **52.5 pips** | **52.5 pips** ✅ |

**Logic**: Uses the LARGER of ATR or Spacing threshold (more conservative).

### Balanced Settings
```
InpTrapATRMultiplier      = 1.5
InpTrapSpacingMultiplier  = 1.2
```

| Symbol | ATR Threshold | Spacing Threshold | **Auto Threshold** |
|--------|---------------|-------------------|--------------------|
| EURUSD | 22.5 pips | **30 pips** | **30 pips** |
| GBPUSD | 30 pips | **36 pips** | **36 pips** |
| XAUUSD | **60 pips** | 60 pips | **60 pips** |
| USDJPY | 37.5 pips | **42 pips** | **42 pips** |

### Aggressive Settings
```
InpTrapATRMultiplier      = 1.2
InpTrapSpacingMultiplier  = 1.0
```

| Symbol | ATR Threshold | Spacing Threshold | **Auto Threshold** |
|--------|---------------|-------------------|--------------------|
| EURUSD | 18 pips | **25 pips** | **25 pips** |
| GBPUSD | 24 pips | **30 pips** | **30 pips** |
| XAUUSD | **48 pips** | 50 pips | **50 pips** |
| USDJPY | 30 pips | **35 pips** | **35 pips** |

---

## 🎯 USAGE

### Auto Mode (Recommended)
```
InpTrapAutoThreshold     = true   // Enable auto calculation
InpTrapATRMultiplier     = 2.0    // 2x ATR
InpTrapSpacingMultiplier = 1.5    // 1.5x spacing
InpTrapGapThreshold      = 50.0   // Fallback if auto fails
```

EA will automatically calculate optimal threshold for each symbol.

**Log Output**:
```
[RGDv2][EURUSD][TRAP] Auto Trap Threshold: 37.5 pips (ATR: 15.0 × 2.0 = 30.0 | Spacing: 25.0 × 1.5 = 37.5)
```

### Manual Mode (Expert Tuning)
```
InpTrapAutoThreshold     = false  // Disable auto
InpTrapGapThreshold      = 25.0   // Manual threshold for EURUSD
```

EA will use the fixed threshold value.

---

## ✅ ADVANTAGES

1. **Symbol-Agnostic**: Works for any symbol without manual tuning
2. **Volatility-Adaptive**: ATR automatically adjusts to market conditions
3. **Grid-Aware**: Spacing multiplier ensures threshold makes sense relative to grid structure
4. **Conservative**: Uses MAX of both methods to avoid false positives
5. **Transparent**: Logs calculated threshold every hour for verification
6. **Fallback Safe**: Reverts to manual mode if calculation fails
7. **Performance**: Cached calculation (recalc every 1 hour only)

---

## ⚙️ TUNING GUIDE

### For Different Trading Styles

#### Conservative (Fewer traps, larger loss)
```
InpTrapATRMultiplier      = 3.0   // 3x ATR (very wide)
InpTrapSpacingMultiplier  = 2.0   // 2x spacing
InpTrapConditionsRequired = 2     // Need 2/5 conditions
InpTrapDDThreshold        = -20.0 // Deep DD threshold
```

**Result**: Detects only severe traps, accepts larger DD before escape.

#### Balanced (Default)
```
InpTrapATRMultiplier      = 2.0   // 2x ATR
InpTrapSpacingMultiplier  = 1.5   // 1.5x spacing
InpTrapConditionsRequired = 1     // Need 1/5 conditions
InpTrapDDThreshold        = -15.0 // Moderate DD threshold
```

**Result**: Good balance between sensitivity and false positives.

#### Aggressive (More traps, smaller loss)
```
InpTrapATRMultiplier      = 1.5   // 1.5x ATR (tighter)
InpTrapSpacingMultiplier  = 1.2   // 1.2x spacing
InpTrapConditionsRequired = 1     // Need 1/5 conditions
InpTrapDDThreshold        = -10.0 // Shallow DD threshold
```

**Result**: Detects traps early, escapes with smaller loss, but more false positives.

---

## 🧪 TESTING RECOMMENDATIONS

### Test 1: Multi-Symbol Verification
Test the same settings across multiple symbols:
```
Symbols: EURUSD, GBPUSD, XAUUSD, USDJPY
Period: 3 months
Settings: Conservative (default)

Expected:
- Each symbol has different auto threshold
- All thresholds make sense relative to symbol volatility
- Trap detection activates appropriately for each
```

### Test 2: Volatility Adaptation
Test during different market conditions:
```
Symbol: EURUSD
Periods:
- Low volatility (July 2024)
- High volatility (NFP week)

Expected:
- Threshold increases during high volatility
- Threshold decreases during low volatility
- Log shows threshold recalculation
```

### Test 3: Manual vs Auto Comparison
```
Test A: InpTrapAutoThreshold = false, InpTrapGapThreshold = 25.0 (manual)
Test B: InpTrapAutoThreshold = true, multipliers = (1.5, 1.2) (aggressive)

Compare:
- Number of trap detections
- Quick Exit activations
- Final balance
- Max DD
```

---

## 📝 CHANGELOG

### Phase 5.5 (2025-01-09)
- ✅ Added `trap_auto_threshold` parameter
- ✅ Added `trap_atr_multiplier` parameter (default 2.0)
- ✅ Added `trap_spacing_multiplier` parameter (default 1.5)
- ✅ Implemented `CalculateAutoGapThreshold()` in TrapDetector
- ✅ Implemented `GetEffectiveGapThreshold()` with caching
- ✅ Added `GetATRPips()` and `GetCurrentSpacing()` to GridBasket
- ✅ Updated `CheckCondition_Gap()` to use effective threshold
- ✅ Added hourly logging of calculated threshold
- ✅ Updated EA inputs and configuration display
- ✅ Tested compilation (no errors)

---

## 🚀 NEXT STEPS

### Phase 6: Advanced Trap Conditions
- Implement "Moving Away" detection
- Implement "Stuck" detection
- Add trend-based trap detection

### Phase 8: Performance Testing
- Backtest auto mode across 10 symbols
- Compare auto vs manual results
- Optimize default multipliers
- Document best practices per symbol class

---

## 📚 CODE REFERENCES

**Files Modified**:
- `src/core/Params.mqh` - Added 3 new parameters
- `src/ea/RecoveryGridDirection_v3.mq5` - Added 3 new inputs, updated display
- `src/core/TrapDetector.mqh` - Implemented auto calculation logic
- `src/core/GridBasket.mqh` - Added helper getters for ATR and spacing

**Key Functions**:
- `CTrapDetector::CalculateAutoGapThreshold()` - Hybrid calculation
- `CTrapDetector::GetEffectiveGapThreshold()` - Auto/manual mode switch
- `CGridBasket::GetATRPips()` - Expose ATR to trap detector
- `CGridBasket::GetCurrentSpacing()` - Expose spacing to trap detector

---

## ✅ COMPLETION CHECKLIST

- [x] Parameters added to `Params.mqh`
- [x] Inputs added to EA
- [x] TrapDetector constructor updated
- [x] Auto calculation methods implemented
- [x] GridBasket helper methods added
- [x] Caching and logging implemented
- [x] Compilation successful (no errors)
- [x] Documentation created
- [x] Default values set (conservative)
- [x] Ready for testing

**Status**: ✅ **IMPLEMENTATION COMPLETE - READY FOR TESTING**


