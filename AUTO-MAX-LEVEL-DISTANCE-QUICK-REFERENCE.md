# Auto Max Level Distance - Quick Reference 🚀

## 📋 What Is It?
Auto-scales `InpMaxLevelDistance` based on current grid spacing, eliminating manual tuning for different symbols.

---

## ⚙️ Configuration

### Auto Mode (Default) ✅
```
InpAutoMaxLevelDistance = true
InpLazyDistanceMultiplier = 20.0
```
**Result:** Max distance = Current Spacing × 20

### Manual Mode
```
InpAutoMaxLevelDistance = false
InpMaxLevelDistance = 500
```
**Result:** Max distance = 500 pips (fixed)

---

## 📊 Auto Calculation Examples

| Symbol | Spacing | Multiplier | Max Distance | Max Levels |
|--------|---------|-----------|--------------|------------|
| EURUSD | 25 pips | 20x | **500 pips** | ~20 |
| XAUUSD | 150 pips | 20x | **3000 pips** | ~20 |
| GBPUSD | 50 pips | 20x | **1000 pips** | ~20 |
| USDJPY | 40 pips | 20x | **800 pips** | ~20 |

---

## 🎯 Preset Files (Ready to Use)

### EURUSD
```bash
presets/EURUSD-TESTED.set
```
- Spacing: 25 pips
- Auto Max Distance: 500 pips
- Grid Levels: 10

### XAUUSD
```bash
presets/XAUUSD-TESTED.set
```
- Spacing: 150 pips
- Auto Max Distance: 3000 pips
- Grid Levels: 5

### GBPUSD
```bash
presets/GBPUSD-TESTED.set
```
- Spacing: 50 pips
- Auto Max Distance: 1000 pips
- Grid Levels: 7

### USDJPY
```bash
presets/USDJPY-TESTED.set
```
- Spacing: 40 pips
- Auto Max Distance: 800 pips
- Grid Levels: 8

---

## 🔍 Log Verification

### Check if auto is enabled:
```
1. LAZY GRID FILL: ENABLED ⚠️
   Initial warm levels: 1
   Max level distance: AUTO (Spacing × 20.0)  ← Look for this line
   Max DD for expansion: -20.0%
```

### Check if manual is used:
```
1. LAZY GRID FILL: ENABLED ⚠️
   Initial warm levels: 1
   Max level distance: 500 pips (manual)  ← Manual mode
   Max DD for expansion: -20.0%
```

---

## 🧪 Quick Test Steps

1. **Load Preset**: Open MT5 Strategy Tester → Load `EURUSD-TESTED.set`
2. **Check Logs**: Look for "Max level distance: AUTO (Spacing × 20.0)"
3. **Verify Expansion**: Grid should expand up to ~20 levels (~500 pips)
4. **Test Other Symbols**: Repeat with XAUUSD, GBPUSD, USDJPY

---

## 💡 Key Benefits

✅ **No Manual Tuning**: Works across all symbols automatically
✅ **Adaptive**: Scales with market volatility
✅ **Consistent Risk**: ~20 levels max for all symbols
✅ **Fallback**: Manual mode available if needed

---

## ⚠️ Important Notes

1. **Auto mode reads current spacing** from CSpacingEngine (includes ATR adaptation)
2. **Multiplier of 20x** ensures consistent risk profile across symbols
3. **Preset files** automatically enable auto mode (default behavior)
4. **Manual override** available via `InpAutoMaxLevelDistance=false`

---

## 🎯 Recommended Settings

| Setting | Value | Reason |
|---------|-------|--------|
| `InpAutoMaxLevelDistance` | `true` | Let EA adapt to symbol volatility |
| `InpLazyDistanceMultiplier` | `20.0` | ~20 levels max (safe default) |
| `InpMaxLevelDistance` | `500` | Fallback if auto fails |

---

## 🚀 Status: Production Ready ✅

Auto max level distance is fully implemented and tested! Just load the preset for your symbol and start backtesting! 🎉

