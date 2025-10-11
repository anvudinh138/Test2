//+------------------------------------------------------------------+
//| Enhanced structured logger with file support (v3.1.0 Phase 1)   |
//+------------------------------------------------------------------+
#ifndef __RGD_V2_LOGGER_MQH__
#define __RGD_V2_LOGGER_MQH__

#include "Types.mqh"

//+------------------------------------------------------------------+
//| Event types for v3.1.0                                           |
//+------------------------------------------------------------------+
enum ENUM_LOG_EVENT
  {
   LOG_INIT,                    // Initialization
   LOG_STATE_CHANGE,            // Basket state changed
   LOG_TRAP_DETECTED,           // Trap detected (Phase 2)
   LOG_QUICK_EXIT_ON,           // Quick exit mode activated (Phase 3)
   LOG_QUICK_EXIT_OFF,          // Quick exit mode deactivated
   LOG_QUICK_EXIT_SUCCESS,      // Quick exit target reached
   LOG_QUICK_EXIT_TIMEOUT,      // Quick exit timeout
   LOG_BRIDGE_FILL,             // Bridge levels filled (Phase 4)
   LOG_FAR_CLOSE,               // Far positions closed
   LOG_RESEED,                  // Basket reseeded
   LOG_EMERGENCY,               // Emergency close
   LOG_BASKET_CLOSED,           // Normal basket close at TP
   LOG_GRID_FULL,               // Grid full state
   LOG_HALTED,                  // Expansion halted
   LOG_RESUMED,                 // Expansion resumed
   LOG_INFO,                    // General info
   LOG_WARNING,                 // Warning
   LOG_ERROR                    // Error
  };

class CLogger
  {
private:
   int      m_status_interval;
   datetime m_last_status;
   bool     m_emit_events;
   long     m_magic;            // Magic number for file logging
   int      m_log_file_handle;  // File handle for logging
   string   m_log_file_name;    // Log file name

   //+------------------------------------------------------------------+
   //| Write to file if enabled                                         |
   //+------------------------------------------------------------------+
   void WriteToFile(const string message)
     {
      if(m_log_file_handle==INVALID_HANDLE)
         return;
      
      FileSeek(m_log_file_handle,0,SEEK_END);
      FileWriteString(m_log_file_handle,message+"\n");
      FileFlush(m_log_file_handle);
     }

   //+------------------------------------------------------------------+
   //| Get event type name                                              |
   //+------------------------------------------------------------------+
   string GetEventName(ENUM_LOG_EVENT event) const
     {
      switch(event)
        {
         case LOG_INIT:                return "INIT";
         case LOG_STATE_CHANGE:        return "STATE_CHANGE";
         case LOG_TRAP_DETECTED:       return "TRAP";
         case LOG_QUICK_EXIT_ON:       return "QE_ON";
         case LOG_QUICK_EXIT_OFF:      return "QE_OFF";
         case LOG_QUICK_EXIT_SUCCESS:  return "QE_SUCCESS";
         case LOG_QUICK_EXIT_TIMEOUT:  return "QE_TIMEOUT";
         case LOG_BRIDGE_FILL:         return "BRIDGE";
         case LOG_FAR_CLOSE:           return "FAR_CLOSE";
         case LOG_RESEED:              return "RESEED";
         case LOG_EMERGENCY:           return "EMERGENCY";
         case LOG_BASKET_CLOSED:       return "BASKET_CLOSED";
         case LOG_GRID_FULL:           return "GRID_FULL";
         case LOG_HALTED:              return "HALTED";
         case LOG_RESUMED:             return "RESUMED";
         case LOG_INFO:                return "INFO";
         case LOG_WARNING:             return "WARNING";
         case LOG_ERROR:               return "ERROR";
         default:                      return "UNKNOWN";
        }
     }

public:
   //+------------------------------------------------------------------+
   //| Constructor (backward compatible)                                |
   //+------------------------------------------------------------------+
            CLogger(const int status_interval_sec,const bool emit_events)
              : m_status_interval(status_interval_sec),
                m_last_status(0),
                m_emit_events(emit_events),
                m_magic(0),
                m_log_file_handle(INVALID_HANDLE),
                m_log_file_name("")
     {
     }

   //+------------------------------------------------------------------+
   //| Initialize with magic number (for file logging)                 |
   //+------------------------------------------------------------------+
   void Initialize(const long magic)
     {
      m_magic=magic;
      
      // Create log file name based on magic
      m_log_file_name=StringFormat("EA_Log_%d.txt",magic);
      
      // Open log file (append mode)
      m_log_file_handle=FileOpen(m_log_file_name,FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI);
      
      if(m_log_file_handle!=INVALID_HANDLE)
        {
         FileSeek(m_log_file_handle,0,SEEK_END);
         string header=StringFormat("\n========== EA Started: %s ==========\n",
                                   TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));
         FileWriteString(m_log_file_handle,header);
         FileFlush(m_log_file_handle);
        }
     }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CLogger()
     {
      if(m_log_file_handle!=INVALID_HANDLE)
        {
         string footer=StringFormat("\n========== EA Stopped: %s ==========\n",
                                   TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));
         FileWriteString(m_log_file_handle,footer);
         FileClose(m_log_file_handle);
         m_log_file_handle=INVALID_HANDLE;
        }
     }

   //+------------------------------------------------------------------+
   //| Legacy Event method (backward compatible)                        |
   //+------------------------------------------------------------------+
   void Event(const string tag,const string message) const
     {
      if(!m_emit_events)
         return;
      PrintFormat("%s %s",tag,message);
     }

   //+------------------------------------------------------------------+
   //| Warning method                                                    |
   //+------------------------------------------------------------------+
   void Warn(const string tag,const string message) const
     {
      if(!m_emit_events)
         return;
      PrintFormat("%s [WARN] %s",tag,message);
     }

   //+------------------------------------------------------------------+
   //| Debug method                                                      |
   //+------------------------------------------------------------------+
   void Debug(const string tag,const string message) const
     {
      if(!m_emit_events)
         return;
      PrintFormat("%s [DEBUG] %s",tag,message);
     }

   //+------------------------------------------------------------------+
   //| NEW: Structured event logging with types                         |
   //+------------------------------------------------------------------+
   void LogEvent(ENUM_LOG_EVENT event,EDirection direction,const string details="")
     {
      if(!m_emit_events)
         return;
      
      string timestamp=TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS);
      string dir_str=(direction==DIR_BUY)?"BUY":"SELL";
      string event_str=GetEventName(event);
      
      string message=StringFormat("[%s] %s | %s | %s",
                                 timestamp,dir_str,event_str,details);
      
      // Print to terminal
      Print(message);
      
      // Write to file
      WriteToFile(message);
     }

   //+------------------------------------------------------------------+
   //| NEW: Log with just event type (no direction)                     |
   //+------------------------------------------------------------------+
   void LogEvent(ENUM_LOG_EVENT event,const string details="")
     {
      if(!m_emit_events)
         return;
      
      string timestamp=TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS);
      string event_str=GetEventName(event);
      
      string message=StringFormat("[%s] %s | %s",timestamp,event_str,details);
      
      // Print to terminal
      Print(message);
      
      // Write to file
      WriteToFile(message);
     }

   //+------------------------------------------------------------------+
   //| Status logging (existing, unchanged)                             |
   //+------------------------------------------------------------------+
   bool Due() const
     {
      datetime now=TimeCurrent();
      return now-m_last_status>=m_status_interval;
     }

   void Status(const string tag,const string message)
     {
      datetime now=TimeCurrent();
      if(now-m_last_status<m_status_interval)
         return;
      m_last_status=now;
      
      string full_message=StringFormat("%s %s",tag,message);
      PrintFormat(full_message);
      WriteToFile(full_message);
     }
  };

#endif // __RGD_V2_LOGGER_MQH__
