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
#include "TrapDetector.mqh"
#include "TrendFilter.mqh"

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
   bool           m_trading_enabled;  // Trend filter control (seed/reseed)
   bool           m_refill_enabled;   // Refill control (for NO_REFILL mode)
   bool           m_closed_recently;
   string         m_close_reason;     // Last close reason (for tracking BasketSL)
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

   //+------------------------------------------------------------------+
   //| NEW MEMBERS FOR LAZY GRID FILL & TRAP DETECTION                  |
   //+------------------------------------------------------------------+

   // Lazy grid fill tracking
   SGridState     m_grid_state;
   ENUM_GRID_STATE m_basket_state;

   // Trap detection
   CTrapDetector  *m_trap_detector;
   CTrendFilter   *m_trend_filter;

   // Quick exit mode
   bool           m_quick_exit_mode;
   double         m_quick_exit_target;
   double         m_original_target;
   datetime       m_quick_exit_start_time;
   SQuickExitConfig m_quick_exit_config;

   // Gap tracking
   double         m_last_gap_size;
   datetime       m_last_gap_check;

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

      // Check trend filter
      if(!m_trading_enabled)
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),"Initial seed blocked by trend filter");
         return;
        }

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
      m_close_reason=reason;  // Track close reason
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

   //+------------------------------------------------------------------+
   //| Check if basket SL is hit (spacing-based)                        |
   //+------------------------------------------------------------------+
   bool           CheckBasketSL()
     {
      // Only check if basket has positions
      if(m_total_lot<=0.0 || m_avg_price<=0.0)
         return false;

      // Get current spacing in price units
      double current_spacing_pips=(m_spacing!=NULL)?m_spacing.GetSpacing():m_params.spacing_pips;
      double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      double spacing_px=current_spacing_pips*point*10.0;

      // Calculate SL distance in price units
      double sl_distance_px=spacing_px*m_params.basket_sl_spacing;

      // Get current price
      double current_price=(m_direction==DIR_BUY)?SymbolInfoDouble(m_symbol,SYMBOL_BID):SymbolInfoDouble(m_symbol,SYMBOL_ASK);

      // Check if price moved against basket by SL distance
      bool sl_hit=false;
      if(m_direction==DIR_BUY)
        {
         // BUY basket: SL hit if price drops below (avg - SL distance)
         double sl_price=m_avg_price-sl_distance_px;
         sl_hit=(current_price<=sl_price);
        }
      else
        {
         // SELL basket: SL hit if price rises above (avg + SL distance)
         double sl_price=m_avg_price+sl_distance_px;
         sl_hit=(current_price>=sl_price);
        }

      if(sl_hit && m_log!=NULL)
        {
         int digits=(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
         m_log.Event(Tag(),StringFormat("Basket SL HIT: avg=%."+IntegerToString(digits)+"f cur=%."+IntegerToString(digits)+"f spacing=%.1f pips dist=%.1fx loss=%.2f USD",
                                        m_avg_price,current_price,current_spacing_pips,m_params.basket_sl_spacing,m_pnl_usd));
        }

      return sl_hit;
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
                         m_trading_enabled(true),
                         m_refill_enabled(true),
                         m_closed_recently(false),
                         m_close_reason(""),
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
                         m_volume_digits(0),
                         m_basket_state(GRID_STATE_ACTIVE),
                         m_trap_detector(NULL),
                         m_trend_filter(NULL),
                         m_quick_exit_mode(false),
                         m_quick_exit_target(0.0),
                         m_original_target(0.0),
                         m_quick_exit_start_time(0),
                         m_last_gap_size(0.0),
                         m_last_gap_check(0)
     {
      m_grid_state.Reset();
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
      if(!m_trading_enabled)
         return;  // Trend filter disabled trading (NONE/CLOSE_ALL modes)
      if(!m_refill_enabled)
         return;  // NO_REFILL mode: block refill, allow existing positions
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

      // Basket Stop Loss check (spacing-based)
      if(m_params.basket_sl_enabled && CheckBasketSL())
        {
         CloseBasket("BasketSL");
         return;  // Exit early after SL closure
        }

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
   string         GetCloseReason() const { return m_close_reason; }
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

   // Grid protection
   int            GetFilledLevels() const
     {
      int filled=0;
      for(int i=0;i<ArraySize(m_levels);i++)
        {
         if(m_levels[i].filled)
            filled++;
        }
      return filled;
     }

   bool           IsGridFull() const
     {
      if(m_max_levels<=0)
         return false;
      int filled=GetFilledLevels();
      return filled>=m_max_levels;
     }

   EBasketKind    Kind() const { return m_kind; }
   EDirection     Direction() const { return m_direction; }

   double         NormalizeLot(const double volume) const { return NormalizeVolumeValue(volume); }

   // Public wrapper for CloseBasket (for TrendAction)
   void           ForceClose(const string reason)
     {
      CloseBasket(reason);
     }

   //+------------------------------------------------------------------+
   //| NEW PUBLIC METHODS FOR LAZY GRID & QUICK EXIT                    |
   //+------------------------------------------------------------------+

   // Initialize trap detector and trend filter
   void           SetTrendFilter(CTrendFilter* filter) { m_trend_filter = filter; }

   // Lazy grid fill methods (declarations only - implemented below)
   void           SeedInitialGrid();
   void           OnLevelFilled(int level);
   bool           CheckForNextLevel();
   int            GetLastFilledLevel() const { return m_grid_state.lastFilledLevel; }
   bool           IsPriceReasonable(double pending_price) const;

   // Quick exit mode methods (declarations only - implemented below)
   void           ActivateQuickExitMode();
   void           DeactivateQuickExitMode();
   void           CheckQuickExitTP();
   double         CalculateQuickExitTarget();
   bool           IsInQuickExitMode() const { return m_quick_exit_mode; }
   ENUM_GRID_STATE GetState() const { return m_basket_state; }

   // Gap management methods (declarations only - implemented below)
   double         CalculateGapSize();
   void           FillBridgeLevels();
   void           CloseFarPositions();
   bool           HasLargeGap() const { return m_last_gap_size > m_params.trap_gap_threshold; }

   // Trap detection (declarations only - implemented below)
   void           HandleTrapDetected();
   bool           CheckTrapConditions();

   // State management
   void           SetState(ENUM_GRID_STATE state) { m_basket_state = state; }
   void           ReseedBasket();

   // Position info (declarations only - implemented below)
   int            GetPositionCount() const;
   double         GetFloatingPnL() const { return m_pnl_usd; }
   double         GetDDPercent() const;
   datetime       GetOldestPositionTime() const;
   double         GetLevelPrice(int level) const;

   // TSL detection (placeholder for multi-job spawn trigger)
   bool           IsTSLActive() const
     {
      // TODO: Implement TSL logic when feature is added
      // For now, always return false
      return false;
     }

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

   void           SetActive(const bool active)
     {
      m_active=active;
     }

   void           SetTradingEnabled(const bool enabled)
     {
      m_trading_enabled=enabled;
     }

   bool           IsTradingEnabled() const
     {
      return m_trading_enabled;
     }

   void           SetRefillEnabled(const bool enabled)
     {
      m_refill_enabled=enabled;
     }

   bool           IsRefillEnabled() const
     {
      return m_refill_enabled;
     }

   //+------------------------------------------------------------------+
   //| IMPLEMENTATION OF NEW METHODS FOR LAZY GRID & QUICK EXIT         |
   //+------------------------------------------------------------------+

   //+------------------------------------------------------------------+
   //| Seed initial grid with lazy fill (only 1-2 levels)               |
   //+------------------------------------------------------------------+
   void SeedInitialGrid()
     {
      if(!m_params.lazy_grid_enabled)
        {
         // Use standard grid fill
         PlaceInitialOrders();
         return;
        }

      Print("🌱 LAZY GRID: Seeding initial ", m_params.initial_warm_levels, " levels for ", DirectionLabel());

      double current_price = (m_direction == DIR_BUY) ?
                            SymbolInfoDouble(m_symbol, SYMBOL_ASK) :
                            SymbolInfoDouble(m_symbol, SYMBOL_BID);

      double spacing = m_spacing.ComputeSpacing();

      // Place only initial warm levels
      for(int i = 1; i <= m_params.initial_warm_levels && i < m_params.grid_levels; i++)
        {
         double level_price;
         if(m_direction == DIR_BUY)
            level_price = current_price - (spacing * _Point * i);
         else
            level_price = current_price + (spacing * _Point * i);

         double lot = LevelLot(i);
         AppendLevel(level_price, lot);
        }

      // Update grid state
      m_grid_state.currentMaxLevel = m_params.initial_warm_levels;
      m_grid_state.pendingCount = m_params.initial_warm_levels;
      m_basket_state = GRID_STATE_ACTIVE;

      // Place the orders
      PlaceInitialOrders();
     }

   //+------------------------------------------------------------------+
   //| Called when a level fills - expand grid on demand                |
   //+------------------------------------------------------------------+
   void OnLevelFilled(int level)
     {
      if(!m_params.lazy_grid_enabled) return;

      m_grid_state.lastFilledLevel = level;
      m_grid_state.lastFilledPrice = m_levels[level].price;
      m_grid_state.lastFilledTime = TimeCurrent();

      Print("📍 Level ", level, " filled for ", DirectionLabel());

      // Check if we should expand
      if(!CheckForNextLevel())
        {
         Print("🛑 Expansion halted for ", DirectionLabel());
        }
     }

   //+------------------------------------------------------------------+
   //| Check if we should place next level                              |
   //+------------------------------------------------------------------+
   bool CheckForNextLevel()
     {
      if(!m_params.lazy_grid_enabled) return false;

      // Check trend FIRST
      if(m_trend_filter && m_trend_filter.IsCounterTrend(m_direction))
        {
         Print("🛑 Counter-trend detected - HALT expansion for ", DirectionLabel());
         m_basket_state = GRID_STATE_HALTED;
         return false;
        }

      // Check DD threshold
      double dd = GetDDPercent();
      if(dd < m_params.max_dd_for_expansion)
        {
         Print("⚠️ DD threshold reached (", dd, "%) - HALT expansion");
         m_basket_state = GRID_STATE_HALTED;
         return false;
        }

      // Check if we've reached max levels
      if(m_grid_state.currentMaxLevel >= m_params.grid_levels - 1)
        {
         Print("📊 Max levels reached - Grid full");
         m_basket_state = GRID_STATE_GRID_FULL;
         return false;
        }

      // OK to place next level
      int next_level = m_grid_state.currentMaxLevel + 1;
      double spacing = m_spacing.ComputeSpacing();

      double next_price;
      if(m_direction == DIR_BUY)
         next_price = m_grid_state.lastFilledPrice - (spacing * _Point);
      else
         next_price = m_grid_state.lastFilledPrice + (spacing * _Point);

      // Verify price is reasonable
      if(!IsPriceReasonable(next_price))
        {
         Print("⚠️ Next level price unreasonable - HALT");
         return false;
        }

      // Place the next level
      double lot = LevelLot(next_level);
      AppendLevel(next_price, lot);

      Print("➕ Placing next level ", next_level, " @ ", next_price);

      // Update state
      m_grid_state.currentMaxLevel = next_level;
      m_grid_state.pendingCount++;

      // Execute the order
      ENUM_ORDER_TYPE order_type = (m_direction == DIR_BUY) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
      m_executor.PlaceOrder(m_symbol, order_type, lot, next_price, 0, 0, m_magic, "L" + IntegerToString(next_level));

      return true;
     }

   //+------------------------------------------------------------------+
   //| Check if pending price is reasonable                             |
   //+------------------------------------------------------------------+
   bool IsPriceReasonable(double pending_price) const
     {
      double current_price = (m_direction == DIR_BUY) ?
                            SymbolInfoDouble(m_symbol, SYMBOL_BID) :
                            SymbolInfoDouble(m_symbol, SYMBOL_ASK);

      double distance = MathAbs(current_price - pending_price) / _Point;

      if(m_direction == DIR_SELL)
        {
         // SELL pending must be ABOVE current price
         return (pending_price > current_price) && (distance < m_params.max_level_distance);
        }
      else
        {
         // BUY pending must be BELOW current price
         return (pending_price < current_price) && (distance < m_params.max_level_distance);
        }
     }

   //+------------------------------------------------------------------+
   //| Activate quick exit mode                                         |
   //+------------------------------------------------------------------+
   void ActivateQuickExitMode()
     {
      if(m_quick_exit_mode || !m_params.quick_exit_enabled) return;

      Print("⚡ QUICK EXIT MODE ACTIVATED for ", DirectionLabel());

      m_quick_exit_mode = true;
      m_quick_exit_start_time = TimeCurrent();

      // Backup original target
      m_original_target = m_params.target_cycle_usd;

      // Calculate quick exit target
      m_quick_exit_target = CalculateQuickExitTarget();

      Print("   Current PnL: $", GetFloatingPnL());
      Print("   Quick exit target: $", m_quick_exit_target);

      // Set new target (can be negative for accepting loss)
      m_params.target_cycle_usd = m_quick_exit_target;

      // Close far positions if enabled
      if(m_params.quick_exit_close_far)
        {
         Print("   Closing far positions to accelerate exit...");
         CloseFarPositions();
         RefreshState();  // Recalculate metrics
        }

      // Recalculate TP
      CalculateGroupTP();

      Print("   New TP price: ", m_tp_price);

      m_basket_state = GRID_STATE_QUICK_EXIT;

      if(m_log)
         m_log.Event(Tag(), "QUICK_EXIT_MODE_ON");
     }

   //+------------------------------------------------------------------+
   //| Calculate quick exit target based on mode                        |
   //+------------------------------------------------------------------+
   double CalculateQuickExitTarget()
     {
      switch(m_params.quick_exit_mode)
        {
         case QE_FIXED:
            return m_params.quick_exit_loss;  // e.g., -$10, -$20

         case QE_PERCENTAGE:
           {
            double current_dd = GetFloatingPnL();
            return current_dd * m_params.quick_exit_percentage;  // e.g., 30% of -$200 = -$60
           }

         case QE_DYNAMIC:
           {
            double dd_percent = GetDDPercent();
            if(dd_percent < -30.0) return -30.0;
            else if(dd_percent < -20.0) return -20.0;
            else return -10.0;
           }
        }

      return m_params.quick_exit_loss;
     }

   //+------------------------------------------------------------------+
   //| Deactivate quick exit mode                                       |
   //+------------------------------------------------------------------+
   void DeactivateQuickExitMode()
     {
      if(!m_quick_exit_mode) return;

      Print("🔄 Quick exit mode deactivated for ", DirectionLabel());

      m_quick_exit_mode = false;
      m_params.target_cycle_usd = m_original_target;
      m_basket_state = GRID_STATE_ACTIVE;

      // Recalculate TP with original target
      CalculateGroupTP();

      if(m_log)
         m_log.Event(Tag(), "QUICK_EXIT_MODE_OFF");
     }

   //+------------------------------------------------------------------+
   //| Calculate gap size between positions                             |
   //+------------------------------------------------------------------+
   double CalculateGapSize()
     {
      if(GetPositionCount() < 2) return 0;

      double max_gap = 0;
      double prev_price = 0;

      // Find largest gap between consecutive positions
      for(int i = 0; i < ArraySize(m_levels); i++)
        {
         if(!m_levels[i].filled) continue;

         if(prev_price != 0)
           {
            double gap = MathAbs(m_levels[i].price - prev_price) / _Point;
            if(gap > max_gap)
               max_gap = gap;
           }
         prev_price = m_levels[i].price;
        }

      m_last_gap_size = max_gap;
      m_last_gap_check = TimeCurrent();

      // Update trap detector if exists
      if(m_trap_detector)
         m_trap_detector.SetGapSize(max_gap);

      return max_gap;
     }

   //+------------------------------------------------------------------+
   //| Supporting method implementations                                |
   //+------------------------------------------------------------------+
   void CheckQuickExitTP()
     {
      if(!m_quick_exit_mode) return;

      double current_pnl = GetFloatingPnL();

      // Check if reached target
      if(current_pnl >= m_quick_exit_target)
        {
         Print("✅ QUICK EXIT TARGET REACHED! Target: $", m_quick_exit_target, " Actual: $", current_pnl);
         CloseBasket("QUICK_EXIT_SUCCESS");
         DeactivateQuickExitMode();

         if(m_params.quick_exit_reseed)
           {
            Print("🔄 Reseeding after quick exit...");
            // Will be handled by lifecycle controller
           }
         return;
        }

      // Check timeout
      int duration = (int)(TimeCurrent() - m_quick_exit_start_time);
      if(duration > m_params.quick_exit_timeout_min * 60)
        {
         Print("⏰ Quick exit timeout - Deactivate");
         DeactivateQuickExitMode();
        }
     }

   void FillBridgeLevels()
     {
      // Placeholder for bridge level filling
      // Will be implemented in Phase 2
     }

   void CloseFarPositions()
     {
      double current_price = (m_direction == DIR_BUY) ?
                            SymbolInfoDouble(m_symbol, SYMBOL_BID) :
                            SymbolInfoDouble(m_symbol, SYMBOL_ASK);

      double threshold = m_params.max_position_distance;
      int closed_count = 0;

      Print("✂️ Closing far positions (>", threshold, " pips)");

      // Simplified - close positions tracked in levels array
      for(int i = 0; i < ArraySize(m_levels); i++)
        {
         if(!m_levels[i].filled) continue;

         double distance = MathAbs(current_price - m_levels[i].price) / _Point;

         if(distance > threshold)
           {
            Print("  ├─ Close L", i, " @ ", m_levels[i].price);
            if(m_executor.ClosePositionByMagic(m_magic, m_levels[i].ticket))
              {
               m_levels[i].filled = false;
               m_levels[i].ticket = 0;
               closed_count++;
              }
           }
        }

      if(closed_count > 0)
        {
         Print("  └─ Total closed: ", closed_count, " positions");
         RefreshState();
        }
     }

   void HandleTrapDetected()
     {
      ActivateQuickExitMode();
     }

   bool CheckTrapConditions()
     {
      if(!m_trap_detector) return false;

      // Update metrics
      m_trap_detector.UpdateMetrics(m_avg_price, m_pnl_usd, m_total_lot,
                                   GetPositionCount(), GetOldestPositionTime());

      // Detect trap
      bool is_trapped = m_trap_detector.DetectTrapConditions();

      if(is_trapped && m_basket_state != GRID_STATE_QUICK_EXIT)
        {
         HandleTrapDetected();
        }

      return is_trapped;
     }

   void ReseedBasket()
     {
      Print("🔄 Reseeding ", DirectionLabel(), " basket");
      ClearLevels();
      m_grid_state.Reset();
      m_basket_state = GRID_STATE_RESEEDING;
      m_quick_exit_mode = false;

      double anchor = (m_direction == DIR_BUY) ?
                     SymbolInfoDouble(m_symbol, SYMBOL_ASK) :
                     SymbolInfoDouble(m_symbol, SYMBOL_BID);

      if(Init(anchor))
        {
         m_basket_state = GRID_STATE_ACTIVE;
         Print("✅ ", DirectionLabel(), " basket reseeded");
        }
     }

   int GetPositionCount() const
     {
      return GetFilledLevels();
     }

   double GetDDPercent() const
     {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance == 0) return 0;
      return (m_pnl_usd / balance) * 100;
     }

   datetime GetOldestPositionTime() const
     {
      // Simplified - return time estimate
      return TimeCurrent() - 3600;
     }

   double GetLevelPrice(int level) const
     {
      if(level >= 0 && level < ArraySize(m_levels))
         return m_levels[level].price;
      return 0;
     }
  };

#endif // __RGD_V2_GRID_BASKET_MQH__
