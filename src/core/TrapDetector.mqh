//+------------------------------------------------------------------+
//| Trap Detector - Multi-condition trap detection                   |
//+------------------------------------------------------------------+
#ifndef __RGD_V2_TRAP_DETECTOR_MQH__
#define __RGD_V2_TRAP_DETECTOR_MQH__

#include "Types.mqh"
#include "TrendFilter.mqh"
#include "Logger.mqh"

// Forward declaration to avoid circular dependency
class CGridBasket;

//+------------------------------------------------------------------+
//| CTrapDetector - Detects trap conditions (Phase 5: 3 core only)  |
//+------------------------------------------------------------------+
class CTrapDetector
  {
private:
   CGridBasket      *m_basket;         // Reference to basket
   CTrendFilter     *m_trend_filter;   // Reference to trend filter
   CLogger          *m_log;            // Logger
   
   STrapState        m_trap_state;     // Current trap state
   
   // Configuration (from SParams)
   bool              m_enabled;
   double            m_gap_threshold;
   double            m_dd_threshold;
   int               m_conditions_required;
   int               m_stuck_minutes;
   
   // Price tracking for "moving away" detection (Phase 6)
   double            m_last_price;
   datetime          m_last_price_time;
   double            m_last_distance;
   
   string            m_symbol;
   double            m_point;
   
   string Tag() const
     {
      return StringFormat("[RGDv2][%s][TRAP]", m_symbol);
     }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
                     CTrapDetector(CGridBasket *basket,
                                   CTrendFilter *trend_filter,
                                   CLogger *log,
                                   const bool enabled,
                                   const double gap_threshold,
                                   const double dd_threshold,
                                   const int conditions_required,
                                   const int stuck_minutes)
                       : m_basket(basket),
                         m_trend_filter(trend_filter),
                         m_log(log),
                         m_enabled(enabled),
                         m_gap_threshold(gap_threshold),
                         m_dd_threshold(dd_threshold),
                         m_conditions_required(conditions_required),
                         m_stuck_minutes(stuck_minutes),
                         m_last_price(0),
                         m_last_price_time(0),
                         m_last_distance(0)
     {
      m_symbol = _Symbol;
      m_point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_trap_state.Reset();
     }
   
   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
                    ~CTrapDetector() {}
   
   //+------------------------------------------------------------------+
   //| Main detection function (Phase 5: 3 conditions only)            |
   //+------------------------------------------------------------------+
   bool DetectTrapConditions();
   
   //+------------------------------------------------------------------+
   //| Individual condition checks (Phase 5: 3 core conditions)        |
   //+------------------------------------------------------------------+
   bool CheckCondition_Gap();
   bool CheckCondition_CounterTrend();
   bool CheckCondition_HeavyDD();
   
   //+------------------------------------------------------------------+
   //| Phase 6 conditions (stub for now)                                |
   //+------------------------------------------------------------------+
   bool CheckCondition_MovingAway() { return false; }  // Phase 6
   bool CheckCondition_Stuck() { return false; }       // Phase 6
   
   //+------------------------------------------------------------------+
   //| Getters                                                           |
   //+------------------------------------------------------------------+
   STrapState GetTrapState() const { return m_trap_state; }
   bool IsTrapped() const { return m_trap_state.detected; }
   bool IsEnabled() const { return m_enabled; }
   
   //+------------------------------------------------------------------+
   //| Reset state                                                       |
   //+------------------------------------------------------------------+
   void Reset()
     {
      m_trap_state.Reset();
      m_last_price = 0;
      m_last_price_time = 0;
      m_last_distance = 0;
     }

private:
   //+------------------------------------------------------------------+
   //| Helper: Log trap detection                                       |
   //+------------------------------------------------------------------+
   void LogTrapDetection(bool cond1, bool cond2, bool cond3, bool cond4, bool cond5);
   
   //+------------------------------------------------------------------+
   //| Helper: Get basket gap size (calls into CGridBasket)            |
   //+------------------------------------------------------------------+
   double GetBasketGapSize();
   
   //+------------------------------------------------------------------+
   //| Helper: Get basket DD percent                                    |
   //+------------------------------------------------------------------+
   double GetBasketDDPercent();
   
   //+------------------------------------------------------------------+
   //| Helper: Get basket direction                                     |
   //+------------------------------------------------------------------+
   EDirection GetBasketDirection();
  };

//+------------------------------------------------------------------+
//| Main detection logic (Phase 5: 3 core conditions)                |
//+------------------------------------------------------------------+
bool CTrapDetector::DetectTrapConditions()
  {
   if(!m_enabled)
      return false;
   
   if(m_basket == NULL)
      return false;
   
   // Phase 5: Check 3 core conditions only
   bool cond1 = CheckCondition_Gap();
   bool cond2 = CheckCondition_CounterTrend();
   bool cond3 = CheckCondition_HeavyDD();
   
   // Phase 6: Stub for now (always false)
   bool cond4 = CheckCondition_MovingAway();
   bool cond5 = CheckCondition_Stuck();
   
   // Count conditions met
   int count = 0;
   int flags = 0;
   
   if(cond1) { count++; flags |= TRAP_COND_GAP; }
   if(cond2) { count++; flags |= TRAP_COND_COUNTER_TREND; }
   if(cond3) { count++; flags |= TRAP_COND_HEAVY_DD; }
   if(cond4) { count++; flags |= TRAP_COND_MOVING_AWAY; }
   if(cond5) { count++; flags |= TRAP_COND_STUCK; }
   
   bool is_trap = (count >= m_conditions_required);
   
   // New trap detected
   if(is_trap && !m_trap_state.detected)
     {
      m_trap_state.detected = true;
      m_trap_state.detectedTime = TimeCurrent();
      m_trap_state.conditionsMet = count;
      m_trap_state.conditionFlags = flags;
      m_trap_state.gapSize = GetBasketGapSize();
      m_trap_state.ddAtDetection = GetBasketDDPercent();
      
      LogTrapDetection(cond1, cond2, cond3, cond4, cond5);
     }
   // Trap resolved
   else if(!is_trap && m_trap_state.detected)
     {
      if(m_log != NULL)
         m_log.Event(Tag(), StringFormat("✅ Trap conditions resolved (%d/5 now)", count));
      
      Reset();
     }
   
   return is_trap;
  }

//+------------------------------------------------------------------+
//| Check: Gap condition                                              |
//+------------------------------------------------------------------+
bool CTrapDetector::CheckCondition_Gap()
  {
   double gap_size = GetBasketGapSize();
   return (gap_size > m_gap_threshold);
  }

//+------------------------------------------------------------------+
//| Check: Counter-trend condition                                    |
//+------------------------------------------------------------------+
bool CTrapDetector::CheckCondition_CounterTrend()
  {
   if(m_trend_filter == NULL)
      return false;
   
   if(!m_trend_filter.IsEnabled())
      return false;
   
   // Get current trend state
   ETrendState trend_state = m_trend_filter.GetTrendState();
   
   // Get basket direction
   EDirection basket_dir = GetBasketDirection();
   
   // Check if basket is counter-trend:
   // - BUY basket in TREND_DOWN = counter-trend
   // - SELL basket in TREND_UP = counter-trend
   if(basket_dir == DIR_BUY && trend_state == TREND_DOWN)
      return true;
   
   if(basket_dir == DIR_SELL && trend_state == TREND_UP)
      return true;
   
   return false;
  }

//+------------------------------------------------------------------+
//| Check: Heavy DD condition                                         |
//+------------------------------------------------------------------+
bool CTrapDetector::CheckCondition_HeavyDD()
  {
   double dd = GetBasketDDPercent();
   return (dd < m_dd_threshold);
  }

//+------------------------------------------------------------------+
//| Helper: Log trap detection                                        |
//+------------------------------------------------------------------+
void CTrapDetector::LogTrapDetection(bool cond1, bool cond2, bool cond3, bool cond4, bool cond5)
  {
   string dir_str = (GetBasketDirection() == DIR_BUY) ? "BUY" : "SELL";
   
   Print("🚨 TRAP DETECTED for ", dir_str, " basket");
   Print("   Conditions met: ", m_trap_state.conditionsMet, "/5");
   Print("   ├─ Gap (", DoubleToString(m_trap_state.gapSize, 1), " pips): ", cond1 ? "✅" : "❌");
   Print("   ├─ Counter-trend: ", cond2 ? "✅" : "❌");
   Print("   ├─ Heavy DD (", DoubleToString(m_trap_state.ddAtDetection, 2), "%): ", cond3 ? "✅" : "❌");
   Print("   ├─ Moving away: ", cond4 ? "✅" : "❌", " (Phase 6)");
   Print("   └─ Stuck: ", cond5 ? "✅" : "❌", " (Phase 6)");
   
   if(m_log != NULL)
     {
      string details = StringFormat("Conditions: %d/5 | Gap: %.1f | DD: %.2f%%",
                                   m_trap_state.conditionsMet,
                                   m_trap_state.gapSize,
                                   m_trap_state.ddAtDetection);
      m_log.Event(Tag(), "TRAP_DETECTED: " + details);
     }
  }

//+------------------------------------------------------------------+
//| Helper: Get basket gap size (forward to GridBasket method)       |
//+------------------------------------------------------------------+
double CTrapDetector::GetBasketGapSize()
  {
   if(m_basket == NULL)
      return 0.0;
   
   return m_basket.CalculateGapSize();
  }

//+------------------------------------------------------------------+
//| Helper: Get basket DD percent (forward to GridBasket method)     |
//+------------------------------------------------------------------+
double CTrapDetector::GetBasketDDPercent()
  {
   if(m_basket == NULL)
      return 0.0;
   
   return m_basket.GetDDPercent();
  }

//+------------------------------------------------------------------+
//| Helper: Get basket direction (forward to GridBasket method)      |
//+------------------------------------------------------------------+
EDirection CTrapDetector::GetBasketDirection()
  {
   if(m_basket == NULL)
      return DIR_BUY;
   
   return m_basket.GetDirection();
  }

#endif // __RGD_V2_TRAP_DETECTOR_MQH__

