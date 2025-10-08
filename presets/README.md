# Test Presets for v3.1.0

## Purpose

These presets help **reproduce specific market scenarios** to test:
- Lazy Grid Fill behavior
- Trap Detection accuracy  
- Quick Exit effectiveness
- Gap Management logic

## 4 Core Scenarios

### 1. Range Market (Normal Operation)
**File**: `01-Range-Normal.set`

**Market**: EURUSD, Sideways 50-100 pips  
**Expected**:
- ✅ Grid expands gradually
- ✅ Both baskets close at TP normally
- ✅ No traps detected
- ✅ DD < 10%

**Test Period**: 2024-01-15 to 2024-01-22 (1 week)

---

### 2. Strong Uptrend 300+ pips (SELL Trap Test)
**File**: `02-Uptrend-300p-SELLTrap.set`

**Market**: EURUSD Strong rally (300+ pips, minimal pullback)  
**Expected**:
- ⚠️ SELL basket should HALT expansion early
- ⚠️ Trap detected: Gap + Counter-trend + DD
- ⚠️ Quick Exit activated (target: -$10 to -$20)
- ✅ BUY basket profits normally
- ✅ SELL escapes with small loss

**Test Period**: 2024-03-10 to 2024-03-17 (strong NFP week)

---

### 3. Whipsaw (Both Baskets Trapped)
**File**: `03-Whipsaw-BothTrapped.set`

**Market**: GBPUSD High volatility, rapid reversals  
**Expected**:
- ⚠️ BUY trapped during downswing
- ⚠️ SELL trapped during upswing
- ⚠️ Both in Quick Exit mode
- ✅ First basket to escape helps second (x2 multiplier)
- ✅ Both exit with acceptable losses

**Test Period**: 2024-02-01 to 2024-02-08 (BOE surprise)

---

### 4. Gap + Sideways (Bridge Fill Test)
**File**: `04-Gap-Sideways-Bridge.set`

**Market**: XAUUSD Gap from news, then consolidation  
**Expected**:
- 📊 Gap detected (200-400 pips)
- 🌉 Bridge levels filled automatically
- ✅ Average price improves
- ✅ TP becomes achievable
- ✅ Basket closes at reduced target

**Test Period**: 2024-04-01 to 2024-04-05 (Gold spike)

---

## Parameter Differences by Scenario

| Parameter | Range | Uptrend | Whipsaw | Gap |
|-----------|-------|---------|---------|-----|
| **Symbol** | EURUSD | EURUSD | GBPUSD | XAUUSD |
| **Spacing** | 25p Hybrid | 25p Hybrid | 50p Hybrid | 150p Hybrid |
| **Grid Levels** | 10 | 5 | 7 | 5 |
| **Lot Base** | 0.01 | 0.01 | 0.01 | 0.01 |
| **Lot Scale** | 1.5 | 2.0 | 2.0 | 2.0 |
| **Target/Cycle** | $5 | $5 | $6 | $10 |
| **Lazy Grid** | OFF | OFF | OFF | OFF |
| **Trap Detection** | OFF | OFF | OFF | OFF |
| **Quick Exit** | OFF | OFF | OFF | OFF |

**Note**: Phase 0 = ALL features OFF. Test with legacy dynamic grid first.

---

## How to Use

### 1. Load Preset in MT5
```
Strategy Tester → Settings → Load → Select preset file
```

### 2. Run Backtest
```
Mode: Every tick (most accurate)
Period: As specified above
Visual mode: Optional (slower)
```

### 3. Record KPIs
```
Max DD: ______%
Final Balance: $______
Total Trades: ______
Win Rate: ______%
Recovery Time (if trapped): ______ hours
```

### 4. Compare: Dynamic Grid vs Lazy Grid

**Phase 0 Test** (Current):
- Features: Dynamic Grid (legacy)
- Trap: Should occur in scenarios 2, 3, 4
- Recovery: Slow/never

**Phase 3+ Test** (After implementation):
- Features: Lazy Grid + Trap Detection + Quick Exit
- Trap: Detected early
- Recovery: Fast (<1 hour)

---

## Expected Results (Phase 0 Baseline)

### Scenario 1 (Range):
- ✅ Should work fine
- DD: 5-10%
- Profit: Moderate

### Scenario 2 (Uptrend):
- ❌ SELL basket trapped badly
- DD: 30-50%
- Recovery: 2-3 days OR never

### Scenario 3 (Whipsaw):
- ❌ Both baskets trapped
- DD: 40-60%
- Recovery: Very slow

### Scenario 4 (Gap):
- ❌ Gap trap
- DD: 20-40%
- Recovery: If price returns to gap

---

## After Phase 3-4 Implementation

### Expected Improvements:
- **Max DD**: ↓ 50-70% reduction
- **Recovery Time**: 30-60 minutes (vs days)
- **Loss per Trap**: -$10 to -$30 (vs -$100 to -$300)
- **Trap Escape Rate**: 80%+ success

---

## Backtest Report Template

```
========================================
Scenario: [Range/Uptrend/Whipsaw/Gap]
Version: v3.1.0 Phase [0/3/4]
========================================
Symbol: ________
Period: ________ to ________
Initial Balance: $10,000

RESULTS:
Final Balance: $________
Max DD: ________% ($________)
Total Trades: ________
Win Rate: _______%
Profit Factor: ________

TRAP EVENTS:
Traps Detected: ________
Quick Exits: ________
Escape Success Rate: _______%
Avg Loss per Trap: $________
Avg Recovery Time: ________ minutes

NOTES:
[Any observations, anomalies, or issues]
========================================
```

---

## Next Steps

1. ✅ Create 4 preset files
2. ⏳ Run Phase 0 baseline tests
3. ⏳ Document results (CSV export)
4. ⏳ Compare after Phase 3-4 implementation

---

**Status**: Presets ready for Phase 0 testing  
**Purpose**: Establish baseline before implementing new features

