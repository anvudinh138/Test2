//+------------------------------------------------------------------+
//| Lightweight structured logger                                    |
//+------------------------------------------------------------------+
#ifndef __RGD_V2_LOGGER_MQH__
#define __RGD_V2_LOGGER_MQH__

class CLogger
  {
private:
   int      m_status_interval;
   datetime m_last_status;
   bool     m_emit_events;

public:
            CLogger(const int status_interval_sec,const bool emit_events)
              : m_status_interval(status_interval_sec),
                m_last_status(0),
                m_emit_events(emit_events)
     {
     }

   void     Event(const string tag,const string message) const
     {
      if(!m_emit_events)
         return;
      PrintFormat("%s %s",tag,message);
     }

   bool     Due() const
     {
      datetime now=TimeCurrent();
      return now-m_last_status>=m_status_interval;
     }

   void     Status(const string tag,const string message)
     {
      datetime now=TimeCurrent();
      if(now-m_last_status<m_status_interval)
         return;
      m_last_status=now;
      PrintFormat("%s %s",tag,message);
     }
  };

#endif // __RGD_V2_LOGGER_MQH__
