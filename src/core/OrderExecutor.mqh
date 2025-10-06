//+------------------------------------------------------------------+
//| Order executor handling throttling and validation                |
//+------------------------------------------------------------------+
#ifndef __RGD_V2_ORDER_EXECUTOR_MQH__
#define __RGD_V2_ORDER_EXECUTOR_MQH__

#include <Trade/Trade.mqh>
#include "Types.mqh"
#include "OrderValidator.mqh"

class COrderExecutor
  {
private:
   string           m_symbol;
   COrderValidator *m_validator;
   int              m_slippage_points;
   int              m_cooldown_sec;
   datetime         m_last_order_time;
   int              m_bypass;
   CTrade           m_trade;

   bool             Ready()
     {
      datetime now=TimeCurrent();
      if(m_bypass>0)
        {
         m_bypass--;
         return true;
        }
      if(now-m_last_order_time<m_cooldown_sec)
         return false;
      return true;
     }

   bool             TrackResult()
     {
      if(m_trade.ResultRetcode()==TRADE_RETCODE_DONE ||
         m_trade.ResultRetcode()==TRADE_RETCODE_DONE_PARTIAL)
        {
         m_last_order_time=TimeCurrent();
         return true;
        }
      return false;
     }

public:
                     COrderExecutor(const string symbol,
                                    COrderValidator *validator,
                                    const int slippage_points,
                                    const int cooldown_sec)
                       : m_symbol(symbol),
                         m_validator(validator),
                         m_slippage_points(slippage_points),
                         m_cooldown_sec(cooldown_sec),
                         m_last_order_time(0),
                         m_bypass(0)
     {
      m_trade.SetExpertMagicNumber(0);
      m_trade.SetDeviationInPoints(m_slippage_points);
     }

   void              SetMagic(const long magic)
     {
      m_trade.SetExpertMagicNumber(magic);
     }

   void              BypassNext(const int n)
     {
      if(n>0) m_bypass+=n;
     }

   ulong             Market(const EDirection dir,const double lot,const string comment="")
     {
      if(!Ready())
         return 0;
      bool ok=(dir==DIR_BUY)?m_trade.Buy(lot,m_symbol,0.0,0.0,0.0,comment)
                            :m_trade.Sell(lot,m_symbol,0.0,0.0,0.0,comment);
      if(ok && TrackResult())
         return m_trade.ResultOrder();
      return 0;
     }

   ulong             Limit(const EDirection dir,const double price,const double lot,const string comment="")
     {
      if(!Ready())
         return 0;
      if(m_validator!=NULL && !m_validator.CanPlaceLimit(dir,price))
         return 0;
      double norm=NormalizeDouble(price,(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS));
      bool ok=(dir==DIR_BUY)?m_trade.BuyLimit(lot,norm,m_symbol,0.0,0.0,ORDER_TIME_GTC,0,comment)
                             :m_trade.SellLimit(lot,norm,m_symbol,0.0,0.0,ORDER_TIME_GTC,0,comment);
      if(ok && TrackResult())
         return m_trade.ResultOrder();
      return 0;
     }

   ulong             Stop(const EDirection dir,const double price,const double lot,const string comment="")
     {
      if(!Ready())
         return 0;
      if(m_validator!=NULL && !m_validator.CanPlaceStop(dir,price))
         return 0;
      double norm=NormalizeDouble(price,(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS));
      bool ok=(dir==DIR_BUY)?m_trade.BuyStop(lot,norm,m_symbol,0.0,0.0,ORDER_TIME_GTC,0,comment)
                             :m_trade.SellStop(lot,norm,m_symbol,0.0,0.0,ORDER_TIME_GTC,0,comment);
      if(ok && TrackResult())
         return m_trade.ResultOrder();
      return 0;
     }

   bool              ClosePosition(const ulong ticket,const string reason)
     {
      if(!PositionSelectByTicket(ticket))
         return true;
      if(!Ready())
         return false;
      bool ok=m_trade.PositionClose(ticket,m_slippage_points);
      if(ok && TrackResult())
        {
         Comment(reason);
         return true;
        }
      return false;
     }

   void              CloseAllByDirection(const EDirection dir,const long magic)
     {
      int total=(int)PositionsTotal();
      for(int i=total-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0)
            continue;
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol)
            continue;
         if(PositionGetInteger(POSITION_MAGIC)!=magic)
            continue;
         long type=PositionGetInteger(POSITION_TYPE);
         if((dir==DIR_BUY && type==POSITION_TYPE_BUY) ||
            (dir==DIR_SELL && type==POSITION_TYPE_SELL))
           {
            m_trade.PositionClose(ticket,m_slippage_points);
            TrackResult();
           }
        }
     }

   void              CancelPendingByDirection(const EDirection dir,const long magic)
     {
      int total=(int)OrdersTotal();
      for(int i=total-1;i>=0;i--)
        {
         ulong ticket=OrderGetTicket(i);
         if(ticket==0)
            continue;
         if(!OrderSelect(ticket))
            continue;
         if(OrderGetString(ORDER_SYMBOL)!=m_symbol)
            continue;
         if(OrderGetInteger(ORDER_MAGIC)!=magic)
            continue;
         ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         bool match=false;
         if(dir==DIR_BUY)
           {
            match=(type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP);
           }
         else
           {
            match=(type==ORDER_TYPE_SELL_LIMIT || type==ORDER_TYPE_SELL_STOP);
           }
         if(match)
            m_trade.OrderDelete(ticket);
        }
     }
  };

#endif // __RGD_V2_ORDER_EXECUTOR_MQH__
