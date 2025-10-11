//+------------------------------------------------------------------+
//| Lifecycle controller orchestrating both directional baskets      |
//+------------------------------------------------------------------+
#ifndef __RGD_V2_LIFECYCLE_CONTROLLER_MQH__
#define __RGD_V2_LIFECYCLE_CONTROLLER_MQH__

#include <Indicators/Trend.mqh>
#include "Types.mqh"
#include "Params.mqh"
#include "SpacingEngine.mqh"
#include "OrderExecutor.mqh"
#include "GridBasket.mqh"
#include "TrendFilter.mqh"
#include "TrendStrengthAnalyzer.mqh"
#include "Logger.mqh"

class CLifecycleController
  {
private:
   string            m_symbol;
   SParams           m_params;
   CSpacingEngine   *m_spacing;
   COrderExecutor   *m_executor;
   CLogger          *m_log;
   long              m_magic;

   CGridBasket      *m_buy;
   CGridBasket      *m_sell;
   CTrendFilter     *m_trend_filter;
   CTrendStrengthAnalyzer *m_trend_analyzer;  // Phase 13: Market state analysis
   bool              m_halted;

   // Grid protection
   datetime          m_cooldown_until;        // Cooldown end time
   bool              m_in_cooldown;           // Currently in cooldown

   // P&L tracking
   double            m_total_realized_pnl;    // Cumulative realized profit

   string            Tag() const { return StringFormat("[RGDv2][%s][LC]",m_symbol); }

   double           CurrentPrice(const EDirection dir) const
     {
      return (dir==DIR_BUY)?SymbolInfoDouble(m_symbol,SYMBOL_ASK)
                           :SymbolInfoDouble(m_symbol,SYMBOL_BID);
     }

   double           NormalizeVolume(const double volume) const
     {
      if(volume<=0.0)
         return 0.0;
      double step=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
      double min=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
      double max=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MAX);
      double result=volume;
      int digits=0;
      if(step>0.0)
        {
         double steps=MathRound(volume/step);
         result=steps*step;
         double tmp=step;
         while(tmp<1.0 && digits<8)
           {
            tmp*=10.0;
            digits++;
            if(MathAbs(tmp-MathRound(tmp))<1e-6)
               break;
           }
        }
      if(result<=0.0)
         result=(min>0.0)?min:volume;
      if(min>0.0 && result<min)
         result=min;
      if(max>0.0 && result>max)
         result=max;
      if(digits>0)
         result=NormalizeDouble(result,digits);
      return result;
     }

   CGridBasket*      Basket(const EDirection dir)
     {
      return (dir==DIR_BUY)?m_buy:m_sell;
     }

   bool              HasExistingPositions() const
     {
      int total=PositionsTotal();
      for(int i=0;i<total;i++)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0)
            continue;
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol)
            continue;
         if(PositionGetInteger(POSITION_MAGIC)!=m_magic)
            continue;
         return true;
        }
      return false;
     }

   bool              TryReseedBasket(CGridBasket *basket,const EDirection dir)
     {
      if(basket==NULL)
         return false;
      if(basket.IsActive())
         return false;

      // Check trend filter before reseeding
      if(!basket.IsTradingEnabled())
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),StringFormat("Reseed %s blocked by trend filter", (dir==DIR_BUY)?"BUY":"SELL"));
         return false;
        }

      double seed_lot=NormalizeVolume(m_params.lot_base);
      if(seed_lot<=0.0)
         return false;
      double price=CurrentPrice(dir);
      if(price<=0.0)
         return false;
      basket.ResetTargetReduction();
      if(basket.Init(price))
        {
         if(m_log!=NULL)
           m_log.Event(Tag(),StringFormat("Reseed %s grid", (dir==DIR_BUY)?"BUY":"SELL"));

         return true;
        }
      return false;
     }

   void              FlattenAll(const string reason)
     {
      if(m_log!=NULL)
         m_log.Event(Tag(),StringFormat("Flatten requested: %s",reason));
      if(m_executor!=NULL)
        {
         m_executor.SetMagic(m_magic);
         if(m_buy!=NULL)
           {
            m_executor.CloseAllByDirection(DIR_BUY,m_magic);
            m_executor.CancelPendingByDirection(DIR_BUY,m_magic);
           }
         if(m_sell!=NULL)
           {
            m_executor.CloseAllByDirection(DIR_SELL,m_magic);
            m_executor.CancelPendingByDirection(DIR_SELL,m_magic);
           }
        }
      if(m_buy!=NULL)
         m_buy.MarkInactive();
      if(m_sell!=NULL)
         m_sell.MarkInactive();
      m_halted=true;
     }

   void              CheckGridProtection()
     {
      // Grid protection feature removed (not needed with lazy grid)
      return;
     }

public:
                     CLifecycleController(const string symbol,
                                          const SParams &params,
                                          CSpacingEngine *spacing,
                                          COrderExecutor *executor,
                                          CLogger *log,
                                          const long magic)
                       : m_symbol(symbol),
                         m_params(params),
                         m_spacing(spacing),
                         m_executor(executor),
                         m_log(log),
                         m_magic(magic),
                         m_buy(NULL),
                         m_sell(NULL),
                         m_trend_filter(NULL),
                         m_trend_analyzer(NULL),
                         m_halted(false),
                         m_cooldown_until(0),
                         m_in_cooldown(false),
                         m_total_realized_pnl(0.0)
     {
      // Trend filter disabled (will implement in later phase)
      m_trend_filter=NULL;
     }

   bool              Init()
     {
      // Initialize trend filter
      if(m_trend_filter!=NULL && !m_trend_filter.Init())
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),"Trend filter init failed");
         delete m_trend_filter;
         m_trend_filter=NULL;
        }

      // Phase 13: Initialize trend strength analyzer
      if(m_params.dynamic_spacing_enabled)
        {
         m_trend_analyzer=new CTrendStrengthAnalyzer(m_symbol,m_params.trend_timeframe,m_log);
         if(m_log!=NULL)
           {
            m_log.Event(Tag(),StringFormat("Phase 13: Trend analyzer enabled (TF: %s)",
                                          EnumToString(m_params.trend_timeframe)));
           }
        }

      double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
      double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      if(ask<=0 || bid<=0)
        return false;

      // Check if we should preserve existing positions (TF switch protection)
      bool has_positions=m_params.preserve_on_tf_switch && HasExistingPositions();

      if(has_positions)
        {
         // Reconstruct mode: baskets will discover their positions
         if(m_log!=NULL)
            m_log.Event(Tag(),"[TF-Preserve] Existing positions detected, reconstructing baskets");

         m_buy=new CGridBasket(m_symbol,DIR_BUY,BASKET_PRIMARY,m_params,m_spacing,m_executor,m_log,m_magic);
         m_sell=new CGridBasket(m_symbol,DIR_SELL,BASKET_PRIMARY,m_params,m_spacing,m_executor,m_log,m_magic);

         // Phase 12: Set trend filter for conditional Basket SL
         m_buy.SetTrendFilter(m_trend_filter);
         m_sell.SetTrendFilter(m_trend_filter);

         // Phase 13: Set trend analyzer for dynamic spacing
         m_buy.SetTrendAnalyzer(m_trend_analyzer);
         m_sell.SetTrendAnalyzer(m_trend_analyzer);

         // Mark baskets active without seeding
         m_buy.SetActive(true);
         m_sell.SetActive(true);

         // Force immediate refresh to discover positions
         m_buy.Update();
         m_sell.Update();

         if(m_log!=NULL)
           {
            int buy_positions=m_buy.IsActive()?1:0;
            int sell_positions=m_sell.IsActive()?1:0;
            m_log.Event(Tag(),StringFormat("[TF-Preserve] Reconstruction complete: BUY:%s SELL:%s",
                                          m_buy.IsActive()?"Active":"Inactive",
                                          m_sell.IsActive()?"Active":"Inactive"));
           }

         return true;
        }

      // Normal mode: seed new grid
      double seed_lot=NormalizeVolume(m_params.lot_base);

      // Seed BUY basket
      m_buy=new CGridBasket(m_symbol,DIR_BUY,BASKET_PRIMARY,m_params,m_spacing,m_executor,m_log,m_magic);
      m_buy.SetTradingEnabled(true);
      m_buy.SetTrendFilter(m_trend_filter);  // Phase 12: For conditional Basket SL
      m_buy.SetTrendAnalyzer(m_trend_analyzer);  // Phase 13: For dynamic spacing
      if(!m_buy.Init(ask))
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),"Failed to seed BUY basket");
         delete m_buy;
         m_buy=NULL;
         return false;
        }

      m_sell=new CGridBasket(m_symbol,DIR_SELL,BASKET_PRIMARY,m_params,m_spacing,m_executor,m_log,m_magic);
      m_sell.SetTradingEnabled(true);
      m_sell.SetTrendFilter(m_trend_filter);  // Phase 12: For conditional Basket SL
      m_sell.SetTrendAnalyzer(m_trend_analyzer);  // Phase 13: For dynamic spacing
      if(!m_sell.Init(bid))
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),"Failed to seed SELL basket");
         if(m_executor!=NULL)
           {
            m_executor.SetMagic(m_magic);
            m_executor.CloseAllByDirection(DIR_BUY,m_magic);
            m_executor.CancelPendingByDirection(DIR_BUY,m_magic);
           }
         delete m_buy;
         m_buy=NULL;
         delete m_sell;
         m_sell=NULL;
         return false;
        }

      if(m_log!=NULL)
         m_log.Event(Tag(),"Lifecycle bootstrapped");
      return true;
     }

   void              Update()
     {
      if(m_halted)
         return;

      // Trend filter disabled (will implement in Phase 6+)

      // Check grid protection first (before updating baskets)
      CheckGridProtection();

      // Skip trading if in cooldown
      if(m_in_cooldown)
         return;

      if(m_buy!=NULL)
         m_buy.Update();
      if(m_sell!=NULL)
         m_sell.Update();
      
      // Phase 5: Check trap conditions for both baskets
      if(m_buy!=NULL)
         m_buy.CheckTrapConditions();
      if(m_sell!=NULL)
         m_sell.CheckTrapConditions();

      // Phase 13 Layer 4: Check time-based exit
      if(m_buy!=NULL && m_buy.CheckTimeBasedExit())
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),"⏰ Closing BUY basket - Time exit triggered");
         m_buy.CloseBasket("TimeExit");
        }
      if(m_sell!=NULL && m_sell.CheckTimeBasedExit())
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),"⏰ Closing SELL basket - Time exit triggered");
         m_sell.CloseBasket("TimeExit");
        }

      if(m_buy!=NULL && m_buy.ClosedRecently())
        {
         double realized=m_buy.TakeRealizedProfit();
         m_total_realized_pnl+=realized;  // Track cumulative realized PnL
         if(realized>0 && m_sell!=NULL)
            m_sell.ReduceTargetBy(realized);
         TryReseedBasket(m_buy,DIR_BUY);
        }
      if(m_sell!=NULL && m_sell.ClosedRecently())
        {
         double realized=m_sell.TakeRealizedProfit();
         m_total_realized_pnl+=realized;  // Track cumulative realized PnL
         if(realized>0 && m_buy!=NULL)
            m_buy.ReduceTargetBy(realized);
         TryReseedBasket(m_sell,DIR_SELL);
        }
     }

   void              Shutdown()
     {
      if(m_buy!=NULL)
        {
         delete m_buy;
         m_buy=NULL;
        }
      if(m_sell!=NULL)
        {
         delete m_sell;
         m_sell=NULL;
        }
      if(m_trend_filter!=NULL)
        {
         delete m_trend_filter;
         m_trend_filter=NULL;
        }
      if(m_trend_analyzer!=NULL)
        {
         delete m_trend_analyzer;
         m_trend_analyzer=NULL;
        }
     }

   // P&L tracking methods (for multi-job system)
   double            GetUnrealizedPnL() const
     {
      double pnl=0.0;
      if(m_buy!=NULL)
         pnl+=m_buy.BasketPnL();
      if(m_sell!=NULL)
         pnl+=m_sell.BasketPnL();
      return pnl;
     }

   double            GetRealizedPnL() const
     {
      return m_total_realized_pnl;
     }

   double            GetTotalPnL() const
     {
      return GetUnrealizedPnL()+GetRealizedPnL();
     }

   // Phase 13: Trend analyzer access
   CTrendStrengthAnalyzer* GetTrendAnalyzer() const
     {
      return m_trend_analyzer;
     }

   bool              IsTSLActive() const
     {
      bool tsl_active=false;
      if(m_buy!=NULL)
         tsl_active=tsl_active || m_buy.IsTSLActive();
      if(m_sell!=NULL)
         tsl_active=tsl_active || m_sell.IsTSLActive();
      return tsl_active;
     }

   bool              IsGridFull() const
     {
      bool grid_full=false;
      if(m_buy!=NULL)
         grid_full=grid_full || m_buy.IsGridFull();
      if(m_sell!=NULL)
         grid_full=grid_full || m_sell.IsGridFull();
      return grid_full;
     }

   string            Symbol() const { return m_symbol; }
   SParams           Params() const { return m_params; }
  };

#endif // __RGD_V2_LIFECYCLE_CONTROLLER_MQH__
