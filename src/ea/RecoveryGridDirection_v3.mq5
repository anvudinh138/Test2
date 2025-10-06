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

//--- Symbol Preset (Auto-configure for different symbols)
input ENUM_SYMBOL_PRESET InpSymbolPreset    = PRESET_AUTO;  // Symbol preset (AUTO, EURUSD, XAUUSD, GBPUSD, USDJPY, CUSTOM)

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
input bool              InpDynamicGrid      = true;  // Enable dynamic grid
input int               InpWarmLevels       = 5;     // Initial pending levels
input int               InpRefillThreshold  = 2;     // Refill when pendings <= this
input int               InpRefillBatch      = 3;     // Levels per refill
input int               InpMaxPendings      = 15;    // Max pending orders

//--- Profit Target
input double            InpTargetCycleUSD   = 6.0;   // Target profit per cycle (USD)

//--- Risk Management (Session Stop Loss)
input double            InpSessionSL_USD    = 10000; // Session stop loss (USD) - for monitoring only

//--- Grid Protection (Anti Blow-Up)
input bool              InpGridProtection   = true;  // Enable grid full auto-close
input int               InpCooldownMinutes  = 30;    // Cooldown after grid full (minutes)

//--- News Filter (pause trading during high-impact news)
input bool              InpNewsFilterEnabled   = false;  // Enable news filter
input string            InpNewsImpactFilter    = "High"; // Impact filter (High, Medium+, All)
input int               InpNewsBufferMinutes   = 30;     // Buffer before/after news (minutes)

//--- Execution
input int               InpOrderCooldownSec = 5;     // Min seconds between orders (anti-spam)
input int               InpSlippagePips     = 0;     // Max slippage (pips)
input bool              InpRespectStops     = false; // Respect broker stops level (false for backtest)
input double            InpCommissionPerLot = 0.0;   // Commission per lot (for PnL calc only, does NOT affect live)

//--- Globals
SParams              g_params;
CLogger             *g_logger        = NULL;
CSpacingEngine      *g_spacing       = NULL;
COrderValidator     *g_validator     = NULL;
COrderExecutor      *g_executor      = NULL;
CLifecycleController*g_controller    = NULL;
CNewsFilter         *g_news_filter   = NULL;

void BuildParams()
  {
   // First apply manual inputs (baseline configuration)
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

   // Apply preset overrides (if not CUSTOM)
   if(InpSymbolPreset != PRESET_CUSTOM)
     {
      CPresetManager::ApplyPreset(g_params, InpSymbolPreset, _Symbol);
     }
  }

int OnInit()
  {
   BuildParams();

   g_logger   = new CLogger(InpStatusInterval,InpLogEvents);
   g_spacing  = new CSpacingEngine(_Symbol,g_params.spacing_mode,g_params.atr_period,g_params.atr_timeframe,g_params.spacing_atr_mult,g_params.spacing_pips,g_params.min_spacing_pips);
   g_validator= new COrderValidator(_Symbol,g_params.respect_stops_level);
   g_executor = new COrderExecutor(_Symbol,g_validator,g_params.slippage_pips,g_params.order_cooldown_sec);
   if(g_executor!=NULL)
      g_executor.SetMagic(g_params.magic);
   g_news_filter = new CNewsFilter(InpNewsFilterEnabled,InpNewsImpactFilter,InpNewsBufferMinutes,g_logger);
   g_controller = new CLifecycleController(_Symbol,g_params,g_spacing,g_executor,g_logger,g_params.magic);

   if(g_controller==NULL || !g_controller.Init())
     {
      if(g_logger!=NULL)
         g_logger.Event("[RGDv2]","Controller init failed");
      return(INIT_FAILED);
     }
   
   // Debug info
   if(g_logger!=NULL)
     {
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      g_logger.Event("[RGDv2]",StringFormat("Init OK - Ask=%.5f Bid=%.5f LotBase=%.2f GridLevels=%d Dynamic=%s",
                                            ask,bid,g_params.lot_base,g_params.grid_levels,
                                            g_params.grid_dynamic_enabled?"ON":"OFF"));

      // Log news filter status
      if(InpNewsFilterEnabled)
         g_logger.Event("[RGDv2]",StringFormat("News Filter: ENABLED (Impact=%s, Buffer=%d min)",
                                               InpNewsImpactFilter,InpNewsBufferMinutes));
      else
         g_logger.Event("[RGDv2]","News Filter: DISABLED");

      // Log grid protection status
      if(InpGridProtection)
         g_logger.Event("[RGDv2]",StringFormat("Grid Protection: ENABLED (Cooldown=%d min after grid full)",
                                               InpCooldownMinutes));
      else
         g_logger.Event("[RGDv2]","Grid Protection: DISABLED");

      // Log active preset
      string preset_name = CPresetManager::GetPresetName(InpSymbolPreset);
      if(InpSymbolPreset == PRESET_CUSTOM)
         g_logger.Event("[RGDv2]",StringFormat("Preset: CUSTOM (manual inputs)"));
      else
         g_logger.Event("[RGDv2]",StringFormat("Preset: %s (Spacing=%.1f, ATR=%s, Cooldown=%d min)",
                                               preset_name,
                                               g_params.spacing_pips,
                                               EnumToString(g_params.atr_timeframe),
                                               g_params.grid_cooldown_minutes));
     }

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
