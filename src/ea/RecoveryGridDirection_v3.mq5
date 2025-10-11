#property strict

#include <Trade/Trade.mqh>

#include <RECOVERY-GRID-DIRECTION_v3/core/Types.mqh>
#include <RECOVERY-GRID-DIRECTION_v3/core/Params.mqh>
#include <RECOVERY-GRID-DIRECTION_v3/core/PresetManager.mqh>
#include <RECOVERY-GRID-DIRECTION_v3/core/Logger.mqh>
#include <RECOVERY-GRID-DIRECTION_v3/core/SpacingEngine.mqh>
#include <RECOVERY-GRID-DIRECTION_v3/core/OrderValidator.mqh>
#include <RECOVERY-GRID-DIRECTION_v3/core/OrderExecutor.mqh>
#include <RECOVERY-GRID-DIRECTION_v3/core/GridBasket.mqh>
#include <RECOVERY-GRID-DIRECTION_v3/core/LifecycleController.mqh>
#include <RECOVERY-GRID-DIRECTION_v3/core/NewsFilter.mqh>

//--- Inputs
//--- Identity
input long              InpMagic            = 990045;  // Magic Number (IMPORTANT: Change this first!)

//--- Symbol Preset (Volatility-based for easy backtesting)
input ENUM_SYMBOL_PRESET InpSymbolPreset    = PRESET_AUTO;  // Volatility preset (AUTO, LOW_VOL, MEDIUM_VOL, HIGH_VOL, CUSTOM)
input bool              InpUseTestedPresets = true;  // Use tested presets when available (EUR, XAU, GBP, JPY)

//--- Logging
input int               InpStatusInterval   = 60;      // Status log interval (seconds)
input bool              InpLogEvents        = true;    // Enable event logging

//--- Spacing Engine
input ENUM_TIMEFRAMES   InpAtrTimeframe     = PERIOD_M15;  // ATR timeframe
input int               InpAtrPeriod        = 14;          // ATR period

enum InpSpacingModeEnum { InpSpacingPips=0, InpSpacingATR=1, InpSpacingHybrid=2 };
input InpSpacingModeEnum InpSpacingMode     = InpSpacingHybrid;  // Spacing mode
input double            InpSpacingStepPips  = 25.0;  // Base spacing (pips)
input double            InpSpacingAtrMult   = 0.6;   // ATR multiplier
input double            InpMinSpacingPips   = 12.0;  // Min spacing floor (pips)

//--- Grid Configuration
input int               InpGridLevels       = 5;     // Grid levels per side
input double            InpLotBase          = 0.01;  // Base lot size
input double            InpLotScale         = 2.0;   // Lot scale multiplier

//--- Profit Target
input double            InpTargetCycleUSD   = 10.0;   // Target profit per cycle (USD)

//--- Risk Management (Session Stop Loss)
input double            InpSessionSL_USD    = 10000; // Session stop loss (USD) - for monitoring only

//--- News Filter (pause trading during high-impact news)
input bool              InpNewsFilterEnabled   = true;  // Enable news filter
input string            InpNewsImpactFilter    = "High"; // Impact filter (High, Medium+, All)
input int               InpNewsBufferMinutes   = 60;     // Buffer before/after news (minutes)

//--- Execution
input int               InpOrderCooldownSec = 5;     // Min seconds between orders (anti-spam)
input int               InpSlippagePips     = 0;     // Max slippage (pips)
input bool              InpRespectStops     = false; // Respect broker stops level (false for backtest)
input double            InpCommissionPerLot = 0.0;   // Commission per lot (for PnL calc only, does NOT affect live)



//--- Phase 13: Dynamic Spacing & Trend Strength (XAUUSD Protection) - ALWAYS ENABLED (proven feature)
input group             "=== Phase 13: Dynamic Spacing (ALWAYS ON) ==="
// InpDynamicSpacingEnabled removed - now always true (proven feature)
input double            InpDynamicSpacingMax    = 3.0;         // Max spacing multiplier (3.0 = 3x wider in extreme trend)
input ENUM_TIMEFRAMES   InpTrendTimeframe       = PERIOD_M15;  // Timeframe for trend analysis

//--- Phase 13 Layer 4: Time-Based Exit (Safe Solution)
input group             "=== Phase 13 Layer 4: Time-Based Exit ==="
input bool              InpTimeExitEnabled      = true;       // Enable time-based exit (OFF by default - TEST FIRST!)
input int               InpTimeExitHours        = 24;          // Hours threshold before exit (24 hours = 1 day)
input double            InpTimeExitMaxLoss      = -100.0;      // Max acceptable loss in USD (e.g., -100)
input bool              InpTimeExitTrendOnly    = true;        // Only exit if counter-trend (recommended: true)

//+------------------------------------------------------------------+
//| NEW PARAMETERS FOR v3.1.0 - Lazy Grid Fill + Trap Detection     |
//+------------------------------------------------------------------+

//--- Lazy Grid Fill (Phase 1) - ALWAYS ENABLED (proven feature)
input group             "=== Lazy Grid Fill (v3.1 - ALWAYS ON) ==="
// InpLazyGridEnabled removed - now always true (proven feature)
input int               InpInitialWarmLevels    = 1;           // Initial pending levels (1-2)
input bool              InpAutoMaxLevelDistance = true;        // Auto-calculate max level distance
input int               InpMaxLevelDistance     = 500;         // Manual max distance (pips) - used if auto=false
input double            InpLazyDistanceMultiplier = 20.0;      // Spacing multiplier for auto mode (20x spacing)
input double            InpMaxDDForExpansion    = -20.0;       // Stop expanding if DD < this (%)

//--- Trap Detection (Phase 5)
input group             "=== Trap Detection (v3.1 - Phase 5) ==="
input bool              InpTrapDetectionEnabled = true;       // Enable trap detection
input bool              InpTrapAutoThreshold    = true;        // Auto-calculate gap threshold
input double            InpTrapGapThreshold     = 50.0;        // Manual gap threshold (pips) - used if auto=false
input double            InpTrapATRMultiplier    = 1.0;         // ATR multiplier for auto mode (2.0 = 2x ATR)
input double            InpTrapSpacingMultiplier = 1.0;        // Spacing multiplier for auto mode (1.5 = 1.5x spacing)
input double            InpTrapDDThreshold      = -15.0;       // DD threshold (%)
input int               InpTrapConditionsRequired = 1;         // Min conditions to trigger (1-5)
input int               InpTrapStuckMinutes     = 0;          // Minutes to consider "stuck"

//--- Quick Exit Mode (Phase 3)
input group             "=== Quick Exit Mode (v3.1 - Phase 0: OFF) ==="
input bool              InpQuickExitEnabled     = true;       // Enable quick exit (OFF for Phase 0)
input ENUM_QUICK_EXIT_MODE InpQuickExitMode    = QE_FIXED;    // Exit mode
input double            InpQuickExitLoss        = 0.0;       // Fixed loss amount ($)
input double            InpQuickExitPercentage  = 0.30;        // Percentage mode (30% of DD)
input bool              InpQuickExitCloseFar    = true;        // Close far positions in quick exit
input bool              InpQuickExitReseed      = true;        // Auto reseed after exit
input int               InpQuickExitTimeoutMinutes = 0;       // Timeout (minutes)


//--- Globals
SParams              g_params;
CLogger             *g_logger        = NULL;
CSpacingEngine      *g_spacing       = NULL;
COrderValidator     *g_validator     = NULL;
COrderExecutor      *g_executor      = NULL;
CLifecycleController*g_controller    = NULL;
CNewsFilter         *g_news_filter   = NULL;

//+------------------------------------------------------------------+
//| Print comprehensive configuration                                |
//+------------------------------------------------------------------+
void PrintConfiguration()
  {
   if(g_logger==NULL)
      return;
   
   Print("========================================");
   Print("EA CONFIGURATION");
   Print("========================================");
   Print("Version: v3.1.0 Phase 1 (Observability)");
   Print("Magic: ",InpMagic);
   Print("Symbol: ",_Symbol);
   Print("");
   
   // Spacing configuration
   Print("--- Spacing Engine ---");
   string spacing_mode_str="";
   switch(InpSpacingMode)
     {
      case 0: spacing_mode_str="PIPS (Fixed)"; break;
      case 1: spacing_mode_str="ATR (Adaptive)"; break;
      case 2: spacing_mode_str="HYBRID (ATR with floor)"; break;
     }
   Print("Mode: ",spacing_mode_str);
   Print("Base spacing: ",InpSpacingStepPips," pips");
   if(InpSpacingMode!=0)
     {
      Print("ATR multiplier: ",InpSpacingAtrMult);
      Print("Min spacing: ",InpMinSpacingPips," pips");
      Print("ATR period: ",InpAtrPeriod," (",EnumToString(InpAtrTimeframe),")");
     }
   Print("");
   
   // Grid configuration
   Print("--- Grid Configuration ---");
   Print("Grid levels: ",InpGridLevels);
   Print("Base lot: ",InpLotBase);
   Print("Lot scale: ",InpLotScale,(InpLotScale==1.0?" (Flat)":(InpLotScale==2.0?" (Martingale)":"")));
   Print("Target per cycle: $",InpTargetCycleUSD);
   Print("");
   
   Print("");
   
   // Risk management
   Print("--- Risk Management ---");
   Print("Session SL: $",InpSessionSL_USD," (monitoring only)");
   Print("");
   
   // Filters
   Print("--- Filters ---");
   Print("News filter: ",(InpNewsFilterEnabled?"ENABLED":"DISABLED"));
   if(InpNewsFilterEnabled)
     {
      Print("  Impact: ",InpNewsImpactFilter);
      Print("  Buffer: ",InpNewsBufferMinutes," minutes");
     }
   Print("");
   
   // v3.1.0 Features (Phase 0-4)
   Print("========================================");
   Print("v3.1.0 NEW FEATURES STATUS");
   Print("========================================");
   
   // Lazy Grid Fill (Phase 1) - ALWAYS ENABLED
   Print("1. LAZY GRID FILL: ALWAYS ENABLED ✓");
   Print("   Initial warm levels: ",InpInitialWarmLevels);
   if(InpAutoMaxLevelDistance)
     {
      Print("   Max level distance: AUTO (Spacing × ",InpLazyDistanceMultiplier,")");
     }
   else
     {
      Print("   Max level distance: ",InpMaxLevelDistance," pips (manual)");
     }
   Print("   Max DD for expansion: ",InpMaxDDForExpansion,"%");
   
   // Trap Detection (Phase 5)
   Print("2. TRAP DETECTION: ",(InpTrapDetectionEnabled?"ENABLED ⚠️":"DISABLED ✓"));
   if(InpTrapDetectionEnabled)
     {
      if(InpTrapAutoThreshold)
        {
         Print("   Gap threshold: AUTO (ATR × ",InpTrapATRMultiplier," | Spacing × ",InpTrapSpacingMultiplier,")");
        }
      else
        {
         Print("   Gap threshold: ",InpTrapGapThreshold," pips (manual)");
        }
      Print("   DD threshold: ",InpTrapDDThreshold,"%");
      Print("   Conditions required: ",InpTrapConditionsRequired,"/5");
      Print("   Stuck minutes: ",InpTrapStuckMinutes);
     }
   
   // Quick Exit Mode (Phase 3)
   Print("3. QUICK EXIT MODE: ",(InpQuickExitEnabled?"ENABLED ⚠️":"DISABLED ✓"));
   if(InpQuickExitEnabled)
     {
      string qe_mode_str="";
      switch(InpQuickExitMode)
        {
         case QE_FIXED: qe_mode_str="FIXED"; break;
         case QE_PERCENTAGE: qe_mode_str="PERCENTAGE"; break;
         case QE_DYNAMIC: qe_mode_str="DYNAMIC"; break;
        }
      Print("   Mode: ",qe_mode_str);
      Print("   Target loss: $",InpQuickExitLoss);
      if(InpQuickExitMode==QE_PERCENTAGE)
         Print("   Percentage: ",(InpQuickExitPercentage*100),"%");
      Print("   Close far: ",(InpQuickExitCloseFar?"YES":"NO"));
      Print("   Auto reseed: ",(InpQuickExitReseed?"YES":"NO"));
      Print("   Timeout: ",InpQuickExitTimeoutMinutes," minutes");
     }
   
   
   Print("");

   // Phase validation (lazy grid is now always on - proven feature)
   if(InpTrapDetectionEnabled || InpQuickExitEnabled)
     {
      Print("⚠️  WARNING: Some experimental features are enabled!");
      Print("    Test thoroughly on demo before live trading.");
     }
   else
     {
      Print("✅ Using proven features only (lazy grid, dynamic spacing).");
     }
   
   Print("========================================");
   Print("Initialization complete. Waiting for tick...");
   Print("========================================");
  }

void BuildParams()
  {
   // Initialize ALL params with manual inputs FIRST (default values)
   g_params.spacing_mode       =(ESpacingMode)InpSpacingMode;
   g_params.spacing_pips       =InpSpacingStepPips;
   g_params.spacing_atr_mult   =InpSpacingAtrMult;
   g_params.min_spacing_pips   =InpMinSpacingPips;
   g_params.atr_period         =InpAtrPeriod;
   g_params.atr_timeframe      =InpAtrTimeframe;

   g_params.grid_levels        =InpGridLevels;
   g_params.lot_base           =InpLotBase;
   g_params.lot_scale          =InpLotScale;

   g_params.target_cycle_usd   =InpTargetCycleUSD;
   g_params.session_sl_usd     =InpSessionSL_USD;

   g_params.slippage_pips      =InpSlippagePips;
   g_params.order_cooldown_sec =InpOrderCooldownSec;
   g_params.respect_stops_level=InpRespectStops;
   g_params.commission_per_lot =InpCommissionPerLot;

   g_params.magic              =InpMagic;

   // Timeframe preservation (bug fix - always enabled)
   g_params.preserve_on_tf_switch=true;

   // Phase 13: Dynamic Spacing & Trend Strength - ALWAYS ENABLED (proven feature)
   g_params.dynamic_spacing_enabled=true;  // Always true - proven feature
   g_params.dynamic_spacing_max   =InpDynamicSpacingMax;
   g_params.trend_timeframe       =InpTrendTimeframe;

   // Phase 13 Layer 4: Time-Based Exit
   g_params.time_exit_enabled     =InpTimeExitEnabled;
   g_params.time_exit_hours       =InpTimeExitHours;
   g_params.time_exit_max_loss_usd=InpTimeExitMaxLoss;
   g_params.time_exit_trend_only  =InpTimeExitTrendOnly;

   // NEW v3.1.0 parameters
   // Lazy grid fill - ALWAYS ENABLED (proven feature)
   g_params.lazy_grid_enabled     =true;  // Always true - proven feature
   g_params.initial_warm_levels   =InpInitialWarmLevels;
   g_params.auto_max_level_distance=InpAutoMaxLevelDistance;
   g_params.max_level_distance    =InpMaxLevelDistance;
   g_params.lazy_distance_multiplier=InpLazyDistanceMultiplier;
   g_params.max_dd_for_expansion  =InpMaxDDForExpansion;
   
   // Trap detection
   g_params.trap_detection_enabled=InpTrapDetectionEnabled;
   g_params.trap_auto_threshold   =InpTrapAutoThreshold;
   g_params.trap_gap_threshold    =InpTrapGapThreshold;
   g_params.trap_atr_multiplier   =InpTrapATRMultiplier;
   g_params.trap_spacing_multiplier=InpTrapSpacingMultiplier;
   g_params.trap_dd_threshold     =InpTrapDDThreshold;
   g_params.trap_conditions_required=InpTrapConditionsRequired;
   g_params.trap_stuck_minutes    =InpTrapStuckMinutes;
   
   // Quick exit mode
   g_params.quick_exit_enabled    =InpQuickExitEnabled;
   g_params.quick_exit_mode       =InpQuickExitMode;
   g_params.quick_exit_loss       =InpQuickExitLoss;
   g_params.quick_exit_percentage =InpQuickExitPercentage;
   g_params.quick_exit_close_far  =InpQuickExitCloseFar;
   g_params.quick_exit_reseed     =InpQuickExitReseed;
   g_params.quick_exit_timeout_min=InpQuickExitTimeoutMinutes;

   // THEN apply preset overrides (if not CUSTOM)
   // Preset will override only the critical params (spacing, grid, target, cooldown)
   if(InpSymbolPreset != PRESET_CUSTOM)
     {
      CPresetManager::ApplyPreset(g_params, InpSymbolPreset, _Symbol, InpUseTestedPresets);
     }
  }

int OnInit()
  {
   BuildParams();

   g_logger   = new CLogger(InpStatusInterval,InpLogEvents);
   if(g_logger!=NULL)
     {
      g_logger.Initialize(g_params.magic);  // Initialize file logging with magic number
      g_logger.LogEvent(LOG_INIT,StringFormat("EA v3.1.0 Phase 1 - Magic: %d",g_params.magic));
     }
   
   g_spacing  = new CSpacingEngine(_Symbol,g_params.spacing_mode,g_params.atr_period,g_params.atr_timeframe,g_params.spacing_atr_mult,g_params.spacing_pips,g_params.min_spacing_pips);
   g_validator= new COrderValidator(_Symbol,g_params.respect_stops_level);
   g_executor = new COrderExecutor(_Symbol,g_validator,g_params.slippage_pips,g_params.order_cooldown_sec);
   if(g_executor!=NULL)
      g_executor.SetMagic(g_params.magic);
   g_news_filter = new CNewsFilter(InpNewsFilterEnabled,InpNewsImpactFilter,InpNewsBufferMinutes,g_logger);

   // Single lifecycle controller (simplified)
   g_controller = new CLifecycleController(_Symbol,g_params,g_spacing,g_executor,g_logger,g_params.magic);

   if(g_controller==NULL || !g_controller.Init())
     {
      if(g_logger!=NULL)
         g_logger.Event("[RGDv2]","Controller init failed");
      return(INIT_FAILED);
     }
   
   // Print comprehensive configuration (Phase 1)
   PrintConfiguration();

   return(INIT_SUCCEEDED);
  }

void OnTick()
  {
   // Check if market is open
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);

   // Skip weekend
   if(dt.day_of_week==0 || dt.day_of_week==6)
      return;

   // Check symbol trading allowed
   if(!SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE))
      return;

   // Check news filter (pause trading during high-impact news)
   string active_event = "";
   if(g_news_filter != NULL && g_news_filter.IsNewsTime(active_event))
     {
      // Log once when entering news window (IsNewsTime handles this internally)
      // Skip trading during news
      return;
     }

   // Update lifecycle controller
   if(g_controller!=NULL)
      g_controller.Update();
  }

void OnDeinit(const int reason)
  {
   if(g_controller!=NULL){ g_controller.Shutdown(); delete g_controller; g_controller=NULL; }
   if(g_news_filter!=NULL){ delete g_news_filter; g_news_filter=NULL; }
   if(g_executor!=NULL){ delete g_executor; g_executor=NULL; }
   if(g_validator!=NULL){ delete g_validator; g_validator=NULL; }
   if(g_spacing!=NULL){ delete g_spacing; g_spacing=NULL; }
   if(g_logger!=NULL){ delete g_logger; g_logger=NULL; }
  }
