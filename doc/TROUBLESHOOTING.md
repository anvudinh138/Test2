# Troubleshooting Guide - Recovery Grid Direction v3.1.0

## Common Issues & Solutions

### 🔴 EA Not Trading

**Symptoms**: No positions opened, no activity in logs

**Solutions**:
1. Check if market is open (not weekend/holiday)
2. Verify AutoTrading is enabled in MT5
3. Check if News Filter is blocking trades
4. Ensure sufficient margin available
5. Verify symbol trading is allowed by broker
6. Check EA initialization logs for errors

### 🔴 "Market Closed" Errors

**Symptoms**:
```
failed sell limit 500 EURUSD at 4.85857 [Market closed]
```

**Solutions**:
1. For backtesting: Don't start on weekends
2. Check symbol trading sessions
3. Verify historical data is available
4. Set `InpRespectStops = false` for backtesting

### 🔴 High Drawdown

**Symptoms**: Account DD exceeds 30-40%

**Solutions**:
1. **Enable Time-Based Exit** (critical!)
   ```
   InpTimeExitEnabled = true
   InpTimeExitHours = 24
   InpTimeExitMaxLoss = -100.0
   ```
2. Reduce lot size (`InpLotBase = 0.01`)
3. Use flat scaling (`InpLotScale = 1.0`)
4. Increase grid spacing for volatile symbols
5. Reduce grid levels (`InpGridLevels = 5`)

### 🔴 Grid Not Expanding

**Symptoms**: Only 1-2 levels placed, no expansion

**Causes & Solutions**:
1. **DD threshold reached** - Check `InpMaxDDForExpansion` setting
2. **Max distance exceeded** - Adjust `InpLazyDistanceMultiplier`
3. **Max levels reached** - Check `InpGridLevels` setting
4. **Insufficient margin** - Reduce lot sizes

### 🔴 Compilation Errors

**Common errors**:
```
'InpLazyGridEnabled' - undeclared identifier
'm_gap_manager' - undeclared identifier
```

**Solution**: You're using the old version. The v3.1.0 refactor:
- Removed multi-job system
- Removed basket SL
- Removed gap management
- Lazy grid is always enabled (not configurable)
- Dynamic spacing is always enabled

### 🔴 News Filter Not Working

**Symptoms**: Trading during news events

**Solutions**:
1. Enable WebRequest in MT5:
   - Tools → Options → Expert Advisors
   - Check "Allow WebRequest for listed URL"
   - Add: `https://nfs.faireconomy.media`
2. Check internet connection
3. Verify `InpNewsFilterEnabled = true`
4. Check news filter logs for errors

### 🔴 Orders Rejected by Broker

**Error messages**:
```
Invalid stops
Invalid volume
Trade is disabled
```

**Solutions**:
1. Check broker's minimum/maximum lot sizes
2. Verify stops level requirements
3. Ensure symbol is tradeable
4. Check account type allows EAs
5. Verify sufficient margin

### 🔴 Time Exit Not Triggering

**Symptoms**: Positions stay open > 24 hours

**Solutions**:
1. Verify `InpTimeExitEnabled = true`
2. Check loss is within acceptable range (`InpTimeExitMaxLoss`)
3. If `InpTimeExitTrendOnly = true`, verify position is counter-trend
4. Check logs for time exit evaluation

## Performance Issues

### Slow Backtesting

**Solutions**:
1. Use "Open prices only" mode for initial tests
2. Reduce date range
3. Disable visual mode
4. Close other applications
5. Reduce logging verbosity

### Memory Usage High

**Solutions**:
1. Reduce `InpGridLevels`
2. Clear old log files
3. Restart MT5 periodically
4. Use 64-bit MT5 version

## Configuration Problems

### Wrong Symbol Settings

**Problem**: EA uses wrong spacing/levels for symbol

**Solution**: Use symbol presets:
```
InpSymbolPreset = PRESET_AUTO
InpUseTestedPresets = true
```

### Duplicate Magic Numbers

**Problem**: Multiple EAs interfering

**Solution**: Use unique magic for each instance:
- Instance 1: `InpMagic = 990045`
- Instance 2: `InpMagic = 990046`
- Instance 3: `InpMagic = 990047`

## Critical Settings Checklist

✅ **For ALL Production Use**:
```
InpTimeExitEnabled = true
InpTimeExitHours = 24
InpTimeExitMaxLoss = -100.0
```

✅ **For Volatile Symbols (XAUUSD)**:
```
InpSpacingStepPips = 150
InpGridLevels = 5
InpLotBase = 0.01
```

✅ **For Backtesting**:
```
InpRespectStops = false
InpCommissionPerLot = 7.0
```

## Debug Information

### Check EA Status
1. Open Experts tab for logs
2. Look for initialization messages
3. Check for error messages (red text)
4. Verify basket status updates

### Log Locations
- Terminal logs: `View → Experts`
- File logs: `MQL5/Logs/` folder
- Custom logs: Check EA initialization message

### Key Log Messages
```
"EA v3.1.0 Phase 1 - Magic: 990045"  # Successful init
"Lazy Grid Fill: ALWAYS ENABLED"     # Feature status
"Dynamic Spacing: ALWAYS ENABLED"    # Feature status
"News filter ACTIVE"                 # News blocking
"Time exit triggered"                # Time-based close
"Basket SL skipped"                  # Old feature (removed)
```

## Getting Help

1. **Check Documentation**:
   - README.md - Overview
   - STRATEGY_SPEC.md - Technical details
   - ARCHITECTURE.md - Module structure

2. **Review Configuration**:
   - CONFIG_EXAMPLE.yaml - Example settings
   - Symbol presets in PresetManager.mqh

3. **Test Systematically**:
   - Start with default settings
   - Change one parameter at a time
   - Use Strategy Tester first
   - Test on demo before live

## Known Limitations

1. **No automated stop loss** - Manual monitoring required
2. **Accepts losses** - By design during strong trends
3. **High margin usage** - Both grids active simultaneously
4. **Broker limits** - Some brokers limit pending orders
5. **News dependency** - Requires internet connection

---

*Last Updated: October 2024*