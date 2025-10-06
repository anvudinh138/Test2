//+------------------------------------------------------------------+
//| NewsFilter.mqh - Economic calendar news filter                   |
//| Pauses trading during high-impact news events                    |
//+------------------------------------------------------------------+
#ifndef __RGD_V2_NEWS_FILTER_MQH__
#define __RGD_V2_NEWS_FILTER_MQH__

#include "Logger.mqh"

//+------------------------------------------------------------------+
//| News event structure                                              |
//+------------------------------------------------------------------+
struct SNewsEvent
  {
   datetime       event_time;       // Event time (UTC)
   string         currency;         // Currency (USD, EUR, etc.)
   string         title;            // Event title
   string         impact;           // High, Medium, Low
   bool           is_active;        // Currently in buffer window
  };

//+------------------------------------------------------------------+
//| News Filter - API client for ForexFactory calendar               |
//+------------------------------------------------------------------+
class CNewsFilter
  {
private:
   SNewsEvent     m_events[];              // Cached events
   datetime       m_last_fetch;            // Last API call time
   int            m_fetch_interval_sec;    // Seconds between API calls (1 hour)
   string         m_api_url;               // ForexFactory calendar URL
   int            m_buffer_minutes;        // Minutes before/after news
   string         m_impact_filter;         // High, Medium+, All
   bool           m_enabled;               // Filter enabled
   CLogger       *m_log;

   // Error handling & rate limiting
   datetime       m_last_error_log;        // Last error log time
   int            m_error_log_interval;    // Error log interval (1 hour)
   int            m_retry_count;           // Current retry attempt
   int            m_max_retries;           // Max retry attempts (5)

   // Historical calendar support (for backtest)
   bool           m_use_mql_calendar;      // Use MQL5 Calendar API (backtest mode)
   datetime       m_history_start;         // Start time for historical fetch
   datetime       m_history_end;           // End time for historical fetch

   // Log rate limiting
   datetime       m_last_fetch_log;        // Last fetch attempt log time
   int            m_fetch_log_interval;    // Fetch log interval (5 min)

   string         Tag() const { return "[NewsFilter]"; }

   //+------------------------------------------------------------------+
   //| Extract string value from JSON (simple parser)                   |
   //+------------------------------------------------------------------+
   string         ExtractJsonValue(const string json, const string key, int search_start)
     {
      // Find key
      string search_key = "\"" + key + "\"";
      int key_pos = StringFind(json, search_key, search_start);
      if(key_pos < 0)
         return "";

      // Find colon after key
      int colon_pos = StringFind(json, ":", key_pos);
      if(colon_pos < 0)
         return "";

      // Find value start (skip whitespace and quotes)
      int value_start = colon_pos + 1;
      while(value_start < StringLen(json))
        {
         string ch = StringSubstr(json, value_start, 1);
         if(ch != " " && ch != "\"")
            break;
         value_start++;
        }

      // Find value end (comma, closing brace, or quote)
      int value_end = value_start;
      bool in_quotes = (StringSubstr(json, value_start - 1, 1) == "\"");

      while(value_end < StringLen(json))
        {
         string ch = StringSubstr(json, value_end, 1);
         if(in_quotes)
           {
            if(ch == "\"")
               break;
           }
         else
           {
            if(ch == "," || ch == "}" || ch == "]")
               break;
           }
         value_end++;
        }

      if(value_end <= value_start)
         return "";

      string value = StringSubstr(json, value_start, value_end - value_start);

      // Clean up
      StringReplace(value, "\"", "");
      StringTrimLeft(value);
      StringTrimRight(value);

      return value;
     }

   //+------------------------------------------------------------------+
   //| Parse datetime from ForexFactory format                          |
   //+------------------------------------------------------------------+
   datetime       ParseDateTime(const string date_str)
     {
      // Format: "2025-10-06 12:30:00" or "2025-10-06T12:30:00"
      if(StringLen(date_str) < 16)
         return 0;

      // Extract components
      int year = (int)StringToInteger(StringSubstr(date_str, 0, 4));
      int month = (int)StringToInteger(StringSubstr(date_str, 5, 2));
      int day = (int)StringToInteger(StringSubstr(date_str, 8, 2));

      // Handle both space and T separator
      int time_start = 11;
      if(StringSubstr(date_str, 10, 1) == "T")
         time_start = 11;

      int hour = (int)StringToInteger(StringSubstr(date_str, time_start, 2));
      int minute = (int)StringToInteger(StringSubstr(date_str, time_start + 3, 2));

      MqlDateTime dt;
      dt.year = year;
      dt.mon = month;
      dt.day = day;
      dt.hour = hour;
      dt.min = minute;
      dt.sec = 0;

      return StructToTime(dt);
     }

   //+------------------------------------------------------------------+
   //| Check if event matches impact filter                             |
   //+------------------------------------------------------------------+
   bool           ShouldIncludeEvent(const string impact)
     {
      if(m_impact_filter == "All")
         return true;
      if(m_impact_filter == "High" && impact == "High")
         return true;
      if(m_impact_filter == "Medium+" && (impact == "High" || impact == "Medium"))
         return true;
      return false;
     }

   //+------------------------------------------------------------------+
   //| Fetch calendar from ForexFactory API with retry logic            |
   //+------------------------------------------------------------------+
   bool           FetchCalendar()
     {
      m_api_url = "https://nfs.faireconomy.media/ff_calendar_thisweek.json";

      if(m_log != NULL)
         m_log.Event(Tag(), StringFormat("Fetching calendar from API (attempt 1/%d)...", m_max_retries));

      // Retry logic with exponential backoff
      for(m_retry_count = 1; m_retry_count <= m_max_retries; m_retry_count++)
        {
         char post[];
         char result[];
         string headers;
         int timeout = 5000;  // 5 seconds

         ResetLastError();
         int http_code = WebRequest("GET", m_api_url, "", "", timeout, post, 0, result, headers);

         // Check for WebRequest permission error
         if(http_code == -1)
           {
            int error = GetLastError();
            datetime now = TimeCurrent();

            // Rate-limit error logs (once per hour)
            if(m_log != NULL && (now - m_last_error_log >= m_error_log_interval))
              {
               m_log.Event(Tag(), StringFormat("WebRequest failed (attempt %d/%d): error %d",
                                              m_retry_count, m_max_retries, error));
               m_log.Event(Tag(), "Enable WebRequest for URL: https://nfs.faireconomy.media");
               m_log.Event(Tag(), "Go to: Tools → Options → Expert Advisors → Allow WebRequest");
               m_last_error_log = now;
              }

            // Don't retry on permission error
            if(error == 4060)  // ERR_WEBREQUEST_INVALID_ADDRESS
               return false;

            // Exponential backoff before retry
            if(m_retry_count < m_max_retries)
              {
               int wait_ms = (int)MathPow(2, m_retry_count) * 1000;  // 2^n seconds
               Sleep(wait_ms);
               continue;
              }

            return false;
           }

         // Check HTTP status code
         if(http_code == 200)
           {
            // Success - parse JSON
            string json = CharArrayToString(result);
            if(m_log != NULL)
               m_log.Event(Tag(), StringFormat("API fetch successful (attempt %d/%d) - JSON size: %d bytes",
                                              m_retry_count, m_max_retries, StringLen(json)));

            bool parsed = ParseCalendarJSON(json);
            return parsed;
           }
         else
           {
            // HTTP error - retry
            datetime now = TimeCurrent();
            if(m_log != NULL && (now - m_last_error_log >= m_error_log_interval))
              {
               m_log.Event(Tag(), StringFormat("HTTP error %d (attempt %d/%d)",
                                              http_code, m_retry_count, m_max_retries));
               m_last_error_log = now;
              }

            // Exponential backoff
            if(m_retry_count < m_max_retries)
              {
               int wait_ms = (int)MathPow(2, m_retry_count) * 1000;
               Sleep(wait_ms);
               continue;
              }
           }
        }

      return false;  // All retries failed
     }

   //+------------------------------------------------------------------+
   //| Fetch calendar from MQL5 Calendar API (historical data)          |
   //+------------------------------------------------------------------+
   bool           FetchMqlCalendar()
     {
      if(m_log != NULL)
         m_log.Event(Tag(), "Fetching historical calendar from MQL5 Calendar API...");

      // Get calendar database
      MqlCalendarCountry countries[];
      int country_count = CalendarCountries(countries);

      if(country_count <= 0)
        {
         if(m_log != NULL)
            m_log.Event(Tag(), "Calendar database not available - ensure MT5 calendar is synced");
         return false;
        }

      if(m_log != NULL)
         m_log.Event(Tag(), StringFormat("Calendar database: %d countries loaded", country_count));

      // Define time range for historical fetch
      // For backtest: fetch from backtest start to end + 1 week buffer
      datetime now = TimeCurrent();
      m_history_start = now - (30 * 86400);  // 30 days back
      m_history_end = now + (7 * 86400);     // 7 days forward

      if(m_log != NULL)
        {
         MqlDateTime dt_start, dt_end;
         TimeToStruct(m_history_start, dt_start);
         TimeToStruct(m_history_end, dt_end);
         m_log.Event(Tag(), StringFormat("Fetching events from %04d.%02d.%02d to %04d.%02d.%02d",
                                        dt_start.year, dt_start.mon, dt_start.day,
                                        dt_end.year, dt_end.mon, dt_end.day));
        }

      // Fetch calendar values (economic events)
      MqlCalendarValue values[];
      int event_count = CalendarValueHistory(values, m_history_start, m_history_end);

      if(event_count <= 0)
        {
         if(m_log != NULL)
            m_log.Event(Tag(), StringFormat("No calendar events found in range (returned %d)", event_count));
         return false;
        }

      if(m_log != NULL)
         m_log.Event(Tag(), StringFormat("Retrieved %d raw calendar values from MQL5", event_count));

      // Parse and filter events
      return ParseMqlCalendarValues(values, event_count);
     }

   //+------------------------------------------------------------------+
   //| Parse MQL5 Calendar values into our event structure              |
   //+------------------------------------------------------------------+
   bool           ParseMqlCalendarValues(const MqlCalendarValue &values[], int count)
     {
      ArrayResize(m_events, 0);

      int filtered_count = 0;
      int max_events = 500;  // Increased for historical data

      for(int i = 0; i < count && filtered_count < max_events; i++)
        {
         // Get event details
         MqlCalendarEvent event;
         if(!CalendarEventById(values[i].event_id, event))
            continue;

         // Get country info
         MqlCalendarCountry country;
         if(!CalendarCountryById(event.country_id, country))
            continue;

         // Map importance to impact level
         // MQL5 importance: 0=None, 1=Low, 2=Medium, 3=High
         string impact = "Low";
         if(event.importance == CALENDAR_IMPORTANCE_HIGH)
            impact = "High";
         else if(event.importance == CALENDAR_IMPORTANCE_MODERATE)
            impact = "Medium";
         else if(event.importance == CALENDAR_IMPORTANCE_LOW)
            impact = "Low";
         else
            continue;  // Skip events with no importance

         // Filter by impact
         if(!ShouldIncludeEvent(impact))
            continue;

         // Add event to our list
         ArrayResize(m_events, filtered_count + 1);
         m_events[filtered_count].event_time = values[i].time;
         m_events[filtered_count].currency = country.currency;
         m_events[filtered_count].title = event.name;
         m_events[filtered_count].impact = impact;
         m_events[filtered_count].is_active = false;
         filtered_count++;
        }

      if(m_log != NULL)
        {
         m_log.Event(Tag(), StringFormat("Loaded %d events from MQL5 Calendar (filter: %s impact)",
                                        filtered_count, m_impact_filter));

         // Log next upcoming event
         SNewsEvent next;
         if(GetNextEvent(next))
           {
            MqlDateTime dt;
            TimeToStruct(next.event_time, dt);
            int time_until = (int)((next.event_time - TimeCurrent()) / 60);  // minutes
            m_log.Event(Tag(), StringFormat("Next: [%s] [%s] %s @ %02d:%02d UTC (in %d minutes)",
                                           next.impact, next.currency, next.title,
                                           dt.hour, dt.min, time_until));
           }
         else
           {
            m_log.Event(Tag(), "No upcoming events found in MQL5 calendar");
           }
        }

      return filtered_count > 0;
     }

   //+------------------------------------------------------------------+
   //| Parse ForexFactory JSON response                                 |
   //+------------------------------------------------------------------+
   bool           ParseCalendarJSON(const string json)
     {
      ArrayResize(m_events, 0);

      int event_count = 0;
      int max_events = 100;

      // Find array start
      int array_start = StringFind(json, "[");
      if(array_start < 0)
         return false;

      // Parse events (simple approach - look for objects)
      int pos = array_start + 1;

      while(pos < StringLen(json) && event_count < max_events)
        {
         // Find next object start
         int obj_start = StringFind(json, "{", pos);
         if(obj_start < 0)
            break;

         // Find object end
         int obj_end = StringFind(json, "}", obj_start);
         if(obj_end < 0)
            break;

         // Extract values from this object
         string title = ExtractJsonValue(json, "title", obj_start);
         string country = ExtractJsonValue(json, "country", obj_start);
         string date_str = ExtractJsonValue(json, "date", obj_start);
         string impact = ExtractJsonValue(json, "impact", obj_start);

         // Validate and filter
         if(title != "" && date_str != "" && ShouldIncludeEvent(impact))
           {
            datetime event_dt = ParseDateTime(date_str);
            if(event_dt > 0)
              {
               // Add event
               ArrayResize(m_events, event_count + 1);
               m_events[event_count].event_time = event_dt;
               m_events[event_count].currency = country;
               m_events[event_count].title = title;
               m_events[event_count].impact = impact;
               m_events[event_count].is_active = false;
               event_count++;
              }
           }

         // Move to next object
         pos = obj_end + 1;
        }

      if(m_log != NULL)
        {
         m_log.Event(Tag(), StringFormat("Loaded %d events (filter: %s impact)",
                                        event_count, m_impact_filter));

         // Log next upcoming event
         SNewsEvent next;
         if(GetNextEvent(next))
           {
            MqlDateTime dt;
            TimeToStruct(next.event_time, dt);
            int time_until = (int)((next.event_time - TimeCurrent()) / 60);  // minutes
            m_log.Event(Tag(), StringFormat("Next: [%s] [%s] %s @ %02d:%02d UTC (in %d minutes)",
                                           next.impact, next.currency, next.title,
                                           dt.hour, dt.min, time_until));
           }
         else
           {
            m_log.Event(Tag(), "No upcoming events found in calendar");
           }
        }

      return event_count > 0;
     }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
                     CNewsFilter(const bool enabled,
                                 const string impact_filter,
                                 const int buffer_minutes,
                                 CLogger *logger)
                       : m_enabled(enabled),
                         m_impact_filter(impact_filter),
                         m_buffer_minutes(buffer_minutes),
                         m_log(logger),
                         m_last_fetch(0),
                         m_fetch_interval_sec(3600),      // 1 hour
                         m_last_error_log(0),
                         m_error_log_interval(3600),      // 1 hour
                         m_retry_count(0),
                         m_max_retries(5),                // Max 5 retry attempts
                         m_use_mql_calendar(false),       // Auto-detect mode
                         m_history_start(0),
                         m_last_fetch_log(0),
                         m_fetch_log_interval(300),       // 5 min
                         m_history_end(0)
     {
      ArrayResize(m_events, 0);

      if(m_log != NULL && m_enabled)
         m_log.Event(Tag(), StringFormat("Initialized: filter=%s, buffer=%d min, max_retries=%d",
                                        m_impact_filter, m_buffer_minutes, m_max_retries));
     }

   //+------------------------------------------------------------------+
   //| Check if currently within news window                            |
   //+------------------------------------------------------------------+
   bool           IsNewsTime(string &active_event)
     {
      if(!m_enabled)
         return false;

      // Fetch calendar if needed (every hour or if empty)
      datetime now = TimeCurrent();
      bool need_fetch = (ArraySize(m_events) == 0) || ((now - m_last_fetch) >= m_fetch_interval_sec);

      if(need_fetch)
        {
         // Rate-limit fetch logs (only log every 5 minutes)
         bool should_log = (m_log != NULL) && ((now - m_last_fetch_log) >= m_fetch_log_interval);

         if(should_log)
           {
            if(ArraySize(m_events) == 0)
               m_log.Event(Tag(), "First fetch - loading news calendar...");
            else
              {
               int minutes_since = (int)((now - m_last_fetch) / 60);
               m_log.Event(Tag(), StringFormat("Refreshing calendar (%d min since last fetch)", minutes_since));
              }
           }

         // Fallback strategy: API → MQL5 Calendar → cached events
         bool fetch_success = false;

         // Try ForexFactory API first (works in live/demo)
         if(!m_use_mql_calendar)
           {
            if(should_log)
               m_log.Event(Tag(), "Attempting ForexFactory API...");

            fetch_success = FetchCalendar();

            if(fetch_success)
              {
               m_last_fetch = now;
               m_last_fetch_log = now;  // Reset log timer on success
               if(m_log != NULL)
                  m_log.Event(Tag(), "Calendar loaded from ForexFactory API");
              }
            else
              {
               // API failed - try MQL5 Calendar as fallback
               if(should_log)
                  m_log.Event(Tag(), "ForexFactory API failed - trying MQL5 Calendar API...");

               fetch_success = FetchMqlCalendar();

               if(fetch_success)
                 {
                  m_last_fetch = now;
                  m_last_fetch_log = now;  // Reset log timer on success
                  m_use_mql_calendar = true;  // Remember to use MQL calendar from now on
                  if(m_log != NULL)
                     m_log.Event(Tag(), "Calendar loaded from MQL5 Calendar API (will use this source going forward)");
                 }
               else if(should_log)
                 {
                  m_log.Event(Tag(), "Both API sources failed - using cached events (if any)");
                  m_last_fetch_log = now;  // Reset log timer even on failure
                 }
              }
           }
         else
           {
            // Already using MQL5 Calendar - continue with it
            if(should_log)
               m_log.Event(Tag(), "Fetching from MQL5 Calendar API...");

            fetch_success = FetchMqlCalendar();

            if(fetch_success)
              {
               m_last_fetch = now;
               m_last_fetch_log = now;  // Reset log timer on success
              }
            else if(should_log)
              {
               m_log.Event(Tag(), "MQL5 Calendar fetch failed - using cached events (if any)");
               m_last_fetch_log = now;  // Reset log timer even on failure
              }
           }
        }

      // Check if within buffer window of any event
      int buffer_seconds = m_buffer_minutes * 60;

      for(int i = 0; i < ArraySize(m_events); i++)
        {
         datetime event_time = m_events[i].event_time;
         int time_diff = (int)(event_time - now);

         // Within buffer window?
         if(MathAbs(time_diff) <= buffer_seconds)
           {
            // Log state transition (enter news window)
            if(!m_events[i].is_active && m_log != NULL)
              {
               MqlDateTime dt;
               TimeToStruct(event_time, dt);
               m_log.Event(Tag(), StringFormat("NEWS WINDOW ENTERED: [%s] [%s] %s @ %02d:%02d UTC (buffer: %d min)",
                                              m_events[i].impact,
                                              m_events[i].currency,
                                              m_events[i].title,
                                              dt.hour, dt.min,
                                              m_buffer_minutes));
              }

            m_events[i].is_active = true;
            active_event = StringFormat("[%s] [%s] %s",
                                       m_events[i].impact,
                                       m_events[i].currency,
                                       m_events[i].title);
            return true;
           }
         else if(m_events[i].is_active)
           {
            // Log state transition (exit news window)
            if(m_log != NULL)
               m_log.Event(Tag(), StringFormat("NEWS WINDOW EXITED: %s", m_events[i].title));
            m_events[i].is_active = false;
           }
        }

      active_event = "";
      return false;
     }

   //+------------------------------------------------------------------+
   //| Get next upcoming event                                          |
   //+------------------------------------------------------------------+
   bool           GetNextEvent(SNewsEvent &next_event)
     {
      if(ArraySize(m_events) == 0)
         return false;

      datetime now = TimeCurrent();
      datetime nearest_time = D'2099.12.31';
      int nearest_idx = -1;

      for(int i = 0; i < ArraySize(m_events); i++)
        {
         if(m_events[i].event_time > now && m_events[i].event_time < nearest_time)
           {
            nearest_time = m_events[i].event_time;
            nearest_idx = i;
           }
        }

      if(nearest_idx >= 0)
        {
         next_event = m_events[nearest_idx];
         return true;
        }

      return false;
     }

   //+------------------------------------------------------------------+
   //| Get event count                                                   |
   //+------------------------------------------------------------------+
   int            GetEventCount() const { return ArraySize(m_events); }
  };

#endif // __RGD_V2_NEWS_FILTER_MQH__
