# Testing Checklist - Recovery Grid Direction v3.1.0

## Pre-Test Setup

- [ ] MetaTrader 5 installed with Strategy Tester
- [ ] EA compiled without errors
- [ ] Test account configured (demo or tester)
- [ ] Historical data downloaded for test symbol
- [ ] Spread and commission settings realistic

## Functional Tests

### Core Functions
- [ ] Both BUY and SELL grids initialize correctly
- [ ] Market seeds placed at current price
- [ ] Initial pending orders placed (1-2 levels with lazy fill)
- [ ] Grid spacing calculated correctly per mode (PIPS/ATR/HYBRID)

### Lazy Grid Fill (Always ON)
- [ ] Starts with only 1-2 pending levels
- [ ] Expands grid as levels fill
- [ ] Respects max level distance
- [ ] Stops expansion when DD threshold reached
- [ ] Logs expansion events correctly

### Dynamic Spacing (Always ON)
- [ ] Spacing multiplier adjusts based on trend strength
- [ ] RANGE: 1.0x multiplier applied
- [ ] WEAK_TREND: 1.5x multiplier applied
- [ ] STRONG_TREND: 2.0x multiplier applied
- [ ] EXTREME_TREND: 3.0x multiplier applied

### Time-Based Exit
- [ ] Tracks time underwater correctly
- [ ] Exits after 24 hours if enabled
- [ ] Only exits if loss <= max acceptable loss
- [ ] Respects trend-only mode setting
- [ ] Logs time exit reason

### Profit & TP Management
- [ ] Average price calculated correctly
- [ ] Group TP computed as break-even + target
- [ ] TP hit closes entire basket atomically
- [ ] Realized profit reduces opposite basket's target
- [ ] New TP price moves closer after profit redistribution

### Basket Reseeding
- [ ] Closed basket reseeds automatically
- [ ] Fresh grid starts from current market price
- [ ] Target reduction preserved after reseed
- [ ] No delay in reseeding (simplified logic)

## Scenario Tests

### Market Conditions
- [ ] **Strong Uptrend**: SELL basket accumulates loss, accepts exit
- [ ] **Strong Downtrend**: BUY basket accumulates loss, accepts exit
- [ ] **Range Market**: Both baskets close profitably
- [ ] **Gap Opening**: Grid handles price gaps correctly
- [ ] **High Volatility**: Dynamic spacing widens appropriately

### Risk Scenarios
- [ ] High drawdown stops grid expansion
- [ ] Time exit prevents catastrophic losses
- [ ] Both baskets can be active simultaneously
- [ ] Manual intervention works (close all positions)
- [ ] News filter pauses trading during events

## Performance Validation

### Backtest Metrics
- [ ] Win rate > 60%
- [ ] Max DD < 30% (with time exit enabled)
- [ ] Profit factor > 1.2
- [ ] Recovery time < 48 hours average
- [ ] Monthly return positive

### Symbol-Specific Tests
- [ ] **EURUSD**: Conservative settings work (25 pips, 10 levels)
- [ ] **XAUUSD**: High volatility handled (150 pips, 5 levels)
- [ ] **GBPUSD**: Medium volatility (50 pips, 7 levels)
- [ ] **Custom Symbol**: Manual configuration works

## Logging & Debugging

### Event Logging
- [ ] Init/deinit events logged
- [ ] Order open/close with reasons
- [ ] Grid expansion events (lazy fill)
- [ ] Spacing adjustments (dynamic spacing)
- [ ] Time exit triggers
- [ ] Profit redistribution events

### Error Handling
- [ ] Invalid broker responses handled
- [ ] Insufficient margin detected
- [ ] Maximum orders limit respected
- [ ] Network disconnection recovery
- [ ] Invalid price/volume corrections

## Acceptance Criteria

### Minimum Requirements
- [ ] 1000+ trades without critical errors
- [ ] Average cycle profit > 0
- [ ] No broker rule violations
- [ ] All core features functioning
- [ ] Logs are clear and informative

### Production Readiness
- [ ] Tested on demo for 2+ weeks
- [ ] Multiple symbols validated
- [ ] Different market conditions tested
- [ ] Time exit proven to limit losses
- [ ] Documentation matches behavior

## Test Configuration Example

```yaml
# Recommended test settings
symbol: EURUSD
period: M15
date_from: 2024-01-01
date_to: 2024-04-01
initial_deposit: 10000
leverage: 1:100

# EA Settings
magic: 990045
symbol_preset: PRESET_AUTO
lot_base: 0.01
lot_scale: 1.0
target_cycle_usd: 10.0
time_exit_enabled: true
time_exit_hours: 24
time_exit_max_loss: -100.0
```

## Known Limitations

1. **No automated stop loss** - Manual monitoring required
2. **Accepts losses** - Part of strategy design
3. **High exposure possible** - Both grids active
4. **News dependency** - Requires internet for calendar
5. **Broker constraints** - Some brokers limit pending orders

---

*Last Updated: October 2024*