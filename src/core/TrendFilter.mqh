//+------------------------------------------------------------------+
//| Trend Filter - Prevent counter-trend positions                   |
//+------------------------------------------------------------------+
#ifndef __RGD_V2_TREND_FILTER_MQH__
#define __RGD_V2_TREND_FILTER_MQH__

#include <Trade/Trade.mqh>
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Trend state enum                                                 |
//+------------------------------------------------------------------+
enum ETrendState
  {
   TREND_NEUTRAL    = 0,  // No clear trend
   TREND_UP         = 1,  // Strong uptrend
   TREND_DOWN       = 2   // Strong downtrend
  };

//+------------------------------------------------------------------+
//| TrendFilter class                                                |
//+------------------------------------------------------------------+
class CTrendFilter
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_ema_timeframe;
   int               m_ema_period;
   int               m_adx_period;
   double            m_adx_threshold;
   double            m_buffer_pips;
   bool              m_enabled;
   CLogger          *m_log;

   // Indicator handles
   int               m_ema_handle;
   int               m_adx_handle;

   // Cache
   ETrendState       m_last_state;
   datetime          m_last_check_time;
   datetime          m_last_state_change_time;  // Hysteresis: time of last state change

   string            Tag() const
     {
      return StringFormat("[RGDv2][%s][TF]",m_symbol);
     }

   //+------------------------------------------------------------------+
   //| Get EMA value                                                    |
   //+------------------------------------------------------------------+
   double            GetEMA()
     {
      if(m_ema_handle==INVALID_HANDLE)
         return 0.0;

      double buffer[1];
      if(CopyBuffer(m_ema_handle,0,0,1,buffer)!=1)
         return 0.0;

      return buffer[0];
     }

   //+------------------------------------------------------------------+
   //| Get ADX value                                                    |
   //+------------------------------------------------------------------+
   double            GetADX()
     {
      if(m_adx_handle==INVALID_HANDLE)
         return 0.0;

      double buffer[1];
      if(CopyBuffer(m_adx_handle,0,0,1,buffer)!=1)
         return 0.0;

      return buffer[0];
     }

public:
                     CTrendFilter(const string symbol,
                                  const bool enabled,
                                  const ENUM_TIMEFRAMES ema_timeframe,
                                  const int ema_period,
                                  const int adx_period,
                                  const double adx_threshold,
                                  const double buffer_pips,
                                  CLogger *log)
                       : m_symbol(symbol),
                         m_enabled(enabled),
                         m_ema_timeframe(ema_timeframe),
                         m_ema_period(ema_period),
                         m_adx_period(adx_period),
                         m_adx_threshold(adx_threshold),
                         m_buffer_pips(buffer_pips),
                         m_log(log),
                         m_ema_handle(INVALID_HANDLE),
                         m_adx_handle(INVALID_HANDLE),
                         m_last_state(TREND_NEUTRAL),
                         m_last_check_time(0),
                         m_last_state_change_time(0)
     {
     }

                    ~CTrendFilter()
     {
      if(m_ema_handle!=INVALID_HANDLE)
         IndicatorRelease(m_ema_handle);
      if(m_adx_handle!=INVALID_HANDLE)
         IndicatorRelease(m_adx_handle);
     }

   //+------------------------------------------------------------------+
   //| Initialize indicators                                            |
   //+------------------------------------------------------------------+
   bool              Init()
     {
      if(!m_enabled)
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),"Trend filter DISABLED");
         return true;
        }

      // Create EMA indicator
      m_ema_handle=iMA(m_symbol,m_ema_timeframe,m_ema_period,0,MODE_EMA,PRICE_CLOSE);
      if(m_ema_handle==INVALID_HANDLE)
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),StringFormat("Failed to create EMA indicator (period=%d, TF=%s)",
                                          m_ema_period,EnumToString(m_ema_timeframe)));
         return false;
        }

      // Create ADX indicator
      m_adx_handle=iADX(m_symbol,PERIOD_CURRENT,m_adx_period);
      if(m_adx_handle==INVALID_HANDLE)
        {
         if(m_log!=NULL)
            m_log.Event(Tag(),StringFormat("Failed to create ADX indicator (period=%d)",m_adx_period));
         IndicatorRelease(m_ema_handle);
         m_ema_handle=INVALID_HANDLE;
         return false;
        }

      if(m_log!=NULL)
         m_log.Event(Tag(),StringFormat("Trend filter initialized (EMA%d %s, ADX%d>%.1f, Buffer=%.0f pips)",
                                       m_ema_period,EnumToString(m_ema_timeframe),
                                       m_adx_period,m_adx_threshold,m_buffer_pips));

      return true;
     }

   //+------------------------------------------------------------------+
   //| Check if strong uptrend                                          |
   //+------------------------------------------------------------------+
   bool              IsStrongUptrend()
     {
      if(!m_enabled)
         return false;

      double ema=GetEMA();
      if(ema<=0.0)
         return false;

      double adx=GetADX();
      if(adx<m_adx_threshold)
         return false;

      double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
      double buffer_px=m_buffer_pips*SymbolInfoDouble(m_symbol,SYMBOL_POINT)*10.0;

      return(ask>ema+buffer_px);
     }

   //+------------------------------------------------------------------+
   //| Check if strong downtrend                                        |
   //+------------------------------------------------------------------+
   bool              IsStrongDowntrend()
     {
      if(!m_enabled)
         return false;

      double ema=GetEMA();
      if(ema<=0.0)
         return false;

      double adx=GetADX();
      if(adx<m_adx_threshold)
         return false;

      double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      double buffer_px=m_buffer_pips*SymbolInfoDouble(m_symbol,SYMBOL_POINT)*10.0;

      return(bid<ema-buffer_px);
     }

   //+------------------------------------------------------------------+
   //| Get current trend state                                          |
   //+------------------------------------------------------------------+
   ETrendState       GetTrendState()
     {
      if(!m_enabled)
         return TREND_NEUTRAL;

      if(IsStrongUptrend())
         return TREND_UP;
      if(IsStrongDowntrend())
         return TREND_DOWN;

      return TREND_NEUTRAL;
     }

   //+------------------------------------------------------------------+
   //| Update and check for trend changes                               |
   //+------------------------------------------------------------------+
   void              Update()
     {
      if(!m_enabled)
         return;

      double ema=GetEMA();
      double adx=GetADX();

      // DEBUG: Log every check (first time only)
      static bool first_log=true;
      if(first_log && m_log!=NULL)
        {
         double price=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
         m_log.Event(Tag(),StringFormat("[DEBUG] First check: Price=%.5f, EMA=%.5f, ADX=%.1f, Enabled=%s",
                                       price,ema,adx,m_enabled?"YES":"NO"));
         first_log=false;
        }

      // Check if indicators loaded
      if(ema<=0.0 || adx<=0.0)
        {
         static datetime last_warning=0;
         datetime now=TimeCurrent();
         if(now-last_warning>3600 && m_log!=NULL)
           {
            m_log.Event(Tag(),StringFormat("[WARNING] Indicators not ready: EMA=%.5f, ADX=%.1f",ema,adx));
            last_warning=now;
           }
         return;
        }

      ETrendState current_state=GetTrendState();

      // Log state changes
      if(current_state!=m_last_state)
        {
         if(m_log!=NULL)
           {
            string state_str="";
            switch(current_state)
              {
               case TREND_UP:
                  state_str="STRONG UPTREND";
                  break;
               case TREND_DOWN:
                  state_str="STRONG DOWNTREND";
                  break;
               case TREND_NEUTRAL:
                  state_str="NEUTRAL";
                  break;
              }

            double price=(current_state==TREND_UP)?SymbolInfoDouble(m_symbol,SYMBOL_ASK)
                         :SymbolInfoDouble(m_symbol,SYMBOL_BID);

            m_log.Event(Tag(),StringFormat("Trend state changed: %s (Price=%.5f, EMA=%.5f, ADX=%.1f)",
                                          state_str,price,ema,adx));
           }

         m_last_state=current_state;
         m_last_state_change_time=TimeCurrent();  // Track state change time for hysteresis
        }

      m_last_check_time=TimeCurrent();
     }

   //+------------------------------------------------------------------+
   //| Check if BUY basket should be allowed                            |
   //+------------------------------------------------------------------+
   bool              AllowBuyBasket()
     {
      if(!m_enabled)
         return true;

      // Hysteresis: If recently changed to NEUTRAL from DOWNTREND, wait 10 minutes before allowing BUY
      datetime now=TimeCurrent();
      if(m_last_state==TREND_NEUTRAL && (now-m_last_state_change_time)<600)
        {
         // Check if previous state was DOWNTREND by checking current downtrend condition
         if(IsStrongDowntrend())
            return false;  // Still too close to downtrend, wait
        }

      // Block BUY during strong downtrend
      return !IsStrongDowntrend();
     }

   //+------------------------------------------------------------------+
   //| Check if SELL basket should be allowed                           |
   //+------------------------------------------------------------------+
   bool              AllowSellBasket()
     {
      if(!m_enabled)
         return true;

      // Hysteresis: If recently changed to NEUTRAL from UPTREND, wait 10 minutes before allowing SELL
      datetime now=TimeCurrent();
      if(m_last_state==TREND_NEUTRAL && (now-m_last_state_change_time)<600)
        {
         // Check if previous state was UPTREND by checking current uptrend condition
         if(IsStrongUptrend())
            return false;  // Still too close to uptrend, wait
        }

      // Block SELL during strong uptrend
      return !IsStrongUptrend();
     }

   //+------------------------------------------------------------------+
   //| Get trend state as string                                        |
   //+------------------------------------------------------------------+
   string            GetStateString() const
     {
      switch(m_last_state)
        {
         case TREND_UP:
            return "UPTREND";
         case TREND_DOWN:
            return "DOWNTREND";
         case TREND_NEUTRAL:
            return "NEUTRAL";
         default:
            return "UNKNOWN";
        }
     }

   //+------------------------------------------------------------------+
   //| Getters                                                          |
   //+------------------------------------------------------------------+
   bool              IsEnabled() const { return m_enabled; }
   double            GetCurrentEMA() { return GetEMA(); }
   double            GetCurrentADX() { return GetADX(); }
  };

#endif // __RGD_V2_TREND_FILTER_MQH__
