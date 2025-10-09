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

// Forward declarations
class CTrapDetector;
class CTrendFilter;

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
   
   // lazy grid state (v3.1 - Phase 3)
   SGridState     m_grid_state;
   
   // trap detector (v3.1 - Phase 5)
   CTrapDetector *m_trap_detector;
   
   // quick exit mode (v3.1 - Phase 7)
   bool           m_quick_exit_active;
   double         m_quick_exit_target;
   double         m_original_target;
   datetime       m_quick_exit_start_time;

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
      
      // Pre-allocate array for lazy grid (filled dynamically)
      if(m_params.lazy_grid_enabled)
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
         // Old static grid behavior: build all levels upfront
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

   //+------------------------------------------------------------------+
   //| Lazy Grid v1: Seed minimal grid (1 market + 1 pending)          |
   //| Phase 3 - Only called when InpLazyGridEnabled=true              |
   //+------------------------------------------------------------------+
   void           SeedInitialGrid()
     {
      m_executor.SetMagic(m_magic);
      m_executor.BypassNext(2);  // Bypass cooldown for 2 orders
      
      double spacing_px=m_spacing.ToPrice(m_initial_spacing_pips);
      double anchor=SymbolInfoDouble(m_symbol,(m_direction==DIR_BUY)?SYMBOL_ASK:SYMBOL_BID);
      
      m_levels_placed=0;
      m_pending_count=0;
      m_last_grid_price=0.0;
      m_grid_state.Reset();  // Reset lazy grid state
      
      // 1. Place market seed (level 0)
      double seed_lot=LevelLot(0);
      if(seed_lot<=0.0)
         return;
         
      ulong market_ticket=m_executor.Market(m_direction,seed_lot,"RGDv2_LazySeed");
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
      
      // 2. Place ONE pending order (level 1)
      double price=anchor;
      if(m_direction==DIR_BUY)
         price-=spacing_px;
      else
         price+=spacing_px;
         
      double lot=LevelLot(1);
      ulong pending=(m_direction==DIR_BUY)?m_executor.Limit(DIR_BUY,price,lot,"RGDv2_LazyGrid")
                                          :m_executor.Limit(DIR_SELL,price,lot,"RGDv2_LazyGrid");
      if(pending>0)
        {
         m_levels[1].price=price;
         m_levels[1].lot=lot;
         m_levels[1].ticket=pending;
         m_levels[1].filled=false;
         m_levels_placed++;
         m_pending_count++;
         m_last_grid_price=price;
         LogDynamic("SEED",1,price);
        }
      
      // Update lazy grid state
      m_grid_state.currentMaxLevel=1;
      m_grid_state.pendingCount=m_pending_count;
      m_grid_state.lastFilledLevel=0;  // No fills yet, will expand when level 0 fills
      
      if(m_log!=NULL)
         m_log.Event(Tag(),StringFormat("Initial grid seeded (lazy) levels=%d pending=%d",
                                        m_levels_placed,m_pending_count));
     }

   //+------------------------------------------------------------------+
   //| Phase 4: Smart Expansion Helpers                                 |
   //+------------------------------------------------------------------+
   
   //--- Calculate next level price
   double         CalculateNextLevelPrice()
     {
      int next_level=m_grid_state.currentMaxLevel+1;
      double spacing_px=m_spacing.ToPrice(m_initial_spacing_pips);
      double anchor=m_levels[0].price;
      
      if(m_direction==DIR_BUY)
         return anchor-(spacing_px*next_level);
      else
         return anchor+(spacing_px*next_level);
     }
   
   //--- Convert price difference to pips
   double         PriceToDistance(const double price1,const double price2)
     {
      double diff=MathAbs(price1-price2);
      double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      int digits=(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
      
      // For 3/5 digit brokers, divide by 10
      if(digits==3 || digits==5)
         return diff/point/10.0;
      else
         return diff/point;
     }
   
   //--- Validate price is on correct side of market
   bool           IsPriceReasonable(const double price)
     {
      double current=SymbolInfoDouble(m_symbol,
                     (m_direction==DIR_BUY)?SYMBOL_ASK:SYMBOL_BID);
      
      // BUY: pending must be BELOW current
      if(m_direction==DIR_BUY && price>=current)
         return false;
      
      // SELL: pending must be ABOVE current
      if(m_direction==DIR_SELL && price<=current)
         return false;
      
      return true;
     }
   
   //--- Check if grid should expand (all guards)
   bool           ShouldExpandGrid()
     {
      // Guard 0: New level filled? (Phase 4 KEY: Only expand on fill!)
      int current_filled=GetFilledLevels();
      if(current_filled<=m_grid_state.lastFilledLevel)
        {
         // No new fills since last expansion - silent return
         return false;
        }
      
      // Guard 1: Max levels reached?
      if(m_grid_state.currentMaxLevel>=m_max_levels-1)
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),"Expansion blocked: GRID_FULL");
         return false;
        }
      
      // Guard 2: DD too deep?
      if(m_total_lot>0.0)
        {
         double account_balance=AccountInfoDouble(ACCOUNT_BALANCE);
         if(account_balance>0.0)
           {
            double dd_pct=(m_pnl_usd/account_balance)*100.0;
            if(dd_pct<m_params.max_dd_for_expansion)
              {
               if(m_log!=NULL)
                  m_log.Event(Tag(),StringFormat("Expansion blocked: DD too deep %.2f%% < %.2f%%",
                                                 dd_pct,m_params.max_dd_for_expansion));
               return false;
              }
           }
        }
      
      // Guard 3: Distance too far?
      double next_price=CalculateNextLevelPrice();
      double distance_pips=PriceToDistance(next_price,m_levels[0].price);
      if(distance_pips>m_params.max_level_distance)
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),StringFormat("Expansion blocked: Distance %.1f pips > %.1f max",
                                          distance_pips,m_params.max_level_distance));
         return false;
        }
      
      // Guard 4: Price reasonable?
      if(!IsPriceReasonable(next_price))
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),"Expansion blocked: Price on wrong side of market");
         return false;
        }
      
      return true;
     }
   
   //--- Expand grid by one level
   void           ExpandOneLevel()
     {
      int next_level=m_grid_state.currentMaxLevel+1;
      
      double spacing_px=m_spacing.ToPrice(m_initial_spacing_pips);
      double anchor=m_levels[0].price;
      
      double price=anchor;
      if(m_direction==DIR_BUY)
         price-=(spacing_px*next_level);
      else
         price+=(spacing_px*next_level);
      
      double lot=LevelLot(next_level);
      if(lot<=0.0)
         return;
      
      m_executor.SetMagic(m_magic);
      ulong ticket=(m_direction==DIR_BUY)
                  ?m_executor.Limit(DIR_BUY,price,lot,"RGDv2_LazyExpand")
                  :m_executor.Limit(DIR_SELL,price,lot,"RGDv2_LazyExpand");
      
      if(ticket>0)
        {
         m_levels[next_level].price=price;
         m_levels[next_level].lot=lot;
         m_levels[next_level].ticket=ticket;
         m_levels[next_level].filled=false;
         
         m_levels_placed++;
         m_pending_count++;
         m_last_grid_price=price;
         
         m_grid_state.currentMaxLevel=next_level;
         m_grid_state.pendingCount=m_pending_count;
         // lastFilledLevel already updated in RefillBatch()
         
         LogDynamic("EXPAND",next_level,price);
         
         if(m_log!=NULL)
            m_log.Event(Tag(),StringFormat("Lazy grid expanded to level %d, pending=%d/%d (filled=%d)",
                                          next_level,m_pending_count,m_max_levels,m_grid_state.lastFilledLevel));
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
      
      // Phase 4: Use lazy grid if enabled
      if(m_params.lazy_grid_enabled)
        {
         SeedInitialGrid();
         return;
        }
      
      // Fallback: Static grid (place all levels at once)
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
         m_log.Event(Tag(),StringFormat("Static grid seeded levels=%d",ArraySize(m_levels)));
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
         
         // Update level filled status (Phase 4: Track fills for lazy grid)
         for(int j=0;j<ArraySize(m_levels);j++)
           {
            if(m_levels[j].ticket==ticket && !m_levels[j].filled)
              {
               m_levels[j].filled=true;
               break;
              }
           }
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
      double current_spacing_pips=(m_spacing!=NULL)?m_spacing.SpacingPips():m_params.spacing_pips;
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
      
      // Initialize trap detector pointer to NULL
      m_trap_detector=NULL;
      
      // Initialize quick exit state
      m_quick_exit_active=false;
      m_quick_exit_target=0.0;
      m_original_target=0.0;
      m_quick_exit_start_time=0;
     }
   
   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
                    ~CGridBasket()
     {
      // Cleanup trap detector
      if(m_trap_detector!=NULL)
        {
         delete m_trap_detector;
         m_trap_detector=NULL;
        }
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

      // Initialize trap detector (Phase 5)
      // Note: TrendFilter will be passed from LifecycleController (for now NULL)
      m_trap_detector=new CTrapDetector(GetPointer(this),
                                         NULL,  // TrendFilter reference (will be set later)
                                         m_log,
                                         m_params.trap_detection_enabled,
                                         m_params.trap_gap_threshold,
                                         m_params.trap_dd_threshold,
                                         m_params.trap_conditions_required,
                                         m_params.trap_stuck_minutes);

      return true;
     }

   //+------------------------------------------------------------------+
   //| Reseed basket with fresh grid (for Quick Exit auto-reseed)      |
   //+------------------------------------------------------------------+
   void           Reseed()
     {
      if(m_spacing==NULL)
         return;

      // Get current price for anchor
      double anchor_price=SymbolInfoDouble(m_symbol,(m_direction==DIR_BUY)?SYMBOL_ASK:SYMBOL_BID);

      // Clear old state
      ClearLevels();
      m_target_reduction=0.0;
      m_last_realized=0.0;

      // Rebuild grid and place orders
      double spacing_pips=m_spacing.SpacingPips();
      double spacing_px=m_spacing.ToPrice(spacing_pips);
      if(spacing_px>0.0)
        {
         m_initial_spacing_pips=spacing_pips;
         BuildGrid(anchor_price,spacing_px);
         PlaceInitialOrders();
         m_active=true;
         RefreshState();

         if(m_log!=NULL)
            m_log.Event(Tag(),StringFormat("[%s] Basket reseeded at %.5f",DirectionLabel(),anchor_price));
        }
     }

   //+------------------------------------------------------------------+
   //| Refill/Expand Grid (Lazy Grid Only)                              |
   //+------------------------------------------------------------------+
   void           RefillBatch()
     {
      // Only handle lazy grid expansion
      if(!m_params.lazy_grid_enabled)
         return;
      
      // Check if we should expand by one level
      int current_filled=GetFilledLevels();
      if(ShouldExpandGrid())
        {
         // Update lastFilledLevel BEFORE expansion
         m_grid_state.lastFilledLevel=current_filled;
         ExpandOneLevel();
        }
     }

   void           Update()
     {
      if(!m_active)
         return;
      m_closed_recently=false;
      RefreshState();
      
      // Phase 7: Check Quick Exit TP (highest priority - escape trap ASAP)
      if(CheckQuickExitTP())
        {
         return;  // Quick exit closed basket, skip other checks
        }
      
      // Phase 5: Check for new trap conditions (detect traps before they worsen)
      CheckTrapConditions();

      // Basket Stop Loss check (spacing-based)
      if(m_params.basket_sl_enabled && CheckBasketSL())
        {
         CloseBasket("BasketSL");
         return;  // Exit early after SL closure
        }

      // Lazy grid expansion
      if(m_params.lazy_grid_enabled)
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
         RefillBatch();  // Calls ExpandOneLevel() if guards pass
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
   //| Phase 5: Trap Detection Helper Methods                           |
   //+------------------------------------------------------------------+
   
   //+------------------------------------------------------------------+
   //| Calculate gap size between filled positions                      |
   //+------------------------------------------------------------------+
   double         CalculateGapSize() const
     {
      // Find all filled positions
      double prices[];
      int count=0;
      
      for(int i=0;i<ArraySize(m_levels);i++)
        {
         if(m_levels[i].filled && m_levels[i].ticket>0)
           {
            ArrayResize(prices,count+1);
            prices[count]=m_levels[i].price;
            count++;
           }
        }
      
      if(count<2)
         return 0.0;  // Need at least 2 positions
      
      // Sort prices
      ArraySort(prices);
      
      // Find largest gap between consecutive positions
      double max_gap=0.0;
      double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      int digits=(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
      
      for(int i=0;i<count-1;i++)
        {
         double gap=MathAbs(prices[i+1]-prices[i])/point;
         
         // Convert to pips (handle 3/5 digit brokers)
         if(digits==3 || digits==5)
            gap/=10.0;
         
         if(gap>max_gap)
            max_gap=gap;
        }
      
      return max_gap;
     }
   
   //+------------------------------------------------------------------+
   //| Get DD percent (for trap detection)                              |
   //+------------------------------------------------------------------+
   double         GetDDPercent() const
     {
      double balance=AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance<=0.0)
         return 0.0;
      
      return (m_pnl_usd/balance)*100.0;
     }
   
   //+------------------------------------------------------------------+
   //| Get basket direction (for trap detection)                        |
   //+------------------------------------------------------------------+
   EDirection     GetDirection() const
     {
      return m_direction;
     }
   
   //+------------------------------------------------------------------+
   //| Handle trap detected (Phase 7: activate Quick Exit once only)    |
   //+------------------------------------------------------------------+
   void           HandleTrapDetected()
     {
      if(m_trap_detector==NULL)
         return;
      
      // Only activate Quick Exit if not already active (prevent spam)
      if(m_quick_exit_active)
         return;
      
      STrapState trap_state=m_trap_detector.GetTrapState();
      
      // Log trap detection ONCE
      if(m_log!=NULL)
        {
         m_log.Event(Tag(),"🚨 TRAP DETECTED!");
         m_log.Event(Tag(),StringFormat("   Gap: %.1f pips",trap_state.gapSize));
         m_log.Event(Tag(),StringFormat("   DD: %.2f%%",trap_state.ddAtDetection));
         m_log.Event(Tag(),StringFormat("   Conditions: %d/5",trap_state.conditionsMet));
        }
      
      // Phase 7: Activate Quick Exit Mode to escape trap (once only)
      ActivateQuickExitMode();
     }
   
   //+------------------------------------------------------------------+
   //| Check for trap conditions (call from LifecycleController)        |
   //+------------------------------------------------------------------+
   void           CheckTrapConditions()
     {
      if(m_trap_detector==NULL || !m_trap_detector.IsEnabled())
         return;
      
      if(!m_active)
         return;
      
      if(m_trap_detector.DetectTrapConditions())
        {
         HandleTrapDetected();
        }
     }
   
   //+------------------------------------------------------------------+
   //| Set trend filter reference (called from LifecycleController)     |
   //+------------------------------------------------------------------+
   void           SetTrendFilter(CTrendFilter *trend_filter)
     {
      // Will be implemented when needed
      // For now, trap detector works without trend filter
     }
   
   //+------------------------------------------------------------------+
   //| Phase 7: Activate Quick Exit Mode                                |
   //+------------------------------------------------------------------+
   void           ActivateQuickExitMode()
     {
      if(!m_params.quick_exit_enabled)
         return;
      
      if(m_quick_exit_active)
        {
         // Already active - silently ignore to prevent log spam
         return;
        }
      
      m_original_target = m_params.target_cycle_usd;
      m_quick_exit_target = CalculateQuickExitTarget();
      m_quick_exit_active = true;
      m_quick_exit_start_time = TimeCurrent();
      
      if(m_log!=NULL)
         m_log.Event(Tag(),StringFormat("[%s] Quick Exit ACTIVATED | Original Target: $%.2f → New Target: $%.2f (Accept loss: $%.2f)",
                                        DirectionLabel(),m_original_target,m_quick_exit_target,m_quick_exit_target));
     }
   
   //+------------------------------------------------------------------+
   //| Phase 7: Calculate Quick Exit Target (negative target = accept loss)|
   //+------------------------------------------------------------------+
   double         CalculateQuickExitTarget()
     {
      double current_pnl = m_pnl_usd;
      double target = 0.0;
      
      switch(m_params.quick_exit_mode)
        {
         case QE_FIXED:
            // Accept a fixed loss amount
            target = -m_params.quick_exit_loss;
            break;
         
         case QE_PERCENTAGE:
            // Accept X% of current DD
            // Example: DD = -$100, percentage = 30% → target = -$30 (accept $30 loss to escape)
            if(current_pnl < 0)
               target = current_pnl * (m_params.quick_exit_percentage / 100.0);
            else
               target = -m_params.quick_exit_loss; // fallback to fixed
            break;
         
         case QE_DYNAMIC:
           {
            // Dynamic: choose smaller loss between fixed and percentage
            double percentage_loss = (current_pnl < 0) ? (current_pnl * m_params.quick_exit_percentage / 100.0) : 0.0;
            target = MathMax(-m_params.quick_exit_loss, percentage_loss); // choose less negative (smaller loss)
            break;
           }
        }
      
      // Debug log removed - too verbose
      return target;
     }
   
   //+------------------------------------------------------------------+
   //| Phase 7: Check if Quick Exit TP reached                          |
   //+------------------------------------------------------------------+
   bool           CheckQuickExitTP()
     {
      if(!m_quick_exit_active)
         return false;
      
      // Timeout check
      if(m_params.quick_exit_timeout_min > 0)
        {
         int elapsed_minutes = (int)((TimeCurrent() - m_quick_exit_start_time) / 60);
         if(elapsed_minutes >= m_params.quick_exit_timeout_min)
           {
            if(m_log!=NULL)
               m_log.Warn(Tag(),StringFormat("[%s] Quick Exit TIMEOUT (%d minutes) - deactivating", 
                                             DirectionLabel(),elapsed_minutes));
            DeactivateQuickExitMode();
            return false;
           }
        }
      
      double current_pnl = m_pnl_usd;
      
      // Check if we've reached the quick exit target (negative target = accept small loss)
      // Example: target = -$20, current = -$18 → CLOSE! (loss reduced enough)
      if(current_pnl >= m_quick_exit_target)
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),StringFormat("[%s] 🎯 Quick Exit TARGET REACHED! PnL: $%.2f >= Target: $%.2f → CLOSING ALL",
                                           DirectionLabel(),current_pnl,m_quick_exit_target));
         
         // Close all positions in this basket
         CloseBasket("QuickExit");
         
         // Auto reseed if enabled
         if(m_params.quick_exit_reseed)
           {
            if(m_log!=NULL)
               m_log.Event(Tag(),StringFormat("[%s] Quick Exit: Auto-reseeding basket after escape",DirectionLabel()));
            Reseed();
           }
         
         DeactivateQuickExitMode();
         return true;
        }
      
      return false;
     }
   
   //+------------------------------------------------------------------+
   //| Phase 7: Deactivate Quick Exit Mode                              |
   //+------------------------------------------------------------------+
   void           DeactivateQuickExitMode()
     {
      if(!m_quick_exit_active)
         return;
      
      m_quick_exit_active = false;
      m_quick_exit_target = 0.0;
      m_quick_exit_start_time = 0;
      
      // Restore original target
      m_params.target_cycle_usd = m_original_target;
      
      // Debug log removed - deactivation happens silently after timeout or close
     }
  };

// Include TrapDetector after GridBasket definition (to resolve circular dependency)
#include "TrapDetector.mqh"

#endif // __RGD_V2_GRID_BASKET_MQH__
