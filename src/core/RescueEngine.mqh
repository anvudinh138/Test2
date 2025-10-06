//+------------------------------------------------------------------+
//| Rescue engine deciding when to deploy opposite basket            |
//+------------------------------------------------------------------+
#ifndef __RGD_V2_RESCUE_ENGINE_MQH__
#define __RGD_V2_RESCUE_ENGINE_MQH__

#include "Types.mqh"
#include "Params.mqh"
#include "Logger.mqh"

class CRescueEngine
  {
private:
   string   m_symbol;
   SParams  m_params;
   CLogger *m_log;
   datetime m_last_rescue_time;
   int      m_cycles;

   string   Tag() const { return StringFormat("[RGDv2][%s][Rescue]",m_symbol); }

   bool     BreachLastGrid(const EDirection loser_dir,const double last_grid_price,const double spacing_px,const double price) const
     {
      if(spacing_px<=0.0)
         return false;
      double offset=spacing_px*m_params.offset_ratio;
      if(loser_dir==DIR_BUY)
         return price<=(last_grid_price-offset);
      return price>=(last_grid_price+offset);
     }

public:
            CRescueEngine(const string symbol,const SParams &params,CLogger *logger)
              : m_symbol(symbol),
                m_params(params),
                m_log(logger),
                m_last_rescue_time(0),
                m_cycles(0)
     {
     }

   bool     CooldownOk() const
     {
      if(m_params.cooldown_bars<=0)
         return true;
      int seconds=PeriodSeconds();
      if(seconds<=0)
         seconds=60;
      datetime window=m_params.cooldown_bars*seconds;
      return (TimeCurrent()-m_last_rescue_time)>=window;
     }

   bool     CyclesAvailable() const
     {
      if(m_params.max_cycles_per_side<=0)
         return true;
      return m_cycles<m_params.max_cycles_per_side;
     }

   bool     ShouldRescue(const EDirection loser_dir,
                         const double last_grid_price,
                         const double spacing_px,
                         const double current_price,
                         const double loser_dd_usd) const
     {
      bool breach=BreachLastGrid(loser_dir,last_grid_price,spacing_px,current_price);
      bool dd=(loser_dd_usd>=m_params.dd_open_usd);
      return breach || dd;
     }

   void     RecordRescue()
     {
      m_cycles++;
      m_last_rescue_time=TimeCurrent();
     }

   void     ResetCycleCounter()
     {
      m_cycles=0;
     }

   void     LogSkip(const string reason) const
     {
      if(m_log!=NULL)
         m_log.Status(Tag(),reason);
     }
  };

#endif // __RGD_V2_RESCUE_ENGINE_MQH__
