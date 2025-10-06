# Multi-Job Lifecycle System - Design Document

## 🎯 Problem Statement

### Current Architecture (Single Lifecycle)
- **1 BUY basket + 1 SELL basket** managed by single LifecycleController
- **Infinite grid levels** → unlimited DCA when price trends strongly
- **Rescue dependency**: Losing basket depends on winning basket to rescue
- **Slow bubble burst**: When price trends strongly (e.g., strong downtrend):
  1. SELL basket (A) takes profit repeatedly ($5 target)
  2. BUY basket (B) accumulates lots via DCA (0.3-0.4 lot total)
  3. Rescue cannot save B forever → B becomes "slow bubble"
  4. Eventually: **Account blow-up** when B drawdown explodes

### Root Cause Analysis (Based on User's Images)

**Scenario: Strong Downtrend**
```
Initial: Sideways → A (SELL) + B (BUY) profitable, equity grows ✅

News/Trend starts:
├─ Price drops strongly
├─ A (SELL) closes profit at $5 target ✅
├─ B (BUY) hits 10+ grid levels (0.3-0.4 lot accumulated) ❌
├─ A rescues B continuously
├─ A closes profit again at $5 ✅
├─ B still losing heavily (DCA can't save) ❌
└─ Bubble grows until BOOM 💥 (account blown)
```

**Key Issue**:
- Single lifecycle **forced to wait** for old losing basket to break even
- New opportunities **blocked** while waiting for rescue
- Limited grid → can't DCA enough to save losing basket
- Infinite grid → slow bubble explosion

---

## 🚀 Proposed Solution: Multi-Job System

### Core Concept

**Treat each lifecycle as an independent JOB with:**
- ✅ Limited grid levels (5-10, not infinite)
- ✅ Dedicated budget (stop loss per job)
- ✅ Independent magic number group
- ✅ Isolated P&L tracking
- ✅ Automatic spawning when full

**When Job A grid full:**
1. Set **SL for Job A** (e.g., -$50 max loss) → treat as "sunk cost"
2. **Spawn Job B** at current price → new lifecycle, fresh start
3. Job B trades independently (doesn't wait for Job A breakeven)
4. If Job B also full → spawn Job C, D, E...

### Benefits

| Current System | Multi-Job System |
|---------------|-----------------|
| 1 lifecycle waits for rescue | Multiple jobs trade independently |
| Bubble grows when trend strong | Each job has limited risk (SL) |
| No new trades until breakeven | Always active at current price |
| Risk concentrated in 1 basket | Risk distributed across jobs |
| Account blow = total loss | Job blow = limited loss, others continue |

---

## 🏗️ Architecture Design

### 1. Job Structure

```cpp
struct SJob
{
   int          job_id;              // Unique job identifier
   long         magic_base;          // Base magic (e.g., 100000, 200000, 300000)
   datetime     created_at;          // Job spawn time

   // Lifecycle (existing structure)
   CLifecycleController *controller; // BUY + SELL baskets

   // Job-specific risk
   double       job_sl_usd;          // Max loss for this job (e.g., -$50)
   double       job_dd_threshold;    // Drawdown % to abandon job (e.g., 30%)

   // Status
   EJobStatus   status;              // ACTIVE, FULL, STOPPED, ABANDONED
   bool         is_full;             // Grid full (all levels filled)
   bool         is_tsl_active;       // Trailing stop active

   // Stats
   double       realized_pnl;        // Total realized P&L
   double       unrealized_pnl;      // Current floating P&L
   double       peak_equity;         // Peak equity for this job
};

enum EJobStatus
{
   JOB_ACTIVE,      // Trading normally
   JOB_FULL,        // Grid full, waiting for price return or spawn new
   JOB_STOPPED,     // SL hit or user stop
   JOB_ABANDONED    // DD too high, other jobs can't save this
};
```

### 2. Job Manager (New Component)

```cpp
class CJobManager
{
private:
   SJob         m_jobs[];            // Array of active jobs
   int          m_next_job_id;       // Auto-increment ID
   long         m_magic_increment;   // Magic number spacing (100000)
   double       m_global_dd_limit;   // Global DD% to stop spawning (e.g., 50%)

   // Portfolio-level tracking
   CPortfolioLedger *m_ledger;       // Global ledger (all jobs combined)

public:
   // Job lifecycle
   int          SpawnJob(const string symbol, const SParams &params);
   void         StopJob(const int job_id, const string reason);
   void         AbandonJob(const int job_id);

   // Main loop (replaces current OnTick)
   void         OnTick();

   // Job detection
   bool         ShouldSpawnNew(const SJob &current_job);
   bool         ShouldStopJob(const SJob &job);
   bool         ShouldAbandonJob(const SJob &job);

   // Portfolio queries
   double       GetTotalRealizedPnL();
   double       GetTotalUnrealizedPnL();
   int          GetActiveJobCount();
   SJob*        GetNewestJob();
};
```

### 3. Spawn Triggers

**When to spawn new job:**

```cpp
bool CJobManager::ShouldSpawnNew(const SJob &job)
{
   // Trigger 1: Grid full (all levels filled)
   if(job.controller.m_buy.IsGridFull() ||
      job.controller.m_sell.IsGridFull())
      return true;

   // Trigger 2: TSL active (basket in profit, trailing)
   if(job.is_tsl_active)
      return true;

   // Trigger 3: Job-specific DD threshold breached
   double job_dd_pct = (job.peak_equity - job.unrealized_pnl) / job.peak_equity * 100;
   if(job_dd_pct >= job.job_dd_threshold)
      return true;

   // Guard: Don't spawn if global DD too high
   double global_dd = m_ledger.GetEquityDrawdownPercent();
   if(global_dd >= m_global_dd_limit)
      return false;

   return false;
}
```

### 4. Stop/Abandon Logic

**Stop (SL hit):**
```cpp
bool CJobManager::ShouldStopJob(const SJob &job)
{
   // Close all positions when job SL breached
   if(job.unrealized_pnl <= -job.job_sl_usd)
   {
      job.controller.CloseAll("Job SL hit");
      job.status = JOB_STOPPED;
      return true;
   }
   return false;
}
```

**Abandon (DD too high, can't save):**
```cpp
bool CJobManager::ShouldAbandonJob(const SJob &job)
{
   // If job DD >= global account DD → other jobs can't save this
   double job_dd_usd = MathAbs(job.unrealized_pnl);
   double account_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double job_dd_pct = job_dd_usd / account_equity * 100;

   if(job_dd_pct >= m_global_dd_limit)
   {
      job.status = JOB_ABANDONED;
      // Keep positions open (might recover), but stop managing
      return true;
   }
   return false;
}
```

---

## 📊 Magic Number Design

### Current (Single Lifecycle)
```
Magic: 202501 (fixed)
All orders: same magic
```

### Multi-Job (Isolated with Offset)

**User-defined start + offset pattern:**
```
Input: InpMagicStart = 1000
Input: InpMagicOffset = 421

Job A: Magic 1000
Job B: Magic 1421  (1000 + 421)
Job C: Magic 1842  (1421 + 421)
Job D: Magic 2263  (1842 + 421)
...
```

**Magic calculation:**
```cpp
long CalculateJobMagic(int job_id)
{
   // job_id starts from 1
   return m_magic_start + ((job_id - 1) * m_magic_offset);
}

// Examples:
// Job 1: 1000 + (0 * 421) = 1000
// Job 2: 1000 + (1 * 421) = 1421
// Job 3: 1000 + (2 * 421) = 1842
```

**Why offset pattern?**
- ✅ Avoids collision with other EAs (custom start point)
- ✅ Clear visual separation in Terminal (1000, 1421, 1842...)
- ✅ Easy to identify job by magic: `job_id = (magic - start) / offset + 1`
- ✅ Supports up to 50+ jobs without overlap

### Order Comment Format (Job Identification)

**Current format:**
```
RGDv2_Seed
RGDv2_RescueSeed
RGDv2_GridRefill
```

**Multi-Job format (with Job ID):**
```
RGDv2_J1_Seed        // Job 1 seed order
RGDv2_J2_Seed        // Job 2 seed order
RGDv2_J1_RescueSeed  // Job 1 rescue
RGDv2_J3_GridRefill  // Job 3 grid refill
```

**Implementation:**
```cpp
string CJobManager::BuildComment(int job_id, const string type)
{
   return StringFormat("RGDv2_J%d_%s", job_id, type);
   // Examples:
   // job_id=1, type="Seed"       → "RGDv2_J1_Seed"
   // job_id=2, type="RescueSeed" → "RGDv2_J2_RescueSeed"
}
```

**Benefits:**
- ✅ Easy debug: See which job in Terminal
- ✅ Easy stats: Filter history by job_id
- ✅ Clear visual: "J1", "J2", "J3" in comment column
- ✅ Backward compat: Existing code searches "RGDv2_" prefix

---

## 🔄 Main Loop Flow

```cpp
void CJobManager::OnTick()
{
   // 1. Update all jobs
   for(int i = 0; i < ArraySize(m_jobs); i++)
   {
      if(m_jobs[i].status != JOB_ACTIVE)
         continue;

      // Update lifecycle (existing logic)
      m_jobs[i].controller.OnTick();

      // Update job stats
      m_jobs[i].unrealized_pnl = m_jobs[i].controller.GetUnrealizedPnL();
      m_jobs[i].realized_pnl = m_jobs[i].controller.GetRealizedPnL();

      // Check stop conditions
      if(ShouldStopJob(m_jobs[i]))
         StopJob(m_jobs[i].job_id, "SL hit");

      if(ShouldAbandonJob(m_jobs[i]))
         AbandonJob(m_jobs[i].job_id);
   }

   // 2. Check spawn trigger (only newest job can spawn)
   SJob *newest = GetNewestJob();
   if(newest != NULL && ShouldSpawnNew(*newest))
   {
      SpawnJob(newest.controller.Symbol(), newest.controller.Params());
   }

   // 3. Update global portfolio stats
   m_ledger.Update();
}
```

---

## ⚠️ Critical Challenges

### 1. Cross-Job Grid Collision

**Problem**: Job A (TSL active) spawns Job B → grid prices overlap

**Scenario:**
```
Job A (Magic 1000, TSL active):
├─ BUY grid at 3340, 3345, 3350 (original seed)
└─ SELL rescue at 3355 (TSL active)

Job B spawns at current price 3348:
├─ BUY grid at 3338, 3343, 3348  ← Collision with Job A!
└─ SELL grid at 3353, 3358

Problem: Both jobs have orders near same prices
```

**Solution: Job-Aware Position Filtering**

```cpp
// Each job ONLY counts its own positions (by magic)
bool CJobManager::IsMyOrder(ulong ticket, int job_id)
{
   if(!PositionSelectByTicket(ticket)) return false;

   long order_magic = PositionGetInteger(POSITION_MAGIC);
   long job_magic = CalculateJobMagic(job_id);

   return order_magic == job_magic;
}

// GridBasket::RefreshState() filtered by job magic
void RefreshState()
{
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);

      // CRITICAL: Check magic matches this job
      if(!IsMyOrder(ticket, m_job_id))  // ← NEW: Job ID check
         continue;

      // Rest of logic...
   }
}
```

**Key Rules:**
1. ✅ Each job counts ONLY its own magic
2. ✅ Grid prices can overlap (different jobs, different magic)
3. ✅ No cross-job position aggregation
4. ✅ Comment includes job_id for visual identification

### 2. Dependency Hell

**Problem**: Job B rescue might think Job A positions are "winner basket"

**Solution**:
- Each job operates in **isolated magic namespace**
- `PositionsTotal()` filtered by job magic range
- No cross-job position counting

### 3. Resource Limits

**Problem**: 10 jobs × 10 levels × 2 baskets = 200 orders
- Broker max pending: 100-200 orders
- EA becomes unmanageable

**Solution**:
- Max jobs limit: 5-10 jobs
- Abandon old jobs when limit reached
- Dynamic grid only (fewer pendings)

### 4. Stats Tracking

**Problem**: How to show stats for 5+ jobs?

**Solution**:
```
[Portfolio] Total PnL: +$150.23 | Active Jobs: 3 | Abandoned: 1

Job 1 (Magic 200000): ABANDONED | PnL: -$45.00 | Age: 2h 15m
Job 2 (Magic 300000): FULL      | PnL: +$12.00 | Age: 1h 30m
Job 3 (Magic 400000): ACTIVE    | PnL: +$8.50  | Age: 45m
Job 4 (Magic 500000): ACTIVE    | PnL: +$3.20  | Age: 15m
```

---

## 📋 Implementation Phases

### Phase 1: Foundation (1-2 weeks)
- [ ] Create `SJob` struct
- [ ] Create `CJobManager` class
- [ ] Implement magic number isolation
- [ ] Update `PositionsTotal()` filtering
- [ ] Test: 2 jobs trading independently

### Phase 2: Spawn Logic (1 week)
- [ ] Grid full detection (`IsGridFull()`)
- [ ] TSL active detection
- [ ] Spawn trigger implementation
- [ ] Test: Auto-spawn when grid full

### Phase 3: Risk Management (1 week)
- [ ] Job SL (per-job stop loss)
- [ ] Job DD threshold (abandon logic)
- [ ] Global DD limit (stop spawning)
- [ ] Test: Job stop/abandon correctly

### Phase 4: UI & Stats (1 week)
- [ ] Chart display (multi-job panel)
- [ ] Logging (job lifecycle events)
- [ ] Portfolio summary
- [ ] Test: All stats accurate

### Phase 5: Optimization (1 week)
- [ ] Cross-job interference prevention
- [ ] Resource limit handling
- [ ] Performance optimization
- [ ] Full backtest suite

---

## 🎯 Expected Behavior

### Scenario: Strong Downtrend (User's Case)

**Current System (FAIL)**:
```
1. SELL profit, BUY accumulates 0.4 lot
2. SELL rescue BUY continuously
3. BUY never breaks even
4. Bubble explodes → BOOM 💥
```

**Multi-Job System (SUCCESS)**:
```
1. Job 1: SELL profit, BUY hits 10 levels (full)
   → Set SL -$50 for Job 1
   → Spawn Job 2 at current price

2. Job 2: Fresh start at 3300
   → BUY/SELL trade independently
   → Makes $20 profit while Job 1 still losing

3. Price continues down → Job 2 also full
   → Spawn Job 3 at 3250

4. Job 1 SL hit → Close at -$50 loss
   Jobs 2 & 3 still active, making profit

Result: Limited loss per job, always active trading ✅
```

---

## 🚧 Breaking Changes

⚠️ **This is MAJOR redesign**:

1. **Architecture**: Single lifecycle → Multi-job manager
2. **Magic numbers**: Fixed → Dynamic (job-based)
3. **P&L tracking**: Global → Per-job + Portfolio
4. **Risk management**: Global SL → Job SL + Global DD
5. **UI**: Single basket stats → Multi-job panel

**Migration path**:
- Keep current EA as v2.x (stable)
- Build multi-job as v3.0 (experimental branch)
- Extensive testing before production

---

## 📝 Configuration Example

```cpp
// Multi-Job System Inputs
input group  "=== Multi-Job System (v3.0) ==="
input bool   InpMultiJobEnabled = false;        // Enable multi-job system (OFF by default, experimental)
input int    InpMaxJobs = 5;                    // Max concurrent jobs (5-10 recommended)
input double InpJobSL_USD = 50.0;               // SL per job in USD (0=disabled)
input double InpJobDDThreshold = 30.0;          // Abandon job if DD >= this % (e.g., 30%)
input double InpGlobalDDLimit = 50.0;           // Stop spawning if global DD >= this % (e.g., 50%)
input int    InpGridLevelsPerJob = 10;          // Max grid levels per job (5-10, smaller = more jobs)

input group  "=== Magic Number (Job Isolation) ==="
input long   InpMagicStart = 1000;              // Starting magic number (e.g., 1000)
input long   InpMagicOffset = 421;              // Magic offset between jobs (e.g., 421)
// Job A: 1000, Job B: 1421, Job C: 1842...

input group  "=== Spawn Triggers ==="
input bool   InpSpawnOnGridFull = true;         // Spawn new job when grid full
input bool   InpSpawnOnTSL = true;              // Spawn new job when TSL active
input bool   InpSpawnOnJobDD = true;            // Spawn new job when job DD >= threshold
```

---

## 🔍 Open Questions

1. **Job cleanup**: When to remove stopped/abandoned jobs from array?
   - Option A: Keep all jobs (history)
   - Option B: Remove after N hours
   - **Recommendation**: Keep max 10 jobs in memory, archive old ones

2. **Rescue between jobs**: Should Job B rescue Job A?
   - Option A: No cross-job rescue (isolated)
   - Option B: Allow if Job A DD < threshold
   - **Recommendation**: NO cross-job rescue (keep isolated)

3. **Chart display**: How to show 5+ jobs on chart?
   - Option A: Panel with scrollable job list
   - Option B: Only show newest job + portfolio total
   - **Recommendation**: Panel with top 5 active jobs

4. **Backtest**: How to test multi-job in tester?
   - Challenge: Tester doesn't support multi-magic well
   - Solution: Custom stats export, manual analysis

---

## ✅ Success Criteria

Multi-job system is successful when:

1. ✅ Can spawn 5+ jobs independently
2. ✅ Job SL limits loss per job (-$50 max)
3. ✅ New jobs trade while old jobs stuck
4. ✅ No cross-job interference (orders, magic)
5. ✅ Portfolio profit even with some job losses
6. ✅ Strong trend doesn't blow account (limited per-job risk)
7. ✅ Stats clear and accurate per job + portfolio

---

## 🎓 Learning from User's Experience

**Key insight**:
> "Rescue cannot save forever. Waiting for breakeven blocks new opportunities."

**Multi-job philosophy**:
> "Cut losses quickly (job SL), start fresh often (spawn new), stay active always (independent jobs)."

This is **evolution from DCA-heavy to portfolio-based** risk management.

---

**Status**: 🟡 Design Complete - Ready for Implementation Discussion
**Effort**: 5-6 weeks (phased approach)
**Risk**: HIGH (breaking changes, complex architecture)
**Reward**: HIGH (solves blow-up problem, always-active trading)
