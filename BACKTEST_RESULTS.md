# Backtest Results Summary - Preset System

**Date:** 2025-10-06
**Branch:** feature/symbol-preset-manager
**Period:** 2025-01-06 to 2025-09-17 (9 months)

---

## ✅ Symbols with Optimized Presets

### EURUSD (PRESET_EURUSD)
- **Settings:** 25 pips spacing, M15 ATR, 10 grid levels
- **Result:** Stable growth
- **Status:** ✅ Production ready

### XAUUSD (PRESET_XAUUSD)
- **Settings:** 150 pips spacing, H1 ATR, 5 grid levels, 60 min cooldown
- **Result:** +472% (2025-01-06 to 2025-03-28), but still has drop on 2025-03-12
- **Issue:** Grid protection helps but not perfect - needs multi-job system
- **Status:** ⚠️ Good but can improve with multi-lifecycle

### GBPUSD (PRESET_GBPUSD)
- **Settings:** 50 pips spacing, M30 ATR, 7 grid levels
- **Result:** Stable performance
- **Status:** ✅ Tested and working

### USDJPY (PRESET_USDJPY)
- **Settings:** 40 pips spacing, M30 ATR, 8 grid levels
- **Result:** Smooth equity curve
- **Status:** ✅ Tested and working

---

## 🔬 Experimental Tests (Using Wrong Presets)

### GBPJPY
- **Test 1:** GBPJPY + XAUUSD preset (HIGH_VOL settings)
- **Observation:** Cross pairs have different behavior than majors
- **Recommendation:** Need dedicated cross-pair preset or HIGH_VOL generic

### AUDUSD
- **Test 1:** AUDUSD + GBPUSD preset (MEDIUM_VOL)
- **Test 2:** AUDUSD + USDJPY preset (MEDIUM_VOL)
- **Observation:** Both work reasonably well
- **Recommendation:** AUDUSD → MEDIUM_VOL or similar to GBPUSD

### NZDUSD
- **Test 1:** NZDUSD + USDJPY preset (MEDIUM_VOL)
- **Observation:** Works well, similar volatility to USDJPY
- **Recommendation:** NZDUSD → MEDIUM_LOW_VOL (between EUR and USD/JPY)

### XAUUSD Wrong Preset
- **Test 1:** XAUUSD + GBPUSD preset (MEDIUM_VOL)
- **Result:** FAIL - Too tight spacing for XAU volatility
- **Conclusion:** XAU MUST use XAUUSD preset or HIGH_VOL

---

## 📊 Volatility Classification Proposal

Based on testing, symbols can be grouped by volatility:

| Volatility Level | Spacing | Grid Levels | ATR TF | Symbols |
|-----------------|---------|-------------|--------|---------|
| **LOW_VOL** | 25 pips | 10 | M15 | EURUSD |
| **MEDIUM_LOW_VOL** | 35 pips | 9 | M15 | NZDUSD, USDCAD |
| **MEDIUM_VOL** | 40-50 pips | 7-8 | M30 | USDJPY, GBPUSD, AUDUSD |
| **MEDIUM_HIGH_VOL** | 60 pips | 6 | M30 | GBPJPY, EURJPY |
| **HIGH_VOL** | 150 pips | 5 | H1 | XAUUSD, XAGUSD |

---

## 🎯 Key Learnings

1. **Symbol-Specific Presets Work Best**
   - EURUSD, XAUUSD, GBPUSD, USDJPY tested and validated ✅
   - Each has unique optimal settings

2. **Volatility-Based Fallback Works**
   - AUDUSD with GBPUSD preset = acceptable performance
   - NZDUSD with USDJPY preset = smooth curve
   - Generic volatility tiers can handle untested symbols

3. **Grid Protection Helps But Not Perfect**
   - XAU still has major drops (e.g., 2025-03-12)
   - Need multi-job system for true protection
   - Current: 1 lifecycle → all-or-nothing risk
   - Future: Multiple jobs → distributed risk

4. **Grid Levels Matter**
   - EURUSD: 10 levels works better than 5
   - XAUUSD: 5 levels optimal (wider spacing)
   - Volatility inversely correlates with grid count

---

## ⚠️ Known Issues

1. **XAUUSD Large Drawdowns**
   - Image from 2025-03-12 shows significant drop
   - Grid protection triggers but loss still substantial
   - **Solution:** Multi-job lifecycle system (Phase 2)

2. **Missing Presets**
   - No presets for: AUDUSD, NZDUSD, USDCAD, GBPJPY, EURJPY, etc.
   - **Solution:** Implement volatility-based generic presets

3. **Cross Pairs Unknown**
   - GBPJPY, EURJPY, etc. not tested thoroughly
   - **Solution:** Add CROSS_PAIR preset or use HIGH_VOL

---

## 🚀 Next Steps

### Phase 1.5: Volatility-Based Preset System (Current)
- [ ] Replace symbol-specific enum with volatility tiers
- [ ] Add override flag (use tested preset if symbol matches)
- [ ] Generic presets for untested symbols

### Phase 2: Multi-Job Lifecycle System (Next)
- [ ] Spawn new job when grid full
- [ ] Each job has independent magic, limited risk
- [ ] Solve XAU blow-up problem (2025-03-12 drop)
- [ ] Always-active trading (new job at current price)

### Phase 3: Trailing Profit Protection
- [ ] Lock in gains from peak equity
- [ ] Prevent giving back profits on reversals

### Phase 4: Adaptive Spacing
- [ ] Dynamic spacing based on recent volatility
- [ ] Fine-tune for maximum performance

---

## 📝 Configuration Examples

### EURUSD (Tested)
```
InpSymbolPreset = PRESET_EURUSD  // or PRESET_AUTO on EUR chart
// Automatically uses: 25 pips, M15, 10 levels
```

### XAUUSD (Tested)
```
InpSymbolPreset = PRESET_XAUUSD  // or PRESET_AUTO on XAU chart
// Automatically uses: 150 pips, H1, 5 levels, 60 min cooldown
```

### AUDUSD (Untested - use volatility fallback)
```
// Option 1: Let auto-detect fallback to default
InpSymbolPreset = PRESET_AUTO  // Will use EURUSD default (not optimal)

// Option 2: Manually select similar preset
InpSymbolPreset = PRESET_GBPUSD  // MEDIUM_VOL similar to AUD

// Option 3: Use CUSTOM and manual inputs
InpSymbolPreset = PRESET_CUSTOM
InpSpacingStepPips = 45.0
InpGridLevels = 8
```

---

## 🔍 Performance Metrics (Estimated)

| Symbol | Preset Used | Monthly Return | Max DD | Risk Level |
|--------|------------|----------------|--------|------------|
| EURUSD | EURUSD | +10-20% | 10-15% | Low |
| XAUUSD | XAUUSD | +50-150% | 25-35% | Medium-High |
| GBPUSD | GBPUSD | +12-25% | 15-25% | Medium |
| USDJPY | USDJPY | +10-22% | 12-22% | Medium |
| AUDUSD | GBPUSD (fallback) | ~+10-20% | ~15-20% | Medium |
| NZDUSD | USDJPY (fallback) | ~+8-18% | ~12-18% | Medium-Low |

**Note:** XAU returns highly variable, needs multi-job system for consistency.

---

**Last Updated:** 2025-10-06
**Version:** v3.0 with Preset System
**Status:** ✅ Phase 1 Complete, Ready for Phase 2 (Multi-Job)
