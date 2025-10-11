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

   // profit target
   double       target_cycle_usd;

   // session risk limit (keep for safety)
   double       session_sl_usd;

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

   // basket stop loss (Phase 1.2 - spacing-based risk management)
   bool         basket_sl_enabled;       // enable basket stop loss
   double       basket_sl_spacing;       // SL distance in spacing units (e.g., 2.0 = 2x spacing)

   // Phase 12: Trend-Aware Reseed
   EReseedMode  reseed_mode;             // when to reseed after basket SL
   int          reseed_cooldown_min;     // cooldown minutes before reseed (COOLDOWN mode)
   bool         reseed_with_trend_only;  // enable trend filter for reseed (Phase 12)

   // Phase 13: Dynamic Spacing & Trend Strength
   bool         dynamic_spacing_enabled; // enable dynamic spacing based on trend strength
   double       dynamic_spacing_max;     // max spacing multiplier (default 3.0)
   ENUM_TIMEFRAMES trend_timeframe;      // timeframe for trend analysis (default M15)

   //+------------------------------------------------------------------+
   //| NEW PARAMETERS FOR v3.1.0 (Phase 0: OFF by default)             |
   //+------------------------------------------------------------------+
   
   // lazy grid fill (Phase 1)
   bool         lazy_grid_enabled;       // enable lazy grid fill
   int          initial_warm_levels;     // initial pending levels (1-2)
   bool         auto_max_level_distance; // auto-calculate max level distance
   int          max_level_distance;      // max distance to next level (pips) - manual
   double       lazy_distance_multiplier;// spacing multiplier for auto mode (default 20x)
   double       max_dd_for_expansion;    // stop expanding if DD < this (%)
   
   // trap detection (Phase 2)
   bool         trap_detection_enabled;  // enable trap detection
   bool         trap_auto_threshold;     // auto-calculate gap threshold
   double       trap_gap_threshold;      // gap threshold (pips) - manual mode
   double       trap_atr_multiplier;     // ATR multiplier for auto mode
   double       trap_spacing_multiplier; // spacing multiplier for auto mode
   double       trap_dd_threshold;       // DD threshold (%)
   int          trap_conditions_required;// min conditions to trigger (3/5)
   int          trap_stuck_minutes;      // minutes to consider "stuck"
   
   // quick exit mode (Phase 3)
   bool         quick_exit_enabled;      // enable quick exit
   ENUM_QUICK_EXIT_MODE quick_exit_mode; // exit mode
   double       quick_exit_loss;         // fixed loss amount ($)
   double       quick_exit_percentage;   // percentage mode (30% of DD)
   bool         quick_exit_close_far;    // close far positions in quick exit
   bool         quick_exit_reseed;       // auto reseed after exit
   int          quick_exit_timeout_min;  // timeout (minutes)
   
   // gap management (Phase 9-10 - auto-adaptive using multipliers)
   bool         auto_fill_bridge;        // auto fill bridge levels (200-400 pips range)
   double       gap_bridge_min_multiplier; // min gap size (spacing × this, e.g., 8.0)
   double       gap_bridge_max_multiplier; // max gap size (spacing × this, e.g., 16.0)
   int          max_bridge_levels;       // max bridge levels per gap

   // Phase 10: CloseFar for large gaps (>400 pips range)
   bool         gap_close_far_enabled;   // enable close-far for large gaps
   double       gap_close_far_multiplier; // close-far threshold (spacing × this, e.g., 16.0)
   double       gap_close_far_distance;  // distance from avg to consider "far" (spacing × this, e.g., 8.0)
   double       max_acceptable_loss;     // max loss to abandon trapped ($)
   int          min_positions_before_reseed; // min positions before reseed (default: 2)
  };

#endif // __RGD_V2_PARAMS_MQH__
