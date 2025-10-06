# Multi-Job Phase 2 & 3 Testing Guide

**Status**: Code complete, ready for testing
**Branch**: `feature/multi-job-v3.0`
**Completed**: Phase 1 (Foundation) + Phase 2 (Spawn) + Phase 3 (Risk)

---

## 🎯 What Was Implemented

### Phase 2: Spawn Triggers
1. **IsGridFull()** - Detects when grid reaches max levels
2. **IsTSLActive()** - Detects when TSL is active on any basket
3. **ShouldSpawnNew()** - Decision logic for auto-spawn
   - Trigger 1: Grid full (BUY or SELL)
   - Trigger 2: TSL active
   - Trigger 3: Job DD >= threshold
   - Guards: Cooldown, max spawns, global DD
4. **UpdateJobs()** - Auto-spawn integration

### Phase 3: Risk Management
1. **GetUnrealizedPnL()** - Tracks floating P&L per job
2. **GetRealizedPnL()** - Tracks closed profit per job
3. **ShouldStopJob()** - Job SL enforcement
4. **ShouldAbandonJob()** - Job DD abandon logic
5. **AbandonJob()** - Mark job unsaveable, keep positions

### Files Modified
- `src/core/GridBasket.mqh` - Added IsGridFull(), IsTSLActive(), GetActivePositionCount()
- `src/core/LifecycleController.mqh` - Added GetUnrealizedPnL(), GetRealizedPnL(), GetTotalPnL(), IsTSLActive(), IsGridFull()
- `src/core/JobManager.mqh` - Added spawn/risk logic, updated UpdateJobs()
- `src/ea/RecoveryGridDirection_v2.mq5` - Added inputs, updated constructor

---

## ✅ Testing Checklist

### Test 1: Compilation

**Steps:**
1. Open MetaEditor
2. Open `src/ea/RecoveryGridDirection_v2.mq5`
3. Press F7 (Compile)

**Expected:**
- ✅ 0 errors, 0 warnings

**If fails:**
- Check error message
- Verify all includes correct
- Check constructor parameter count matches

---

### Test 2: Legacy Mode (Backward Compatibility)

**Purpose**: Verify v2.x still works

**Settings:**
```
InpMultiJobEnabled = false
InpMagic = 990045
```

**Steps:**
1. Strategy Tester
2. Symbol: EURUSD
3. Period: M5
4. Date: 2024-01-02 to 2024-01-03
5. Start

**Expected:**
- ✅ EA initializes
- ✅ Seeds BUY + SELL
- ✅ Normal trading (no job logic)
- ✅ Log: `[RGDv2]` (not `[RGDv3]`)

---

### Test 3: Multi-Job Single Job (Phase 1 + 2 + 3)

**Purpose**: Verify full system with 1 job

**Settings:**
```
InpMultiJobEnabled = true
InpMaxJobs = 1
InpMagicStart = 1000
InpSpawnCooldownSec = 30
InpJobSL_USD = 50.0
InpJobDDThreshold = 30.0
InpGridLevels = 6
```

**Steps:**
1. Strategy Tester (same as Test 2)
2. Start

**Expected:**
- ✅ Job 1 spawned (Magic 1000)
- ✅ Seeds BUY + SELL
- ✅ Orders: `RGDv2_J1_Seed`
- ✅ P&L tracking works
- ✅ Log: `[RGDv3][EURUSD][JobMgr]`

---

### Test 4: Grid Full Auto-Spawn (Phase 2)

**Purpose**: Verify grid full trigger

**Settings:**
```
InpMultiJobEnabled = true
InpMaxJobs = 5
InpGridLevels = 3           // ← Small grid
InpSpawnCooldownSec = 10    // ← Short cooldown
InpJobSL_USD = 100.0        // ← High SL (won't hit)
```

**Steps:**
1. Run backtest on strong trend (2024-01-02 to 2024-01-05)
2. Wait for Job 1 to fill 3 grid levels
3. Check logs

**Expected:**
- ✅ Job 1 fills 3 levels
- ✅ Log: `[Spawn] Job 1 grid full, spawning new job`
- ✅ Job 2 spawned (Magic 1421)
- ✅ Both jobs trade independently
- ✅ Orders: `RGDv2_J1_...` and `RGDv2_J2_...`

**Verify:**
- Job 1 and Job 2 have different magic numbers
- No cross-job position counting
- Both can have orders at similar prices (no collision)

---

### Test 5: TSL Active Auto-Spawn (Phase 2)

**Purpose**: Verify TSL trigger

**Settings:**
```
InpMultiJobEnabled = true
InpMaxJobs = 5
InpGridLevels = 10
InpTSLEnabled = true
InpTSLStartPoints = 1000
InpDDOpenUSD = 8.0          // Low threshold for quick rescue
InpSpawnCooldownSec = 10
```

**Steps:**
1. Run backtest
2. Wait for rescue deployment + TSL activation
3. Check logs

**Expected:**
- ✅ Rescue deploys on Job 1
- ✅ TSL activates
- ✅ Log: `[Spawn] Job 1 TSL active, spawning new job`
- ✅ Job 2 spawned

**Verify:**
- Job 1 continues trailing
- Job 2 starts fresh at current price
- Both jobs active simultaneously

---

### Test 6: Spawn Cooldown (Phase 2)

**Purpose**: Verify cooldown prevents rapid spawns

**Settings:**
```
InpSpawnCooldownSec = 60    // ← 1 minute cooldown
InpGridLevels = 2           // ← Very small grid
```

**Steps:**
1. Run backtest
2. Job 1 fills → triggers spawn
3. Immediately Job 2 fills → tries to spawn

**Expected:**
- ✅ Job 1 → Job 2 spawned
- ✅ Job 2 fills, but spawn blocked
- ✅ Log: `[Spawn] Cooldown active (5/60 sec)`
- ✅ Wait 60 sec → Job 3 spawned

---

### Test 7: Job SL Hit (Phase 3)

**Purpose**: Verify job stop loss

**Settings:**
```
InpMultiJobEnabled = true
InpMaxJobs = 5
InpJobSL_USD = 10.0         // ← Low SL for testing
InpGridLevels = 10
```

**Steps:**
1. Run backtest on strong trend
2. Job 1 accumulates losing positions
3. Wait for PnL to hit -$10

**Expected:**
- ✅ Job 1 PnL reaches -$10
- ✅ Log: `[SL] Job 1 PnL -10.50 <= -10.00, stopping`
- ✅ Log: `Job 1 stopped: SL hit: -10.50 USD`
- ✅ All Job 1 positions closed
- ✅ Job 1 status = JOB_STOPPED
- ✅ New jobs still can spawn

**Verify in Terminal:**
- All positions with Magic 1000 (Job 1) closed
- Other jobs (Magic 1421, 1842...) still active

---

### Test 8: Job Abandon (Phase 3)

**Purpose**: Verify abandon logic

**Settings:**
```
InpMultiJobEnabled = true
InpMaxJobs = 5
InpJobSL_USD = 0            // ← Disable SL
InpJobDDThreshold = 20.0    // ← Low abandon threshold
InpGlobalDDLimit = 50.0
```

**Steps:**
1. Run backtest
2. Let Job 1 accumulate large loss (20% DD)
3. Check logs

**Expected:**
- ✅ Job 1 DD reaches 20%
- ✅ Log: `[Abandon] Job 1 DD 20.5% >= 20.0%, abandoning`
- ✅ Log: `Job 1 abandoned (DD too high, positions kept open)`
- ✅ Job 1 status = JOB_ABANDONED
- ✅ **Positions NOT closed** (might recover)
- ✅ Job 1 no longer managed (Update() skipped)
- ✅ New jobs still spawn

**Verify:**
- Job 1 positions still open in Terminal
- JobManager skips Job 1 in UpdateJobs() loop
- Other jobs trade normally

---

### Test 9: Global DD Block (Phase 2)

**Purpose**: Verify global DD stops new spawns

**Settings:**
```
InpMultiJobEnabled = true
InpMaxJobs = 10
InpGlobalDDLimit = 10.0     // ← Low limit
InpGridLevels = 3
```

**Steps:**
1. Run backtest
2. Create 10% global DD
3. Try to trigger spawn (grid full)

**Expected:**
- ✅ Global DD reaches 10%
- ✅ Grid full triggers spawn attempt
- ✅ Log: `[Spawn] Global DD 10.5% >= 10.0%, blocked`
- ✅ No new job spawned
- ✅ Existing jobs continue trading

---

### Test 10: Multi-Job Portfolio (Full Test)

**Purpose**: Verify 3+ jobs trading simultaneously

**Settings:**
```
InpMultiJobEnabled = true
InpMaxJobs = 5
InpGridLevels = 5
InpSpawnCooldownSec = 30
InpJobSL_USD = 50.0
InpJobDDThreshold = 30.0
InpGlobalDDLimit = 50.0
```

**Steps:**
1. Run backtest on volatile period (2024-01-02 to 2024-01-10)
2. Let system spawn 3+ jobs
3. Check logs and Terminal

**Expected:**
- ✅ Job 1 spawns at start
- ✅ Job 1 grid full → Job 2 spawns
- ✅ Job 2 TSL active → Job 3 spawns
- ✅ All jobs trade independently
- ✅ Job 1 hits SL → stopped
- ✅ Job 2 & 3 continue trading
- ✅ Portfolio profit even if Job 1 lost

**Verify:**
- Orders with Magic 1000, 1421, 1842
- Comments: `RGDv2_J1_...`, `RGDv2_J2_...`, `RGDv2_J3_...`
- No cross-job interference
- Accurate P&L tracking per job

---

## 📊 Success Criteria

Phase 2 & 3 testing successful when:

1. ✅ Compiles without errors
2. ✅ Legacy mode works (backward compatible)
3. ✅ Grid full auto-spawns new job
4. ✅ TSL active auto-spawns new job
5. ✅ Spawn cooldown prevents rapid loops
6. ✅ Max spawns limit enforced
7. ✅ Global DD blocks new spawns
8. ✅ Job SL stops job at -$X
9. ✅ Job DD abandons unsaveable jobs
10. ✅ Multiple jobs trade independently
11. ✅ No cross-job position counting
12. ✅ P&L tracking accurate per job
13. ✅ Portfolio continues even if 1 job stops
14. ✅ Logs clear with job_id tags

---

## 🐛 Common Issues

### Issue 1: "Undeclared identifier GetUnrealizedPnL"
**Solution**: LifecycleController.mqh missing methods. Check Phase 3 Step 3 implementation.

### Issue 2: "Wrong parameters count for CJobManager"
**Solution**: EA passing wrong number of params. Update RecoveryGridDirection_v2.mq5 line 537-552.

### Issue 3: "Job keeps spawning infinitely"
**Solution**: Check spawn cooldown and max spawns limit.

### Issue 4: "Job SL not triggering"
**Solution**: Check InpJobSL_USD > 0 and PnL tracking working.

### Issue 5: "Jobs counting each other's positions"
**Solution**: Verify IsMyOrder() filters by job magic correctly.

---

## 📝 Testing Report Template

```
## Phase 2 & 3 Testing Report

**Date**: 2025-10-04
**Tester**: [Your name]
**Branch**: feature/multi-job-v3.0

### Compilation
- [ ] Pass

### Legacy Mode
- [ ] Pass

### Grid Full Spawn
- [ ] Pass - Job 2 spawned when Job 1 grid full

### TSL Active Spawn
- [ ] Pass - Job 2 spawned when Job 1 TSL active

### Spawn Cooldown
- [ ] Pass - 30 sec cooldown working

### Job SL Hit
- [ ] Pass - Job stopped at -$50

### Job Abandon
- [ ] Pass - Job abandoned at 30% DD, positions kept

### Global DD Block
- [ ] Pass - Spawn blocked at 50% DD

### Multi-Job Portfolio
- [ ] Pass - 3 jobs trading independently

### Overall Result
- [ ] ✅ PASS - Ready for production testing
- [ ] ❌ FAIL - Issues: [list]

### Notes
[Observations, suggestions, concerns]
```

---

## 🚀 Next Steps (After Phase 2 & 3 Complete)

**Phase 4**: UI & Stats (optional)
- Multi-job panel display
- Per-job P&L chart
- Portfolio summary

**Production Testing**:
- Demo account testing (1-2 weeks)
- Monitor spawn behavior
- Monitor risk enforcement
- Check edge cases

---

**Status**: Ready for testing! 🚀

**When ready**: Test tonight, report results, then consider Phase 4 or production demo testing.
