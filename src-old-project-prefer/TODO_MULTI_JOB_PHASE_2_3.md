# Multi-Job Phase 2 & 3 TODO

**Branch**: `feature/multi-job-v3.0`
**Status**: Implementation in progress
**Goal**: Auto-spawn + Risk Management

---

## Phase 2: Spawn Triggers

### Step 1: Grid Full Detection (GridBasket)

**File**: `src/core/GridBasket.mqh`

- [ ] Add `IsGridFull()` method
  - Check if active positions count >= grid_levels
  - Return true when grid fully loaded
- [ ] Add `GetActivePositionCount()` helper
  - Count positions with current magic
  - Exclude pending orders

**Estimate**: 15 minutes

---

### Step 2: TSL Active Detection (GridBasket)

**File**: `src/core/GridBasket.mqh`

- [ ] Add `IsTSLActive()` method
  - Check if m_tsl_enabled == true
  - Return TSL activation status
- [ ] Update TSL activation flag in existing TSL logic

**Estimate**: 10 minutes

---

### Step 3: Spawn Decision Logic (JobManager)

**File**: `src/core/JobManager.mqh`

- [ ] Add `ShouldSpawnNew(SJob &job)` method
  - Trigger 1: Grid full (BUY or SELL)
  - Trigger 2: TSL active on any basket
  - Trigger 3: Job DD >= threshold
  - Guard: Block if global DD >= limit
- [ ] Add spawn cooldown (30 seconds between spawns)
  - Prevent rapid spawn loops
  - Add `m_last_spawn_time` member

**Estimate**: 20 minutes

---

### Step 4: Auto-Spawn Integration

**File**: `src/core/JobManager.mqh`

- [ ] Update `UpdateJobs()` to check spawn triggers
  - Get newest job
  - Call ShouldSpawnNew()
  - Spawn if triggered
  - Log spawn reason
- [ ] Add spawn counter limit per session (max 10 spawns)
  - Prevent infinite spawn loops
  - Add `m_total_spawns` member

**Estimate**: 15 minutes

---

## Phase 3: Risk Management

### Step 5: Job Stop Loss (JobManager)

**File**: `src/core/JobManager.mqh`

- [ ] Add `ShouldStopJob(SJob &job)` method
  - Check unrealized PnL <= -job_sl_usd
  - Return true if SL breached
- [ ] Update `UpdateJobs()` to enforce job SL
  - Call ShouldStopJob() for each active job
  - Call StopJob() if triggered
  - Log SL hit event

**Estimate**: 15 minutes

---

### Step 6: Job Abandon Logic (JobManager)

**File**: `src/core/JobManager.mqh`

- [ ] Add `ShouldAbandonJob(SJob &job)` method
  - Calculate job DD% relative to account equity
  - Return true if job DD >= global DD limit
- [ ] Add `AbandonJob(job_id)` method
  - Set status = JOB_ABANDONED
  - Keep positions open (might recover)
  - Stop managing this job
  - Log abandon event

**Estimate**: 15 minutes

---

### Step 7: P&L Tracking (LifecycleController)

**File**: `src/core/LifecycleController.mqh`

- [ ] Add `GetUnrealizedPnL()` method
  - Return m_buy.PnL() + m_sell.PnL()
- [ ] Add `GetRealizedPnL()` method
  - Return m_buy.RealizedPnL() + m_sell.RealizedPnL()
- [ ] Add `GetTotalPnL()` method
  - Return unrealized + realized
- [ ] Add `IsTSLActive()` method
  - Return m_buy.IsTSLActive() || m_sell.IsTSLActive()
- [ ] Add `IsGridFull()` method
  - Return m_buy.IsGridFull() || m_sell.IsGridFull()

**Estimate**: 15 minutes

---

### Step 8: JobManager Risk Enforcement

**File**: `src/core/JobManager.mqh`

- [ ] Update `UpdateJobs()` with full risk management
  - Update job stats (P&L, peak equity)
  - Check ShouldStopJob() → StopJob()
  - Check ShouldAbandonJob() → AbandonJob()
  - Check ShouldSpawnNew() → SpawnJob()
- [ ] Add detailed logging for each decision
  - Log spawn triggers
  - Log SL hits
  - Log abandons

**Estimate**: 20 minutes

---

### Step 9: EA Input Parameters

**File**: `src/ea/RecoveryGridDirection_v2.mq5`

- [ ] Add spawn trigger inputs
  - InpSpawnOnGridFull (default true)
  - InpSpawnOnTSL (default true)
  - InpSpawnCooldownSec (default 30)
- [ ] Add risk management inputs
  - InpJobSL_USD (default 50.0)
  - InpJobDDThreshold (default 30.0)
- [ ] Pass new params to JobManager constructor
- [ ] Update SParams struct in Params.mqh

**Estimate**: 20 minutes

---

## Testing Checklist

### Phase 2 Tests (Spawn Triggers)

- [ ] **Test 1: Grid Full Spawn**
  - Set InpGridLevels = 3 (small grid)
  - Strong trend → Job 1 fills 3 levels
  - Expected: Job 2 spawns automatically
  - Verify: Log shows "Grid full, spawning Job 2"

- [ ] **Test 2: TSL Active Spawn**
  - Wait for rescue deployment + TSL activation
  - Expected: Job 2 spawns when TSL active
  - Verify: Log shows "TSL active, spawning Job 2"

- [ ] **Test 3: Spawn Cooldown**
  - Trigger spawn twice quickly
  - Expected: Second spawn blocked for 30 seconds
  - Verify: Log shows "Spawn cooldown active"

- [ ] **Test 4: Global DD Block**
  - Set InpGlobalDDLimit = 10%
  - Create 10% DD
  - Expected: Spawn blocked
  - Verify: Log shows "Global DD limit, spawn blocked"

---

### Phase 3 Tests (Risk Management)

- [ ] **Test 5: Job SL Hit**
  - Set InpJobSL_USD = 10.0
  - Let Job 1 lose > $10
  - Expected: Job 1 stopped, all positions closed
  - Verify: Log shows "Job 1 stopped: SL hit -$10.50"

- [ ] **Test 6: Job Abandon**
  - Set InpJobDDThreshold = 20%
  - Let Job 1 DD reach 20%
  - Expected: Job 1 abandoned, positions kept open
  - Verify: Log shows "Job 1 abandoned: DD 20.5%"

- [ ] **Test 7: Multi-Job Active**
  - Job 1 stopped at -$50 SL
  - Job 2 still active making profit
  - Expected: Portfolio continues trading
  - Verify: Job 2 independent, no impact from Job 1

- [ ] **Test 8: P&L Tracking**
  - Check logs for per-job P&L
  - Expected: Accurate unrealized + realized tracking
  - Verify: Numbers match Terminal positions

---

## Success Criteria

Phase 2 & 3 complete when:

1. ✅ Grid full auto-spawns new job
2. ✅ TSL active auto-spawns new job
3. ✅ Spawn cooldown prevents rapid loops
4. ✅ Global DD blocks new spawns
5. ✅ Job SL stops job at -$X limit
6. ✅ Job DD abandons unsaveable jobs
7. ✅ Multiple jobs trade independently
8. ✅ P&L tracking accurate per job

---

## Estimated Time

- Phase 2: ~1 hour (4 steps)
- Phase 3: ~1.5 hours (5 steps)
- Testing: ~30 minutes
- **Total**: ~3 hours

---

## Implementation Order

1. GridBasket helpers (IsGridFull, IsTSLActive) ← Foundation
2. LifecycleController getters (PnL, TSL, GridFull) ← Bridge
3. JobManager spawn logic (ShouldSpawnNew) ← Core
4. JobManager risk logic (ShouldStop, ShouldAbandon) ← Core
5. JobManager UpdateJobs() integration ← Orchestration
6. EA inputs & params ← Configuration
7. Testing ← Validation

---

**Status**: Ready to implement
**Next**: Start with GridBasket helpers
