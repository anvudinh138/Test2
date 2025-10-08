9. TESTING STRATEGY
9.1 Unit Tests
Test 9.1.1: Lazy Grid Fill
Objective: Verify grid expands one level at a time with proper guards
Setup:

Initialize basket with InpInitialWarmLevels = 1
No trend filter active
Normal market conditions

Test Cases:
Test A: Normal Expansion
1. Seed basket → Should have 1 market + 1 pending
2. Fill level 1 → Should place level 2 only
3. Fill level 2 → Should place level 3 only
✅ Expected: One level added per fill

Test B: Counter-Trend Halt
1. Seed basket
2. Fill level 1
3. Activate counter-trend (simulate)
4. Try to expand
✅ Expected: Expansion halted, state = HALTED

Test C: DD Threshold Halt
1. Seed basket
2. Simulate DD < -20%
3. Fill level 1
4. Try to expand
✅ Expected: Expansion halted due to DD

Test D: Max Levels Reached
1. Seed basket with InpGridLevels = 5
2. Fill levels 1-4
3. Fill level 5
4. Try to expand
✅ Expected: State = GRID_FULL, no more expansion
Test 9.1.2: Trap Detection
Objective: Verify trap detection triggers correctly with multiple conditions
Test Cases:
Test A: No Trap (Normal DD)
Conditions:
- Gap: 100 pips (< 200) ❌
- Counter-trend: No ❌
- DD: -15% (> -20%) ❌
✅ Expected: NOT detected (0/5 conditions)

Test B: Minimal Trap (2 conditions)
Conditions:
- Gap: 250 pips ✅
- Counter-trend: Yes ✅
- DD: -15% ❌
- Moving away: No ❌
- Stuck: No ❌
Result: 2/5 conditions
✅ Expected: NOT detected (< 3 required)

Test C: Valid Trap (3 conditions)
Conditions:
- Gap: 250 pips ✅
- Counter-trend: Yes ✅
- DD: -22% ✅
- Moving away: No ❌
- Stuck: No ❌
Result: 3/5 conditions
✅ Expected: DETECTED, quick exit activated

Test D: Strong Trap (5 conditions)
Conditions:
- Gap: 300 pips ✅
- Counter-trend: Yes ✅
- DD: -25% ✅
- Moving away: Yes ✅
- Stuck: Yes (35 min) ✅
Result: 5/5 conditions
✅ Expected: DETECTED, aggressive quick exit
Test 9.1.3: Quick Exit Mode
Objective: Verify quick exit calculations and TP hit detection
Test Cases:
Test A: Fixed Mode (-$10)
Setup:
- InpQuickExitMode = QE_FIXED
- InpQuickExitLoss = -10.0
- Current DD: -$200

Steps:
1. Activate quick exit
2. Check targetCycleUSD = -10.0
3. Calculate TP price
4. Verify TP closer to current price
✅ Expected: TP ~10 pips from average (vs 30 pips normal)

Test B: Percentage Mode (30%)
Setup:
- InpQuickExitMode = QE_PERCENTAGE
- InpQuickExitPercentage = 0.30
- Current DD: -$200

Steps:
1. Activate quick exit
2. Check targetCycleUSD = -200 * 0.30 = -60.0
3. Calculate TP
✅ Expected: Target = -$60

Test C: Dynamic Mode
Setup:
- InpQuickExitMode = QE_DYNAMIC
- DD scenarios: -15%, -25%, -35%

Steps:
1. DD = -15% → Target should be -$10
2. DD = -25% → Target should be -$20
3. DD = -35% → Target should be -$30
✅ Expected: Dynamic scaling based on DD severity

Test D: TP Hit Detection
Setup:
- Quick exit active, target = -$10
- Current PnL: -$50

Steps:
1. Simulate price movement
2. PnL improves to -$15 (not hit yet)
3. PnL improves to -$8 (hit!)
4. Check basket closes all positions
5. Check reseed triggered
✅ Expected: Positions closed at -$8, basket reseeded

Test E: Timeout
Setup:
- Quick exit active
- InpQuickExitTimeoutMinutes = 60

Steps:
1. Activate quick exit
2. Wait 65 minutes (simulate)
3. Check deactivation
4. Verify target restored
✅ Expected: Mode deactivated, normal target restored
Test 9.1.4: Gap Management
Objective: Verify bridge fill and far position closing
Test Cases:
Test A: Small Gap (No Action)
Setup:
- Positions: 1.1000, 1.1050, 1.1100
- Max gap: 50 pips

✅ Expected: No bridge fill, normal operation

Test B: Medium Gap (Bridge Fill)
Setup:
- Positions: 1.1000, 1.1050, 1.1350 (300 pip gap)
- InpMaxBridgeLevels = 5

Steps:
1. Calculate gap = 300 pips
2. Trigger bridge fill
3. Check bridge levels placed: 1.1100, 1.1150, 1.1200, 1.1250, 1.1300
✅ Expected: 5 bridge levels placed between gap

Test C: Large Gap (Close Far)
Setup:
- Positions: 1.1000, 1.1050, 1.1500 (450 pip gap)
- Current price: 1.1500
- InpMaxPositionDistance = 300

Steps:
1. Calculate gap = 450 pips
2. Identify far positions: 1.1000 (500 pips), 1.1050 (450 pips)
3. Close far positions
4. Recalculate basket
✅ Expected: 2 positions closed, basket recalculated

Test D: Reseed After Gap Close
Setup:
- 3 positions, all > 300 pips away
- Close all 3

Steps:
1. Close far positions
2. Check remaining = 0
3. Trigger reseed
✅ Expected: Fresh basket seeded at current price

9.2 Integration Tests
Test 9.2.1: Full Cycle - Normal Market
Scenario: Range-bound market, no strong trends
Steps:
1. Seed BUY + SELL baskets
2. Price oscillates 50 pips
3. Levels fill gradually (lazy fill)
4. BUY hits TP first
5. BUY profit reduces SELL target
6. BUY reseeds
7. SELL hits TP
8. SELL reseeds
Expected Results:

✅ Grid expands lazily (1 level at a time)
✅ No trap detection
✅ Both baskets close at TP
✅ Profit redistribution works
✅ Reseeds successful

Test 9.2.2: Strong Uptrend Scenario
Scenario: Price moves 300 pips up rapidly
Steps:
1. Seed BUY + SELL @ 1.1000
2. Price → 1.1300 (300 pips up)
3. SELL levels fill: L0, L1, L2
4. Trend filter detects strong uptrend
5. SELL expansion halted
6. Gap forms: L2 (1.1100) to current (1.1300)
7. Trap detector triggers (gap + counter-trend + DD)
8. Quick exit mode activated
9. SELL target set to -$10
10. Price retraces to 1.1250
11. SELL TP hit at -$12
12. SELL basket closes and reseeds @ 1.1250
13. BUY basket continues normal, hits TP
Expected Results:

✅ SELL expansion halted correctly
✅ Trap detected with 3+ conditions
✅ Quick exit activated
✅ SELL escaped with small loss (-$12 vs potential -$200)
✅ BUY unaffected, closes normally
✅ Fresh SELL basket seeded at 1.1250

Test 9.2.3: Gap Trap + Sideways
Scenario: Strong trend creates gap, then price goes sideways in gap
Steps:
1. Seed baskets @ 1.1000
2. Uptrend → 1.1300
3. SELL trapped: L0 (1.1000), L1 (1.1050)
4. Gap: 250 pips
5. Price consolidates 1.1200-1.1280
6. Bridge fill triggered
7. New levels: 1.1150, 1.1200, 1.1250
8. Price fills bridge levels
9. Average improves: 1.1000 → 1.1125
10. TP becomes achievable
11. Price retraces to 1.1100
12. SELL TP hit
Expected Results:

✅ Gap detected correctly
✅ Bridge levels filled
✅ Average price improved
✅ TP hit successfully

Test 9.2.4: Both Baskets Trapped
Scenario: Whipsaw market traps both baskets
Steps:
1. Seed baskets @ 1.1000
2. Uptrend → 1.1300 (SELL trapped)
3. Sudden downtrend → 1.0700 (BUY trapped)
4. Both baskets in quick exit mode
5. Price stabilizes @ 1.1000
6. BUY hits quick exit TP first (-$15)
7. BUY profit x2 helps SELL
8. SELL target reduced significantly
9. SELL hits TP shortly after
10. Both baskets reseed @ 1.1000
Expected Results:

✅ Both traps detected independently
✅ Both quick exit modes activated
✅ Profit sharing x2 multiplier applied
✅ Both escaped successfully
✅ Fresh start for both baskets

Test 9.2.5: Grid Full Emergency
Scenario: Grid fills completely during strong trend
Steps:
1. Seed BUY basket @ 1.1000, InpGridLevels = 5
2. Strong downtrend
3. Levels fill: L1, L2, L3, L4, L5
4. Grid full state reached
5. Opposite SELL basket profitable
6. Wait for SELL TP
7. SELL closes, profit reduces BUY target
8. BUY TP becomes achievable
9. BUY closes at reduced target
10. Reseed both baskets
Expected Results:

✅ Grid full detected
✅ State = GRID_FULL
✅ Waiting for opposite rescue
✅ Rescue successful
✅ BUY closes with acceptable loss


9.3 Stress Tests
Test 9.3.1: High Volatility (XAU/USD)
Setup:

Symbol: XAU/USD
Timeframe: M15
Period: NFP announcement day
Spacing: ATR-based, 150 pips

Expected Behavior:

✅ Lazy fill prevents overexposure
✅ Wide ATR spacing adapts to volatility
✅ Trap detection triggers early
✅ Quick exit prevents large losses
✅ Multiple reseeds handle rapid swings

Test 9.3.2: Gap at Market Open
Setup:

Monday open with 200 pip gap
Existing positions from Friday

Expected Behavior:

✅ Gap detected on first tick
✅ Far positions identified
✅ Emergency close or reseed triggered
✅ New basket seeded at current price

Test 9.3.3: Low Liquidity
Setup:

Symbol: Exotic pair (e.g., USD/TRY)
Spread: 50+ pips
Slippage: High

Expected Behavior:

✅ Order validator rejects unreasonable orders
✅ Lazy fill adapts to wide spreads
✅ Trap detection accounts for spread
✅ Quick exit tolerates slippage

Test 9.3.4: Extended Trend (1000+ pips)
Setup:

Simulate EUR/USD march 2023 (800 pip trend)
One direction for 2 weeks

Expected Behavior:

✅ Losing basket halted early
✅ Multiple quick exits and reseeds
✅ Winning basket continues normally
✅ Total DD remains under control (<30%)


9.4 Regression Tests
After each change, verify:

✅ Existing presets still work (EUR, XAU, GBP, JPY)
✅ News filter integration unaffected
✅ Trend filter still functions
✅ Logging captures all events
✅ Performance metrics accurate