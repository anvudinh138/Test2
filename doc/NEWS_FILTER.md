# News Filter Feature

## Overview

The News Filter pauses trading during high-impact economic news events to avoid volatile price movements, slippage, and unpredictable spread widening.

## How It Works

### 1. **News Calendar Sources (Automatic Fallback)**

The news filter uses a **smart fallback strategy** to ensure calendar data is available in all modes:

**Priority 1: ForexFactory API** (Live/Demo only)
- **Source**: ForexFactory Calendar API
- **URL**: `https://nfs.faireconomy.media/ff_calendar_thisweek.json`
- **Update Frequency**: Every 1 hour (3600 seconds)
- **Availability**: Live and demo trading only (WebRequest required)

**Priority 2: MQL5 Calendar API** (Backtest + Live/Demo)
- **Source**: Built-in MT5 Calendar database
- **Functions**: `CalendarValueHistory()`, `CalendarEventById()`, `CalendarCountryById()`
- **Update Frequency**: Every 1 hour (3600 seconds)
- **Availability**: Works in backtest, live, and demo modes
- **Range**: Fetches 30 days back + 7 days forward

**Priority 3: Cached Events**
- **Source**: Last successful fetch from either API
- **Availability**: Always (as long as one previous fetch succeeded)

### 2. **Automatic Source Selection**

```
┌─────────────────────┐
│  IsNewsTime()       │
└──────────┬──────────┘
           │
           ├─→ First attempt: ForexFactory API
           │   ├─ Success? → Use ForexFactory (live/demo)
           │   └─ Failed?  → Try MQL5 Calendar
           │
           └─→ MQL5 Calendar API
               ├─ Success? → Use MQL5 Calendar permanently
               └─ Failed?  → Use cached events (if any)
```

The filter automatically detects which source works and sticks with it.

### 3. **ForexFactory JSON Response Format**

```json
[
  {
    "title": "Non-Farm Payrolls",
    "country": "USD",
    "date": "2025-10-06 12:30:00",
    "impact": "High",
    "forecast": "150K",
    "previous": "142K"
  }
]
```

### 4. **MQL5 Calendar API Structure**

The MQL5 Calendar API provides structured economic calendar data:

```mql5
MqlCalendarValue {
   ulong event_id;        // Event identifier
   datetime time;         // Event time (UTC)
   datetime period;       // Period
   int revision;          // Revision
   long actual_value;     // Actual value
   long prev_value;       // Previous value
   long revised_prev_value;
   long forecast_value;   // Forecast value
   ENUM_CALENDAR_EVENT_IMPACT impact_type;
};

MqlCalendarEvent {
   ulong id;                          // Event ID
   ENUM_CALENDAR_EVENT_TYPE type;     // Event type
   ENUM_CALENDAR_EVENT_SECTOR sector; // Sector
   ENUM_CALENDAR_EVENT_FREQUENCY frequency;
   ENUM_CALENDAR_EVENT_TIMEMODE time_mode;
   ulong country_id;                  // Country identifier
   ENUM_CALENDAR_EVENT_UNIT unit;     // Unit
   ENUM_CALENDAR_EVENT_IMPORTANCE importance;  // LOW, MODERATE, HIGH
   ENUM_CALENDAR_EVENT_MULTIPLIER multiplier;
   ENUM_CALENDAR_EVENT_IMPACT impact_type;
   string name;                       // Event name
   string source_url;
   string event_code;
   string currency_code;
};
```

**Importance Mapping**:
- `CALENDAR_IMPORTANCE_HIGH` → `"High"`
- `CALENDAR_IMPORTANCE_MODERATE` → `"Medium"`
- `CALENDAR_IMPORTANCE_LOW` → `"Low"`

### 5. **News Window Logic**

```
News Event Time: 12:30 UTC
Buffer: 30 minutes

Trading PAUSED from:
  12:00 UTC (30 min before)
  to
  13:00 UTC (30 min after)
```

**During news window**:
- EA skips `g_controller.Update()`
- No new orders opened
- Existing positions remain open
- Logs: "Trading paused - News: [High] [USD] Non-Farm Payrolls"

## Configuration

### Input Parameters

```mql5
//--- News Filter
input bool   InpNewsFilterEnabled   = false;  // Enable news filter
input string InpNewsImpactFilter    = "High"; // Impact: High, Medium+, All
input int    InpNewsBufferMinutes   = 30;     // Buffer before/after (minutes)
```

### Impact Filter Options

| Filter | Events Filtered |
|--------|----------------|
| `High` | Only High impact events (NFP, FOMC, CPI) |
| `Medium+` | High + Medium impact events |
| `All` | All events (High, Medium, Low) |

**Recommended**: Start with `High` filter only

## API Integration

### Rate Limiting & Retry Logic

**To avoid server abuse**:

1. **Cache Duration**: 1 hour (3600 sec)
   - Events cached in memory
   - Only refetch after 1 hour expires

2. **Retry Logic**: Max 5 attempts with exponential backoff
   ```
   Attempt 1: immediate
   Attempt 2: wait 2 seconds
   Attempt 3: wait 4 seconds
   Attempt 4: wait 8 seconds
   Attempt 5: wait 16 seconds
   ```

3. **Error Logging**: Rate-limited to once per hour
   - Prevents log spam if API continuously fails
   - Clear notification to user about WebRequest permission

### WebRequest Permission Required

**IMPORTANT**: Must enable WebRequest for ForexFactory URL in MT5

**Steps**:
1. Tools → Options → Expert Advisors
2. Check "Allow WebRequest for listed URL"
3. Add: `https://nfs.faireconomy.media`

**Without permission**: WebRequest returns error -1, EA logs warning once per hour

### Error Handling

| Error Code | Meaning | Action |
|-----------|---------|--------|
| -1 | WebRequest not allowed | Log: "Enable WebRequest permission for: https://nfs.faireconomy.media" |
| 200 | Success | Parse JSON, cache events |
| 404/500 | Server error | Retry up to 5 times, then skip until next hour |
| Timeout | Network timeout (5 sec) | Retry with backoff |

## Implementation Details

### News Filter State Machine

```
[IDLE]
  ↓ (every hour)
[FETCH API] → (retry up to 5x if fail)
  ↓ (success)
[PARSE JSON] → cache events
  ↓
[CHECK NEWS WINDOW each tick]
  ↓
  ├─ Within buffer? → PAUSE TRADING
  └─ Outside buffer? → ALLOW TRADING
```

### Integration with Main EA

**OnInit()**:
```mql5
g_news_filter = new CNewsFilter(InpNewsFilterEnabled,
                                 InpNewsImpactFilter,
                                 InpNewsBufferMinutes,
                                 g_logger);
```

**OnTick()**:
```mql5
string active_event = "";
if (g_news_filter != NULL && g_news_filter.IsNewsTime(active_event)) {
   // Skip trading during news
   return;
}

// Normal trading
g_controller.Update();
```

**OnDeinit()**:
```mql5
if (g_news_filter != NULL) {
   delete g_news_filter;
   g_news_filter = NULL;
}
```

## Logging Examples

### Successful ForexFactory API Fetch (Live/Demo)
```
[NewsFilter] First fetch - loading news calendar...
[NewsFilter] Attempting ForexFactory API...
[NewsFilter] Fetching calendar from API (attempt 1/5)...
[NewsFilter] API fetch successful (attempt 1/5) - JSON size: 45231 bytes
[NewsFilter] Loaded 47 events (filter: High impact)
[NewsFilter] Calendar loaded from ForexFactory API
[NewsFilter] Next: [High] [USD] Non-Farm Payrolls @ 12:30 UTC (in 125 minutes)
```

### Fallback to MQL5 Calendar (Live/Demo when API fails)
```
[NewsFilter] First fetch - loading news calendar...
[NewsFilter] Attempting ForexFactory API...
[NewsFilter] WebRequest failed (attempt 1/5): error 4060
[NewsFilter] ForexFactory API failed - trying MQL5 Calendar API...
[NewsFilter] Fetching historical calendar from MQL5 Calendar API...
[NewsFilter] Calendar database: 195 countries loaded
[NewsFilter] Fetching events from 2025.09.06 to 2025.10.13
[NewsFilter] Retrieved 1247 raw calendar values from MQL5
[NewsFilter] Loaded 89 events from MQL5 Calendar (filter: High impact)
[NewsFilter] Calendar loaded from MQL5 Calendar API (will use this source going forward)
[NewsFilter] Next: [High] [USD] Non-Farm Payrolls @ 12:30 UTC (in 125 minutes)
```

### MQL5 Calendar in Backtest
```
[NewsFilter] First fetch - loading news calendar...
[NewsFilter] Attempting ForexFactory API...
[NewsFilter] ForexFactory API failed - trying MQL5 Calendar API...
[NewsFilter] Fetching historical calendar from MQL5 Calendar API...
[NewsFilter] Calendar database: 195 countries loaded
[NewsFilter] Fetching events from 2024.01.01 to 2024.02.07
[NewsFilter] Retrieved 2341 raw calendar values from MQL5
[NewsFilter] Loaded 156 events from MQL5 Calendar (filter: High impact)
[NewsFilter] Next: [High] [USD] CPI @ 14:30 UTC (in 342 minutes)
```

### News Window Entered
```
[NewsFilter] NEWS WINDOW ENTERED: [High] [USD] Non-Farm Payrolls @ 12:30 UTC (buffer: 30 min)
[RGDv2] Trading paused - News: [High] [USD] Non-Farm Payrolls
```

### News Window Exited
```
[NewsFilter] NEWS WINDOW EXITED: Non-Farm Payrolls
[RGDv2] Trading resumed
```

### API Error (with permission issue)
```
[NewsFilter] WebRequest failed: error 4060 - Enable WebRequest for URL: https://nfs.faireconomy.media
[NewsFilter] Go to: Tools → Options → Expert Advisors → Allow WebRequest
```

## Testing

### Test on Demo First

1. **Enable filter**: `InpNewsFilterEnabled = true`
2. **Set to High only**: `InpNewsImpactFilter = "High"`
3. **Use 30 min buffer**: `InpNewsBufferMinutes = 30`
4. **Check logs**: Verify API fetch successful
5. **Wait for news**: Confirm trading pauses before/after event

### Manual Testing

**Force API fetch** (for testing):
- Restart EA → triggers immediate fetch
- Check logs for "Loaded X events"
- Use "Next event" log to see upcoming news

### Backtest Support

✅ **News filter NOW WORKS in Strategy Tester**:
- Uses MQL5 Calendar API (historical data)
- Automatically falls back from ForexFactory → MQL5 Calendar
- Calendar database must be synced in MT5 (usually auto-syncs)
- Fetches historical events for backtest period (30 days back + 7 days forward)

**Requirements for Backtest**:
1. MT5 Calendar database synced (check Tools → Calendar)
2. Enable news filter: `InpNewsFilterEnabled = true`
3. Calendar data available for backtest period

**Fallback behavior**:
- Live/Demo: Tries ForexFactory API first → falls back to MQL5 Calendar
- Backtest: Uses MQL5 Calendar directly (WebRequest blocked in Strategy Tester)

## Performance Impact

- **Memory**: ~10KB for 100 cached events
- **API calls**: 1 request per hour maximum
- **CPU**: Negligible (simple string comparison each tick)
- **Network**: 5-10KB JSON download per hour

## Safety Notes

✅ **What filter does**:
- Prevents opening NEW positions during news
- Logs news windows clearly

❌ **What filter does NOT do**:
- Does NOT close existing positions before news
- Does NOT modify existing orders/SL/TP
- Does NOT guarantee zero slippage (positions still open)

**Recommendation**: Consider manual intervention for major events (NFP, FOMC) if large positions open

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "WebRequest failed: error 4060" | Normal in backtest - EA will auto-fallback to MQL5 Calendar. For live/demo, enable WebRequest permission |
| "Calendar database not available" | Check Tools → Calendar in MT5, ensure calendar is synced |
| "Loaded 0 events" | Check internet connection (live) or calendar sync (backtest) |
| News filter not working | Check `InpNewsFilterEnabled = true` |
| Too many pauses | Switch from "All" → "High" impact filter |
| Missing historical events in backtest | Ensure MT5 calendar database is synced (usually automatic) |
| "Both API sources failed" | Check internet + calendar sync, will use cached events if available |

## Example Configuration

### Conservative (Recommended)
```mql5
InpNewsFilterEnabled   = true
InpNewsImpactFilter    = "High"      // Only major events
InpNewsBufferMinutes   = 30          // 30 min before/after
```

### Aggressive (More trading time)
```mql5
InpNewsFilterEnabled   = true
InpNewsImpactFilter    = "High"
InpNewsBufferMinutes   = 15          // Shorter buffer
```

### Very Conservative
```mql5
InpNewsFilterEnabled   = true
InpNewsImpactFilter    = "Medium+"   // High + Medium
InpNewsBufferMinutes   = 60          // 1 hour buffer
```

## Recent Updates

**v2.0 - Historical News Support** ✅
- [x] MQL5 Calendar API integration for backtest support
- [x] Automatic fallback: ForexFactory API → MQL5 Calendar → cached events
- [x] Works seamlessly in live, demo, AND backtest modes
- [x] Comprehensive logging for both API sources

## Future Enhancements

Possible improvements (not implemented yet):
- [ ] Auto-close positions X minutes before major news
- [ ] Symbol-specific filtering (only USD news for EURUSD)
- [ ] Tighten SL before news (reduce risk)
- [ ] Custom news list (user-defined events)
- [ ] Configurable historical range (currently 30 days back + 7 days forward)
