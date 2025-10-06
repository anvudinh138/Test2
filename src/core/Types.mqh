//+------------------------------------------------------------------+
//| Project: Recovery Grid Direction v2                              |
//| Purpose: Shared enums and POD structures                         |
//+------------------------------------------------------------------+
#ifndef __RGD_V2_TYPES_MQH__
#define __RGD_V2_TYPES_MQH__

enum EDirection
  {
   DIR_BUY  = 0,
   DIR_SELL = 1
  };

enum ESpacingMode
  {
   SPACING_PIPS   = 0,
   SPACING_ATR    = 1,
   SPACING_HYBRID = 2
  };

enum EBasketKind
  {
   BASKET_PRIMARY = 0,
   BASKET_HEDGE   = 1
  };

struct SGridLevel
  {
   double price;   // entry price for pending level
   double lot;     // lot size for this level
   ulong  ticket;  // ticket once placed
   bool   filled;  // level already converted to position
  };

struct SBasketSummary
  {
   EDirection direction;
   EBasketKind kind;
   double total_lot;
   double avg_price;
   double pnl_usd;
   double tp_price;
   double last_grid_price;
   bool   trailing_active;
  };

#endif // __RGD_V2_TYPES_MQH__
