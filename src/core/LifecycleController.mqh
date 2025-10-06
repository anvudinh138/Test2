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
#include "RescueEngine.mqh"
#include "PortfolioLedger.mqh"
#include "GridBasket.mqh"
#include "Logger.mqh"

class CLifecycleController
  {
private:
   string            m_symbol;
   SParams           m_params;
   CSpacingEngine   *m_spacing;
   COrderExecutor   *m_executor;
   CRescueEngine    *m_rescue;
   CPortfolioLedger *m_ledger;
   CLogger          *m_log;
   long              m_magic;

   CGridBasket      *m_buy;
   CGridBasket      *m_sell;
   bool              m_halted;

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

   void              UpdateRoles(CGridBasket *loser,CGridBasket *winner)
     {
      if(m_buy!=NULL)
         m_buy.SetKind(BASKET_PRIMARY);
      if(m_sell!=NULL)
         m_sell.SetKind(BASKET_PRIMARY);
      if(winner!=NULL)
         winner.SetKind(BASKET_HEDGE);
     }

   void              EnsureRescueReset()
     {
      bool active_buy=(m_buy!=NULL) && m_buy.IsActive();
      bool active_sell=(m_sell!=NULL) && m_sell.IsActive();
      if(!active_buy && !active_sell && m_rescue!=NULL)
         m_rescue.ResetCycleCounter();
     }

   bool              TryReseedBasket(CGridBasket *basket,const EDirection dir,const bool allow_new_orders)
     {
      if(!allow_new_orders)
         return false;
      if(basket==NULL)
         return false;
      if(basket.IsActive())
         return false;
      double seed_lot=NormalizeVolume(m_params.lot_base);
      if(seed_lot<=0.0)
         return false;
      if(m_ledger!=NULL && !m_ledger.ExposureAllowed(seed_lot,m_magic,m_symbol))
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
      EnsureRescueReset();
     }

public:
                     CLifecycleController(const string symbol,
                                          const SParams &params,
                                          CSpacingEngine *spacing,
                                          COrderExecutor *executor,
                                          CRescueEngine *rescue,
                                          CPortfolioLedger *ledger,
                                          CLogger *log,
                                          const long magic)
                       : m_symbol(symbol),
                         m_params(params),
                         m_spacing(spacing),
                         m_executor(executor),
                         m_rescue(rescue),
                         m_ledger(ledger),
                         m_log(log),
                         m_magic(magic),
                         m_buy(NULL),
                         m_sell(NULL),
                         m_halted(false)
     {
     }

   bool              Init()
     {
      double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
      double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      if(ask<=0 || bid<=0)
        return false;

      double seed_lot=NormalizeVolume(m_params.lot_base);
      if(m_ledger!=NULL && !m_ledger.ExposureAllowed(seed_lot,m_magic,m_symbol))
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),"Exposure cap reached before bootstrap");
         return false;
        }

      m_buy=new CGridBasket(m_symbol,DIR_BUY,BASKET_PRIMARY,m_params,m_spacing,m_executor,m_log,m_magic);
      if(!m_buy.Init(ask))
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),"Failed to seed BUY basket");
         delete m_buy;
         m_buy=NULL;
         return false;
        }

      if(m_ledger!=NULL && !m_ledger.ExposureAllowed(seed_lot,m_magic,m_symbol))
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),"Exposure cap hit before SELL basket");
         if(m_executor!=NULL)
           {
            m_executor.SetMagic(m_magic);
            m_executor.CloseAllByDirection(DIR_BUY,m_magic);
            m_executor.CancelPendingByDirection(DIR_BUY,m_magic);
           }
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

      datetime now=TimeCurrent();

      if(m_ledger!=NULL)
         m_ledger.UpdateEquitySnapshot();

      if(m_ledger!=NULL && m_ledger.SessionRiskBreached())
        {
         FlattenAll("Session SL");
         return;
        }

      if(m_buy!=NULL)
         m_buy.Update();
      if(m_sell!=NULL)
         m_sell.Update();

      double spacing_pips=m_spacing.SpacingPips();
      double spacing_px=m_spacing.ToPrice(spacing_pips);
      double atr_points=m_spacing.AtrPoints();
      if(atr_points<=0.0)
         atr_points=spacing_px;

      CGridBasket *loser=NULL;
      CGridBasket *winner=NULL;
      double worst=0.0;

      if(m_buy!=NULL && m_buy.IsActive())
        {
         double pnl=m_buy.BasketPnL();
         if(pnl<0 && pnl<worst)
           {
            worst=pnl;
            loser=m_buy;
           }
        }
      if(m_sell!=NULL && m_sell.IsActive())
        {
         double pnl=m_sell.BasketPnL();
         if(pnl<0 && pnl<worst)
           {
            worst=pnl;
            loser=m_sell;
           }
      }
      if(loser!=NULL)
        {
         winner=(loser==m_buy)?m_sell:m_buy;
         if(winner!=NULL && !winner.IsActive())
            winner=NULL;
        }

      UpdateRoles(loser,winner);

      if(loser!=NULL && winner!=NULL && m_rescue!=NULL)
        {
         double price_winner=CurrentPrice(winner.Direction());
         double dd=-MathMin(0.0,loser.BasketPnL());
         double rescue_lot=winner.NormalizeLot(m_params.recovery_lot);
         if(rescue_lot>0.0 && m_rescue.CooldownOk() && m_rescue.CyclesAvailable())
           {
            if(m_rescue.ShouldRescue(loser.Direction(),loser.LastGridPrice(),spacing_px,price_winner,dd))
              {
               bool exposure_ok=(m_ledger==NULL) || m_ledger.ExposureAllowed(rescue_lot,m_magic,m_symbol);
               if(exposure_ok)
                 {
                  winner.DeployRecovery(price_winner);
                  m_rescue.RecordRescue();
                  if(m_log!=NULL)
                     m_log.Event(Tag(),"Rescue deployed");
                 }
               else
                 {
                  m_rescue.LogSkip("Exposure cap blocks rescue");
                 }
              }
           }
        }

      if(m_buy!=NULL && m_buy.ClosedRecently())
        {
         double realized=m_buy.TakeRealizedProfit();
         if(realized>0 && m_sell!=NULL)
            m_sell.ReduceTargetBy(realized);
         TryReseedBasket(m_buy,DIR_BUY,true);
        }
      if(m_sell!=NULL && m_sell.ClosedRecently())
        {
         double realized=m_sell.TakeRealizedProfit();
         if(realized>0 && m_buy!=NULL)
            m_buy.ReduceTargetBy(realized);
         TryReseedBasket(m_sell,DIR_SELL,true);
        }

      EnsureRescueReset();
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
  };

#endif // __RGD_V2_LIFECYCLE_CONTROLLER_MQH__
