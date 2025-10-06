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
   bool              m_halted;

   // Grid protection
   datetime          m_cooldown_until;        // Cooldown end time
   bool              m_in_cooldown;           // Currently in cooldown

   // P&L tracking (for multi-job system)
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

   bool              TryReseedBasket(CGridBasket *basket,const EDirection dir)
     {
      if(basket==NULL)
         return false;
      if(basket.IsActive())
         return false;
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
      if(!m_params.grid_protection_enabled)
         return;

      // Check cooldown status
      datetime now=TimeCurrent();
      if(m_in_cooldown)
        {
         if(now>=m_cooldown_until)
           {
            m_in_cooldown=false;
            if(m_log!=NULL)
               m_log.Event(Tag(),"Cooldown ended - EA active again");
           }
         else
           {
            // Still in cooldown - skip trading
            return;
           }
        }

      // Check if any basket hit grid full
      bool buy_full=(m_buy!=NULL && m_buy.IsGridFull());
      bool sell_full=(m_sell!=NULL && m_sell.IsGridFull());

      if(buy_full || sell_full)
        {
         // Calculate current floating loss
         double total_pnl=0.0;
         if(m_buy!=NULL)
            total_pnl+=m_buy.BasketPnL();
         if(m_sell!=NULL)
            total_pnl+=m_sell.BasketPnL();

         string side=(buy_full && sell_full)?"BUY+SELL":(buy_full?"BUY":"SELL");

         if(m_log!=NULL)
           {
            int buy_filled=(m_buy!=NULL)?m_buy.GetFilledLevels():0;
            int sell_filled=(m_sell!=NULL)?m_sell.GetFilledLevels():0;
            m_log.Event(Tag(),StringFormat("Grid FULL detected: %s | BUY:%d SELL:%d | Floating PnL:%.2f USD",
                                          side,buy_filled,sell_filled,total_pnl));
           }

         // Close all positions (accept current loss to prevent blow-up)
         FlattenAll(StringFormat("Grid exhausted (%s) - Auto-close at %.2f USD",side,total_pnl));

         // Set cooldown
         int cooldown_seconds=m_params.grid_cooldown_minutes*60;
         m_cooldown_until=now+cooldown_seconds;
         m_in_cooldown=true;

         if(m_log!=NULL)
           {
            MqlDateTime dt;
            TimeToStruct(m_cooldown_until,dt);
            m_log.Event(Tag(),StringFormat("Cooldown activated: %d minutes (until %02d:%02d)",
                                          m_params.grid_cooldown_minutes,dt.hour,dt.min));
           }
        }
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
                         m_halted(false),
                         m_cooldown_until(0),
                         m_in_cooldown(false),
                         m_total_realized_pnl(0.0)
     {
     }

   bool              Init()
     {
      double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
      double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      if(ask<=0 || bid<=0)
        return false;

      double seed_lot=NormalizeVolume(m_params.lot_base);

      m_buy=new CGridBasket(m_symbol,DIR_BUY,BASKET_PRIMARY,m_params,m_spacing,m_executor,m_log,m_magic);
      if(!m_buy.Init(ask))
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),"Failed to seed BUY basket");
         delete m_buy;
         m_buy=NULL;
         return false;
        }

      m_sell=new CGridBasket(m_symbol,DIR_SELL,BASKET_PRIMARY,m_params,m_spacing,m_executor,m_log,m_magic);
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

      // Check grid protection first (before updating baskets)
      CheckGridProtection();

      // Skip trading if in cooldown
      if(m_in_cooldown)
         return;

      if(m_buy!=NULL)
         m_buy.Update();
      if(m_sell!=NULL)
         m_sell.Update();

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
