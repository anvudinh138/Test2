//+------------------------------------------------------------------+
//| Project: Recovery Grid Direction v3                              |
//| Purpose: Smart trap detection module                             |
//+------------------------------------------------------------------+
#ifndef __RGD_V3_TRAP_DETECTOR_MQH__
#define __RGD_V3_TRAP_DETECTOR_MQH__

#include "Types.mqh"
#include "Params.mqh"
#include "TrendFilter.mqh"

//+------------------------------------------------------------------+
//| CTrapDetector Class                                              |
//| Detects when a basket is trapped and needs quick exit            |
//+------------------------------------------------------------------+
class CTrapDetector
  {
private:
   SParams              m_params;           // Strategy parameters (by value)
   CTrendFilter*        m_trend_filter;     // Reference to trend filter
   STrapState           m_trap_state;       // Current trap state

   // Direction tracking
   EDirection           m_direction;        // Basket direction

   // Price tracking for movement detection
   double               m_last_price;
   datetime             m_last_price_time;

   // Internal references (set by GridBasket)
   double               m_avg_price;
   double               m_current_pnl;
   double               m_total_volume;
   int                  m_position_count;
   datetime             m_oldest_position_time;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CTrapDetector(const SParams &params, CTrendFilter* trend_filter, EDirection dir)
     {
      m_params = params;
      m_trend_filter = trend_filter;
      m_direction = dir;
      m_last_price = 0;
      m_last_price_time = 0;
      m_trap_state.Reset();
     }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CTrapDetector() {}

   //+------------------------------------------------------------------+
   //| Update basket metrics (called by GridBasket)                     |
   //+------------------------------------------------------------------+
   void UpdateMetrics(double avg_price, double current_pnl, double total_volume,
                     int position_count, datetime oldest_time)
     {
      m_avg_price = avg_price;
      m_current_pnl = current_pnl;
      m_total_volume = total_volume;
      m_position_count = position_count;
      m_oldest_position_time = oldest_time;
     }

   //+------------------------------------------------------------------+
   //| Main trap detection logic                                        |
   //+------------------------------------------------------------------+
   bool DetectTrapConditions()
     {
      if(!m_params.trap_detection_enabled) return false;
      if(m_position_count == 0) return false;

      // Check all 5 conditions
      bool cond1 = CheckCondition_Gap();
      bool cond2 = CheckCondition_CounterTrend();
      bool cond3 = CheckCondition_HeavyDD();
      bool cond4 = CheckCondition_MovingAway();
      bool cond5 = CheckCondition_Stuck();

      // Count conditions met
      int count = 0;
      int flags = TRAP_COND_NONE;

      if(cond1) { count++; flags |= TRAP_COND_GAP; }
      if(cond2) { count++; flags |= TRAP_COND_COUNTER_TREND; }
      if(cond3) { count++; flags |= TRAP_COND_HEAVY_DD; }
      if(cond4) { count++; flags |= TRAP_COND_MOVING_AWAY; }
      if(cond5) { count++; flags |= TRAP_COND_STUCK; }

      bool is_trap = (count >= m_params.trap_conditions_required);

      if(is_trap && !m_trap_state.detected)
        {
         // New trap detected
         m_trap_state.detected = true;
         m_trap_state.detectedTime = TimeCurrent();
         m_trap_state.conditionsMet = count;
         m_trap_state.conditionFlags = flags;
         m_trap_state.gapSize = CalculateGapSize();
         m_trap_state.ddAtDetection = GetDDPercent();

         LogTrapDetection(cond1, cond2, cond3, cond4, cond5);
        }
      else if(!is_trap && m_trap_state.detected)
        {
         // Trap resolved
         Print("✅ Trap resolved for ", EnumToString(m_direction));
         m_trap_state.Reset();
        }

      return is_trap;
     }

   //+------------------------------------------------------------------+
   //| Check Condition: Large Gap                                       |
   //+------------------------------------------------------------------+
   bool CheckCondition_Gap()
     {
      double gap_size = CalculateGapSize();
      return (gap_size > m_params.trap_gap_threshold);
     }

   //+------------------------------------------------------------------+
   //| Check Condition: Counter Trend                                   |
   //+------------------------------------------------------------------+
   bool CheckCondition_CounterTrend()
     {
      if(CheckPointer(m_trend_filter) == POINTER_INVALID) return false;
      if(!m_trend_filter.IsEnabled()) return false;
      return m_trend_filter.IsCounterTrend(m_direction);
     }

   //+------------------------------------------------------------------+
   //| Check Condition: Heavy DD                                        |
   //+------------------------------------------------------------------+
   bool CheckCondition_HeavyDD()
     {
      double dd = GetDDPercent();
      return (dd < m_params.trap_dd_threshold);
     }

   //+------------------------------------------------------------------+
   //| Check Condition: Price Moving Away                               |
   //+------------------------------------------------------------------+
   bool CheckCondition_MovingAway()
     {
      double current_price = GetCurrentPrice();

      // Need at least 5 minutes of data
      if(TimeCurrent() - m_last_price_time < 300)
        {
         m_last_price = current_price;
         m_last_price_time = TimeCurrent();
         return false;
        }

      double last_distance = MathAbs(m_last_price - m_avg_price);
      double current_distance = MathAbs(current_price - m_avg_price);

      // Update tracking
      m_last_price = current_price;
      m_last_price_time = TimeCurrent();

      // Moving away if distance increased by >10%
      return (current_distance > last_distance * 1.1);
     }

   //+------------------------------------------------------------------+
   //| Check Condition: Stuck Too Long                                  |
   //+------------------------------------------------------------------+
   bool CheckCondition_Stuck()
     {
      if(m_position_count == 0) return false;

      int stuck_duration = (int)(TimeCurrent() - m_oldest_position_time);

      // Stuck > threshold AND still heavy DD
      return (stuck_duration > m_params.trap_stuck_minutes * 60 &&
              GetDDPercent() < -15.0);
     }

   //+------------------------------------------------------------------+
   //| Calculate gap size (placeholder - implemented in GridBasket)     |
   //+------------------------------------------------------------------+
   double CalculateGapSize()
     {
      // This will be properly implemented by calling GridBasket's method
      // For now, return a placeholder
      return 0.0;
     }

   //+------------------------------------------------------------------+
   //| Get DD Percentage                                                |
   //+------------------------------------------------------------------+
   double GetDDPercent()
     {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance == 0) return 0;
      return (m_current_pnl / balance) * 100;
     }

   //+------------------------------------------------------------------+
   //| Get current price based on direction                             |
   //+------------------------------------------------------------------+
   double GetCurrentPrice()
     {
      if(m_direction == DIR_BUY)
         return SymbolInfoDouble(_Symbol, SYMBOL_BID);
      else
         return SymbolInfoDouble(_Symbol, SYMBOL_ASK);
     }

   //+------------------------------------------------------------------+
   //| Log trap detection details                                       |
   //+------------------------------------------------------------------+
   void LogTrapDetection(bool c1, bool c2, bool c3, bool c4, bool c5)
     {
      Print("🚨 TRAP DETECTED for ", EnumToString(m_direction));
      Print("   Conditions met: ", m_trap_state.conditionsMet, "/5");
      Print("   [", (c1 ? "✓" : "✗"), "] Gap: ", m_trap_state.gapSize, " pips");
      Print("   [", (c2 ? "✓" : "✗"), "] Counter-trend");
      Print("   [", (c3 ? "✓" : "✗"), "] Heavy DD: ", m_trap_state.ddAtDetection, "%");
      Print("   [", (c4 ? "✓" : "✗"), "] Price moving away");
      Print("   [", (c5 ? "✓" : "✗"), "] Stuck > ", m_params.trap_stuck_minutes, " min");
     }

   //+------------------------------------------------------------------+
   //| Get trap state                                                   |
   //+------------------------------------------------------------------+
   STrapState GetTrapState() const { return m_trap_state; }

   //+------------------------------------------------------------------+
   //| Reset trap state                                                 |
   //+------------------------------------------------------------------+
   void Reset() { m_trap_state.Reset(); }

   //+------------------------------------------------------------------+
   //| Set gap size (called from GridBasket)                           |
   //+------------------------------------------------------------------+
   void SetGapSize(double gap_pips) { m_trap_state.gapSize = gap_pips; }
  };

#endif // __RGD_V3_TRAP_DETECTOR_MQH__