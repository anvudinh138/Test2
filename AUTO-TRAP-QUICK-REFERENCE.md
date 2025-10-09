# Auto Trap Threshold - Quick Reference Card

**Version**: v3.1.0 Phase 5.5  
**Date**: 2025-01-09

---

## 🎯 TL;DR

**Problem**: Trap threshold needs different values per symbol (EURUSD 25p, XAUUSD 80p, etc.)  
**Solution**: EA now calculates optimal threshold automatically based on ATR + Spacing!

---

## ⚙️ SETTINGS (Copy & Paste)

### Conservative (Default) - Recommended
```
InpTrapAutoThreshold     = true   // Enable auto
InpTrapATRMultiplier     = 2.0    // 2x ATR
InpTrapSpacingMultiplier = 1.5    // 1.5x spacing
InpTrapGapThreshold      = 50.0   // Fallback
InpTrapDDThreshold       = -15.0  // DD threshold
InpTrapConditionsRequired = 1     // 1/5 conditions
```

### Balanced - More Sensitive
```
InpTrapAutoThreshold     = true
InpTrapATRMultiplier     = 1.5    // Tighter
InpTrapSpacingMultiplier = 1.2
InpTrapDDThreshold       = -12.0  // Shallower DD
```

### Aggressive - Early Exit
```
InpTrapAutoThreshold     = true
InpTrapATRMultiplier     = 1.2    // Very tight
InpTrapSpacingMultiplier = 1.0    // Match spacing
InpTrapDDThreshold       = -10.0
```

### Manual - Expert Only
```
InpTrapAutoThreshold     = false  // Disable auto
InpTrapGapThreshold      = 25.0   // YOUR value per symbol
```

---

## 📊 EXPECTED THRESHOLDS

### Conservative (2.0x ATR, 1.5x Spacing)
| Symbol | Result |
|--------|--------|
| EURUSD | 37.5 pips |
| GBPUSD | 45 pips |
| XAUUSD | 80 pips |
| USDJPY | 52.5 pips |

### Balanced (1.5x ATR, 1.2x Spacing)
| Symbol | Result |
|--------|--------|
| EURUSD | 30 pips |
| GBPUSD | 36 pips |
| XAUUSD | 60 pips |
| USDJPY | 42 pips |

### Aggressive (1.2x ATR, 1.0x Spacing)
| Symbol | Result |
|--------|--------|
| EURUSD | 25 pips |
| GBPUSD | 30 pips |
| XAUUSD | 50 pips |
| USDJPY | 35 pips |

---

## 🔍 HOW TO VERIFY IT'S WORKING

### Check Logs (Every Hour)
```
Look for:
[RGDv2][EURUSD][TRAP] Auto Trap Threshold: 37.5 pips 
   (ATR: 15.0 × 2.0 = 30.0 | Spacing: 25.0 × 1.5 = 37.5)

If you see this → Auto mode is working! ✅
If missing → Check InpTrapAutoThreshold = true
```

### Check Trap Detection
```
When gap reaches threshold:
[RGDv2][EURUSD][SELL][PRI] 🚨 TRAP DETECTED!
[RGDv2][EURUSD][SELL][PRI]    Gap: 37.6 pips

Gap ≥ Auto Threshold → Trap detected ✅
```

---

## 🎮 QUICK TEST

### Test 1: EURUSD Auto vs Manual
```
Run A: InpTrapAutoThreshold = true  (auto: ~37 pips)
Run B: InpTrapAutoThreshold = false, InpTrapGapThreshold = 25.0

Compare:
- Number of trap detections (Run B should detect more)
- Final balance
- Max DD
```

### Test 2: Multi-Symbol
```
Test same settings on:
- EURUSD
- XAUUSD
- GBPUSD

Expected: Each symbol has different threshold in logs ✅
```

---

## 🐛 TROUBLESHOOTING

### Problem: No threshold logs
**Solution**: 
- Check `InpTrapAutoThreshold = true`
- Check `InpLogEvents = true`
- Wait 1 hour (logs every hour, not every tick)

### Problem: Threshold seems wrong
**Solution**:
- Check ATR value in log (is it reasonable?)
- Check spacing value in log
- Try manual mode: `InpTrapAutoThreshold = false`

### Problem: Too many traps detected
**Solution**:
- Increase multipliers: `2.0 → 2.5` or `1.5 → 2.0`
- Or use manual: `InpTrapAutoThreshold = false, InpTrapGapThreshold = 50.0`

### Problem: Too few traps detected
**Solution**:
- Decrease multipliers: `2.0 → 1.5` or `1.5 → 1.2`
- Check DD threshold: Maybe too deep (`-15% → -12%`)

---

## 💡 PRO TIPS

### Tip 1: Start Conservative
Use default settings first (2.0, 1.5), then adjust based on results.

### Tip 2: Check Logs First Hour
After starting EA, check logs at 1-hour mark to see calculated threshold.

### Tip 3: Symbol-Specific Manual
If auto doesn't work well for a specific symbol, use manual mode for that symbol only.

### Tip 4: Backtest Both Modes
Run same backtest with auto=true and auto=false, compare results.

### Tip 5: Volatility Changes
If market volatility increases suddenly, threshold auto-adjusts after 1 hour.

---

## 📱 COPY-PASTE PRESETS

### For MT5 Tester (.set file)
```ini
[Trap Detection - Auto Mode Conservative]
InpTrapDetectionEnabled=true
InpTrapAutoThreshold=true
InpTrapGapThreshold=50.0
InpTrapATRMultiplier=2.0
InpTrapSpacingMultiplier=1.5
InpTrapDDThreshold=-15.0
InpTrapConditionsRequired=1
```

### For MT5 Tester (.set file) - Aggressive
```ini
[Trap Detection - Auto Mode Aggressive]
InpTrapDetectionEnabled=true
InpTrapAutoThreshold=true
InpTrapGapThreshold=50.0
InpTrapATRMultiplier=1.2
InpTrapSpacingMultiplier=1.0
InpTrapDDThreshold=-10.0
InpTrapConditionsRequired=1
```

---

## 🚨 IMPORTANT NOTES

1. **Auto mode recalculates every 1 hour** (not every tick for performance)
2. **Uses the LARGER of ATR or Spacing** (conservative approach)
3. **Minimum threshold: 10 pips** (safety floor)
4. **Backward compatible**: Manual mode still works (`InpTrapAutoThreshold=false`)
5. **No performance impact**: Cached calculation

---

## 📞 NEED HELP?

**Check these documents**:
- `PHASE5.5-AUTO-TRAP-THRESHOLD.md` - Full implementation details
- `PHASE5.5-COMPLETE-SUMMARY.md` - Complete summary
- `PHASE7-QUICK-EXIT-EXPLAINED.md` - Quick Exit explanation

**Common issues**:
- Recompile EA if changes not taking effect
- Check MT5 Strategy Tester uses latest .ex5
- Verify preset file not overriding inputs

---

## ✅ CHECKLIST

Before trading with auto mode:
- [ ] Compiled EA successfully
- [ ] Set `InpTrapAutoThreshold = true`
- [ ] Ran 1-hour test to verify logs
- [ ] Checked calculated threshold makes sense
- [ ] Compared with manual mode (optional)
- [ ] Adjusted multipliers if needed

**Happy Auto-Trading!** 🚀


