# 🎯 What to Do NOW - Phase 3 Testing

**Status**: ✅ Phase 3 Code Complete → ⏳ **YOU NEED TO TEST IT**

---

## 📋 Quick Test (5-10 minutes)

### Step 1: Open MT5 Strategy Tester
1. Press `Ctrl+R` (or `Cmd+R` on Mac)
2. Strategy Tester window opens

### Step 2: Configure Test
```
EA: RecoveryGridDirection_v3
Symbol: EURUSD
Period: M1 (1 minute)
Date: 2024-01-15 to 2024-01-16 (1 day only)
Model: Every tick based on real ticks
Deposit: $10,000
```

### Step 3: Load Test Preset
1. Click **"Load"** button (folder icon next to inputs)
2. Navigate to: `Experts/RECOVERY-GRID-DIRECTION_v3/presets/`
3. Select: **`TEST-Phase3-LazyGrid.set`**
4. Click **"Open"**

### Step 4: Verify Settings Loaded
Check these parameters are set:
```
InpLazyGridEnabled = true  ← MOST IMPORTANT!
InpMagic = 990099
InpTargetCycleUSD = 5.0
```

### Step 5: Start Test
1. Click **"Start"** button
2. Wait ~10 seconds for test to complete
3. Check results

---

## ✅ What to Look For

### 1. Check "Journal" Tab
Look for these log messages:
```
✅ "Initial grid seeded (lazy) levels=2 pending=1"  ← MUST SEE THIS!
✅ Should appear twice (once for BUY, once for SELL)
❌ NO "REFILL" messages (expansion disabled in Phase 3 v1)
```

### 2. Check "Graph" or "Results" Tab
Order count:
```
✅ Total orders: 4 (2 per basket)
  - BUY: 1 market + 1 buy limit
  - SELL: 1 market + 1 sell limit
❌ Should NOT see 6+ orders (that would mean old behavior)
```

### 3. Visual Inspection (Optional)
Enable "Visual mode" before starting test:
- You'll see orders placed on chart in real-time
- Should see exactly 2 orders per basket

---

## 🎉 Success Criteria

### ✅ TEST PASS if you see:
1. ✅ Log: "Initial grid seeded (lazy) levels=2 pending=1" (appears twice)
2. ✅ Total orders: 4 (2 BUY + 2 SELL)
3. ✅ NO expansion during 1-day test
4. ✅ No errors in Journal

**Then tell me**: "Phase 3 test passed! Qua Phase 4 luôn." 🚀

---

### ❌ TEST FAIL if you see:
1. ❌ More than 2 orders per basket
2. ❌ "REFILL" messages in log
3. ❌ Different log message
4. ❌ Compilation errors
5. ❌ No orders placed

**Then tell me**: "Phase 3 test failed: [describe what happened]" 🐛

---

## 🚀 After Testing

### If PASS → Phase 4
I'll help you implement **Phase 4: Lazy Grid v2 (Expansion Logic)**
- Add `OnLevelFilled()` event handler
- Implement guards (counter-trend, DD, max levels, distance)
- Enable conditional expansion
- Estimated time: 3-4 hours

### If FAIL → Debug
I'll help you fix the issue quickly

---

## 📸 Optional: Take Screenshots

Helpful for documentation:
1. Journal tab showing log messages
2. Graph tab showing 4 orders
3. Results tab showing order count

---

## ⏱️ Timeline

| Task | Time | Status |
|------|------|--------|
| Open MT5 Tester | 10 sec | ⏳ |
| Load preset | 30 sec | ⏳ |
| Run 1-day test | 10 sec | ⏳ |
| Check results | 2 min | ⏳ |
| Report back | 1 min | ⏳ |
| **Total** | **~5 min** | **⏳ WAITING FOR YOU** |

---

## 🎯 YOUR ACTION ITEMS

1. [ ] Open MT5 Strategy Tester
2. [ ] Load `TEST-Phase3-LazyGrid.set`
3. [ ] Run backtest (1 day)
4. [ ] Check Journal for "Initial grid seeded (lazy) levels=2 pending=1"
5. [ ] Verify 4 total orders (2 per basket)
6. [ ] Report results: PASS or FAIL

---

**Don't overthink it - just run the test and tell me what you see!** 😊

The preset is already configured correctly. Just load it and press Start.

---

**Test now** → **Report results** → **Proceed to Phase 4** 🚀

