//+------------------------------------------------------------------+
//| Trend Strength Analyzer - Phase 13 XAUUSD Protection            |
//| Combines ADX + ATR + EMA angle for market state classification  |
//+------------------------------------------------------------------+
#ifndef __RGD_V2_TREND_STRENGTH_ANALYZER_MQH__
#define __RGD_V2_TREND_STRENGTH_ANALYZER_MQH__

#include "Types.mqh"
#include "Logger.mqh"

class CTrendStrengthAnalyzer
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_timeframe;
   CLogger          *m_log;

   // Indicator handles
   int               m_handle_adx;
   int               m_handle_atr;
   int               m_handle_ema;

   // Thresholds
   double            m_extreme_threshold;  // 0.7 = 70% strength
   double            m_strong_threshold;   // 0.5 = 50% strength
   double            m_weak_threshold;     // 0.3 = 30% strength

   // Cache
   double            m_last_strength;
   EMarketState      m_last_state;
   datetime          m_last_update;

   string            Tag() const { return StringFormat("[TrendAnalyzer][%s]",m_symbol); }

public:
                     CTrendStrengthAnalyzer(const string symbol,
                                            const ENUM_TIMEFRAMES tf,
                                            CLogger *logger)
                       : m_symbol(symbol),
                         m_timeframe(tf),
                         m_log(logger),
                         m_handle_adx(INVALID_HANDLE),
                         m_handle_atr(INVALID_HANDLE),
                         m_handle_ema(INVALID_HANDLE),
                         m_extreme_threshold(0.7),
                         m_strong_threshold(0.5),
                         m_weak_threshold(0.3),
                         m_last_strength(0.0),
                         m_last_state(MARKET_RANGE),
                         m_last_update(0)
     {
      // Initialize indicators
      m_handle_adx=iADX(m_symbol,m_timeframe,14);
      m_handle_atr=iATR(m_symbol,m_timeframe,14);
      m_handle_ema=iMA(m_symbol,m_timeframe,200,0,MODE_EMA,PRICE_CLOSE);

      if(m_handle_adx==INVALID_HANDLE || m_handle_atr==INVALID_HANDLE || m_handle_ema==INVALID_HANDLE)
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),"Failed to initialize indicators");
        }
     }

                    ~CTrendStrengthAnalyzer()
     {
      // Release indicator handles
      if(m_handle_adx!=INVALID_HANDLE)
         IndicatorRelease(m_handle_adx);
      if(m_handle_atr!=INVALID_HANDLE)
         IndicatorRelease(m_handle_atr);
      if(m_handle_ema!=INVALID_HANDLE)
         IndicatorRelease(m_handle_ema);
     }

   //+------------------------------------------------------------------+
   //| Get ADX value                                                    |
   //+------------------------------------------------------------------+
   double            GetADX()
     {
      if(m_handle_adx==INVALID_HANDLE)
         return 0.0;

      double adx[];
      ArraySetAsSeries(adx,true);

      if(CopyBuffer(m_handle_adx,0,0,1,adx)<=0)
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),"Failed to copy ADX buffer");
         return 0.0;
        }

      return adx[0];
     }

   //+------------------------------------------------------------------+
   //| Get normalized ATR (0.0 to 1.0)                                 |
   //+------------------------------------------------------------------+
   double            GetNormalizedATR()
     {
      if(m_handle_atr==INVALID_HANDLE)
         return 0.0;

      double atr[];
      ArraySetAsSeries(atr,true);

      if(CopyBuffer(m_handle_atr,0,0,1,atr)<=0)
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),"Failed to copy ATR buffer");
         return 0.0;
        }

      // Normalize ATR: Current vs Average(20 periods)
      double atr_avg=0.0;
      double atr_hist[];
      ArraySetAsSeries(atr_hist,true);

      if(CopyBuffer(m_handle_atr,0,0,20,atr_hist)>0)
        {
         for(int i=0;i<20;i++)
            atr_avg+=atr_hist[i];
         atr_avg/=20.0;
        }
      else
        {
         atr_avg=atr[0];  // Fallback
        }

      if(atr_avg<=0.0)
         return 0.5;  // Default mid-range

      double normalized=atr[0]/atr_avg;
      return MathMin(1.0,MathMax(0.0,normalized));
     }

   //+------------------------------------------------------------------+
   //| Get EMA angle in degrees                                        |
   //+------------------------------------------------------------------+
   double            GetEMAAngle()
     {
      if(m_handle_ema==INVALID_HANDLE)
         return 0.0;

      double ema[];
      ArraySetAsSeries(ema,true);

      if(CopyBuffer(m_handle_ema,0,0,10,ema)<10)
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),"Failed to copy EMA buffer");
         return 0.0;
        }

      // Calculate angle using linear regression over 10 bars
      double sum_x=0,sum_y=0,sum_xy=0,sum_x2=0;
      int n=10;

      for(int i=0;i<n;i++)
        {
         double x=(double)(n-1-i);  // Reverse order (most recent = 0)
         double y=ema[i];

         sum_x+=x;
         sum_y+=y;
         sum_xy+=x*y;
         sum_x2+=x*x;
        }

      // Linear regression slope
      double slope=(n*sum_xy-sum_x*sum_y)/(n*sum_x2-sum_x*sum_x);

      // Convert slope to angle
      double angle=MathArctan(slope)*180.0/M_PI;

      return angle;  // -90 to +90 degrees
     }

   //+------------------------------------------------------------------+
   //| Get trend strength score (0.0 to 1.0)                           |
   //+------------------------------------------------------------------+
   double            GetTrendStrength()
     {
      // Check if we need to update (cache for 1 minute)
      datetime now=TimeCurrent();
      if(now-m_last_update<60 && m_last_strength>0.0)
        {
         return m_last_strength;
        }

      double adx_value=GetADX();
      double atr_normalized=GetNormalizedATR();
      double ema_angle=GetEMAAngle();

      // Weighted scoring
      // ADX (0-100) → 50% weight
      // ATR normalized (0-1) → 30% weight
      // EMA angle (-90 to +90) → 20% weight

      double adx_score=adx_value/100.0;
      double atr_score=atr_normalized;
      double angle_score=MathAbs(ema_angle)/90.0;

      double strength=(adx_score*0.5)+(atr_score*0.3)+(angle_score*0.2);
      strength=MathMin(1.0,strength);

      // Cache result
      m_last_strength=strength;
      m_last_update=now;

      return strength;
     }

   //+------------------------------------------------------------------+
   //| Classify market state                                           |
   //+------------------------------------------------------------------+
   EMarketState      GetMarketState()
     {
      double strength=GetTrendStrength();

      EMarketState state;
      if(strength>=m_extreme_threshold)
         state=MARKET_EXTREME_TREND;
      else if(strength>=m_strong_threshold)
         state=MARKET_STRONG_TREND;
      else if(strength>=m_weak_threshold)
         state=MARKET_WEAK_TREND;
      else
         state=MARKET_RANGE;

      // Log state changes
      if(state!=m_last_state && m_log!=NULL)
        {
         double adx=GetADX();
         m_log.Event(Tag(),StringFormat("Market state: %s → %s (Strength: %.1f%%, ADX: %.1f)",
                                       EnumToString(m_last_state),
                                       EnumToString(state),
                                       strength*100.0,
                                       adx));
        }

      m_last_state=state;
      return state;
     }

   //+------------------------------------------------------------------+
   //| Should block counter-trend operations?                          |
   //+------------------------------------------------------------------+
   bool              ShouldBlockCounterTrend()
     {
      EMarketState state=GetMarketState();
      return (state>=MARKET_STRONG_TREND);
     }

   //+------------------------------------------------------------------+
   //| Should stop all trading (extreme danger)?                       |
   //+------------------------------------------------------------------+
   bool              ShouldStopAllTrading()
     {
      return (GetMarketState()==MARKET_EXTREME_TREND);
     }

   //+------------------------------------------------------------------+
   //| Get dynamic spacing multiplier based on market state            |
   //+------------------------------------------------------------------+
   double            GetSpacingMultiplier()
     {
      switch(GetMarketState())
        {
         case MARKET_RANGE:
            return 1.0;   // Normal spacing
         case MARKET_WEAK_TREND:
            return 1.5;   // 1.5x spacing
         case MARKET_STRONG_TREND:
            return 2.0;   // 2x spacing
         case MARKET_EXTREME_TREND:
            return 3.0;   // 3x spacing (danger!)
         default:
            return 1.0;
        }
     }

   //+------------------------------------------------------------------+
   //| Get current market state info (for logging/display)             |
   //+------------------------------------------------------------------+
   string            GetStateInfo()
     {
      double strength=GetTrendStrength();
      double adx=GetADX();
      double ema_angle=GetEMAAngle();
      EMarketState state=GetMarketState();

      return StringFormat("State: %s | Strength: %.1f%% | ADX: %.1f | EMA Angle: %.1f°",
                         EnumToString(state),
                         strength*100.0,
                         adx,
                         ema_angle);
     }
  };

#endif // __RGD_V2_TREND_STRENGTH_ANALYZER_MQH__
