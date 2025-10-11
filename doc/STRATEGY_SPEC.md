# Strategy Specification - Recovery Grid Direction v3.1.0

## Core Strategy

A simplified dual-grid trading system that:
1. Maintains two independent grids (BUY and SELL) simultaneously
2. Closes baskets at calculated group TP (break-even + target profit)
3. Uses profits from one basket to reduce the other's TP requirement
4. Automatically reseeds closed baskets with fresh grids
5. Accepts controlled losses during strong trends

## Key Concepts

### Basket
- Collection of positions in one direction (BUY or SELL)
- Has: total lot, average price, floating P&L, group TP price
- Operates independently from the opposite basket

### Grid Structure
- Market seed: Initial market order at current price
- Pending levels: Limit orders placed at fixed intervals
- Lazy fill: Only 1-2 pending levels initially, expands as needed
- Dynamic spacing: Widens in trends (1.0x → 3.0x multiplier)

### Group TP Calculation
```
Average Price = Σ(lot_i × price_i) / Σ(lot_i)
Break-Even = Average Price ± Spread/Commission
Group TP = Break-Even + Target_Profit_USD
```

## Parameters

### Essential Configuration

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `magic` | long | 990045 | Unique identifier (MUST change for each instance) |
| `symbol_preset` | enum | AUTO | Symbol configuration preset |
| `spacing_mode` | enum | HYBRID | PIPS, ATR, or HYBRID spacing |
| `spacing_pips` | double | 25.0 | Base spacing in pips |
| `grid_levels` | int | 6 | Number of levels per side |
| `lot_base` | double | 0.01 | Base lot size |
| `lot_scale` | double | 1.0 | Lot multiplier (1.0=flat, 2.0=martingale) |
| `target_cycle_usd` | double | 10.0 | Profit target per cycle |

### Always-Enabled Features

| Feature | Description | Benefit |
|---------|-------------|---------|
| **Lazy Grid Fill** | Starts with 1-2 levels, expands on demand | Reduces initial exposure |
| **Dynamic Spacing** | Widens spacing in trends (up to 3x) | Fewer positions in adverse conditions |

### Critical Protection

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `time_exit_enabled` | bool | true | Enable time-based exit (CRITICAL!) |
| `time_exit_hours` | int | 24 | Hours underwater before exit |
| `time_exit_max_loss` | double | -100.0 | Max acceptable loss (USD) |
| `time_exit_trend_only` | bool | true | Only exit counter-trend positions |

## Mathematical Formulas

### Average Price
```
avg_price = Σ(lot_i × price_i) / Σ(lot_i)
```

### Basket P&L
```
BUY:  pnl = (Bid - avg_price) × point_value × total_lot - commission
SELL: pnl = (avg_price - Ask) × point_value × total_lot - commission
```

### Group TP Solve
Find `tp_price` where:
```
pnl_at(tp_price) = target_cycle_usd
```

### Profit Redistribution
When basket A closes with profit P:
```
B_new_target = B_old_target - P
B_new_tp = recalculate_tp(B_new_target)
```

### Dynamic Spacing
```
final_spacing = base_spacing × trend_multiplier

where trend_multiplier:
  RANGE: 1.0x
  WEAK_TREND: 1.5x
  STRONG_TREND: 2.0x
  EXTREME_TREND: 3.0x
```

## Trading Logic

### Initialization
1. Create BUY basket with market seed + 1-2 pending levels
2. Create SELL basket with market seed + 1-2 pending levels
3. Both baskets start trading immediately

### Per Tick Processing
1. Check if market is open
2. Check news filter (skip if news event)
3. Update both baskets:
   - Refresh positions and P&L
   - Check for time-based exit
   - Check if group TP hit
   - Expand grid if needed (lazy fill)
4. Handle closed baskets:
   - Take realized profit
   - Reduce opposite basket's target
   - Reseed with fresh grid

### Basket Closure Triggers
1. **Group TP Hit**: Price reaches calculated TP level
2. **Time Exit**: Stuck underwater > 24 hours with acceptable loss
3. **Manual Close**: User intervention

### Grid Expansion Rules (Lazy Fill)
- Only expand if positions < max levels
- Check drawdown threshold (stop if DD too high)
- Verify distance to next level (prevent clustering)
- Add levels with dynamic spacing applied

## Risk Management

### Accepted Risks
- **Trend Losses**: Strategy accepts losses during strong trends
- **No Hard SL**: No automated stop loss (manual monitoring required)
- **Double Exposure**: Both grids active = sum of both baskets

### Protection Mechanisms
- **Time-Based Exit**: Prevents prolonged drawdown
- **Dynamic Spacing**: Reduces positions in trends
- **Lazy Fill**: Limits initial exposure
- **DD Monitoring**: Stops expansion at high drawdown

## Symbol-Specific Settings

### EURUSD (Low Volatility)
- Spacing: 25 pips
- Levels: 10
- Target: $5

### XAUUSD (High Volatility)
- Spacing: 150 pips
- Levels: 5
- Target: $20
- Time exit critical!

### GBPUSD (Medium)
- Spacing: 50 pips
- Levels: 7
- Target: $8

## Performance Expectations

Based on XAUUSD backtests (Jan-Apr 2024):

| Metric | Value |
|--------|-------|
| Win Rate | ~71% |
| Profit Factor | 1.4-1.6 |
| Max DD | -20% (with time exit) |
| Monthly Return | 7-10% |
| Recovery Time | 24-48 hours |

## Important Notes

1. **No Automated Stop Loss** - Monitor account manually
2. **Accepts Losses** - Part of the strategy design
3. **Time Exit Critical** - Must be enabled for production
4. **Both Grids Active** - Total risk = BUY + SELL exposure
5. **Profit Focus** - Maximize gains in favorable conditions

---

*Last Updated: October 2024*