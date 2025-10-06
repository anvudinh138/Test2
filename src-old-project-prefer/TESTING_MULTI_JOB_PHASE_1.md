# Multi-Job Phase 1 Testing Guide

**Status**: Code complete, ready for compilation & testing
**Branch**: `feature/multi-job-v3.0`
**Completed**: Steps 1-5 (83% of Phase 1)

---

## 🎯 What Was Implemented

### Core Components
1. **EJobStatus enum** - Job states (ACTIVE, FULL, STOPPED, ABANDONED)
2. **SJob struct** - Job metadata (id, magic, controller, P&L, status)
3. **CJobManager class** - Spawns and manages multiple jobs
4. **Magic isolation** - Each job has unique magic (start + offset)
5. **Job-aware filtering** - IsMyOrder() prevents cross-job counting
6. **Order comments** - RGDv2_J1_Seed, RGDv2_J2_RescueSeed
7. **EA integration** - Multi-job mode fully wired

### Files Modified
- `src/core/Types.mqh` - Added EJobStatus enum
- `src/core/JobManager.mqh` - **NEW FILE** - Job manager
- `src/core/GridBasket.mqh` - Added job_id, IsMyOrder(), BuildComment()
- `src/core/LifecycleController.mqh` - Added job_id parameter
- `src/ea/RecoveryGridDirection_v2.mq5` - Multi-job inputs & integration

---

## ✅ Step 6: Testing Checklist

### 6.1 Compilation Test (REQUIRED)

**Open MetaEditor:**
1. File → Open → `src/ea/RecoveryGridDirection_v2.mq5`
2. Press **F7** (Compile)
3. Check for errors in Toolbox → Errors tab

**Expected result**: ✅ `0 error(s), 0 warning(s)`

**If compilation fails:**
- Check error message
- Common issues:
  - Missing semicolon
  - Undeclared variable
  - Wrong include path
- Fix and recompile

---

### 6.2 Legacy Mode Test (Backward Compatibility)

**Purpose**: Verify v2.x behavior still works (no multi-job)

**Settings:**
```
InpMultiJobEnabled = false  // ← OFF (legacy mode)
InpMagic = 990045          // Use existing magic
```

**Steps:**
1. Open Strategy Tester (Ctrl+R)
2. Select EA: `RecoveryGridDirection_v2`
3. Symbol: `EURUSD`
4. Period: `M5`
5. Date: 2024-01-02 to 2024-01-03 (1 day)
6. Model: Every tick
7. Settings → Parameters:
   - `InpMultiJobEnabled = false`
   - `InpGridLevels = 6`
   - `InpLotBase = 0.01`
   - `InpTargetCycleUSD = 3.0`
8. **Start** test

**Expected behavior:**
- ✅ EA initializes successfully
- ✅ Log: `[RGDv2] Init OK - Symbol=EURUSD...`
- ✅ Seeds BUY + SELL baskets
- ✅ Orders have comment: `RGDv2_Seed` (NO "J1" - legacy format)
- ✅ All orders use magic `990045`
- ✅ Normal trading behavior (same as v2.7)

**If test fails:**
- Check Experts tab for error logs
- Verify `g_controller` created (not `g_job_manager`)
- Check OnInit() log messages

---

### 6.3 Multi-Job Mode Test (Single Job)

**Purpose**: Verify multi-job system works with 1 job only

**Settings:**
```
InpMultiJobEnabled = true   // ← ON (multi-job mode)
InpMaxJobs = 1              // Limit to 1 job for now
InpMagicStart = 1000        // Starting magic
InpMagicOffset = 421        // Offset (unused for 1 job)
InpGlobalDDLimit = 50.0     // DD limit
```

**Steps:**
1. Strategy Tester settings (same as 6.2)
2. Settings → Parameters:
   - `InpMultiJobEnabled = true`
   - `InpMaxJobs = 1`
   - `InpMagicStart = 1000`
   - `InpGridLevels = 6`
3. **Start** test

**Expected behavior:**
- ✅ EA initializes successfully
- ✅ Log: `[RGDv3] Multi-job mode enabled (Job 1 spawned, Magic 1000)`
- ✅ Seeds BUY + SELL baskets
- ✅ Orders have comment: `RGDv2_J1_Seed` (WITH "J1")
- ✅ All orders use magic `1000` (NOT 990045)
- ✅ Normal trading behavior

**If test fails:**
- Check if `g_job_manager` created
- Verify SpawnJob() returned > 0
- Check magic number = 1000

---

### 6.4 Multi-Job Magic Isolation Test (Manual)

**Purpose**: Verify magic number calculation

**Test in OnInit():**

Add temporary logging after `SpawnJob()`:
```cpp
int first_job = g_job_manager.SpawnJob();
Print("DEBUG: Job 1 magic = ", g_job_manager.CalculateJobMagic(1));  // Should be 1000
Print("DEBUG: Job 2 magic = ", g_job_manager.CalculateJobMagic(2));  // Should be 1421
Print("DEBUG: Job 3 magic = ", g_job_manager.CalculateJobMagic(3));  // Should be 1842
```

**Expected output:**
```
DEBUG: Job 1 magic = 1000
DEBUG: Job 2 magic = 1421
DEBUG: Job 3 magic = 1842
```

**Verify reverse calculation:**
```cpp
Print("DEBUG: Magic 1000 → Job ", g_job_manager.GetJobIdFromMagic(1000));  // Should be 1
Print("DEBUG: Magic 1421 → Job ", g_job_manager.GetJobIdFromMagic(1421));  // Should be 2
```

---

### 6.5 Order Comment Format Test

**Purpose**: Verify comments include job_id

**Check Terminal → Trade tab during test:**

**Legacy mode (InpMultiJobEnabled=false):**
```
Comment: RGDv2_Seed
Comment: RGDv2_RescueSeed
Comment: RGDv2_GridRefill
```

**Multi-job mode (InpMultiJobEnabled=true, Job 1):**
```
Comment: RGDv2_J1_Seed
Comment: RGDv2_J1_RescueSeed
Comment: RGDv2_J1_GridRefill
```

**If Job 2 exists (future test):**
```
Comment: RGDv2_J2_Seed
Comment: RGDv2_J2_RescueSeed
```

---

### 6.6 Position Counting Test (Job Isolation)

**Purpose**: Verify each job counts only its own positions

**Setup:**
- Enable multi-job: `InpMultiJobEnabled = true`
- Max jobs: `InpMaxJobs = 1`

**Verify:**
1. Job 1 opens BUY position (magic 1000, comment RGDv2_J1_Seed)
2. Check log: `[RGDv2][EURUSD][J1][BUY][PRI] ...` (includes "J1")
3. RefreshState() should count ONLY magic 1000 positions
4. TotalLot() should match positions with magic 1000

**Manual verification:**
- Add debug log in GridBasket::RefreshState():
  ```cpp
  Print("DEBUG: RefreshState Job ", m_job_id, " Magic ", m_magic, " found ", m_total_lot, " lot");
  ```

---

## 🐛 Common Issues & Solutions

### Issue 1: Compilation Error - "Undeclared identifier"
**Solution**: Check include order in RecoveryGridDirection_v2.mq5:
- JobManager.mqh must be AFTER LifecycleController.mqh

### Issue 2: "JobManager creation failed"
**Solution**: Check OnInit() logs, verify:
- All shared resources created (spacing, executor, rescue)
- Constructor parameters correct

### Issue 3: "First job spawn failed"
**Solution**: Check SpawnJob() logs, common causes:
- Max jobs = 0
- Global DD already exceeded
- Controller.Init() failed (check symbol valid)

### Issue 4: Orders still use old magic (990045)
**Solution**: Verify:
- InpMultiJobEnabled = true
- g_job_manager != NULL (not g_controller)
- SpawnJob() succeeded

### Issue 5: Comments missing "J1"
**Solution**: Check:
- m_job_id passed to GridBasket constructor
- BuildComment() used (not hardcoded strings)

---

## 📊 Success Criteria

Phase 1 testing is successful when:

1. ✅ Compiles without errors
2. ✅ Legacy mode works (InpMultiJobEnabled=false)
3. ✅ Multi-job mode works (InpMultiJobEnabled=true, 1 job)
4. ✅ Magic number calculated correctly (1000, 1421, 1842)
5. ✅ Order comments show job_id (RGDv2_J1_Seed)
6. ✅ Logs show job_id tags ([RGDv2][symbol][J1][LC])
7. ✅ Position filtering isolated (no cross-job counting)

---

## 🚀 Next Steps (After Phase 1 Complete)

**Phase 2**: Spawn Triggers (1 week)
- Detect grid full
- Detect TSL active
- Auto-spawn new job
- Test: 2-3 jobs trading simultaneously

**Phase 3**: Risk Management (1 week)
- Job SL (per-job stop loss)
- Job DD threshold (abandon logic)
- Global DD limit enforcement
- Test: Job stops correctly

**Phase 4**: UI & Stats (1 week)
- Multi-job panel display
- Per-job P&L tracking
- Portfolio summary
- Test: Stats accurate

---

## 📝 Testing Report Template

```
## Phase 1 Testing Report

**Date**: YYYY-MM-DD
**Tester**: [Your name]
**Branch**: feature/multi-job-v3.0
**Commit**: [git commit hash]

### 6.1 Compilation Test
- [ ] Pass - 0 errors, 0 warnings
- [ ] Fail - Error: [describe]

### 6.2 Legacy Mode Test
- [ ] Pass - v2.x behavior confirmed
- [ ] Fail - Issue: [describe]

### 6.3 Multi-Job Single Job Test
- [ ] Pass - Job 1 spawned, magic 1000
- [ ] Fail - Issue: [describe]

### 6.4 Magic Calculation Test
- [ ] Pass - 1000, 1421, 1842 correct
- [ ] Fail - Issue: [describe]

### 6.5 Comment Format Test
- [ ] Pass - RGDv2_J1_Seed confirmed
- [ ] Fail - Issue: [describe]

### 6.6 Position Isolation Test
- [ ] Pass - Each job counts only its magic
- [ ] Fail - Issue: [describe]

### Overall Result
- [ ] ✅ PASS - Ready for Phase 2
- [ ] ❌ FAIL - Needs fixes: [list issues]

### Notes
[Any observations, suggestions, or concerns]
```

---

## 💡 Tips for Testing

1. **Start simple**: Test legacy mode first (known working state)
2. **One change at a time**: Test single job before multiple jobs
3. **Check logs**: Experts tab is your friend
4. **Use Visual Mode**: See orders appear in real-time
5. **Take screenshots**: Document any issues found
6. **Test on demo**: NEVER test on live account

---

**Status**: Ready for testing! 🚀

**When ready to continue**: After successful testing, proceed to Phase 2 (Spawn Triggers)
