//+------------------------------------------------------------------+
//| Portfolio level risk tracking                                    |
//+------------------------------------------------------------------+
#ifndef __RGD_V2_PORTFOLIO_LEDGER_MQH__
#define __RGD_V2_PORTFOLIO_LEDGER_MQH__

#include "Types.mqh"

class CPortfolioLedger
  {
private:
   double  m_exposure_cap_lots;
   double  m_session_sl_usd;
   double  m_peak_equity;

public:
            CPortfolioLedger(const double exposure_cap_lots,
                              const double session_sl_usd)
              : m_exposure_cap_lots(exposure_cap_lots),
                m_session_sl_usd(session_sl_usd),
                m_peak_equity(0.0)
     {
     }

   void     UpdateEquitySnapshot()
     {
      double equity=AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity>m_peak_equity)
         m_peak_equity=equity;
     }

   double   PeakEquity() const { return m_peak_equity; }

   double   TotalExposureLots(const long magic,const string symbol) const
     {
      double lots=0.0;
      int total=(int)PositionsTotal();
      for(int i=0;i<total;i++)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0)
            continue;
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL)!=symbol)
            continue;
         if(PositionGetInteger(POSITION_MAGIC)!=magic)
            continue;
         lots+=PositionGetDouble(POSITION_VOLUME);
        }
      return lots;
     }

   bool     ExposureAllowed(const double additional,const long magic,const string symbol) const
     {
      if(m_exposure_cap_lots<=0.0)
         return true;
      double current=TotalExposureLots(magic,symbol);
      return (current+additional)<=m_exposure_cap_lots;
     }

   bool     SessionRiskBreached()
     {
      if(m_session_sl_usd<=0.0)
         return false;
      UpdateEquitySnapshot();
      double equity=AccountInfoDouble(ACCOUNT_EQUITY);
      double drawdown=m_peak_equity-equity;
      return drawdown>=m_session_sl_usd;
     }

   bool     TrailingDrawdownHit(const double trail_dd_usd)
     {
      if(trail_dd_usd<=0.0)
         return false;
      UpdateEquitySnapshot();
      double equity=AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_peak_equity<=0.0)
         return false;
      return (m_peak_equity-equity)>=trail_dd_usd;
     }
  };

#endif // __RGD_V2_PORTFOLIO_LEDGER_MQH__
