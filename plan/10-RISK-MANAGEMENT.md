10. RISK MANAGEMENT
10.1 Built-in Safety Mechanisms
10.1.1 Lazy Grid Fill
Risk Mitigated: Overexposure during strong trends
Mechanism:

Only 1-2 pending levels at a time
Expansion gated by trend filter + DD checks
Maximum level distance enforced

Parameters:
cppInpInitialWarmLevels = 1           // Start conservative
InpMaxLevelDistance = 500          // Safety limit
InpMaxDDForExpansion = -20.0       // Halt if DD too deep
10.1.2 Trap Detection Multi-Condition
Risk Mitigated: False positives (normal DD triggering quick exit)
Mechanism:

Requires 3 out of 5 conditions
Conditions independent and diverse
Prevents premature exits

Tuning:
cppInpTrapConditionsRequired = 3      // Balance: too high = miss traps
                                   //          too low = false positives
10.1.3 Quick Exit with Limits
Risk Mitigated: Accepting too large a loss to exit
Mechanism:

Configurable loss threshold
Timeout prevents indefinite mode
Optional far position closing

Parameters:
cppInpQuickExitLoss = -10.0           // Small loss acceptable
InpQuickExitTimeoutMinutes = 60    // 1 hour max
InpMaxAcceptableLoss = -100.0      // Global limit
10.1.4 Basket-Level Stop Loss
Risk Mitigated: Single basket blowing up
Mechanism:

Per-basket SL monitoring
Independent of session SL
Auto-reseed or halt option

Parameters:
cppInpBasketSL_USD = 100.0            // Per-basket limit
InpAutoReseedAfterSL = true        // Fresh start vs halt
10.1.5 Session-Level Stop Loss (Backup)
Risk Mitigated: Total account drawdown
Mechanism:

Monitors both baskets combined
Emergency shutdown if threshold hit
Last resort safety net

Parameters:
cppInpSessionSL_USD = 500.0           // Global account limit

10.2 Risk Scenarios & Mitigation
Scenario A: Flash Crash
Event: 500 pip move in 1 minute
Risks:

Multiple levels filled instantly
Slippage on closes
Gap created immediately

Mitigation:

✅ Lazy fill limits initial exposure (only 1-2 pendings)
✅ Trap detection triggers on first tick post-crash
✅ Quick exit activated immediately
✅ Far positions closed if gap > 400 pips
✅ Reseed at new price level

Expected Outcome:

Loss contained to -$20 to -$50 vs potential -$500+

Scenario B: News Spike (Both Directions)
Event: NFP causes 200 pip up, then 300 pip down in 15 minutes
Risks:

Both baskets trapped simultaneously
Whipsaw fills multiple levels
No clear trend for filter

Mitigation:

✅ News filter pauses trading during event
✅ If positions already open, trap detection for both
✅ First basket to escape helps second (x2 multiplier)
✅ Emergency close if both DD > threshold

Expected Outcome:

Trading paused during event OR
Both baskets escape with small losses (-$10 to -$30 each)

Scenario C: Extended One-Way Trend
Event: 1000 pip trend over 2 weeks (no retracement)
Risks:

Losing basket never recovers
Multiple reseeds all fail
Cumulative small losses add up

Mitigation:

✅ Trend filter halts expansion early
✅ Each reseed has independent trap detection
✅ Winning basket accumulates profit to offset
✅ Session SL provides final backstop

Expected Outcome:

5-10 quick exits at -$10 each = -$50 to -$100 total
Winning basket profits offset: +$200+
Net positive or small loss

Scenario D: Low Liquidity / Wide Spread
Event: Exotic pair, 50 pip spread, thin orderbook
Risks:

Trap detection false positive (spread = fake gap)
Slippage on quick exit closes
TP price unreachable due to spread

Mitigation:

✅ Gap calculation ignores positions within spread range
✅ Order validator checks spread before placing
✅ Quick exit loss tolerance accounts for spread
✅ Recommend avoiding exotics or use preset for high volatility

Expected Outcome:

System detects poor conditions
Fewer trades placed
Losses higher per trade but frequency lower


10.3 Parameter Safety Ranges
ParameterConservativeBalancedAggressiveNotesInpInitialWarmLevels11-22-3Higher = more exposureInpTrapConditionsRequired432Lower = more false positivesInpQuickExitLoss-$5-$10-$20Higher loss = faster exitInpTrapGapThreshold150200300Lower = more sensitiveInpTrapDDThreshold-15%-20%-25%Lower = earlier triggerInpMaxPositionDistance200300400Lower = more frequent closesInpBasketSL_USD$50$100$200Lower = tighter riskInpSessionSL_USD$300$500$1000Last resort
Recommended Starting Point: Balanced column for testing

10.4 Monitoring & Alerts
Real-Time Monitoring Dashboard
Key Metrics to Display:
BUY Basket:
├─ State: ACTIVE / HALTED / QUICK_EXIT
├─ Positions: 3
├─ Floating PnL: -$15
├─ DD%: -8%
├─ TP Price: 1.1025 (Distance: 25 pips)
└─ Gap Size: 50 pips

SELL Basket:
├─ State: QUICK_EXIT ⚡
├─ Positions: 4
├─ Floating PnL: -$18
├─ DD%: -12%
├─ TP Price: 1.1105 (Distance: 10 pips) ← CLOSE!
└─ Gap Size: 180 pips

Global:
├─ Total Floating: -$33
├─ Session Profit: +$127
├─ Traps Detected Today: 2
└─ Quick Exits Today: 1 (Success rate: 100%)
Alert Conditions
cpp// Critical alerts (push notification)
- Trap detected → Both baskets
- Quick exit activated
- Basket SL hit
- Session SL approaching (80%)
- Emergency close triggered

// Warning alerts (log only)
- Gap > 300 pips
- DD approaching trap threshold (-18%)
- Grid full on one basket
- Trend filter halted expansion