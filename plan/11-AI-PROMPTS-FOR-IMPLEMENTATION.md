11.1 Initial Setup Prompt
You are implementing an enhancement to an MQL5 trading EA called "Recovery Grid Direction v3". 

CONTEXT:
The EA currently uses a "dynamic grid" that pre-fills multiple pending levels, causing overexposure during strong trends. When trends occur, gaps form between old trapped positions and new positions, making break-even nearly impossible.

YOUR TASK:
Implement a "Lazy Grid Fill + Trap Detection + Quick Exit" system.

KEY REQUIREMENTS:
1. Lazy Grid Fill: Only 1-2 pending levels at a time, expand on-demand
2. Trap Detection: Multi-condition algorithm (5 conditions, require 3+)
3. Quick Exit Mode: Accept small loss (-$10 to -$20) to escape trap fast
4. Gap Management: Bridge fill or close far positions

FILES TO MODIFY:
- src/core/GridBasket.mqh (MAJOR changes)
- src/core/LifecycleController.mqh (moderate changes)
- src/core/Types.mqh (new enums/structs)
- src/core/Params.mqh (new input parameters)

NEW FILES TO CREATE:
- src/core/TrapDetector.mqh

ARCHITECTURE:
- GridBasket owns TrapDetector instance
- TrapDetector has reference to TrendFilter
- QuickExit logic embedded in GridBasket
- LifecycleController monitors both baskets for global risk

CRITICAL RULES:
- NEVER quote exact code from search results (copyright)
- Use clear variable names
- Add comprehensive logging
- Follow existing code style
- Test each component independently

Please confirm understanding and ask any clarifying questions before starting implementation.
11.2 Lazy Grid Fill Implementation Prompt
Implement the Lazy Grid Fill system for GridBasket.mqh.

REQUIREMENTS:

1. INITIAL SEED:
   - Open 1 market order (level 0)
   - Place only InpInitialWarmLevels pending orders (default: 1)
   - Track lastFilledLevel, lastFilledPrice

2. ON LEVEL FILLED:
   - Detect when a pending order fills
   - Call OnLevelFilled(level)
   - Run guard checks BEFORE placing next level:
     a. Trend filter: if counter-trend → HALT
     b. DD threshold: if DD < -20% → HALT
     c. Max levels: if at limit → GRID_FULL
     d. Distance: if next level > 500 pips away → skip
   - If all guards pass → place next pending order
   - Update currentMaxLevel

3. TRACKING:
   - Use struct SGridState to track:
     * lastFilledLevel
     * lastFilledPrice
     * lastFilledTime
     * currentMaxLevel
     * pendingCount

4. RESUME LOGIC:
   - When halted, periodically check if trend weakened
   - If trend OK → resume expansion from lastFilledLevel + 1

EXISTING CODE TO INTEGRATE:
- m_trendFilter.IsCounterTrend(m_direction) for trend check
- m_spacingEngine.ComputeSpacing() for spacing calculation
- m_executor.PlacePending() for order placement

ERROR HANDLING:
- Log each state transition
- Handle failed order placements gracefully
- Validate prices before placing orders

Please implement the core lazy fill functions:
- SeedInitialGrid()
- OnLevelFilled(int level)
- CheckForNextLevel()
- ShouldExpandGrid()
- PlaceNextPendingOrder()
11.3 Trap Detector Implementation Prompt
Create a new file src/core/TrapDetector.mqh that implements multi-condition trap detection.

CLASS STRUCTURE:

class CTrapDetector
{
private:
    CGridBasket* m_basket;
    CTrendFilter* m_trendFilter;
    STrapState m_trapState;
    
    // Price tracking
    double m_lastPrice;
    datetime m_lastPriceTime;

public:
    CTrapDetector(CGridBasket* basket, CTrendFilter* trendFilter);
    
    bool DetectTrapConditions();
    bool CheckCondition_Gap();
    bool CheckCondition_CounterTrend();
    bool CheckCondition_HeavyDD();
    bool CheckCondition_MovingAway();
    bool CheckCondition_Stuck();
    
    STrapState GetTrapState() const;
    void Reset();
};

5 CONDITIONS TO CHECK:

1. Gap Condition:
   - Calculate gap between positions
   - Gap > InpTrapGapThreshold (default: 200 pips)
   
2. Counter-Trend Condition:
   - Check if TrendFilter.IsCounterTrend(basket.direction)
   - Only valid if trend filter enabled
   
3. Heavy DD Condition:
   - Check if basket.GetDDPercent() < InpTrapDDThreshold (default: -20%)
   
4. Moving Away Condition:
   - Track price every 5 minutes
   - Check if distance from average INCREASED by >10%
   
5. Stuck Condition:
   - Find oldest position open time
   - Check if stuck > InpTrapStuckMinutes (default: 30)
   - AND DD still < -15%

LOGIC:
- Count how many conditions are TRUE
- If count >= InpTrapConditionsRequired (default: 3) → TRAP DETECTED
- Log all condition states for debugging
- Set trapState.detected = true on first detection

INTEGRATION:
- GridBasket creates TrapDetector instance in constructor
- GridBasket calls DetectTrapConditions() in Update()
- If detected → GridBasket.HandleTrapDetected()

Please implement this class with comprehensive logging and error handling.
11.4 Quick Exit Mode Implementation Prompt
Implement Quick Exit Mode in GridBasket.mqh.

REQUIREMENTS:

1. ACTIVATION:
   - Called from HandleTrapDetected() when trap confirmed
   - Backup original target: m_originalTarget = m_targetCycleUSD
   - Calculate quick exit target based on mode:
     * QE_FIXED: Use InpQuickExitLoss directly (-$10)
     * QE_PERCENTAGE: currentDD * InpQuickExitPercentage (30%)
     * QE_DYNAMIC: Dynamic based on DD severity
   - Set m_targetCycleUSD = quickExitTarget (NEGATIVE VALUE!)
   - Optionally close far positions (if InpQuickExitCloseFar)
   - Recalculate TP price (will be much closer to current)
   - Set state = GRID_STATE_QUICK_EXIT
   - Log activation with details

2. TP CALCULATION WITH NEGATIVE TARGET:
   - Modify ComputeGroupTPPrice() to handle negative targets
   - Formula remains same: (tp - avg) * pointValue * volume = target + fees
   - For SELL with target -$10 and avg 1.1025:
     * TP will be slightly above avg (e.g., 1.1035)
   - Add debug logging when in quick exit mode

3. MONITORING:
   - In Update(), if state == QUICK_EXIT:
     * Check if currentPnL >= quickExitTarget
     * If YES → Close all positions, deactivate, reseed
     * If NO → Check timeout
   - Timeout after InpQuickExitTimeoutMinutes (default: 60)
   - On timeout → Deactivate, restore original target

4. DEACTIVATION:
   - Restore m_targetCycleUSD = m_originalTarget
   - Recalculate TP price
   - Set state back to ACTIVE or appropriate state
   - Log deactivation

5. INTEGRATION WITH LIFECYCLE:
   - When opposite basket closes in LifecycleController:
     * Check if this basket in quick exit mode
     * If YES → Apply x2 multiplier to profit reduction
     * Example: BUY profit $50 → reduce SELL target by $100

NEW FUNCTIONS:
- ActivateQuickExitMode()
- CalculateQuickExitTarget()
- CheckQuickExitTP()
- DeactivateQuickExitMode()

EDGE CASES:
- What if TP hit gives profit instead of loss? → Still close, take profit
- What if timeout during high DD? → Deactivate, return to normal targeting
- What if trap re-detected after deactivation? → Can reactivate

Please implement with extensive logging for debugging.
11.5 Gap Management Implementation Prompt
Implement Gap Management functions in GridBasket.mqh.

REQUIREMENTS:

1. CALCULATE GAP SIZE:
   - Get all position prices
   - Sort by price
   - Find largest distance between consecutive positions
   - Return in pips

2. FILL BRIDGE LEVELS:
   - Triggered when gap 200-400 pips
   - Calculate how many levels fit in gap (based on spacing)
   - Limit to InpMaxBridgeLevels (default: 5)
   - Place pending orders to "bridge" the gap
   - Example:
     * Last filled: L2 @ 1.1100
     * Current price: 1.1300
     * Gap: 200 pips
     * Spacing: 50 pips
     * Bridge: Place L3@1.1150, L4@1.1200, L5@1.1250

3. CLOSE FAR POSITIONS:
   - Triggered when gap > 400 pips
   - Identify positions > InpMaxPositionDistance from current price
   - Calculate total loss if closed
   - If loss acceptable (< InpMaxAcceptableLoss) → close them
   - If not acceptable → keep, set state WAITING_REVERSAL
   - After closing, recalculate basket metrics
   - If remaining positions < 2 → trigger reseed

4. RESEED BASKET:
   - Close all remaining positions
   - Reset all metrics (average, volume, levels)
   - Seed fresh basket at CURRENT PRICE
   - Start with initial warm levels again
   - Log reseed event

5. PRICE VALIDATION:
   - Before placing any pending:
     * Check if price makes sense (BUY below, SELL above current)
     * Check distance not too far (< InpMaxLevelDistance)
     * Return bool for validity

INTEGRATION:
- Call CalculateGapSize() in Update()
- Decision tree:
  * Gap < 150 → Normal operation
  * Gap 150-200 → Monitor
  * Gap 200-400 → Fill bridge
  * Gap > 400 → Close far positions

NEW FUNCTIONS:
- CalculateGapSize()
- FillBridgeLevels()
- CloseFarPositions()
- ReseedBasket()
- IsPriceReasonable(double pendingPrice, double currentPrice)

LOGGING:
- Log gap size on detection
- Log each bridge level placed
- Log positions closed (with loss amount)
- Log reseed trigger

Please implement with careful price validation and error handling.
11.6 Integration & Testing Prompt
Integrate all components and create comprehensive test scenarios.

INTEGRATION TASKS:

1. LIFECYCLE CONTROLLER:
   - Ensure Update() calls both baskets independently
   - Handle basket closures:
     * Get profit from closed basket
     * Check if opposite basket in quick exit
     * If YES → multiply profit by 2 before reducing target
     * If NO → normal profit reduction
     * Reseed closed basket
   - Implement CheckGlobalRisk():
     * Monitor if both baskets trapped
     * Emergency protocol if both deep in DD
     * Close worse basket, keep better one

2. MAIN EA FILE:
   - Add performance logging (hourly)
   - Display basket states
   - Track trap detections and quick exits per day
   - Success rate metrics

3. INPUT PARAMETERS:
   - Add all new inputs to Params.mqh
   - Group logically (Lazy Grid, Trap Detection, Quick Exit, Gap Management)
   - Set sensible defaults

TESTING SCENARIOS:

Test 1: Normal Range Market
- Expected: Lazy fill works, no traps, normal TP closures

Test 2: Strong Uptrend (300 pips)
- Expected: SELL halted, trap detected, quick exit successful

Test 3: Gap + Sideways
- Expected: Bridge fill, average improves, TP hit

Test 4: Both Baskets Trapped
- Expected: Both quick exit, first to escape helps second

Test 5: Grid Full
- Expected: State GRID_FULL, wait for opposite rescue

FOR EACH TEST:
- Document setup (parameters, initial price)
- Document expected behavior at each step
- Document actual results
- Compare DD: old system vs new system
- Compare recovery time

REGRESSION TESTS:
- Verify existing functionality still works:
  * Preset manager
  * News filter
  * Trend filter
  * Spacing engine
  * Order executor

VALIDATION:
- Run on Strategy Tester: 3 months backtest
- Compare metrics:
  * Max DD: target 50-70% reduction
  * Win rate: target improvement
  * Recovery speed: target 3-5x faster
  * Number of traps escaped: track

Please create test plan document and implementation checklist.
11.7 Documentation & Deployment Prompt
Create comprehensive documentation for the enhanced EA.

REQUIRED DOCUMENTS:

1. USER GUIDE:
   - What's new: Lazy Grid Fill, Trap Detection, Quick Exit
   - Parameter explanations with examples
   - Recommended settings for different:
     * Account sizes
     * Symbols (EUR, XAU, GBP, JPY)
     * Risk appetites (conservative, balanced, aggressive)
   - Common scenarios and expected behavior
   - Troubleshooting guide

2. TECHNICAL DOCUMENTATION:
   - Architecture diagrams (already provided in this plan)
   - State machine documentation
   - Function reference
   - Event logging format
   - Integration points for future enhancements

3. TESTING REPORT:
   - Test scenarios executed
   - Results summary
   - Performance metrics comparison
   - Edge cases discovered
   - Known limitations

4. DEPLOYMENT CHECKLIST:
   - Pre-deployment verification
   - Parameter recommendations
   - Monitoring setup
   - Rollback procedure if needed

5. CHANGELOG:
   - Version: 3.1.0
   - Release date
   - New features
   - Breaking changes (if any)
   - Migration guide from 3.0.0

6. FAQ:
   - Q: Will this work with my existing positions?
   - Q: What if I have custom parameters?
   - Q: Can I disable lazy fill and use old dynamic grid?
   - Q: What's the expected DD reduction?
   - Q: How often should I expect quick exits?

DEPLOYMENT STEPS:
1. Backup current version
2. Compile new version
3. Test on Strategy Tester (mandatory)
4. Deploy to demo account (2 weeks minimum)
5. Monitor metrics daily
6. If successful → deploy to live (small lot)
7. Gradually increase lot size

Please create all documentation with clear examples and screenshots where applicable.