//+------------------------------------------------------------------+
//| NewsCalendar.mqh - Real-time economic calendar integration       |
//| ForexFactory calendar JSON API                                   |
//| Format: https://nfs.faireconomy.media/ff_calendar_thisweek.json  |
//+------------------------------------------------------------------+
#ifndef __RGD_V2_NEWS_CALENDAR_MQH__
#define __RGD_V2_NEWS_CALENDAR_MQH__

#include "Logger.mqh"

//+------------------------------------------------------------------+
//| News event structure                                              |
//+------------------------------------------------------------------+
struct SNewsEvent
  {
   datetime       event_time;       // Event time (UTC)
   string         currency;         // Currency affected (USD, EUR, etc.)
   string         title;            // Event title
   string         impact;           // High, Medium, Low
   bool           is_active;        // Currently within buffer window
  };

//+------------------------------------------------------------------+
//| News Calendar API client                                          |
//+------------------------------------------------------------------+
class CNewsCalendar
  {
private:
   SNewsEvent     m_events[];              // Cached events
   datetime       m_last_fetch;            // Last API call time
   int            m_fetch_interval_sec;    // Seconds between API calls
   string         m_api_url;               // ForexFactory calendar URL
   int            m_buffer_minutes;        // Minutes before/after news
   string         m_impact_filter;         // High, Medium, Low
   bool           m_enabled;               // API enabled
   CLogger       *m_log;

   // Error rate limiting
   datetime       m_last_error_log;        // Last time error was logged
   int            m_error_log_interval;    // Seconds between error logs (anti-spam)

   //+------------------------------------------------------------------+
   //| Load historical news from CSV string (resource or file)           |
   //+------------------------------------------------------------------+
   bool           LoadHistoricalNewsFromString(const string csv_content)
     {
      ArrayResize(m_events,0);
      int event_count=0;

      // Split CSV by lines
      string lines[];
      int line_count=StringSplit(csv_content,'\n',lines);

      // Skip header (first line)
      for(int i=1;i<line_count;i++)
        {
         string line=lines[i];
         StringTrimLeft(line);
         StringTrimRight(line);

         if(StringLen(line)==0)
            continue;

         // Parse CSV line: DateTime,Currency,Event,Impact
         string fields[];
         if(StringSplit(line,',',fields)!=4)
            continue;

         string date_time=fields[0];
         string currency=fields[1];
         string event_name=fields[2];
         string impact=fields[3];

         // Trim fields
         StringTrimLeft(date_time);
         StringTrimRight(date_time);
         StringTrimLeft(currency);
         StringTrimRight(currency);
         StringTrimLeft(event_name);
         StringTrimRight(event_name);
         StringTrimLeft(impact);
         StringTrimRight(impact);

         if(date_time=="" || currency=="" || event_name=="")
            continue;

         // Parse datetime (format: 2025-07-02 12:30)
         datetime event_dt=StringToTime(date_time);
         if(event_dt==0)
            continue;

         // Add event
         ArrayResize(m_events,event_count+1);
         m_events[event_count].event_time=event_dt;
         m_events[event_count].currency=currency;
         m_events[event_count].title=event_name;
         m_events[event_count].impact=impact;
         m_events[event_count].is_active=false;

         event_count++;
        }

      if(m_log!=NULL)
        {
         string msg=StringFormat("Loaded %d historical news events from CSV",event_count);
         m_log.Event("[NewsCalendar]",msg);
        }

      return event_count>0;
     }

   //+------------------------------------------------------------------+
   //| Fetch calendar from ForexFactory                                  |
   //+------------------------------------------------------------------+
   bool           FetchCalendar()
     {
      // ForexFactory calendar JSON API
      // Format: https://nfs.faireconomy.media/ff_calendar_thisweek.json
      string url="https://nfs.faireconomy.media/ff_calendar_thisweek.json";

      char post[];
      char result[];
      string headers;
      int timeout=5000;  // 5 seconds timeout

      ResetLastError();
      int res=WebRequest("GET",url,"","",timeout,post,0,result,headers);

      if(res==-1)
        {
         int error=GetLastError();
         // Rate-limit error logs (only log once per interval to avoid spam)
         // Use TimeGMT() instead of TimeCurrent() for backtest compatibility
         datetime now = TimeGMT();
         if(m_log != NULL && (now - m_last_error_log >= m_error_log_interval))
           {
            m_log.Event("[NewsCalendar]",StringFormat("WebRequest failed: error %d - Check Tools->Options->Expert Advisors->Allow WebRequest for URL: %s",
                                                     error,url));
            m_last_error_log = now;
           }
         return false;
        }

      if(res!=200)
        {
         // Rate-limit error logs
         datetime now = TimeGMT();
         if(m_log != NULL && (now - m_last_error_log >= m_error_log_interval))
           {
            m_log.Event("[NewsCalendar]",StringFormat("HTTP error: %d",res));
            m_last_error_log = now;
           }
         return false;
        }

      // Parse JSON response
      string json=CharArrayToString(result);
      return ParseCalendarJSON(json);
     }

   //+------------------------------------------------------------------+
   //| Parse ForexFactory JSON response                                  |
   //+------------------------------------------------------------------+
   bool           ParseCalendarJSON(const string json)
     {
      // ForexFactory JSON structure:
      // [
      //   {
      //     "title": "Non-Farm Payrolls",
      //     "country": "USD",
      //     "date": "2025-10-03 12:30:00",  // UTC
      //     "impact": "High",
      //     "forecast": "150K",
      //     "previous": "142K"
      //   },
      //   ...
      // ]

      // Clear old events
      ArrayResize(m_events,0);

      // Simple JSON parsing (MQL5 doesn't have native JSON parser)
      // We'll use string search for key fields
      int event_count=0;
      int max_events=100;
      ArrayResize(m_events,max_events);

      // Split by events (look for "title" field as delimiter)
      int pos=0;
      while(pos<StringLen(json) && event_count<max_events)
        {
         // Find next event
         int title_pos=StringFind(json,"\"title\"",pos);
         if(title_pos<0)
            break;

         // Extract event data
         string title="";
         string country="";
         string date_str="";
         string impact="";

         // Extract title
         int title_start=StringFind(json,":",title_pos)+1;
         int title_end=StringFind(json,",",title_start);
         if(title_end<0)
            title_end=StringFind(json,"}",title_start);
         title=ExtractJsonString(json,title_start,title_end);

         // Extract country
         int country_pos=StringFind(json,"\"country\"",title_pos);
         if(country_pos>0 && country_pos<title_pos+500)
           {
            int country_start=StringFind(json,":",country_pos)+1;
            int country_end=StringFind(json,",",country_start);
            if(country_end<0)
               country_end=StringFind(json,"}",country_start);
            country=ExtractJsonString(json,country_start,country_end);
           }

         // Extract date
         int date_pos=StringFind(json,"\"date\"",title_pos);
         if(date_pos>0 && date_pos<title_pos+500)
           {
            int date_start=StringFind(json,":",date_pos)+1;
            int date_end=StringFind(json,",",date_start);
            if(date_end<0)
               date_end=StringFind(json,"}",date_start);
            date_str=ExtractJsonString(json,date_start,date_end);
           }

         // Extract impact
         int impact_pos=StringFind(json,"\"impact\"",title_pos);
         if(impact_pos>0 && impact_pos<title_pos+500)
           {
            int impact_start=StringFind(json,":",impact_pos)+1;
            int impact_end=StringFind(json,",",impact_start);
            if(impact_end<0)
               impact_end=StringFind(json,"}",impact_start);
            impact=ExtractJsonString(json,impact_start,impact_end);
           }

         // Filter by impact
         if(ShouldIncludeEvent(impact))
           {
            m_events[event_count].title=title;
            m_events[event_count].currency=country;
            m_events[event_count].impact=impact;
            m_events[event_count].event_time=ParseDateTime(date_str);
            m_events[event_count].is_active=false;
            event_count++;
           }

         // Move to next event
         pos=title_pos+1;
        }

      // Resize to actual event count
      ArrayResize(m_events,event_count);

      if(m_log!=NULL)
         m_log.Event("[NewsCalendar]",StringFormat("Loaded %d events (filter: %s impact)",
                                                  event_count,m_impact_filter));

      return event_count>0;
     }

   //+------------------------------------------------------------------+
   //| Extract string value from JSON                                    |
   //+------------------------------------------------------------------+
   string         ExtractJsonString(const string json,int start,int end)
     {
      if(start<0 || end<=start || end>StringLen(json))
         return "";

      string value=StringSubstr(json,start,end-start);

      // Remove quotes and whitespace
      StringReplace(value,"\"","");
      StringTrimLeft(value);
      StringTrimRight(value);

      return value;
     }

   //+------------------------------------------------------------------+
   //| Parse datetime string (ForexFactory format)                       |
   //+------------------------------------------------------------------+
   datetime       ParseDateTime(const string date_str)
     {
      // Format: "2025-10-03 12:30:00" (UTC)
      if(StringLen(date_str)<19)
         return 0;

      int year=(int)StringToInteger(StringSubstr(date_str,0,4));
      int month=(int)StringToInteger(StringSubstr(date_str,5,2));
      int day=(int)StringToInteger(StringSubstr(date_str,8,2));
      int hour=(int)StringToInteger(StringSubstr(date_str,11,2));
      int minute=(int)StringToInteger(StringSubstr(date_str,14,2));
      int second=(int)StringToInteger(StringSubstr(date_str,17,2));

      MqlDateTime dt;
      dt.year=year;
      dt.mon=month;
      dt.day=day;
      dt.hour=hour;
      dt.min=minute;
      dt.sec=second;

      return StructToTime(dt);
     }

   //+------------------------------------------------------------------+
   //| Check if event should be included based on impact filter          |
   //+------------------------------------------------------------------+
   bool           ShouldIncludeEvent(const string impact)
     {
      if(m_impact_filter=="All")
         return true;
      if(m_impact_filter=="High" && impact=="High")
         return true;
      if(m_impact_filter=="Medium+" && (impact=="High" || impact=="Medium"))
         return true;
      return false;
     }

public:
                     CNewsCalendar(const bool enabled,
                                   const string impact_filter,
                                   const int buffer_minutes,
                                   CLogger *logger)
                       : m_enabled(enabled),
                         m_impact_filter(impact_filter),
                         m_buffer_minutes(buffer_minutes),
                         m_log(logger),
                         m_last_fetch(0),
                         m_fetch_interval_sec(3600),  // Fetch every 1 hour
                         m_last_error_log(0),
                         m_error_log_interval(3600)    // Log error max once per 1 hour (anti-spam)
     {
      ArrayResize(m_events,0);

      if(m_log!=NULL && m_enabled)
         m_log.Event("[NewsCalendar]",StringFormat("Initialized: filter=%s, buffer=%d min",
                                                  m_impact_filter,m_buffer_minutes));
     }

   //+------------------------------------------------------------------+
   //| Initialize with historical CSV resource (for backtesting)         |
   //+------------------------------------------------------------------+
   bool           InitHistoricalFromResource(const string csv_content)
     {
      if(!m_enabled)
         return false;

      bool loaded=LoadHistoricalNewsFromString(csv_content);
      if(loaded)
        {
         m_last_fetch=TimeGMT();  // Mark as fetched
         if(m_log!=NULL)
           {
            string msg="Historical news loaded from resource for backtesting";
            m_log.Event("[NewsCalendar]",msg);
           }
        }
      return loaded;
     }

   //+------------------------------------------------------------------+
   //| Check if currently within news window                             |
   //+------------------------------------------------------------------+
   bool           IsNewsTime(string &active_event)
     {
      if(!m_enabled)
         return false;

      // For backtesting: If events already loaded from CSV, skip API fetch
      datetime now=TimeGMT();
      if(ArraySize(m_events)==0 || (now-m_last_fetch>m_fetch_interval_sec))
        {
         // Try API fetch (will fail in backtest, that's OK - we have CSV data)
         if(FetchCalendar())
            m_last_fetch=now;
        }

      // Check if within buffer window of any event
      int buffer_seconds=m_buffer_minutes*60;

      for(int i=0;i<ArraySize(m_events);i++)
        {
         datetime event_time=m_events[i].event_time;
         int time_diff=(int)(event_time-now);

         // Within buffer window?
         if(MathAbs(time_diff)<=buffer_seconds)
           {
            // Log state transition
            if(!m_events[i].is_active && m_log!=NULL)
              {
               MqlDateTime dt;
               TimeToStruct(event_time,dt);
               m_log.Event("[NewsCalendar]",StringFormat("NEWS WINDOW ENTERED: %s [%s] %s @ %02d:%02d UTC (buffer: %d min)",
                                                        m_events[i].impact,
                                                        m_events[i].currency,
                                                        m_events[i].title,
                                                        dt.hour,dt.min,
                                                        m_buffer_minutes));
              }

            m_events[i].is_active=true;
            active_event=StringFormat("%s [%s] %s",
                                    m_events[i].impact,
                                    m_events[i].currency,
                                    m_events[i].title);
            return true;
           }
         else if(m_events[i].is_active)
           {
            // Log exit
            if(m_log!=NULL)
               m_log.Event("[NewsCalendar]",StringFormat("NEWS WINDOW EXITED: %s",m_events[i].title));
            m_events[i].is_active=false;
           }
        }

      active_event="";
      return false;
     }

   //+------------------------------------------------------------------+
   //| Get next upcoming event (for display/logging)                     |
   //+------------------------------------------------------------------+
   bool           GetNextEvent(SNewsEvent &next_event)
     {
      if(ArraySize(m_events)==0)
         return false;

      datetime now=TimeGMT();
      datetime nearest_time=D'2099.12.31';
      int nearest_idx=-1;

      for(int i=0;i<ArraySize(m_events);i++)
        {
         if(m_events[i].event_time>now && m_events[i].event_time<nearest_time)
           {
            nearest_time=m_events[i].event_time;
            nearest_idx=i;
           }
        }

      if(nearest_idx>=0)
        {
         next_event=m_events[nearest_idx];
         return true;
        }

      return false;
     }

   //+------------------------------------------------------------------+
   //| Get event count                                                   |
   //+------------------------------------------------------------------+
   int            GetEventCount() const { return ArraySize(m_events); }
  };

#endif // __RGD_V2_NEWS_CALENDAR_MQH__
