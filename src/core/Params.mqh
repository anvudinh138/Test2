//+------------------------------------------------------------------+
//| Strategy parameters                                              |
//+------------------------------------------------------------------+
#ifndef __RGD_V2_PARAMS_MQH__
#define __RGD_V2_PARAMS_MQH__

#include <Trade\Trade.mqh>
#include "Types.mqh"

struct SParams
  {
   // spacing
   ESpacingMode spacing_mode;
   double       spacing_pips;
   double       spacing_atr_mult;
   double       min_spacing_pips;
   int          atr_period;
   ENUM_TIMEFRAMES atr_timeframe;

   // grid
   int          grid_levels;        // number of levels including market seed
   double       lot_base;
   double       lot_scale;

   // dynamic grid
   bool         grid_dynamic_enabled;
   int          grid_warm_levels;      // initial pending count
   int          grid_refill_threshold; // refill when pending <= this
   int          grid_refill_batch;     // add this many per refill
   int          grid_max_pendings;     // hard limit for safety

   // profit target
   double       target_cycle_usd;

   // session risk limit (keep for safety)
   double       session_sl_usd;

   // grid protection (anti blow-up)
   bool         grid_protection_enabled;  // enable grid full auto-close
   int          grid_cooldown_minutes;    // cooldown after grid full (minutes)

   // execution
   int          slippage_pips;
   int          order_cooldown_sec;
   bool         respect_stops_level;
   double       commission_per_lot;

   // misc
   long         magic;

   // multi-job system (Phase 2)
   bool         multi_job_enabled;       // enable multi-job system (experimental)
   int          max_jobs;                // max concurrent jobs (5-10 recommended)
   double       job_sl_usd;              // SL per job in USD (0=disabled)
   double       job_dd_threshold;        // abandon job if DD >= this % (e.g., 30%)
   double       global_dd_limit;         // stop spawning if global DD >= this % (e.g., 50%)

   // magic number (job isolation)
   long         magic_start;             // starting magic number for Job 1
   long         magic_offset;            // magic offset between jobs (e.g., 421)

   // spawn triggers
   bool         spawn_on_grid_full;      // spawn new job when grid full
   bool         spawn_on_tsl;            // spawn new job when TSL active
   bool         spawn_on_job_dd;         // spawn new job when job DD >= threshold
   int          spawn_cooldown_sec;      // cooldown between spawns (seconds)
   int          max_spawns;              // max spawns per session

   // timeframe preservation (prevent duplicate positions on TF switch)
   bool         preserve_on_tf_switch;   // preserve positions on timeframe switch (default: true)
  };

#endif // __RGD_V2_PARAMS_MQH__
