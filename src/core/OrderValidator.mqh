//+------------------------------------------------------------------+
//| Order validation wrapper for broker constraints                  |
//+------------------------------------------------------------------+
#ifndef __RGD_V2_ORDER_VALIDATOR_MQH__
#define __RGD_V2_ORDER_VALIDATOR_MQH__

#include "Types.mqh"
#include "MathHelpers.mqh"

class COrderValidator
  {
private:
   string m_symbol;
   bool   m_respect_stops;

   double StopsLevelPoints() const
     {
      double stops=(double)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
      double freeze=(double)SymbolInfoInteger(m_symbol,SYMBOL_TRADE_FREEZE_LEVEL)*_Point;
      double min_level=MathMax(stops,freeze);
      if(min_level<=0.0)
         min_level=2*_Point;
      return min_level;
     }

public:
            COrderValidator(const string symbol,const bool respect_stops)
              : m_symbol(symbol),
                m_respect_stops(respect_stops)
     {
     }

   bool     CanPlaceLimit(const EDirection dir,const double price) const
     {
      if(!m_respect_stops)
         return true;
      double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
      double min_level=StopsLevelPoints();
      if(dir==DIR_BUY)
         return price<=bid-min_level;
      return price>=ask+min_level;
     }

   bool     CanPlaceStop(const EDirection dir,const double price) const
     {
      if(!m_respect_stops)
         return true;
      double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
      double min_level=StopsLevelPoints();
      if(dir==DIR_BUY)
         return price>=ask+min_level;
      return price<=bid-min_level;
     }
  };

#endif // __RGD_V2_ORDER_VALIDATOR_MQH__
