14. STEP-BY-STEP IMPLEMENTATION CHECKLIST

Phase 2: TrapDetector Module (Day 3-4)
☐ Task 2.1: Create TrapDetector.mqh
File: src/core/TrapDetector.mqh
cpp//+------------------------------------------------------------------+
//|                                                TrapDetector.mqh   |
//|                        Copyright 2025, Your Name                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

#include "Types.mqh"
#include "TrendFilter.mqh"

// Forward declaration
class CGridBasket;

//+------------------------------------------------------------------+
//| CTrapDetector - Multi-condition trap detection                   |
//+------------------------------------------------------------------+
class CTrapDetector
{
private:
    CGridBasket*        m_basket;           // Reference to basket
    CTrendFilter*       m_trendFilter;      // Reference to trend filter
    STrapState          m_trapState;        // Current trap state
    
    // Price tracking for movement detection
    double              m_lastPrice;
    datetime            m_lastPriceTime;
    double              m_lastDistance;     // Last distance from average
    
    string              m_symbol;
    double              m_point;
    
public:
    //+------------------------------------------------------------------+
    //| Constructor                                                       |
    //+------------------------------------------------------------------+
    CTrapDetector(CGridBasket* basket, CTrendFilter* trendFilter)
    {
        m_basket = basket;
        m_trendFilter = trendFilter;
        m_lastPrice = 0;
        m_lastPriceTime = 0;
        m_lastDistance = 0;
        m_symbol = _Symbol;
        m_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        
        m_trapState.Reset();
    }
    
    //+------------------------------------------------------------------+
    //| Destructor                                                        |
    //+------------------------------------------------------------------+
    ~CTrapDetector() {}
    
    //+------------------------------------------------------------------+
    //| Main detection function                                          |
    //+------------------------------------------------------------------+
    bool DetectTrapConditions();
    
    //+------------------------------------------------------------------+
    //| Individual condition checks                                       |
    //+------------------------------------------------------------------+
    bool CheckCondition_Gap();
    bool CheckCondition_CounterTrend();
    bool CheckCondition_HeavyDD();
    bool CheckCondition_MovingAway();
    bool CheckCondition_Stuck();
    
    //+------------------------------------------------------------------+
    //| Getters                                                           |
    //+------------------------------------------------------------------+
    STrapState GetTrapState() const { return m_trapState; }
    bool IsTrapped() const { return m_trapState.detected; }
    
    //+------------------------------------------------------------------+
    //| Reset state                                                       |
    //+------------------------------------------------------------------+
    void Reset()
    {
        m_trapState.Reset();
        m_lastPrice = 0;
        m_lastPriceTime = 0;
        m_lastDistance = 0;
    }
    
private:
    //+------------------------------------------------------------------+
    //| Helper: Log trap detection                                       |
    //+------------------------------------------------------------------+
    void LogTrapDetection(bool cond1, bool cond2, bool cond3, bool cond4, bool cond5);
};

//+------------------------------------------------------------------+
//| Main detection logic                                              |
//+------------------------------------------------------------------+
bool CTrapDetector::DetectTrapConditions()
{
    if(!InpTrapDetectionEnabled) return false;
    if(m_basket == NULL) return false;
    
    // Check all 5 conditions
    bool cond1 = CheckCondition_Gap();
    bool cond2 = CheckCondition_CounterTrend();
    bool cond3 = CheckCondition_HeavyDD();
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
    
    bool isTrap = (count >= InpTrapConditionsRequired);
    
    if(isTrap && !m_trapState.detected)
    {
        // New trap detected
        m_trapState.detected = true;
        m_trapState.detectedTime = TimeCurrent();
        m_trapState.conditionsMet = count;
        m_trapState.conditionFlags = flags;
        m_trapState.gapSize = m_basket.CalculateGapSize();
        m_trapState.ddAtDetection = m_basket.GetDDPercent();
        
        LogTrapDetection(cond1, cond2, cond3, cond4, cond5);
    }
    else if(!isTrap && m_trapState.detected)
    {
        // Trap resolved
        Print("✅ Trap conditions resolved (", count, "/5 now)");
        Reset();
    }
    
    return isTrap;
}

//+------------------------------------------------------------------+
//| Check: Gap condition                                              |
//+------------------------------------------------------------------+
bool CTrapDetector::CheckCondition_Gap()
{
    double gapSize = m_basket.CalculateGapSize();
    return (gapSize > InpTrapGapThreshold);
}

//+------------------------------------------------------------------+
//| Check: Counter-trend condition                                    |
//+------------------------------------------------------------------+
bool CTrapDetector::CheckCondition_CounterTrend()
{
    if(m_trendFilter == NULL || !m_trendFilter.IsEnabled())
        return false;
    
    return m_trendFilter.IsCounterTrend(m_basket.GetDirection());
}

//+------------------------------------------------------------------+
//| Check: Heavy DD condition                                         |
//+------------------------------------------------------------------+
bool CTrapDetector::CheckCondition_HeavyDD()
{
    double dd = m_basket.GetDDPercent();
    return (dd < InpTrapDDThreshold);
}

//+------------------------------------------------------------------+
//| Check: Moving away condition                                      |
//+------------------------------------------------------------------+
bool CTrapDetector::CheckCondition_MovingAway()
{
    double currentPrice = m_basket.GetCurrentPrice();
    double avg = m_basket.GetAveragePrice();
    
    if(avg == 0) return false;  // No average yet
    
    // Need 5 minutes of data
    if(TimeCurrent() - m_lastPriceTime < 300)
    {
        // Initialize on first call
        if(m_lastPriceTime == 0)
        {
            m_lastPrice = currentPrice;
            m_lastPriceTime = TimeCurrent();
            m_lastDistance = MathAbs(currentPrice - avg);
        }
        return false;
    }
    
    double currentDistance = MathAbs(currentPrice - avg) / m_point;
    
    // Check if distance increased by >10%
    bool movingAway = (currentDistance > m_lastDistance * 1.1);
    
    // Update tracking
    m_lastPrice = currentPrice;
    m_lastPriceTime = TimeCurrent();
    m_lastDistance = currentDistance;
    
    return movingAway;
}

//+------------------------------------------------------------------+
//| Check: Stuck condition                                            |
//+------------------------------------------------------------------+
bool CTrapDetector::CheckCondition_Stuck()
{
    int posCount = m_basket.GetPositionCount();
    if(posCount == 0) return false;
    
    // Find oldest position
    datetime oldestTime = TimeCurrent();
    for(int i = 0; i < posCount; i++)
    {
        // Get position open time (method depends on your CPosition implementation)
        datetime openTime = m_basket.GetPositionOpenTime(i);
        if(openTime < oldestTime)
            oldestTime = openTime;
    }
    
    int stuckDuration = (int)(TimeCurrent() - oldestTime);
    
    // Stuck > threshold AND still heavy DD
    bool stuck = (stuckDuration > InpTrapStuckMinutes * 60);
    bool heavyDD = (m_basket.GetDDPercent() < -15.0);
    
    return (stuck && heavyDD);
}

//+------------------------------------------------------------------+
//| Helper: Log trap detection                                        |
//+------------------------------------------------------------------+
void CTrapDetector::LogTrapDetection(bool cond1, bool cond2, bool cond3, bool cond4, bool cond5)
{
    Print("🚨 TRAP DETECTED for ", EnumToString(m_basket.GetDirection()));
    Print("   Conditions met: ", m_trapState.conditionsMet, "/5");
    Print("   ├─ Gap (", m_trapState.gapSize, " pips): ", cond1 ? "✅" : "❌");
    Print("   ├─ Counter-trend: ", cond2 ? "✅" : "❌");
    Print("   ├─ Heavy DD (", m_trapState.ddAtDetection, "%): ", cond3 ? "✅" : "❌");
    Print("   ├─ Moving away: ", cond4 ? "✅" : "❌");
    Print("   └─ Stuck: ", cond5 ? "✅" : "❌");
}
Verification:
✅ Compiles without errors
✅ All 5 condition checks implemented
✅ Requires 3/5 to trigger
✅ Logging comprehensive