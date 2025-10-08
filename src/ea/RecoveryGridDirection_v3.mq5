#property strict
// FORCE RECOMPILE - Phase 3 Debug - 2025.10.08 23:58

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
#include <RECOVERY-GRID-DIRECTION_v3/core/JobManager.mqh>

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
input int               InpGridLevels       = 5;     // Grid levels per side (REDUCED from 10 to 5 for safety)
input double            InpLotBase          = 0.01;  // Base lot size
input double            InpLotScale         = 2.0;   // Lot scale multiplier

//--- Dynamic Grid (auto-refill pending levels)
input bool              InpDynamicGrid      = false;  // Enable dynamic grid
input int               InpWarmLevels       = 5;     // Initial pending levels
input int               InpRefillThreshold  = 2;     // Refill when pendings <= this
input int               InpRefillBatch      = 3;     // Levels per refill
input int               InpMaxPendings      = 15;    // Max pending orders

//--- Profit Target
input double            InpTargetCycleUSD   = 6.0;   // Target profit per cycle (USD)

//--- Risk Management (Session Stop Loss)
input double            InpSessionSL_USD    = 10000; // Session stop loss (USD) - for monitoring only

//--- Grid Protection (Anti Blow-Up)
input bool              InpGridProtection   = false;  // Enable grid full auto-close
input int               InpCooldownMinutes  = 30;    // Cooldown after grid full (minutes)

//--- News Filter (pause trading during high-impact news)
input bool              InpNewsFilterEnabled   = false;  // Enable news filter
input string            InpNewsImpactFilter    = "High"; // Impact filter (High, Medium+, All)
input int               InpNewsBufferMinutes   = 30;     // Buffer before/after news (minutes)

//--- Trend Filter (Phase 1.1 - Strong Trend Protection)
input group             "=== Trend Filter (Phase 1.1 - OFF for Phase 0) ==="
input bool              InpTrendFilterEnabled  = false;              // Enable trend filter
input ETrendAction      InpTrendAction         = TREND_ACTION_NONE;  // Trend action (NONE/CLOSE_ALL/NO_REFILL)
input ENUM_TIMEFRAMES   InpTrendEMA_Timeframe  = PERIOD_H4;          // EMA timeframe
input int               InpTrendEMA_Period     = 200;                // EMA period
input int               InpTrendADX_Period     = 14;                 // ADX period
input double            InpTrendADX_Threshold  = 30.0;               // ADX threshold
input double            InpTrendBufferPips     = 100.0;              // Buffer distance (pips)

//--- Execution
input int               InpOrderCooldownSec = 5;     // Min seconds between orders (anti-spam)
input int               InpSlippagePips     = 0;     // Max slippage (pips)
input bool              InpRespectStops     = false; // Respect broker stops level (false for backtest)
input double            InpCommissionPerLot = 0.0;   // Commission per lot (for PnL calc only, does NOT affect live)

//--- Multi-Job System (Phase 2 - Experimental)
input group             "=== Multi-Job System (v3.0 - EXPERIMENTAL) ==="
input bool              InpMultiJobEnabled  = false; // Enable multi-job system (OFF by default)
input int               InpMaxJobs          = 5;     // Max concurrent jobs (5-10 recommended)
input double            InpJobSL_USD        = 50.0;  // SL per job in USD (0=disabled)
input double            InpJobDDThreshold   = 30.0;  // Abandon job if DD >= this % (e.g., 30%)
input double            InpGlobalDDLimit    = 50.0;  // Stop spawning if global DD >= this % (e.g., 50%)

input group             "=== Magic Number (Job Isolation) ==="
input long              InpMagicOffset      = 421;   // Magic offset between jobs (e.g., 421)

input group             "=== Spawn Triggers ==="
input bool              InpSpawnOnGridFull  = true;  // Spawn new job when grid full
input bool              InpSpawnOnTSL       = true;  // Spawn new job when TSL active
input bool              InpSpawnOnJobDD     = true;  // Spawn new job when job DD >= threshold
input int               InpSpawnCooldownSec = 30;    // Cooldown between spawns (seconds)
input int               InpMaxSpawns        = 10;    // Max spawns per session

//--- Basket Stop Loss (Spacing-Based Risk Management)
input group             "=== Basket Stop Loss (v3.2 - Spacing-Based) ==="
input bool              InpBasketSL_Enabled     = false;       // Enable basket stop loss
input double            InpBasketSL_Spacing     = 2.0;         // SL distance in spacing units (e.g., 2.0 = 2x spacing from entry)
input EReseedMode       InpReseedMode           = RESEED_COOLDOWN; // When to reseed after basket SL
input int               InpReseedCooldownMin    = 30;          // Cooldown minutes before reseed (for COOLDOWN mode)

//+------------------------------------------------------------------+
//| NEW PARAMETERS FOR v3.1.0 - Lazy Grid Fill + Trap Detection     |
//+------------------------------------------------------------------+

//--- Lazy Grid Fill (Phase 1)
input group             "=== Lazy Grid Fill (v3.1 - Phase 0: OFF) ==="
input bool              InpLazyGridEnabled      = false;       // Enable lazy grid fill (OFF for Phase 0)
input int               InpInitialWarmLevels    = 1;           // Initial pending levels (1-2)
input int               InpMaxLevelDistance     = 500;         // Max distance to next level (pips)
input double            InpMaxDDForExpansion    = -20.0;       // Stop expanding if DD < this (%)

//--- Trap Detection (Phase 2)
input group             "=== Trap Detection (v3.1 - Phase 0: OFF) ==="
input bool              InpTrapDetectionEnabled = false;       // Enable trap detection (OFF for Phase 0)
input double            InpTrapGapThreshold     = 200.0;       // Gap threshold (pips)
input double            InpTrapDDThreshold      = -20.0;       // DD threshold (%)
input int               InpTrapConditionsRequired = 3;         // Min conditions to trigger (3/5)
input int               InpTrapStuckMinutes     = 30;          // Minutes to consider "stuck"

//--- Quick Exit Mode (Phase 3)
input group             "=== Quick Exit Mode (v3.1 - Phase 0: OFF) ==="
input bool              InpQuickExitEnabled     = false;       // Enable quick exit (OFF for Phase 0)
input ENUM_QUICK_EXIT_MODE InpQuickExitMode    = QE_FIXED;    // Exit mode
input double            InpQuickExitLoss        = -10.0;       // Fixed loss amount ($)
input double            InpQuickExitPercentage  = 0.30;        // Percentage mode (30% of DD)
input bool              InpQuickExitCloseFar    = true;        // Close far positions in quick exit
input bool              InpQuickExitReseed      = true;        // Auto reseed after exit
input int               InpQuickExitTimeoutMinutes = 60;       // Timeout (minutes)

//--- Gap Management (Phase 4)
input group             "=== Gap Management (v3.1 - Phase 0: OFF) ==="
input bool              InpAutoFillBridge       = false;       // Auto fill bridge levels (OFF for Phase 0)
input int               InpMaxBridgeLevels      = 5;           // Max bridge levels per gap
input double            InpMaxPositionDistance  = 300.0;       // Max distance for position (pips)
input double            InpMaxAcceptableLoss    = -100.0;      // Max loss to abandon trapped ($)

//--- Globals
SParams              g_params;
CLogger             *g_logger        = NULL;
CSpacingEngine      *g_spacing       = NULL;
COrderValidator     *g_validator     = NULL;
COrderExecutor      *g_executor      = NULL;
CLifecycleController*g_controller    = NULL;
CJobManager         *g_job_manager   = NULL;
CNewsFilter         *g_news_filter   = NULL;

//+------------------------------------------------------------------+
//| Print comprehensive configuration                                |
//+------------------------------------------------------------------+
void PrintConfiguration()
  {
   if(g_logger==NULL)
      return;
   Print("test ABCXYZ");
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
   
   // Dynamic Grid (legacy)
   Print("--- Legacy Dynamic Grid ---");
   Print("Enabled: ",(InpDynamicGrid?"YES":"NO"));
   if(InpDynamicGrid)
     {
      Print("  Warm levels: ",InpWarmLevels);
      Print("  Refill threshold: ",InpRefillThreshold);
      Print("  Refill batch: ",InpRefillBatch);
      Print("  Max pendings: ",InpMaxPendings);
     }
   Print("");
   
   // Risk management
   Print("--- Risk Management ---");
   Print("Session SL: $",InpSessionSL_USD," (monitoring only)");
   Print("Grid protection: ",(InpGridProtection?"ENABLED":"DISABLED"));
   if(InpGridProtection)
      Print("  Cooldown: ",InpCooldownMinutes," minutes");
   Print("");
   
   // Filters
   Print("--- Filters ---");
   Print("News filter: ",(InpNewsFilterEnabled?"ENABLED":"DISABLED"));
   if(InpNewsFilterEnabled)
     {
      Print("  Impact: ",InpNewsImpactFilter);
      Print("  Buffer: ",InpNewsBufferMinutes," minutes");
     }
   
   string trend_action_str="";
   switch(InpTrendAction)
     {
      case TREND_ACTION_NONE: trend_action_str="NONE (Block new only)"; break;
      case TREND_ACTION_CLOSE_ALL: trend_action_str="CLOSE_ALL (Flatten counter-trend)"; break;
      case TREND_ACTION_NO_REFILL: trend_action_str="NO_REFILL (Stop adding levels)"; break;
     }
   Print("Trend action: ",trend_action_str);
   Print("");
   
   // v3.1.0 Features (Phase 0-4)
   Print("========================================");
   Print("v3.1.0 NEW FEATURES STATUS");
   Print("========================================");
   
   // Lazy Grid Fill (Phase 1)
   Print("1. LAZY GRID FILL: ",(InpLazyGridEnabled?"ENABLED ⚠️":"DISABLED ✓"));
   if(InpLazyGridEnabled)
     {
      Print("   Initial warm levels: ",InpInitialWarmLevels);
      Print("   Max level distance: ",InpMaxLevelDistance," pips");
      Print("   Max DD for expansion: ",InpMaxDDForExpansion,"%");
     }
   
   // Trap Detection (Phase 2)
   Print("2. TRAP DETECTION: ",(InpTrapDetectionEnabled?"ENABLED ⚠️":"DISABLED ✓"));
   if(InpTrapDetectionEnabled)
     {
      Print("   Gap threshold: ",InpTrapGapThreshold," pips");
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
   
   // Gap Management (Phase 4)
   Print("4. GAP MANAGEMENT: ",(InpAutoFillBridge?"ENABLED ⚠️":"DISABLED ✓"));
   if(InpAutoFillBridge)
     {
      Print("   Max bridge levels: ",InpMaxBridgeLevels);
      Print("   Max position distance: ",InpMaxPositionDistance," pips");
      Print("   Max acceptable loss: $",InpMaxAcceptableLoss);
     }
   
   Print("");
   
   // Phase 0 validation
   if(InpLazyGridEnabled || InpTrapDetectionEnabled || InpQuickExitEnabled || InpAutoFillBridge)
     {
      Print("⚠️  WARNING: Phase 0 expects ALL new features OFF!");
      Print("    Enable only after Phase 1-4 implementation.");
     }
   else
     {
      Print("✅ Phase 0 OK: All new features disabled as expected.");
     }
   
   // Multi-job system
   if(InpMultiJobEnabled)
     {
      Print("");
      Print("--- Multi-Job System (EXPERIMENTAL) ---");
      Print("Max jobs: ",InpMaxJobs);
      Print("Job SL: $",InpJobSL_USD);
      Print("Job DD threshold: ",InpJobDDThreshold,"%");
      Print("Global DD limit: ",InpGlobalDDLimit,"%");
      Print("Magic offset: ",InpMagicOffset);
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

   g_params.grid_dynamic_enabled=InpDynamicGrid;
   g_params.grid_warm_levels   =InpWarmLevels;
   g_params.grid_refill_threshold=InpRefillThreshold;
   g_params.grid_refill_batch  =InpRefillBatch;
   g_params.grid_max_pendings  =InpMaxPendings;

   g_params.target_cycle_usd   =InpTargetCycleUSD;
   g_params.session_sl_usd     =InpSessionSL_USD;

   g_params.grid_protection_enabled=InpGridProtection;
   g_params.grid_cooldown_minutes=InpCooldownMinutes;

   g_params.slippage_pips      =InpSlippagePips;
   g_params.order_cooldown_sec =InpOrderCooldownSec;
   g_params.respect_stops_level=InpRespectStops;
   g_params.commission_per_lot =InpCommissionPerLot;

   g_params.magic              =InpMagic;

   // Multi-job system params
   g_params.multi_job_enabled  =InpMultiJobEnabled;
   g_params.max_jobs           =InpMaxJobs;
   g_params.job_sl_usd         =InpJobSL_USD;
   g_params.job_dd_threshold   =InpJobDDThreshold;
   g_params.global_dd_limit    =InpGlobalDDLimit;
   g_params.magic_start        =InpMagic;
   g_params.magic_offset       =InpMagicOffset;
   g_params.spawn_on_grid_full =InpSpawnOnGridFull;
   g_params.spawn_on_tsl       =InpSpawnOnTSL;
   g_params.spawn_on_job_dd    =InpSpawnOnJobDD;
   g_params.spawn_cooldown_sec =InpSpawnCooldownSec;
   g_params.max_spawns         =InpMaxSpawns;

   // Timeframe preservation (bug fix - always enabled)
   g_params.preserve_on_tf_switch=true;

   // Trend filter (Phase 1.1 - strong trend protection)
   g_params.trend_filter_enabled  =InpTrendFilterEnabled;
   g_params.trend_action          =InpTrendAction;
   g_params.trend_ema_timeframe   =InpTrendEMA_Timeframe;
   g_params.trend_ema_period      =InpTrendEMA_Period;
   g_params.trend_adx_period      =InpTrendADX_Period;
   g_params.trend_adx_threshold   =InpTrendADX_Threshold;
   g_params.trend_buffer_pips     =InpTrendBufferPips;

   // Basket stop loss (Phase 1.2 - spacing-based risk management)
   g_params.basket_sl_enabled     =InpBasketSL_Enabled;
   g_params.basket_sl_spacing     =InpBasketSL_Spacing;
   g_params.reseed_mode           =InpReseedMode;
   g_params.reseed_cooldown_min   =InpReseedCooldownMin;

   // NEW v3.1.0 parameters (Phase 0: OFF by default)
   // Lazy grid fill
   g_params.lazy_grid_enabled     =InpLazyGridEnabled;
   g_params.initial_warm_levels   =InpInitialWarmLevels;
   g_params.max_level_distance    =InpMaxLevelDistance;
   g_params.max_dd_for_expansion  =InpMaxDDForExpansion;
   
   // Trap detection
   g_params.trap_detection_enabled=InpTrapDetectionEnabled;
   g_params.trap_gap_threshold    =InpTrapGapThreshold;
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
   
   // Gap management
   g_params.auto_fill_bridge      =InpAutoFillBridge;
   g_params.max_bridge_levels     =InpMaxBridgeLevels;
   g_params.max_position_distance =InpMaxPositionDistance;
   g_params.max_acceptable_loss   =InpMaxAcceptableLoss;

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

   // Multi-job system (Phase 2) or legacy single lifecycle
   if(g_params.multi_job_enabled)
     {
      // Multi-job mode
      g_job_manager = new CJobManager(_Symbol,g_params,g_spacing,g_executor,g_logger,
                                      g_params.magic_start,g_params.magic_offset,
                                      g_params.global_dd_limit,g_params.job_sl_usd,g_params.job_dd_threshold,
                                      g_params.spawn_cooldown_sec,g_params.max_spawns,
                                      g_params.spawn_on_grid_full,g_params.spawn_on_tsl,g_params.spawn_on_job_dd);

      if(g_job_manager==NULL || !g_job_manager.Init())
        {
         if(g_logger!=NULL)
            g_logger.Event("[RGDv2]","JobManager init failed");
         return(INIT_FAILED);
        }

      if(g_logger!=NULL)
         g_logger.Event("[RGDv2]","Multi-Job System: ENABLED (EXPERIMENTAL)");
     }
   else
     {
      // Legacy single lifecycle mode
      g_controller = new CLifecycleController(_Symbol,g_params,g_spacing,g_executor,g_logger,g_params.magic);

      if(g_controller==NULL || !g_controller.Init())
        {
         if(g_logger!=NULL)
            g_logger.Event("[RGDv2]","Controller init failed");
         return(INIT_FAILED);
        }
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

   // Update lifecycle (multi-job or legacy)
   if(g_params.multi_job_enabled)
     {
      if(g_job_manager!=NULL)
         g_job_manager.Update();
     }
   else
     {
      if(g_controller!=NULL)
         g_controller.Update();
     }
  }

void OnDeinit(const int reason)
  {
   if(g_job_manager!=NULL){ g_job_manager.Shutdown(); delete g_job_manager; g_job_manager=NULL; }
   if(g_controller!=NULL){ g_controller.Shutdown(); delete g_controller; g_controller=NULL; }
   if(g_news_filter!=NULL){ delete g_news_filter; g_news_filter=NULL; }
   if(g_executor!=NULL){ delete g_executor; g_executor=NULL; }
   if(g_validator!=NULL){ delete g_validator; g_validator=NULL; }
   if(g_spacing!=NULL){ delete g_spacing; g_spacing=NULL; }
   if(g_logger!=NULL){ delete g_logger; g_logger=NULL; }
  }
