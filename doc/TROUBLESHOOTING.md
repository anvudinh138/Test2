# Troubleshooting Guide

## ❌ Problem: "Market closed" - No trades in backtest

### Symptoms
```
failed sell limit 500 EURUSD at 4.85857 [Market closed]
CTrade::OrderSend: sell limit 500.00 EURUSD at 4.85857 [market closed]
```

### Root Causes

1. **Weekend/Holiday data**
   - Backtest started on Saturday/Sunday
   - No trading session active

2. **Symbol not available**
   - Symbol has no historical data
   - Wrong symbol name

3. **Broker stops level conflict**
   - `InpRespectStops=true` blocks orders too close to price
   - Some brokers have large stops level

4. **Wrong price feed**
   - Price data corrupted
   - Symbol digits mismatch

### Solutions

#### ✅ Fix 1: Check Backtest Settings

In **Strategy Tester**:

1. **Date Range**: Start on Monday, avoid holidays
   ```
   From: 2024.01.02 (Tuesday)
   To:   2024.03.31
   ```

2. **Mode**: Use `Every tick` or `1 minute OHLC`

3. **Model**: `Real ticks` for accuracy

4. **Symbol**: Ensure data exists
   - Right click symbol → Chart
   - Check if price history loads

#### ✅ Fix 2: EA Settings

```properties
# Required settings
InpRespectStops = false       # Set false for backtest
InpGridLevels = 200           # Your test value
InpLotBase = 0.01             # NOT 500!
InpLotScale = 2               # Martingale multiplier

# Dynamic Grid (to reduce lag)
InpDynamicGrid = true
InpWarmLevels = 5
InpRefillThreshold = 2
InpRefillBatch = 3
InpMaxPendings = 15

# Risk (for stress test)
InpDDOpenUSD = 100
InpSessionSL_USD = 1000
InpExposureCapLots = 20.0     # High for 200 levels
```

#### ✅ Fix 3: Check Symbol Info

Run this script to verify:

```mql5
void OnStart()
{
   string symbol = "EURUSD";
   
   Print("=== Symbol Info ===");
   Print("Ask: ", SymbolInfoDouble(symbol, SYMBOL_ASK));
   Print("Bid: ", SymbolInfoDouble(symbol, SYMBOL_BID));
   Print("Digits: ", SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   Print("Trade Mode: ", SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE));
   Print("Stops Level: ", SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL));
   Print("Volume Min: ", SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN));
   Print("Volume Step: ", SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP));
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   Print("Day of Week: ", dt.day_of_week, " (0=Sun, 6=Sat)");
}
```

#### ✅ Fix 4: Debug Log Check

After init, you should see:
```
[RGDv2] Init OK - Ask=1.08450 Bid=1.08440 LotBase=0.01 GridLevels=200 Dynamic=ON
[RGDv2][EURUSD][BUY][PRI] Dynamic grid warm=6/200
[RGDv2][EURUSD][SELL][PRI] Dynamic grid warm=6/200
```

If you see:
```
[RGDv2] Controller init failed
```

Check:
- Balance > 0
- Symbol exists
- Lot size valid

---

## ❌ Problem: Abnormal prices (e.g., 4.85857 for EURUSD)

### Cause
- Wrong symbol selected
- Data corruption

### Solution
1. Delete history and re-download:
   - Tools → History Center
   - Select symbol → Delete
   - Download again

2. Use different broker's data

3. Check symbol specifications match

---

## ❌ Problem: Lot size 500 (too large)

### Cause
- Wrong input parameter
- LotScale too aggressive

### Solution
```properties
InpLotBase = 0.01        # Start small!
InpLotScale = 1.0        # No martingale
# OR
InpLotScale = 2.0        # Moderate martingale
```

**For 200 levels with LotScale=2**:
- Level 0: 0.01
- Level 10: 10.24
- Level 20: 10,485.76 ⚠️ TOO BIG!

**Safe approach**:
```properties
InpGridLevels = 200
InpLotBase = 0.01
InpLotScale = 1.0        # Flat lot
InpExposureCapLots = 5.0 # Total limit
```

---

## ❌ Problem: Init lag (5-10 seconds)

### Solution
✅ Use Dynamic Grid (already implemented):

```properties
InpDynamicGrid = true
InpWarmLevels = 5        # Only 5 pending at start
InpGridLevels = 200      # Total capacity
```

Now init takes **<1 second**!

---

## 🔍 Common Backtest Issues

### 1. "Not enough money"
```
InpLotBase too large for balance
```
**Fix**: Reduce lot or increase initial deposit

### 2. "Invalid stops"
```
Pending order too close to price
```
**Fix**: 
- Set `InpRespectStops = false`
- Increase `InpMinSpacingPips`

### 3. "Too many orders"
```
Max orders per symbol exceeded
```
**Fix**:
- Reduce `InpGridLevels`
- Or increase `InpWarmLevels` slower
- Check broker limit (usually 200-500)

### 4. Zero trades but no errors
**Checklist**:
- [ ] Date range includes weekdays
- [ ] Symbol has data
- [ ] InpLotBase > Symbol minimum
- [ ] InpExposureCapLots > InpLotBase
- [ ] InpSessionSL_USD not too tight

---

## 📊 Expected Behavior

### Successful init:
```
[RGDv2] Init OK - Ask=1.08450 Bid=1.08440 LotBase=0.01 GridLevels=200 Dynamic=ON
[RGDv2][EURUSD][BUY][PRI] Dynamic grid warm=6/200
[RGDv2][EURUSD][SELL][PRI] Dynamic grid warm=6/200
[RGDv2][EURUSD][LC] Lifecycle bootstrapped
```

### During trading:
```
[RGDv2][EURUSD][BUY][PRI] Refill +3 placed=9/200 pending=5
[RGDv2][EURUSD][SELL][PRI] Refill +3 placed=9/200 pending=4
[RGDv2][EURUSD][LC] Rescue deployed
[RGDv2][EURUSD][BUY][HEDGE] TSL activated
[RGDv2][EURUSD][BUY][HEDGE] Basket closed: GroupTP
```

---

## 🚨 Emergency Checklist

If backtest produces **zero trades**:

1. [ ] Check date range (avoid weekends)
2. [ ] Set `InpRespectStops = false`
3. [ ] Verify `InpLotBase = 0.01` (not 500!)
4. [ ] Check symbol exists and has data
5. [ ] Initial balance > $100
6. [ ] Enable logging: `InpLogEvents = true`
7. [ ] Check Experts tab for errors
8. [ ] Try simpler symbol (EURUSD, not exotics)
9. [ ] Reduce to `InpGridLevels = 6` first
10. [ ] Test static mode: `InpDynamicGrid = false`

---

## 📞 Still Not Working?

Share these in log:
1. Full init log (first 20 lines)
2. EA inputs screenshot
3. Strategy Tester settings
4. Symbol specifications
5. Account balance/leverage

Common missed settings:
- ✅ Mode: Every tick
- ✅ Visualization: OFF (for speed)
- ✅ Optimization: Disabled
- ✅ Forward: Disabled initially

