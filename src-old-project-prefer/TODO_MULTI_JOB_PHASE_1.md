# Multi-Job System - Phase 1 TODO List

**Branch**: `feature/multi-job-v3.0` (create from `feature/lot-percent-risk`)
**Duration**: 1-2 weeks
**Goal**: Foundation - Job struct, Manager class, Magic isolation, Independent trading

---

## 📋 Phase 1 Checklist

### Step 1: Create Branch & Setup (30 min)

- [ ] Create branch from current: `git checkout -b feature/multi-job-v3.0`
- [ ] Update CLAUDE.md with Phase 1 goals
- [ ] Create backup of working v2.x code
- [ ] Test current code compiles before changes

### Step 2: Core Data Structures (2 hours)

#### 2.1 Job Struct (src/core/Types.mqh)

- [ ] Add `EJobStatus` enum:
  ```cpp
  enum EJobStatus
  {
     JOB_ACTIVE,      // Trading normally
     JOB_FULL,        // Grid full, may spawn new
     JOB_STOPPED,     // SL hit or manual stop
     JOB_ABANDONED    // DD too high, can't save
  };
  ```

- [ ] Create `SJob` struct:
  ```cpp
  struct SJob
  {
     int          job_id;              // Unique ID (1, 2, 3...)
     long         magic;               // Job magic number
     datetime     created_at;          // Spawn timestamp

     CLifecycleController *controller; // Job's lifecycle

     double       job_sl_usd;          // Max loss USD
     double       job_dd_threshold;    // DD% abandon

     EJobStatus   status;              // Current status
     bool         is_full;             // Grid full flag
     bool         is_tsl_active;       // TSL active flag

     double       realized_pnl;        // Closed profit
     double       unrealized_pnl;      // Floating P&L
     double       peak_equity;         // Peak for DD calc
  };
  ```

- [ ] Test: Compile Types.mqh successfully

#### 2.2 Job Manager Class (NEW: src/core/JobManager.mqh)

- [ ] Create file `src/core/JobManager.mqh`
- [ ] Add class skeleton:
  ```cpp
  class CJobManager
  {
  private:
     SJob         m_jobs[];            // Job array
     int          m_next_job_id;       // Auto-increment
     long         m_magic_start;       // User input start
     long         m_magic_offset;      // User input offset
     double       m_global_dd_limit;   // Global DD%

     CPortfolioLedger *m_ledger;       // Global ledger
     CLogger      *m_log;              // Logger
     string       m_symbol;            // Symbol

  public:
     CJobManager(const string symbol,
                 const long magic_start,
                 const long magic_offset,
                 const double global_dd_limit,
                 CPortfolioLedger *ledger,
                 CLogger *logger);

     // Job lifecycle
     int  SpawnJob(const SParams &params);
     void StopJob(const int job_id, const string reason);
     void UpdateJobs();

     // Queries
     int  GetActiveJobCount();
     SJob* GetJob(int job_id);

     // Magic helpers
     long CalculateJobMagic(int job_id);
     int  GetJobIdFromMagic(long magic);
  };
  ```

- [ ] Implement constructor
- [ ] Implement `CalculateJobMagic()`:
  ```cpp
  long CalculateJobMagic(int job_id)
  {
     return m_magic_start + ((job_id - 1) * m_magic_offset);
     // Job 1: 1000 + 0*421 = 1000
     // Job 2: 1000 + 1*421 = 1421
  }
  ```

- [ ] Implement `GetJobIdFromMagic()`:
  ```cpp
  int GetJobIdFromMagic(long magic)
  {
     if(magic < m_magic_start) return -1;
     return ((magic - m_magic_start) / m_magic_offset) + 1;
  }
  ```

- [ ] Test: Compile JobManager.mqh successfully

### Step 3: Magic Number Isolation (4 hours)

#### 3.1 Update GridBasket for Job Awareness

- [ ] Add `m_job_id` member to `CGridBasket`:
  ```cpp
  class CGridBasket
  {
  private:
     int m_job_id;  // NEW: Job identifier
     // ... existing members
  };
  ```

- [ ] Update constructor to accept `job_id`
- [ ] Add `IsMyOrder()` method:
  ```cpp
  bool IsMyOrder(ulong ticket) const
  {
     if(!PositionSelectByTicket(ticket)) return false;

     long order_magic = PositionGetInteger(POSITION_MAGIC);
     return order_magic == m_magic;  // m_magic set by job
  }
  ```

- [ ] Update `RefreshState()` to filter by job magic:
  ```cpp
  void RefreshState()
  {
     int total = PositionsTotal();
     for(int i = 0; i < total; i++)
     {
        ulong ticket = PositionGetTicket(i);

        // CRITICAL: Only count this job's orders
        if(!IsMyOrder(ticket))
           continue;

        // Rest of logic...
     }
  }
  ```

- [ ] Update `CountPending()` to filter by job magic
- [ ] Update `TotalLot()` to filter by job magic
- [ ] Update `RescueLot()` to filter by job magic
- [ ] Test: Compile GridBasket.mqh

#### 3.2 Update LifecycleController for Job Awareness

- [ ] Add `m_job_id` member to `CLifecycleController`
- [ ] Update constructor to accept `job_id`
- [ ] Pass `job_id` to BUY/SELL baskets on creation:
  ```cpp
  m_buy = new CGridBasket(m_symbol, DIR_BUY, BASKET_PRIMARY,
                          m_params, spacing, executor, logger,
                          job_magic, job_id);  // ← NEW: job_id
  ```

- [ ] Update `Tag()` to include job_id:
  ```cpp
  string Tag() const
  {
     return StringFormat("[RGDv2][%s][J%d]", m_symbol, m_job_id);
  }
  ```

- [ ] Test: Compile LifecycleController.mqh

#### 3.3 Update OrderExecutor for Job Comments

- [ ] Add `m_job_id` member to `COrderExecutor`
- [ ] Update comment building:
  ```cpp
  string BuildComment(const string type)
  {
     return StringFormat("RGDv2_J%d_%s", m_job_id, type);
     // "RGDv2_J1_Seed", "RGDv2_J2_RescueSeed"
  }
  ```

- [ ] Update all `Market()`, `Limit()` calls to use new format
- [ ] Test: Compile OrderExecutor.mqh

### Step 4: Job Manager Core Functions (4 hours)

#### 4.1 SpawnJob Implementation

- [ ] Implement `SpawnJob()`:
  ```cpp
  int CJobManager::SpawnJob(const SParams &params)
  {
     // Check limits
     if(ArraySize(m_jobs) >= m_max_jobs)
     {
        m_log.Event("[JobMgr]", "Max jobs reached, cannot spawn");
        return -1;
     }

     // Check global DD
     if(m_ledger.GetEquityDrawdownPercent() >= m_global_dd_limit)
     {
        m_log.Event("[JobMgr]", "Global DD limit, spawn blocked");
        return -1;
     }

     // Calculate job magic
     int job_id = m_next_job_id++;
     long job_magic = CalculateJobMagic(job_id);

     // Create job struct
     SJob job;
     job.job_id = job_id;
     job.magic = job_magic;
     job.created_at = TimeCurrent();
     job.status = JOB_ACTIVE;
     // ... init other fields

     // Create lifecycle controller with job magic
     job.controller = new CLifecycleController(
        m_symbol, params, job_magic, job_id, ...
     );

     // Add to array
     int new_size = ArraySize(m_jobs) + 1;
     ArrayResize(m_jobs, new_size);
     m_jobs[new_size - 1] = job;

     m_log.Event("[JobMgr]", StringFormat(
        "Job %d spawned (Magic %d)", job_id, job_magic
     ));

     return job_id;
  }
  ```

- [ ] Test: Can create job struct successfully

#### 4.2 UpdateJobs Implementation

- [ ] Implement `UpdateJobs()`:
  ```cpp
  void CJobManager::UpdateJobs()
  {
     for(int i = 0; i < ArraySize(m_jobs); i++)
     {
        if(m_jobs[i].status != JOB_ACTIVE)
           continue;

        // Update lifecycle
        m_jobs[i].controller.OnTick();

        // Update stats
        m_jobs[i].unrealized_pnl = m_jobs[i].controller.GetUnrealizedPnL();
        m_jobs[i].realized_pnl = m_jobs[i].controller.GetRealizedPnL();

        // Update peak equity
        double current_equity = m_jobs[i].realized_pnl + m_jobs[i].unrealized_pnl;
        if(current_equity > m_jobs[i].peak_equity)
           m_jobs[i].peak_equity = current_equity;
     }
  }
  ```

- [ ] Test: Jobs update correctly

#### 4.3 StopJob Implementation

- [ ] Implement `StopJob()`:
  ```cpp
  void CJobManager::StopJob(int job_id, const string reason)
  {
     SJob *job = GetJob(job_id);
     if(job == NULL) return;

     job.controller.CloseAll(reason);
     job.status = JOB_STOPPED;

     m_log.Event("[JobMgr]", StringFormat(
        "Job %d stopped: %s", job_id, reason
     ));
  }
  ```

- [ ] Test: Can stop job successfully

### Step 5: EA Integration (3 hours)

#### 5.1 Update Main EA (RecoveryGridDirection_v2.mq5)

- [ ] Add multi-job inputs:
  ```cpp
  input group  "=== Multi-Job System (v3.0 EXPERIMENTAL) ==="
  input bool   InpMultiJobEnabled = false;
  input int    InpMaxJobs = 5;
  input double InpJobSL_USD = 50.0;
  input double InpJobDDThreshold = 30.0;
  input double InpGlobalDDLimit = 50.0;
  input int    InpGridLevelsPerJob = 10;

  input group  "=== Magic Number (Job Isolation) ==="
  input long   InpMagicStart = 1000;
  input long   InpMagicOffset = 421;
  ```

- [ ] Add global variables:
  ```cpp
  CJobManager *g_job_manager = NULL;
  ```

- [ ] Update `OnInit()`:
  ```cpp
  int OnInit()
  {
     if(InpMultiJobEnabled)
     {
        // Multi-job mode (v3.0)
        g_job_manager = new CJobManager(
           _Symbol, InpMagicStart, InpMagicOffset,
           InpGlobalDDLimit, g_ledger, g_logger
        );

        // Spawn first job
        g_job_manager.SpawnJob(g_params);
     }
     else
     {
        // Legacy single lifecycle (v2.x)
        g_controller = new CLifecycleController(...);
     }

     return INIT_SUCCEEDED;
  }
  ```

- [ ] Update `OnTick()`:
  ```cpp
  void OnTick()
  {
     if(InpMultiJobEnabled && g_job_manager != NULL)
     {
        g_job_manager.UpdateJobs();
     }
     else if(g_controller != NULL)
     {
        g_controller.OnTick();  // Legacy
     }
  }
  ```

- [ ] Update `OnDeinit()`:
  ```cpp
  void OnDeinit(const int reason)
  {
     if(g_job_manager != NULL)
     {
        delete g_job_manager;
        g_job_manager = NULL;
     }

     if(g_controller != NULL)
     {
        delete g_controller;
        g_controller = NULL;
     }
  }
  ```

- [ ] Test: EA compiles successfully

### Step 6: Testing (4 hours)

#### 6.1 Single Job Test

- [ ] Enable multi-job: `InpMultiJobEnabled = true`
- [ ] Set `InpMaxJobs = 1` (limit to 1 job)
- [ ] Set magic: `InpMagicStart = 1000`, `InpMagicOffset = 421`
- [ ] Run in Strategy Tester (1 day)
- [ ] Verify:
  - [ ] Job 1 created with magic 1000
  - [ ] Orders have comment "RGDv2_J1_Seed"
  - [ ] Job counts only its own positions
  - [ ] No cross-job interference (only 1 job)

#### 6.2 Two Independent Jobs Test (Manual)

- [ ] Set `InpMaxJobs = 2`
- [ ] Manually spawn Job 2 after 1 hour:
  ```cpp
  // Add temporary code in OnTick():
  static bool spawned_job2 = false;
  if(!spawned_job2 && TimeCurrent() - g_jobs[0].created_at >= 3600)
  {
     g_job_manager.SpawnJob(g_params);
     spawned_job2 = true;
  }
  ```

- [ ] Verify:
  - [ ] Job 1: Magic 1000, Comment "RGDv2_J1_..."
  - [ ] Job 2: Magic 1421, Comment "RGDv2_J2_..."
  - [ ] Each job counts only its own orders
  - [ ] Terminal shows both magics clearly
  - [ ] No cross-job position counting

#### 6.3 Magic Isolation Test

- [ ] Create 3 jobs manually
- [ ] Verify magic numbers:
  - [ ] Job 1: 1000
  - [ ] Job 2: 1421
  - [ ] Job 3: 1842
- [ ] Verify `GetJobIdFromMagic()`:
  - [ ] Magic 1000 → job_id 1 ✓
  - [ ] Magic 1421 → job_id 2 ✓
  - [ ] Magic 1842 → job_id 3 ✓
- [ ] Check Terminal comment column:
  - [ ] Clear "J1", "J2", "J3" visible
  - [ ] Easy to identify job visually

#### 6.4 Grid Collision Test

- [ ] Job 1 at price 3350
- [ ] Job 2 at price 3348 (overlapping grids)
- [ ] Verify:
  - [ ] Job 1 grids: 3340, 3345, 3350 (magic 1000)
  - [ ] Job 2 grids: 3338, 3343, 3348 (magic 1421)
  - [ ] Each job RefreshState() counts ONLY its magic
  - [ ] Job 1 total lot = only magic 1000 orders
  - [ ] Job 2 total lot = only magic 1421 orders
  - [ ] No cross-contamination

### Step 7: Documentation & Commit (1 hour)

- [ ] Update CLAUDE.md:
  ```md
  ### Phase 1: Multi-Job Foundation - COMPLETED

  - Created SJob struct with job_id, magic, status
  - Created CJobManager class (spawn, update, stop)
  - Magic isolation: start + offset pattern (1000, 1421, 1842)
  - Job-aware position filtering (RefreshState by job magic)
  - Comment format: RGDv2_J1_Seed, RGDv2_J2_RescueSeed
  - Tested: 3 jobs trading independently, no interference
  ```

- [ ] Update design doc with test results
- [ ] Create commit:
  ```bash
  git add -A
  git commit -m "feat(multi-job): Phase 1 - Foundation complete

  - Add SJob struct with job_id, magic, status
  - Add CJobManager (spawn, update, stop jobs)
  - Implement magic isolation (start + offset)
  - Update GridBasket/LifecycleController for job awareness
  - Add job_id to order comments (RGDv2_J1_Seed)
  - Test: 3 jobs trading independently

  Breaking: EA requires InpMultiJobEnabled=true for v3.0 mode"
  ```

- [ ] Push to remote:
  ```bash
  git push origin feature/multi-job-v3.0
  ```

---

## ✅ Phase 1 Completion Criteria

Phase 1 is complete when:

1. ✅ `CJobManager` can spawn multiple jobs
2. ✅ Each job has unique magic (start + offset)
3. ✅ Jobs trade independently (no cross-counting)
4. ✅ Order comments show job_id clearly
5. ✅ 3 jobs tested without interference
6. ✅ Magic collision avoided (different EAs safe)
7. ✅ Code compiles without errors
8. ✅ Documentation updated

---

## 🚫 What NOT to Implement in Phase 1

- ❌ Spawn triggers (grid full, TSL) → Phase 2
- ❌ Job SL / DD threshold → Phase 3
- ❌ Multi-job UI panel → Phase 4
- ❌ Portfolio stats → Phase 4
- ❌ Optimization → Phase 5

**Focus**: Foundation only. Get jobs trading independently first!

---

## 📊 Estimated Time Breakdown

| Task | Hours |
|------|-------|
| Branch setup | 0.5 |
| Data structures | 2 |
| Magic isolation | 4 |
| Job manager core | 4 |
| EA integration | 3 |
| Testing | 4 |
| Documentation | 1 |
| **TOTAL** | **18.5 hours** |

**Calendar**: 3-4 days (if working 5-6 hours/day)

---

## 🐛 Common Issues & Solutions

### Issue 1: Cross-job position counting
**Symptom**: Job 1 counts Job 2's orders
**Fix**: Ensure `IsMyOrder()` checks `order_magic == m_magic` strictly

### Issue 2: Comment not showing job_id
**Symptom**: Still seeing "RGDv2_Seed" without "J1"
**Fix**: Check `BuildComment()` includes job_id parameter

### Issue 3: Magic calculation wrong
**Symptom**: Job 3 has magic 2000 instead of 1842
**Fix**: Formula should be `start + (id-1)*offset`, not `start + id*offset`

### Issue 4: Compilation errors
**Symptom**: "Undeclared identifier" for SJob
**Fix**: Include Types.mqh before JobManager.mqh

---

**Next**: After Phase 1 complete → Move to Phase 2 (Spawn Logic)
