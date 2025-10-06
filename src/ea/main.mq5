#property strict

#include <Trade/Trade.mqh>

#include <RECOVERY-GRID-DIRECTION_v3/core/Types.mqh>
#include <RECOVERY-GRID-DIRECTION_v3/core/Params.mqh>
#include <RECOVERY-GRID-DIRECTION_v3/core/Logger.mqh>
#include <RECOVERY-GRID-DIRECTION_v3/core/SpacingEngine.mqh>
#include <RECOVERY-GRID-DIRECTION_v3/core/OrderValidator.mqh>
#include <RECOVERY-GRID-DIRECTION_v3/core/OrderExecutor.mqh>
#include <RECOVERY-GRID-DIRECTION_v3/core/PortfolioLedger.mqh>
#include <RECOVERY-GRID-DIRECTION_v3/core/RescueEngine.mqh>
#include <RECOVERY-GRID-DIRECTION_v3/core/GridBasket.mqh>
#include <RECOVERY-GRID-DIRECTION_v3/core/LifecycleController.mqh>

//--- Inputs
input int               InpStatusInterval   = 60;
input bool              InpLogEvents        = true;

input ENUM_TIMEFRAMES InpAtrTimeframe       = PERIOD_M15;
input int             InpAtrPeriod          = 14;

enum InpSpacingModeEnum { InpSpacingPips=0, InpSpacingATR=1, InpSpacingHybrid=2 };
input InpSpacingModeEnum InpSpacingMode     = InpSpacingHybrid;
input double            InpSpacingStepPips  = 25.0;
input double            InpSpacingAtrMult   = 0.6;
input double            InpMinSpacingPips   = 12.0;

input int               InpGridLevels       = 6;
input double            InpLotBase          = 0.10;
input double            InpLotScale         = 1.00;

input bool              InpDynamicGrid      = false;
input int               InpWarmLevels       = 5;
input int               InpRefillThreshold  = 2;
input int               InpRefillBatch      = 3;
input int               InpMaxPendings      = 15;

input double            InpTargetCycleUSD   = 3.0;

input bool              InpTSLEnabled       = true;
input int               InpTSLStartPoints   = 1000;
input int               InpTSLStepPoints    = 200;

input string            InpRecoverySteps    = "1000,2000,3000";
input double            InpRecoveryLot      = 0.10;
input double            InpDDOpenUSD        = 8.0;
input double            InpOffsetRatio      = 0.5;

input double            InpExposureCapLots  = 2.0;
input int               InpMaxCyclesPerSide = 3;
input double            InpSessionSL_USD    = 30.0;
input int               InpCooldownBars     = 5;

input int               InpOrderCooldownSec = 5;
input int               InpSlippagePips     = 1;
input bool              InpRespectStops     = false;  // Set false for backtest

input double            InpCommissionPerLot = 7.0;
input long              InpMagic            = 990045;

//--- Globals
SParams              g_params;
CLogger             *g_logger        = NULL;
CSpacingEngine      *g_spacing       = NULL;
COrderValidator     *g_validator     = NULL;
COrderExecutor      *g_executor      = NULL;
CPortfolioLedger    *g_ledger        = NULL;
CRescueEngine       *g_rescue        = NULL;
CLifecycleController*g_controller    = NULL;

string TrimAll(const string value)
  {
   string tmp=value;
   StringTrimLeft(tmp);
   StringTrimRight(tmp);
   return tmp;
  }

int ParseRecoverySteps(const string csv,int &buffer[])
  {
   if(StringLen(csv)==0)
     {
      ArrayResize(buffer,0);
      return 0;
     }
   string parts[];
   int count=StringSplit(csv,',',parts);
   if(count<=0)
     {
      ArrayResize(buffer,0);
      return 0;
     }
   ArrayResize(buffer,count);
   for(int i=0;i<count;i++)
     {
      string trimmed=TrimAll(parts[i]);
      buffer[i]=(int)StringToInteger(trimmed);
     }
   return count;
  }

void BuildParams()
  {
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

   g_params.tsl_enabled        =InpTSLEnabled;
   g_params.tsl_start_points   =InpTSLStartPoints;
   g_params.tsl_step_points    =InpTSLStepPoints;

   ParseRecoverySteps(InpRecoverySteps,g_params.recovery_steps);
   g_params.recovery_lot       =InpRecoveryLot;
   g_params.dd_open_usd        =InpDDOpenUSD;
   g_params.offset_ratio       =InpOffsetRatio;
   g_params.exposure_cap_lots  =InpExposureCapLots;
   g_params.max_cycles_per_side=InpMaxCyclesPerSide;
   g_params.session_sl_usd     =InpSessionSL_USD;
   g_params.cooldown_bars      =InpCooldownBars;

   g_params.slippage_pips      =InpSlippagePips;
   g_params.order_cooldown_sec =InpOrderCooldownSec;
   g_params.respect_stops_level=InpRespectStops;
   g_params.commission_per_lot =InpCommissionPerLot;

   g_params.magic              =InpMagic;
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
   g_ledger   = new CPortfolioLedger(g_params.exposure_cap_lots,g_params.session_sl_usd);
   g_rescue   = new CRescueEngine(_Symbol,g_params,g_logger);
   g_controller = new CLifecycleController(_Symbol,g_params,g_spacing,g_executor,g_rescue,g_ledger,g_logger,g_params.magic);

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
      
   if(g_controller!=NULL)
      g_controller.Update();
  }

void OnDeinit(const int reason)
  {
   if(g_controller!=NULL){ g_controller.Shutdown(); delete g_controller; g_controller=NULL; }
   if(g_rescue!=NULL){ delete g_rescue; g_rescue=NULL; }
   if(g_ledger!=NULL){ delete g_ledger; g_ledger=NULL; }
   if(g_executor!=NULL){ delete g_executor; g_executor=NULL; }
   if(g_validator!=NULL){ delete g_validator; g_validator=NULL; }
   if(g_spacing!=NULL){ delete g_spacing; g_spacing=NULL; }
   if(g_logger!=NULL){ delete g_logger; g_logger=NULL; }
  }
