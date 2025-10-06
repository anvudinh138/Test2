//+------------------------------------------------------------------+
//| JobManager.mqh - Multi-Job System Manager                       |
//| Manages multiple independent lifecycle instances                |
//+------------------------------------------------------------------+
#ifndef __RGD_V2_JOB_MANAGER_MQH__
#define __RGD_V2_JOB_MANAGER_MQH__

#include "Types.mqh"
#include "Params.mqh"
#include "SpacingEngine.mqh"
#include "OrderExecutor.mqh"
#include "LifecycleController.mqh"
#include "Logger.mqh"

class CJobManager
  {
private:
   string            m_symbol;
   SParams           m_params;
   CSpacingEngine   *m_spacing;
   COrderExecutor   *m_executor;
   CLogger          *m_log;

   SJob              m_jobs[];               // Array of active jobs
   int               m_next_job_id;          // Auto-increment ID
   long              m_magic_start;          // Starting magic number
   long              m_magic_offset;         // Magic offset between jobs

   // Risk management
   double            m_global_dd_limit;      // Global DD% to stop spawning (e.g., 50%)
   double            m_job_sl_usd;           // Job stop loss in USD
   double            m_job_dd_threshold;     // Job DD% to abandon (e.g., 30%)

   // Spawn control
   datetime          m_last_spawn_time;      // Last spawn timestamp
   int               m_spawn_cooldown_sec;   // Cooldown between spawns (seconds)
   int               m_total_spawns;         // Total spawns this session
   int               m_max_spawns;           // Max spawns per session

   // Triggers
   bool              m_spawn_on_grid_full;   // Spawn when grid full
   bool              m_spawn_on_tsl;         // Spawn when TSL active
   bool              m_spawn_on_job_dd;      // Spawn when job DD threshold breached

   string            Tag() const { return StringFormat("[RGDv2][%s][JM]",m_symbol); }

   //+------------------------------------------------------------------+
   //| Calculate magic number for a job                                |
   //+------------------------------------------------------------------+
   long              CalculateJobMagic(const int job_id) const
     {
      // job_id starts from 1
      // Examples: job=1 → magic_start, job=2 → magic_start+offset, etc.
      return m_magic_start+((job_id-1)*m_magic_offset);
     }

   //+------------------------------------------------------------------+
   //| Get newest (latest) job                                         |
   //+------------------------------------------------------------------+
   SJob*             GetNewestJob()
     {
      int size=ArraySize(m_jobs);
      if(size==0)
         return NULL;
      return &m_jobs[size-1];  // Last job in array is newest
     }

   //+------------------------------------------------------------------+
   //| Spawn new job trigger logic                                     |
   //+------------------------------------------------------------------+
   bool              ShouldSpawnNew(const SJob &job)
     {
      // Guard: Don't spawn if not ACTIVE
      if(job.status!=JOB_ACTIVE)
         return false;

      // Guard: Cooldown between spawns
      datetime now=TimeCurrent();
      if((now-m_last_spawn_time)<m_spawn_cooldown_sec)
         return false;

      // Guard: Max spawns per session
      if(m_total_spawns>=m_max_spawns)
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),StringFormat("Max spawns reached (%d), spawn blocked",m_max_spawns));
         return false;
        }

      // Guard: Global DD limit
      double account_equity=AccountInfoDouble(ACCOUNT_EQUITY);
      double account_balance=AccountInfoDouble(ACCOUNT_BALANCE);
      if(account_equity>0.0 && account_balance>0.0)
        {
         double dd_pct=((account_balance-account_equity)/account_balance)*100.0;
         if(dd_pct>=m_global_dd_limit)
           {
            if(m_log!=NULL)
               m_log.Event(Tag(),StringFormat("Global DD %.1f%% >= limit %.1f%%, spawn blocked",dd_pct,m_global_dd_limit));
            return false;
           }
        }

      // Trigger 1: Grid full
      if(m_spawn_on_grid_full && job.controller!=NULL)
        {
         if(job.controller.IsGridFull())
           {
            if(m_log!=NULL)
               m_log.Event(Tag(),StringFormat("Job %d: Grid full detected, spawning new job",job.job_id));
            return true;
           }
        }

      // Trigger 2: TSL active
      if(m_spawn_on_tsl && job.is_tsl_active)
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),StringFormat("Job %d: TSL active, spawning new job",job.job_id));
         return true;
        }

      // Trigger 3: Job DD threshold
      if(m_spawn_on_job_dd && job.peak_equity>0.0)
        {
         double job_dd_pct=((job.peak_equity-job.unrealized_pnl)/job.peak_equity)*100.0;
         if(job_dd_pct>=m_job_dd_threshold)
           {
            if(m_log!=NULL)
               m_log.Event(Tag(),StringFormat("Job %d: DD %.1f%% >= threshold %.1f%%, spawning new job",
                                             job.job_id,job_dd_pct,m_job_dd_threshold));
            return true;
           }
        }

      return false;
     }

   //+------------------------------------------------------------------+
   //| Job stop loss trigger                                           |
   //+------------------------------------------------------------------+
   bool              ShouldStopJob(const SJob &job)
     {
      if(job.status!=JOB_ACTIVE)
         return false;
      if(m_job_sl_usd<=0.0)
         return false;  // SL disabled

      // Check if unrealized PnL <= -job_sl_usd
      if(job.unrealized_pnl<=-m_job_sl_usd)
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),StringFormat("Job %d: SL hit (PnL:%.2f <= -%.2f)",
                                          job.job_id,job.unrealized_pnl,m_job_sl_usd));
         return true;
        }

      return false;
     }

   //+------------------------------------------------------------------+
   //| Job abandon trigger (DD too high, can't save)                   |
   //+------------------------------------------------------------------+
   bool              ShouldAbandonJob(const SJob &job)
     {
      if(job.status!=JOB_ACTIVE)
         return false;

      // If job DD >= global DD limit → other jobs can't save this
      double account_equity=AccountInfoDouble(ACCOUNT_EQUITY);
      if(account_equity<=0.0)
         return false;

      double job_dd_usd=MathAbs(job.unrealized_pnl);
      double job_dd_pct=(job_dd_usd/account_equity)*100.0;

      if(job_dd_pct>=m_global_dd_limit)
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),StringFormat("Job %d: DD %.1f%% >= global limit %.1f%%, abandoning",
                                          job.job_id,job_dd_pct,m_global_dd_limit));
         return true;
        }

      return false;
     }

   //+------------------------------------------------------------------+
   //| Stop job (close all positions, set status)                      |
   //+------------------------------------------------------------------+
   void              StopJob(const int job_id,const string reason)
     {
      for(int i=0;i<ArraySize(m_jobs);i++)
        {
         if(m_jobs[i].job_id==job_id)
           {
            if(m_jobs[i].controller!=NULL)
              {
               // Close all positions via FlattenAll
               m_jobs[i].controller.Shutdown();
               delete m_jobs[i].controller;
               m_jobs[i].controller=NULL;
              }
            m_jobs[i].status=JOB_STOPPED;
            if(m_log!=NULL)
               m_log.Event(Tag(),StringFormat("Job %d stopped: %s",job_id,reason));
            break;
           }
        }
     }

   //+------------------------------------------------------------------+
   //| Abandon job (stop managing, keep positions open)                |
   //+------------------------------------------------------------------+
   void              AbandonJob(const int job_id)
     {
      for(int i=0;i<ArraySize(m_jobs);i++)
        {
         if(m_jobs[i].job_id==job_id)
           {
            m_jobs[i].status=JOB_ABANDONED;
            if(m_log!=NULL)
               m_log.Event(Tag(),StringFormat("Job %d abandoned (positions kept open)",job_id));
            // Note: Controller still exists, but we stop updating it
            break;
           }
        }
     }

public:
                     CJobManager(const string symbol,
                                 const SParams &params,
                                 CSpacingEngine *spacing,
                                 COrderExecutor *executor,
                                 CLogger *log,
                                 const long magic_start,
                                 const long magic_offset,
                                 const double global_dd_limit,
                                 const double job_sl_usd,
                                 const double job_dd_threshold,
                                 const int spawn_cooldown_sec,
                                 const int max_spawns,
                                 const bool spawn_on_grid_full,
                                 const bool spawn_on_tsl,
                                 const bool spawn_on_job_dd)
                       : m_symbol(symbol),
                         m_params(params),
                         m_spacing(spacing),
                         m_executor(executor),
                         m_log(log),
                         m_next_job_id(1),
                         m_magic_start(magic_start),
                         m_magic_offset(magic_offset),
                         m_global_dd_limit(global_dd_limit),
                         m_job_sl_usd(job_sl_usd),
                         m_job_dd_threshold(job_dd_threshold),
                         m_last_spawn_time(0),
                         m_spawn_cooldown_sec(spawn_cooldown_sec),
                         m_total_spawns(0),
                         m_max_spawns(max_spawns),
                         m_spawn_on_grid_full(spawn_on_grid_full),
                         m_spawn_on_tsl(spawn_on_tsl),
                         m_spawn_on_job_dd(spawn_on_job_dd)
     {
      ArrayResize(m_jobs,0);
     }

   //+------------------------------------------------------------------+
   //| Initialize: Spawn first job                                     |
   //+------------------------------------------------------------------+
   bool              Init()
     {
      // Spawn first job (Job 1)
      int job_id=SpawnJob();
      if(job_id<=0)
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),"Failed to spawn initial job");
         return false;
        }

      if(m_log!=NULL)
         m_log.Event(Tag(),StringFormat("JobManager initialized: Job 1 (Magic %d)",CalculateJobMagic(1)));
      return true;
     }

   //+------------------------------------------------------------------+
   //| Spawn new job                                                   |
   //+------------------------------------------------------------------+
   int               SpawnJob()
     {
      int job_id=m_next_job_id;
      long job_magic=CalculateJobMagic(job_id);

      // Create new lifecycle controller
      CLifecycleController *controller=new CLifecycleController(m_symbol,m_params,m_spacing,m_executor,m_log,job_magic);
      if(controller==NULL)
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),StringFormat("Failed to create controller for Job %d",job_id));
         return -1;
        }

      if(!controller.Init())
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),StringFormat("Failed to init controller for Job %d",job_id));
         delete controller;
         return -1;
        }

      // Create job struct
      SJob job;
      job.job_id=job_id;
      job.magic=job_magic;
      job.created_at=TimeCurrent();
      job.controller=controller;
      job.job_sl_usd=m_job_sl_usd;
      job.job_dd_threshold=m_job_dd_threshold;
      job.status=JOB_ACTIVE;
      job.is_full=false;
      job.is_tsl_active=false;
      job.realized_pnl=0.0;
      job.unrealized_pnl=0.0;
      job.peak_equity=AccountInfoDouble(ACCOUNT_EQUITY);

      // Add to jobs array
      int size=ArraySize(m_jobs);
      ArrayResize(m_jobs,size+1);
      m_jobs[size]=job;

      // Update counters
      m_next_job_id++;
      m_total_spawns++;
      m_last_spawn_time=TimeCurrent();

      if(m_log!=NULL)
         m_log.Event(Tag(),StringFormat("Job %d spawned (Magic %d, SL:%.2f USD)",job_id,job_magic,m_job_sl_usd));

      return job_id;
     }

   //+------------------------------------------------------------------+
   //| Main update loop                                                |
   //+------------------------------------------------------------------+
   void              Update()
     {
      // 1. Update all jobs
      for(int i=0;i<ArraySize(m_jobs);i++)
        {
         if(m_jobs[i].status!=JOB_ACTIVE)
            continue;

         // Update lifecycle (existing logic)
         if(m_jobs[i].controller!=NULL)
            m_jobs[i].controller.Update();

         // Update job stats
         if(m_jobs[i].controller!=NULL)
           {
            m_jobs[i].unrealized_pnl=m_jobs[i].controller.GetUnrealizedPnL();
            m_jobs[i].realized_pnl=m_jobs[i].controller.GetRealizedPnL();
            m_jobs[i].is_full=m_jobs[i].controller.IsGridFull();
            m_jobs[i].is_tsl_active=m_jobs[i].controller.IsTSLActive();

            // Update peak equity
            double current_equity=AccountInfoDouble(ACCOUNT_EQUITY);
            if(current_equity>m_jobs[i].peak_equity)
               m_jobs[i].peak_equity=current_equity;
           }

         // Check stop conditions
         if(ShouldStopJob(m_jobs[i]))
           {
            StopJob(m_jobs[i].job_id,"SL hit");
            continue;
           }

         if(ShouldAbandonJob(m_jobs[i]))
           {
            AbandonJob(m_jobs[i].job_id);
            continue;
           }
        }

      // 2. Check spawn trigger (only newest job can spawn)
      SJob *newest=GetNewestJob();
      if(newest!=NULL && ShouldSpawnNew(*newest))
        {
         SpawnJob();
        }
     }

   //+------------------------------------------------------------------+
   //| Shutdown all jobs                                               |
   //+------------------------------------------------------------------+
   void              Shutdown()
     {
      for(int i=0;i<ArraySize(m_jobs);i++)
        {
         if(m_jobs[i].controller!=NULL)
           {
            m_jobs[i].controller.Shutdown();
            delete m_jobs[i].controller;
            m_jobs[i].controller=NULL;
           }
        }
      ArrayResize(m_jobs,0);
     }

   //+------------------------------------------------------------------+
   //| Get total P&L across all jobs                                   |
   //+------------------------------------------------------------------+
   double            GetTotalUnrealizedPnL() const
     {
      double total=0.0;
      for(int i=0;i<ArraySize(m_jobs);i++)
         total+=m_jobs[i].unrealized_pnl;
      return total;
     }

   double            GetTotalRealizedPnL() const
     {
      double total=0.0;
      for(int i=0;i<ArraySize(m_jobs);i++)
         total+=m_jobs[i].realized_pnl;
      return total;
     }

   int               GetActiveJobCount() const
     {
      int count=0;
      for(int i=0;i<ArraySize(m_jobs);i++)
        {
         if(m_jobs[i].status==JOB_ACTIVE)
            count++;
        }
      return count;
     }
  };

#endif // __RGD_V2_JOB_MANAGER_MQH__
