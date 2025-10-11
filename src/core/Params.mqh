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

   // timeframe preservation (prevent duplicate positions on TF switch)
   bool         preserve_on_tf_switch;   // preserve positions on timeframe switch (default: true)

   // Phase 13: Dynamic Spacing & Trend Strength
   bool         dynamic_spacing_enabled; // enable dynamic spacing based on trend strength
   double       dynamic_spacing_max;     // max spacing multiplier (default 3.0)
   ENUM_TIMEFRAMES trend_timeframe;      // timeframe for trend analysis (default M15)

   // Phase 13 Layer 4: Time-Based Exit
   bool         time_exit_enabled;       // enable time-based exit
   int          time_exit_hours;         // hours threshold before exit (default: 24)
   double       time_exit_max_loss_usd;  // max acceptable loss in USD (default: -100)
   bool         time_exit_trend_only;    // only exit if counter-trend (default: true)

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
  };

#endif // __RGD_V2_PARAMS_MQH__
