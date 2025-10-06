//+------------------------------------------------------------------+
//| Math helpers for grid calculations                               |
//+------------------------------------------------------------------+
#ifndef __RGD_V2_MATH_HELPERS_MQH__
#define __RGD_V2_MATH_HELPERS_MQH__

inline double PipPoints(const string symbol)
  {
   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   if(digits==3 || digits==5)
      return 10.0*_Point;
   return _Point;
  }

inline int   NormalizeDecimals(const string symbol)
  {
   return (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
  }

inline double AveragePrice(const double &lots[],const double &prices[],const int count)
  {
   double vol=0.0;
   double weighted=0.0;
   for(int i=0;i<count;i++)
     {
      vol+=lots[i];
      weighted+=lots[i]*prices[i];
     }
   if(vol<=0.0)
      return 0.0;
   return weighted/vol;
  }

#endif // __RGD_V2_MATH_HELPERS_MQH__
