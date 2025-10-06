//+------------------------------------------------------------------+
//| Represents one directional basket with grouped TP math           |
//+------------------------------------------------------------------+
#ifndef __RGD_V2_GRID_BASKET_MQH__
#define __RGD_V2_GRID_BASKET_MQH__

#include <Trade/Trade.mqh>
#include "Types.mqh"
#include "Params.mqh"
#include "SpacingEngine.mqh"
#include "OrderExecutor.mqh"
#include "Logger.mqh"
#include "MathHelpers.mqh"

class CGridBasket
  {
private:
   string         m_symbol;
   EDirection     m_direction;
   EBasketKind    m_kind;
   SParams        m_params;
   CSpacingEngine *m_spacing;
   COrderExecutor *m_executor;
   CLogger       *m_log;
   long           m_magic;

   SGridLevel     m_levels[];
   bool           m_active;
   bool           m_closed_recently;
   int            m_cycles_done;

   double         m_total_lot;
   double         m_avg_price;
   double         m_pnl_usd;
   double         m_tp_price;
   double         m_last_grid_price;
   double         m_target_reduction;
   
   // dynamic grid state
   int            m_max_levels;
   int            m_levels_placed;
   int            m_pending_count;
   double         m_initial_spacing_pips;

   double         m_last_realized;

   double         m_volume_step;
   double         m_volume_min;
   double         m_volume_max;
   int            m_volume_digits;

   string         Tag() const
     {
      string side=(m_direction==DIR_BUY)?"BUY":"SELL";
      string role=(m_kind==BASKET_PRIMARY)?"PRI":"HEDGE";
      return StringFormat("[RGDv2][%s][%s][%s]",m_symbol,side,role);
     }

   string         DirectionLabel() const
     {
      return (m_direction==DIR_BUY)?"BUY":"SELL";
     }

   bool           MatchesOrderDirection(const ENUM_ORDER_TYPE type) const
     {
      if(m_direction==DIR_BUY)
         return (type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP);
      return (type==ORDER_TYPE_SELL_LIMIT || type==ORDER_TYPE_SELL_STOP);
     }

   void           LogDynamic(const string action,const int level,const double price)
     {
      if(m_log==NULL)
         return;
      int digits=(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
      m_log.Event(Tag(),StringFormat("DG/%s dir=%s level=%d price=%s pendings=%d last=%s",
                                     action,
                                     DirectionLabel(),
                                     level,
                                     DoubleToString(price,digits),
                                     m_pending_count,
                                     DoubleToString(m_last_grid_price,digits)));
     }

   double         LevelLot(const int idx) const
     {
      double result=m_params.lot_base;
      for(int i=1;i<=idx;i++)
         result*=m_params.lot_scale;
      return NormalizeVolumeValue(result);
     }

   void           ClearLevels()
     {
      ArrayResize(m_levels,0);
     }

   double         NormalizeVolumeValue(double volume) const
     {
      if(volume<=0.0)
         return 0.0;
      double step=(m_volume_step>0.0)?m_volume_step:0.0;
      double normalized=volume;
      if(step>0.0)
        {
         double steps=MathRound(volume/step);
         normalized=steps*step;
        }
      if(normalized<=0.0)
        normalized=(m_volume_min>0.0)?m_volume_min:volume;
      if(m_volume_min>0.0 && normalized<m_volume_min)
         normalized=m_volume_min;
      if(m_volume_max>0.0 && normalized>m_volume_max)
         normalized=m_volume_max;
      if(m_volume_digits>0)
         normalized=NormalizeDouble(normalized,m_volume_digits);
      return normalized;
     }

   void           AppendLevel(const double price,const double lot)
     {
      int idx=ArraySize(m_levels);
      ArrayResize(m_levels,idx+1);
      m_levels[idx].price=price;
      m_levels[idx].lot=NormalizeVolumeValue(lot);
      m_levels[idx].ticket=0;
      m_levels[idx].filled=false;
     }

   void           BuildGrid(const double anchor_price,const double spacing_px)
     {
      ClearLevels();
      m_max_levels=m_params.grid_levels;
      m_levels_placed=0;
      m_pending_count=0;
      
      // Pre-allocate full array but only fill warm levels
      if(m_params.grid_dynamic_enabled)
        {
         ArrayResize(m_levels,m_max_levels);
         for(int i=0;i<m_max_levels;i++)
           {
            m_levels[i].price=0.0;
            m_levels[i].lot=0.0;
            m_levels[i].ticket=0;
            m_levels[i].filled=false;
           }
        }
      else
        {
         // Old behavior: build all levels
         AppendLevel(anchor_price,LevelLot(0));
         for(int i=1;i<m_params.grid_levels;i++)
           {
            double price=anchor_price;
            if(m_direction==DIR_BUY)
               price-=spacing_px*i;
            else
               price+=spacing_px*i;
            AppendLevel(price,LevelLot(i));
           }
         m_last_grid_price=m_levels[ArraySize(m_levels)-1].price;
        }
     }

   void           PlaceInitialOrders()
     {
      if(ArraySize(m_levels)==0)
         return;
      if(m_executor==NULL)
         return;

      m_executor.SetMagic(m_magic);
      
      if(m_params.grid_dynamic_enabled)
        {
         // Dynamic mode: only place seed + warm levels
         int warm=MathMin(m_params.grid_warm_levels,m_max_levels-1);
         int warm_cap=warm;
         if(m_params.grid_max_pendings>0)
            warm_cap=MathMin(warm,m_params.grid_max_pendings);
         m_executor.BypassNext(1+warm_cap);
         
         double spacing_px=m_spacing.ToPrice(m_initial_spacing_pips);
         double anchor=SymbolInfoDouble(m_symbol,(m_direction==DIR_BUY)?SYMBOL_ASK:SYMBOL_BID);
         
         // Place seed
         double seed_lot=LevelLot(0);
         ulong market_ticket=m_executor.Market(m_direction,seed_lot,"RGDv2_Seed");
         if(market_ticket>0)
           {
            m_levels[0].price=anchor;
            m_levels[0].lot=seed_lot;
            m_levels[0].ticket=market_ticket;
            m_levels[0].filled=true;
            m_levels_placed++;
            m_last_grid_price=anchor;
            LogDynamic("SEED",0,anchor);
           }
         
         // Place warm pending
         for(int i=1;i<=warm_cap;i++)
           {
            double price=anchor;
            if(m_direction==DIR_BUY)
               price-=spacing_px*i;
            else
               price+=spacing_px*i;
            double lot=LevelLot(i);
            ulong pending=(m_direction==DIR_BUY)?m_executor.Limit(DIR_BUY,price,lot,"RGDv2_Grid")
                                                :m_executor.Limit(DIR_SELL,price,lot,"RGDv2_Grid");
            if(pending>0)
              {
               m_levels[i].price=price;
               m_levels[i].lot=lot;
               m_levels[i].ticket=pending;
               m_levels[i].filled=false;
               m_levels_placed++;
               m_pending_count++;
               m_last_grid_price=price;
               LogDynamic("SEED",i,price);
              }
           }

         if((warm>warm_cap) || (m_params.grid_max_pendings>0 && m_pending_count>=m_params.grid_max_pendings))
            LogDynamic("LIMIT",m_levels_placed,m_last_grid_price);

         if(m_pending_count==0)
            m_last_grid_price=anchor;
         
         if(m_log!=NULL)
            m_log.Event(Tag(),StringFormat("Dynamic grid warm=%d/%d",m_levels_placed,m_max_levels));
        }
      else
        {
         // Old static mode: place all
         m_executor.BypassNext(ArraySize(m_levels));
         
         double seed_lot=m_levels[0].lot;
         if(seed_lot<=0.0)
            return;
         ulong market_ticket=m_executor.Market(m_direction,seed_lot,"RGDv2_Seed");
         if(market_ticket>0)
           {
            m_levels[0].ticket=market_ticket;
            m_levels[0].filled=true;
           }
         
         for(int i=1;i<ArraySize(m_levels);i++)
           {
            double price=m_levels[i].price;
            double lot=m_levels[i].lot;
            if(lot<=0.0)
               continue;
            ulong pending=0;
            if(m_direction==DIR_BUY)
               pending=m_executor.Limit(DIR_BUY,price,lot,"RGDv2_Grid");
            else
               pending=m_executor.Limit(DIR_SELL,price,lot,"RGDv2_Grid");
            if(pending>0)
               m_levels[i].ticket=pending;
           }
         
         if(m_log!=NULL)
            m_log.Event(Tag(),StringFormat("Grid seeded levels=%d",ArraySize(m_levels)));
        }
     }

   void           RefreshState()
     {
      m_total_lot=0.0;
      m_avg_price=0.0;
      m_pnl_usd=0.0;

      double lot_acc=0.0;
      double weighted_price=0.0;

      int total=(int)PositionsTotal();
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
         long type=PositionGetInteger(POSITION_TYPE);
         if((m_direction==DIR_BUY && type!=POSITION_TYPE_BUY) ||
            (m_direction==DIR_SELL && type!=POSITION_TYPE_SELL))
            continue;
         double vol=PositionGetDouble(POSITION_VOLUME);
         double price=PositionGetDouble(POSITION_PRICE_OPEN);
         double profit=PositionGetDouble(POSITION_PROFIT);
         lot_acc+=vol;
         weighted_price+=vol*price;
         m_pnl_usd+=profit;
        }

      if(lot_acc>0.0)
        {
         m_total_lot=lot_acc;
         m_avg_price=weighted_price/lot_acc;
        }
      else
        {
         m_total_lot=0.0;
         m_avg_price=0.0;
        }

      if(m_total_lot>0.0)
         CalculateGroupTP();
     }

   void           CalculateGroupTP()
     {
      double tick_value=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_VALUE);
      double tick_size=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tick_value<=0.0 || tick_size<=0.0)
        {
         m_tp_price=m_avg_price;
         return;
        }
      double usd_per_point=(tick_value/tick_size)*m_total_lot;
      double target=MathMax(0.0,m_params.target_cycle_usd-m_target_reduction);
      if(m_params.commission_per_lot>0.0)
         target+=m_params.commission_per_lot*m_total_lot;
      if(usd_per_point<=0.0)
        {
         m_tp_price=m_avg_price;
         return;
        }
      double delta=target/usd_per_point;
      if(m_direction==DIR_BUY)
         m_tp_price=m_avg_price+delta;
      else
         m_tp_price=m_avg_price-delta;
     }

   bool           PriceReachedTP() const
     {
      if(m_total_lot<=0.0)
         return false;
      double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
      if(m_direction==DIR_BUY)
         return (bid>=m_tp_price);
      return (ask<=m_tp_price);
     }

   void           CloseBasket(const string reason)
     {
      if(!m_active)
         return;
      m_last_realized=m_pnl_usd;
      if(m_executor!=NULL)
        {
         m_executor.SetMagic(m_magic);
         m_executor.CloseAllByDirection(m_direction,m_magic);
         m_executor.CancelPendingByDirection(m_direction,m_magic);
        }
      m_active=false;
      m_closed_recently=true;
      m_cycles_done++;
      if(m_log!=NULL)
        m_log.Event(Tag(),StringFormat("Basket closed: %s",reason));
     }

  void           AdjustTarget(const double delta,const string reason)
     {
      if(delta<=0.0)
         return;
      m_target_reduction+=delta;
      if(m_target_reduction<0.0)
         m_target_reduction=0.0;
      if(m_target_reduction>m_params.target_cycle_usd)
         m_target_reduction=m_params.target_cycle_usd;
      CalculateGroupTP();
      if(m_log!=NULL && reason!="" && delta>0.0)
         m_log.Event(Tag(),StringFormat("%s %.2f => %.2f",reason,delta,EffectiveTargetUsd()));
     }

public:
   CGridBasket(const string symbol,
                                 const EDirection direction,
                                 const EBasketKind kind,
                                 const SParams &params,
                                 CSpacingEngine *spacing,
                                 COrderExecutor *executor,
                                 CLogger *logger,
                                 const long magic)
                       : m_symbol(symbol),
                         m_direction(direction),
                         m_kind(kind),
                         m_params(params),
                         m_spacing(spacing),
                         m_executor(executor),
                         m_log(logger),
                         m_magic(magic),
                         m_active(false),
                         m_closed_recently(false),
                         m_cycles_done(0),
                         m_total_lot(0.0),
                         m_avg_price(0.0),
                         m_pnl_usd(0.0),
                         m_tp_price(0.0),
                         m_last_grid_price(0.0),
                         m_target_reduction(0.0),
                         m_max_levels(0),
                         m_levels_placed(0),
                         m_pending_count(0),
                         m_initial_spacing_pips(0.0),
                         m_last_realized(0.0),
                         m_volume_step(0.0),
                         m_volume_min(0.0),
                         m_volume_max(0.0),
                         m_volume_digits(0)
     {
      m_volume_step=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
      m_volume_min=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
      m_volume_max=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MAX);
      m_volume_digits=0;
      double step=m_volume_step;
      if(step>0.0)
        {
         double tmp=step;
         while(tmp<1.0 && m_volume_digits<8)
           {
            tmp*=10.0;
            m_volume_digits++;
            if(MathAbs(tmp-MathRound(tmp))<1e-6)
               break;
           }
        }
      ArrayResize(m_levels,0);
     }

   bool           Init(const double anchor_price)
     {
      if(m_spacing==NULL)
         return false;
      double spacing_pips=m_spacing.SpacingPips();
      double spacing_px=m_spacing.ToPrice(spacing_pips);
      if(spacing_px<=0.0)
         return false;
      m_initial_spacing_pips=spacing_pips;
      BuildGrid(anchor_price,spacing_px);
      m_target_reduction=0.0;
      m_last_realized=0.0;
      PlaceInitialOrders();
      m_active=true;
      m_closed_recently=false;
      RefreshState();
      return true;
     }

   void           RefillBatch()
     {
      if(!m_params.grid_dynamic_enabled)
         return;
      if(m_levels_placed>=m_max_levels)
         return;
      if(m_pending_count>m_params.grid_refill_threshold)
         return;
      if(m_params.grid_max_pendings>0 && m_pending_count>=m_params.grid_max_pendings)
         return;
      
      double spacing_px=m_spacing.ToPrice(m_initial_spacing_pips);
      double anchor_price=SymbolInfoDouble(m_symbol,(m_direction==DIR_BUY)?SYMBOL_BID:SYMBOL_ASK);
      int to_add=MathMin(m_params.grid_refill_batch,m_max_levels-m_levels_placed);
      int added=0;
      
      for(int i=0;i<to_add;i++)
        {
         int idx=m_levels_placed;
         if(idx>=m_max_levels)
            break;
         
         double base_price=(m_levels_placed==0)?anchor_price:m_last_grid_price;
         double price=base_price;
         if(m_direction==DIR_BUY)
            price-=spacing_px;
         else
            price+=spacing_px;
         
         double lot=LevelLot(idx);
         if(lot<=0.0)
            continue;
         
         ulong pending=(m_direction==DIR_BUY)?m_executor.Limit(DIR_BUY,price,lot,"RGDv2_GridRefill")
                                             :m_executor.Limit(DIR_SELL,price,lot,"RGDv2_GridRefill");
         if(pending>0)
           {
            m_levels[idx].price=price;
            m_levels[idx].lot=lot;
            m_levels[idx].ticket=pending;
            m_levels[idx].filled=false;
            m_levels_placed++;
            m_pending_count++;
            m_last_grid_price=price;
            LogDynamic("REFILL",idx,price);
            added++;

            if(m_params.grid_max_pendings>0 && m_pending_count>=m_params.grid_max_pendings)
              {
               LogDynamic("LIMIT",idx,price);
               break;
              }
           }
        }
      
      if(added>0 && m_log!=NULL)
         m_log.Event(Tag(),StringFormat("Refill +%d placed=%d/%d pending=%d",added,m_levels_placed,m_max_levels,m_pending_count));
     }

   void           Update()
     {
      if(!m_active)
         return;
      m_closed_recently=false;
      RefreshState();
      
      // Dynamic grid refill
      if(m_params.grid_dynamic_enabled)
        {
         // Update pending count by direction
         m_pending_count=0;
         int total=(int)OrdersTotal();
         for(int i=0;i<total;i++)
           {
            ulong ticket=OrderGetTicket(i);
            if(ticket==0)
               continue;
            if(!OrderSelect(ticket))
               continue;
            if(OrderGetString(ORDER_SYMBOL)!=m_symbol)
               continue;
            if(OrderGetInteger(ORDER_MAGIC)!=m_magic)
               continue;
            ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            if(!MatchesOrderDirection(type))
               continue;
            m_pending_count++;
           }
         RefillBatch();
        }

      if((m_pnl_usd>=EffectiveTargetUsd()) || PriceReachedTP())
        {
         CloseBasket("GroupTP");
        }
      if(m_active)
        {
         bool no_positions=(m_total_lot<=0.0);
         bool no_pending=true;
         int total=(int)OrdersTotal();
         for(int i=0;i<total;i++)
           {
            ulong ticket=OrderGetTicket(i);
            if(ticket==0)
               continue;
            if(!OrderSelect(ticket))
               continue;
            if(OrderGetString(ORDER_SYMBOL)!=m_symbol)
               continue;
            if(OrderGetInteger(ORDER_MAGIC)!=m_magic)
               continue;
            no_pending=false;
            break;
           }
         if(no_positions && no_pending)
           m_active=false;
        }
     }

   void           ReduceTargetBy(const double profit_usd)
     {
      AdjustTarget(profit_usd,"Pull target by");
     }

   void           TightenTarget(const double delta_usd,const string reason)
     {
      AdjustTarget(delta_usd,reason);
     }

   double         EffectiveTargetUsd() const
     {
      double target=m_params.target_cycle_usd-m_target_reduction;
      if(target<0.0)
         target=0.0;
      return target;
     }

   bool           IsActive() const { return m_active; }
   bool           ClosedRecently() const { return m_closed_recently; }
   double         TakeRealizedProfit()
     {
      double value=m_last_realized;
      m_last_realized=0.0;
      return value;
     }

   int            CyclesDone() const { return m_cycles_done; }
   double         BasketPnL() const { return m_pnl_usd; }
   double         LastGridPrice() const { return m_last_grid_price; }
   double         AveragePrice() const { return m_avg_price; }
   double         TotalLot() const { return m_total_lot; }
   double         GroupTPPrice() const { return m_tp_price; }
   void           SetKind(const EBasketKind kind) { m_kind=kind; }

   EBasketKind    Kind() const { return m_kind; }
   EDirection     Direction() const { return m_direction; }

   double         NormalizeLot(const double volume) const { return NormalizeVolumeValue(volume); }

   SBasketSummary Snapshot() const
     {
      SBasketSummary snap;
      snap.direction=m_direction;
      snap.kind=m_kind;
      snap.total_lot=m_total_lot;
      snap.avg_price=m_avg_price;
      snap.pnl_usd=m_pnl_usd;
      snap.tp_price=m_tp_price;
      snap.last_grid_price=m_last_grid_price;
      snap.trailing_active=false;
      return snap;
     }

   void           ResetTargetReduction()
     {
      m_target_reduction=0.0;
     }

   void           MarkInactive()
     {
      m_active=false;
     }
  };

#endif // __RGD_V2_GRID_BASKET_MQH__
