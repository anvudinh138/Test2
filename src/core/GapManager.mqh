//+------------------------------------------------------------------+
//| Project: Recovery Grid Direction v3.1                            |
//| Purpose: Gap Management - Bridge positions in large gaps         |
//| Phase 9: Gap Management v1 (Calculate + Bridge 200-400 pips)    |
//+------------------------------------------------------------------+
#ifndef __RGD_V3_GAP_MANAGER_MQH__
#define __RGD_V3_GAP_MANAGER_MQH__

#include "Types.mqh"
#include "Params.mqh"
#include "Logger.mqh"
#include "OrderExecutor.mqh"

// Forward declaration
class CGridBasket;

//+------------------------------------------------------------------+
//| Gap Manager Class                                                |
//+------------------------------------------------------------------+
class CGapManager
  {
private:
   CGridBasket   *m_basket;          // Parent basket reference
   COrderExecutor *m_executor;       // Order executor
   CLogger       *m_log;             // Logger
   string         m_symbol;          // Trading symbol
   long           m_magic;           // Magic number
   SParams        m_params;          // Strategy parameters

   datetime       m_last_bridge_time; // Last bridge placement time
   int            m_bridges_placed;   // Total bridges placed this cycle

   //+------------------------------------------------------------------+
   //| Helper: Get tag for logging                                      |
   //+------------------------------------------------------------------+
   string         Tag() const
     {
      return StringFormat("[GapMgr][%s]", m_symbol);
     }

   //+------------------------------------------------------------------+
   //| Helper: Convert price to pips                                    |
   //+------------------------------------------------------------------+
   double         PriceToPips(const double price_diff) const
     {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

      double pips = MathAbs(price_diff) / point;

      // Handle 3/5 digit brokers
      if(digits == 3 || digits == 5)
         pips /= 10.0;

      return pips;
     }

   //+------------------------------------------------------------------+
   //| Helper: Convert pips to price                                    |
   //+------------------------------------------------------------------+
   double         PipsToPrice(const double pips) const
     {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);

      double price = pips * point;

      // Handle 3/5 digit brokers
      if(digits == 3 || digits == 5)
         price *= 10.0;

      return price;
     }

   //+------------------------------------------------------------------+
   //| Find gap boundaries (two furthest positions)                     |
   //+------------------------------------------------------------------+
   bool           FindGapBoundaries(double &price_low, double &price_high)
     {
      // Get all position prices from basket
      double prices[];
      int count = 0;

      // Iterate through basket positions
      int total = (int)PositionsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;

         ArrayResize(prices, count + 1);
         prices[count] = PositionGetDouble(POSITION_PRICE_OPEN);
         count++;
        }

      if(count < 2)
         return false;  // Need at least 2 positions

      // Sort prices
      ArraySort(prices);

      // Find largest gap
      double max_gap = 0.0;
      int gap_start = -1;

      for(int i = 0; i < count - 1; i++)
        {
         double gap = MathAbs(prices[i+1] - prices[i]);
         if(gap > max_gap)
           {
            max_gap = gap;
            gap_start = i;
           }
        }

      if(gap_start >= 0)
        {
         price_low = MathMin(prices[gap_start], prices[gap_start + 1]);
         price_high = MathMax(prices[gap_start], prices[gap_start + 1]);
         return true;
        }

      return false;
     }

   //+------------------------------------------------------------------+
   //| Validate bridge price is reasonable                              |
   //+------------------------------------------------------------------+
   bool           IsPriceReasonable(const double price, const EDirection direction)
     {
      double current = SymbolInfoDouble(m_symbol,
                      (direction == DIR_BUY) ? SYMBOL_ASK : SYMBOL_BID);

      // BUY: bridge must be BELOW current (limit order)
      if(direction == DIR_BUY && price >= current)
         return false;

      // SELL: bridge must be ABOVE current (limit order)
      if(direction == DIR_SELL && price <= current)
         return false;

      return true;
     }

   //+------------------------------------------------------------------+
   //| Calculate bridge lot size (scaled appropriately)                 |
   //+------------------------------------------------------------------+
   double         CalculateBridgeLot(const int bridge_index)
     {
      // Use base lot for bridge positions (can adjust strategy here)
      // For now: use base lot (conservative approach)
      double lot = m_params.lot_base;

      // Alternative: could scale by bridge index
      // lot = m_params.lot_base * MathPow(m_params.lot_scale, bridge_index);

      // Validate lot size
      double min_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double max_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double step_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

      if(lot < min_lot)
         lot = min_lot;
      if(lot > max_lot)
         lot = max_lot;

      // Round to step
      if(step_lot > 0.0)
         lot = MathRound(lot / step_lot) * step_lot;

      return lot;
     }

   //+------------------------------------------------------------------+
   //| Place one bridge order                                           |
   //+------------------------------------------------------------------+
   ulong          PlaceBridgeOrder(const EDirection direction, const double price, const double lot)
     {
      if(m_executor == NULL)
         return 0;

      m_executor.SetMagic(m_magic);

      ulong ticket = 0;
      if(direction == DIR_BUY)
         ticket = m_executor.Limit(DIR_BUY, price, lot, "RGDv3_Bridge");
      else
         ticket = m_executor.Limit(DIR_SELL, price, lot, "RGDv3_Bridge");

      return ticket;
     }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CGapManager(CGridBasket *basket,
               COrderExecutor *executor,
               CLogger *logger,
               const string symbol,
               const long magic,
               const SParams &params)
              : m_basket(basket),
                m_executor(executor),
                m_log(logger),
                m_symbol(symbol),
                m_magic(magic),
                m_params(params),
                m_last_bridge_time(0),
                m_bridges_placed(0)
     {
     }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
                    ~CGapManager()
     {
      // Nothing to cleanup
     }

   //+------------------------------------------------------------------+
   //| Calculate gap size (uses basket method)                          |
   //+------------------------------------------------------------------+
   double         CalculateGapSize()
     {
      if(m_basket == NULL)
         return 0.0;

      // Delegate to basket's CalculateGapSize() method
      return m_basket.CalculateGapSize();
     }

   //+------------------------------------------------------------------+
   //| Main: Fill bridge positions (auto-adaptive range)                |
   //+------------------------------------------------------------------+
   void           FillBridge(const double gap_size, const EDirection direction)
     {
      // Guard 1: Feature disabled
      if(!m_params.auto_fill_bridge)
         return;

      // Guard 2: Calculate auto-adaptive gap range
      double current_spacing = (m_basket != NULL) ? m_basket.GetCurrentSpacing() : m_params.spacing_pips;
      if(current_spacing <= 0)
         current_spacing = m_params.spacing_pips; // Fallback

      double gap_min = current_spacing * m_params.gap_bridge_min_multiplier; // e.g., 25 × 8 = 200 pips
      double gap_max = current_spacing * m_params.gap_bridge_max_multiplier; // e.g., 25 × 16 = 400 pips

      // Guard 3: Gap out of range
      if(gap_size < gap_min || gap_size > gap_max)
        {
         // Silent return - gap is either too small or too large
         return;
        }

      // Guard 4: Cooldown (prevent rapid re-bridging)
      datetime now = TimeCurrent();
      if(now - m_last_bridge_time < 300)  // 5-minute cooldown
        {
         // Silent return - still in cooldown
         return;
        }

      // Find gap boundaries
      double price_low, price_high;
      if(!FindGapBoundaries(price_low, price_high))
        {
         if(m_log != NULL)
            m_log.Warn(Tag(), "FillBridge: Could not find gap boundaries");
         return;
        }

      // Calculate number of bridge levels
      double gap_distance_pips = PriceToPips(price_high - price_low);
      double spacing_pips = (m_params.spacing_mode == SPACING_PIPS) ? m_params.spacing_pips : 60.0;  // default 60 pips
      int num_bridges = (int)(gap_distance_pips / spacing_pips);

      // Cap at max bridge levels
      if(num_bridges > m_params.max_bridge_levels)
         num_bridges = m_params.max_bridge_levels;

      if(num_bridges < 1)
        {
         // Not enough space for even one bridge
         return;
        }

      if(m_log != NULL)
         m_log.Event(Tag(), StringFormat("BRIDGE: Gap detected %.1f pips (range: %.1f-%.1f), placing %d bridge levels",
                                         gap_size, gap_min, gap_max, num_bridges));

      // Place bridge orders
      int placed = 0;
      for(int i = 1; i <= num_bridges; i++)
        {
         // Calculate bridge price (evenly distributed between gap boundaries)
         double bridge_price = price_low + (price_high - price_low) * i / (num_bridges + 1);

         // Validate price
         if(!IsPriceReasonable(bridge_price, direction))
           {
            if(m_log != NULL)
               m_log.Warn(Tag(), StringFormat("BRIDGE: Price %.5f on wrong side of market, skipping", bridge_price));
            continue;
           }

         // Calculate lot
         double bridge_lot = CalculateBridgeLot(i);
         if(bridge_lot <= 0.0)
            continue;

         // Place order
         ulong ticket = PlaceBridgeOrder(direction, bridge_price, bridge_lot);
         if(ticket > 0)
           {
            placed++;
            int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
            if(m_log != NULL)
               m_log.Event(Tag(), StringFormat("BRIDGE: Placed level %d/%d at %.*f (lot %.2f) ticket #%I64u",
                                              i, num_bridges, digits, bridge_price, bridge_lot, ticket));
           }
         else
           {
            if(m_log != NULL)
               m_log.Warn(Tag(), StringFormat("BRIDGE: Failed to place level %d at %.5f", i, bridge_price));
           }
        }

      // Update state
      m_last_bridge_time = now;
      m_bridges_placed += placed;

      if(m_log != NULL)
         m_log.Event(Tag(), StringFormat("BRIDGE: Completed - %d/%d levels placed successfully",
                                        placed, num_bridges));
     }

   //+------------------------------------------------------------------+
   //| Phase 10: Calculate far positions loss                           |
   //+------------------------------------------------------------------+
   double         CalculateFarPositionsLoss(const EDirection direction)
     {
      if(m_basket == NULL)
         return 0.0;

      double avg_price = m_basket.AveragePrice();
      if(avg_price <= 0.0)
         return 0.0;

      double current_spacing = m_basket.GetCurrentSpacing();
      if(current_spacing <= 0)
         current_spacing = m_params.spacing_pips;

      double far_distance_pips = current_spacing * m_params.gap_close_far_distance;
      double far_distance_px = PipsToPrice(far_distance_pips);

      double total_loss = 0.0;
      int far_count = 0;

      int total = (int)PositionsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;

         double pos_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double distance = MathAbs(pos_price - avg_price);

         if(distance > far_distance_px)
           {
            double profit = PositionGetDouble(POSITION_PROFIT);
            total_loss += profit;  // profit is negative for loss
            far_count++;
           }
        }

      if(m_log != NULL && far_count > 0)
         m_log.Event(Tag(), StringFormat("ℹ️  CloseFar: Found %d far positions (>%.1f pips from avg), potential loss: $%.2f",
                                        far_count, far_distance_pips, total_loss));

      return total_loss;
     }

   //+------------------------------------------------------------------+
   //| Phase 10: Check if position is "far" from average                |
   //+------------------------------------------------------------------+
   bool           IsFarPosition(ulong ticket, double avg_price, double far_distance_px)
     {
      if(!PositionSelectByTicket(ticket))
         return false;

      double pos_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double distance = MathAbs(pos_price - avg_price);

      return (distance > far_distance_px);
     }

   //+------------------------------------------------------------------+
   //| Phase 10: Manage large gaps (>threshold) - close far + reseed    |
   //+------------------------------------------------------------------+
   void           ManageLargeGap(const double gap_size, const EDirection direction)
     {
      // Guard 1: Feature disabled
      if(!m_params.gap_close_far_enabled)
         return;

      // Guard 2: Calculate auto-adaptive threshold
      double current_spacing = (m_basket != NULL) ? m_basket.GetCurrentSpacing() : m_params.spacing_pips;
      if(current_spacing <= 0)
         current_spacing = m_params.spacing_pips;

      double close_far_threshold = current_spacing * m_params.gap_close_far_multiplier;

      // Guard 3: Gap not large enough
      if(gap_size <= close_far_threshold)
        {
         // Silent return - gap not large enough for close-far
         return;
        }

      if(m_log != NULL)
         m_log.Event(Tag(), StringFormat("⚠️  LARGE GAP detected: %.1f pips (threshold: %.1f pips)",
                                        gap_size, close_far_threshold));

      // Calculate loss from far positions
      double far_loss = CalculateFarPositionsLoss(direction);

      // Guard 4: Loss validation
      if(far_loss < m_params.max_acceptable_loss)
        {
         if(m_log != NULL)
            m_log.Warn(Tag(), StringFormat("❌ CloseFar SKIPPED: Far loss $%.2f < max acceptable $%.2f",
                                          far_loss, m_params.max_acceptable_loss));
         return;
        }

      if(m_log != NULL)
         m_log.Event(Tag(), StringFormat("✅ CloseFar: Loss $%.2f acceptable (max: $%.2f) → Closing far positions",
                                        far_loss, m_params.max_acceptable_loss));

      // Close far positions
      double avg_price = m_basket.AveragePrice();
      double far_distance_pips = current_spacing * m_params.gap_close_far_distance;
      double far_distance_px = PipsToPrice(far_distance_pips);

      int closed_count = 0;
      double actual_loss = 0.0;

      int total = (int)PositionsTotal();
      for(int i = total - 1; i >= 0; i--)  // Iterate backwards to avoid index issues
        {
         ulong t = PositionGetTicket(i);
         if(t == 0)
            continue;
         if(!PositionSelectByTicket(t))
            continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)
            continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magic)
            continue;

         if(IsFarPosition(t, avg_price, far_distance_px))
           {
            double pos_price = PositionGetDouble(POSITION_PRICE_OPEN);
            double pos_profit = PositionGetDouble(POSITION_PROFIT);
            double distance_pips = PriceToPips(MathAbs(pos_price - avg_price));

            // Close position
            if(m_executor != NULL)
              {
               m_executor.SetMagic(m_magic);
               if(m_executor.ClosePosition(t, "CloseFar_LargeGap"))
                 {
                  closed_count++;
                  actual_loss += pos_profit;

                  int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
                  if(m_log != NULL)
                     m_log.Event(Tag(), StringFormat("   🗑️  Closed far position #%I64u at %.*f (%.1f pips from avg, loss: $%.2f)",
                                                    t, digits, pos_price, distance_pips, pos_profit));
                 }
              }
           }
        }

      if(m_log != NULL)
         m_log.Event(Tag(), StringFormat("✅ CloseFar COMPLETED: Closed %d far positions (total loss: $%.2f)",
                                        closed_count, actual_loss));

      // Check if reseed needed (basket auto-refreshes internally)
      if(m_basket != NULL && closed_count > 0)
        {
         // Get current filled levels (basket has already refreshed)
         int remaining = m_basket.GetFilledLevels();
         if(m_log != NULL)
            m_log.Event(Tag(), StringFormat("   📊 Remaining positions: %d (min before reseed: %d)",
                                           remaining, m_params.min_positions_before_reseed));

         if(remaining < m_params.min_positions_before_reseed)
           {
            if(m_log != NULL)
               m_log.Event(Tag(), StringFormat("   🔄 RESEED triggered: %d positions < %d minimum",
                                              remaining, m_params.min_positions_before_reseed));
            m_basket.Reseed();

            // Reset gap manager state
            Reset();
           }
        }
     }

   //+------------------------------------------------------------------+
   //| Update: Check gaps and manage bridges/close-far                  |
   //+------------------------------------------------------------------+
   void           Update(const EDirection direction)
     {
      // Calculate current gap size
      double gap_size = CalculateGapSize();

      // ⚠️ DEBUG: Log gap size even if zero (critical for troubleshooting)
      static datetime last_debug = 0;
      datetime now_debug = TimeCurrent();
      if(now_debug - last_debug > 600)  // Every 10 minutes
        {
         int filled = (m_basket != NULL) ? m_basket.GetFilledLevels() : 0;
         if(m_log != NULL)
            m_log.Event(Tag(), StringFormat("🔍 DEBUG: Gap=%.1f pips, Filled=%d positions",
                                           gap_size, filled));
         last_debug = now_debug;
        }

      if(gap_size <= 0.0)
         return;  // No gap

      // Calculate adaptive thresholds
      double current_spacing = (m_basket != NULL) ? m_basket.GetCurrentSpacing() : m_params.spacing_pips;
      if(current_spacing <= 0)
         current_spacing = m_params.spacing_pips;

      double bridge_max = current_spacing * m_params.gap_bridge_max_multiplier;
      double close_far_threshold = current_spacing * m_params.gap_close_far_multiplier;

      // Log gap detection (every 5 minutes to avoid spam)
      static datetime last_log = 0;
      datetime now = TimeCurrent();
      if(now - last_log > 300 && gap_size > bridge_max)
        {
         if(m_log != NULL)
            m_log.Event(Tag(), StringFormat("📏 Gap detected: %.1f pips (bridge max: %.1f, close-far threshold: %.1f)",
                                           gap_size, bridge_max, close_far_threshold));
         last_log = now;
        }

      // Phase 10: Handle large gaps (>threshold)
      if(gap_size > close_far_threshold && m_params.gap_close_far_enabled)
        {
         ManageLargeGap(gap_size, direction);
        }
      // Phase 9: Handle medium gaps (bridge range)
      else if(m_params.auto_fill_bridge)
        {
         FillBridge(gap_size, direction);
        }
     }

   //+------------------------------------------------------------------+
   //| Reset stats (call when basket reseeds)                           |
   //+------------------------------------------------------------------+
   void           Reset()
     {
      m_last_bridge_time = 0;
      m_bridges_placed = 0;
     }

   //+------------------------------------------------------------------+
   //| Get stats                                                         |
   //+------------------------------------------------------------------+
   int            GetBridgesPlaced() const { return m_bridges_placed; }
  };

#endif // __RGD_V3_GAP_MANAGER_MQH__
