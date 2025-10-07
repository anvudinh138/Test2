14. STEP-BY-STEP IMPLEMENTATION CHECKLIST

Phase 3: GridBasket Modifications (Day 5-7)
☐ Task 3.1: Add Members to GridBasket
File: src/core/GridBasket.mqh (add to class definition)
cppclass CGridBasket
{
private:
    // ... existing members ...
    
    // NEW: Lazy grid fill tracking
    SGridState          m_gridStateTracking;
    ENUM_GRID_STATE     m_state;            // Current state
    
    // NEW: Trap detection
    CTrapDetector*      m_trapDetector;
    
    // NEW: Quick exit mode
    bool                m_quickExitMode;
    double              m_quickExitTarget;
    double              m_originalTarget;
    datetime            m_quickExitStartTime;
    
    // NEW: State timing
    datetime            m_haltTime;
    datetime            m_stateChangeTime;
    
public:
    // ... existing methods ...
    
    // NEW: Lazy grid fill methods
    void SeedInitialGrid();
    void OnLevelFilled(int level);
    bool CheckForNextLevel();
    bool ShouldExpandGrid();
    void PlaceNextPendingOrder();
    int GetLastFilledLevel() const { return m_gridStateTracking.lastFilledLevel; }
    double GetLevelPrice(int level);
    
    // NEW: Trap handling
    void HandleTrapDetected();
    
    // NEW: Quick exit methods
    void ActivateQuickExitMode();
    void DeactivateQuickExitMode();
    void CheckQuickExitTP();
    double CalculateQuickExitTarget();
    bool IsInQuickExitMode() const { return m_quickExitMode; }
    
    // NEW: Gap management
    double CalculateGapSize();
    void FillBridgeLevels();
    void CloseFarPositions();
    bool IsPriceReasonable(double pendingPrice, double currentPrice);
    
    // NEW: Reseed
    void ReseedBasket();
    
    // NEW: State management
    ENUM_GRID_STATE GetState() const { return m_state; }
    void SetState(ENUM_GRID_STATE newState);
    
    // NEW: Position tracking helpers
    datetime GetPositionOpenTime(int index);
    
    // Modified: Update to include new logic
    void Update();
};

☐ Task 3.2: Implement Lazy Grid Fill
File: src/core/GridBasket.mqh
cpp//+------------------------------------------------------------------+
//| Seed initial grid (lazy mode)                                    |
//+------------------------------------------------------------------+
void CGridBasket::SeedInitialGrid()
{
    if(!InpLazyGridEnabled)
    {
        // Fallback to old dynamic grid if disabled
        SeedDynamicGrid();  // Existing method
        return;
    }
    
    Print("🌱 Seeding LAZY grid for ", EnumToString(m_direction));
    
    // Reset tracking
    m_gridStateTracking.Reset();
    m_state = GRID_STATE_ACTIVE;
    
    // 1. Open market order (Level 0)
    double currentPrice = (m_direction == DIR_BUY) ? 
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
                         SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    m_seedPrice = currentPrice;
    
    ulong ticket = OpenMarketOrder();
    
    if(ticket > 0)
    {
        m_gridStateTracking.lastFilledLevel = 0;
        m_gridStateTracking.lastFilledPrice = currentPrice;
        m_gridStateTracking.lastFilledTime = TimeCurrent();
        m_gridStateTracking.currentMaxLevel = 0;
        
        Print("  ├─ Market order L0 @ ", currentPrice);
    }
    else
    {
        Print("  ❌ Failed to open market order!");
        return;
    }
    
    // 2. Place initial pending levels
    for(int i = 1; i <= InpInitialWarmLevels; i++)
    {
        PlaceNextPendingOrder();
    }
    
    Print("  └─ Initial grid: 1 market + ", InpInitialWarmLevels, " pending = ", 
          InpInitialWarmLevels + 1, " levels");
}

//+------------------------------------------------------------------+
//| Called when a level fills                                         |
//+------------------------------------------------------------------+
void CGridBasket::OnLevelFilled(int level)
{
    Print("📍 Level ", level, " filled @ ", GetLevelPrice(level));
    
    // Update tracking
    if(level > m_gridStateTracking.lastFilledLevel)
    {
        m_gridStateTracking.lastFilledLevel = level;
        m_gridStateTracking.lastFilledPrice = GetLevelPrice(level);
        m_gridStateTracking.lastFilledTime = TimeCurrent();
    }
    
    // Check if should expand
    if(!ShouldExpandGrid())
    {
        return;
    }
    
    // Place next level
    PlaceNextPendingOrder();
}

//+------------------------------------------------------------------+
//| Check if grid should expand (guard checks)                        |
//+------------------------------------------------------------------+
bool CGridBasket::ShouldExpandGrid()
{
    // Guard 1: Check state
    if(m_state != GRID_STATE_ACTIVE)
    {
        Print("  ⏸️ State not ACTIVE (", EnumToString(m_state), ") - No expansion");
        return false;
    }
    
    // Guard 2: Trend filter
    if(m_trendFilter != NULL && m_trendFilter.IsEnabled())
    {
        if(m_trendFilter.IsCounterTrend(m_direction))
        {
            Print("  🛑 Counter-trend detected - HALT expansion");
            SetState(GRID_STATE_HALTED);
            m_haltTime = TimeCurrent();
            return false;
        }
    }
    
    // Guard 3: DD threshold
    double dd = GetDDPercent();
    if(dd < InpMaxDDForExpansion)
    {
        Print("  ⚠️ DD threshold breached (", dd, "%) - HALT expansion");
        SetState(GRID_STATE_HALTED);
        m_haltTime = TimeCurrent();
        return false;
    }
    
    // Guard 4: Max levels
    if(m_gridStateTracking.currentMaxLevel >= InpGridLevels)
    {
        Print("  ✋ Max grid levels reached (", InpGridLevels, ")");
        SetState(GRID_STATE_GRID_FULL);
        return false;
    }
    
    // Guard 5: Distance check
    double spacing = m_spacingEngine.ComputeSpacing();
    double nextPrice = CalculateNextLevelPrice(spacing);
    double currentPrice = GetCurrentPrice();
    double distance = MathAbs(currentPrice - nextPrice) / _Point;
    
    if(distance > InpMaxLevelDistance)
    {
        Print("  ⚠️ Next level too far (", distance, " pips) - Skip");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Place next pending order                                          |
//+------------------------------------------------------------------+
void CGridBasket::PlaceNextPendingOrder()
{
    int nextLevel = m_gridStateTracking.currentMaxLevel + 1;
    
    // Calculate price
    double spacing = m_spacingEngine.ComputeSpacing();
    double lastPrice = m_gridStateTracking.lastFilledPrice;
    double nextPrice;
    
    if(m_direction == DIR_BUY)
    {
        nextPrice = lastPrice - (spacing * _Point);
    }
    else
    {
        nextPrice = lastPrice + (spacing * _Point);
    }
    
    // Validate price
    double currentPrice = GetCurrentPrice();
    if(!IsPriceReasonable(nextPrice, currentPrice))
    {
        Print("  ⚠️ Next price unreasonable: ", nextPrice, " (current: ", currentPrice, ")");
        return;
    }
    
    // Calculate lot size
    double lotSize = ComputeLotSize(nextLevel);
    
    // Place order
    ulong ticket = m_executor.PlacePending(m_direction, lotSize, nextPrice, 0, 0, "L" + IntegerToString(nextLevel));
    
    if(ticket > 0)
    {
        m_gridStateTracking.currentMaxLevel = nextLevel;
        m_gridStateTracking.pendingCount++;
        
        Print("  ✅ Placed L", nextLevel, " @ ", nextPrice, " (", lotSize, " lot)");
    }
    else
    {
        Print("  ❌ Failed to place L", nextLevel);
    }
}

//+------------------------------------------------------------------+
//| Calculate next level price                                        |
//+------------------------------------------------------------------+
double CGridBasket::CalculateNextLevelPrice(double spacing)
{
    double lastPrice = m_gridStateTracking.lastFilledPrice;
    
    if(m_direction == DIR_BUY)
    {
        return lastPrice - (spacing * _Point);
    }
    else
    {
        return lastPrice + (spacing * _Point);
    }
}

//+------------------------------------------------------------------+
//| Get level price by index                                          |
//+------------------------------------------------------------------+
double CGridBasket::GetLevelPrice(int level)
{
    if(level == 0) return m_seedPrice;
    
    // Calculate based on spacing
    double spacing = m_spacingEngine.ComputeSpacing();
    
    if(m_direction == DIR_BUY)
    {
        return m_seedPrice - (spacing * _Point * level);
    }
    else
    {
        return m_seedPrice + (spacing * _Point * level);
    }
}

//+------------------------------------------------------------------+
//| Check if price is reasonable for pending order                    |
//+------------------------------------------------------------------+
bool CGridBasket::IsPriceReasonable(double pendingPrice, double currentPrice)
{
    double distance = MathAbs(currentPrice - pendingPrice) / _Point;
    
    // Must be within max distance
    if(distance > InpMaxLevelDistance)
        return false;
    
    if(m_direction == DIR_SELL)
    {
        // SELL pending must be ABOVE current price
        return (pendingPrice > currentPrice);
    }
    else
    {
        // BUY pending must be BELOW current price
        return (pendingPrice < currentPrice);
    }
}
Verification:
✅ Compiles
✅ Seeds 1 market + N pending (N = InpInitialWarmLevels)
✅ Guards prevent expansion when needed
✅ Tracks last filled level correctly

☐ Task 3.3: Implement Quick Exit Mode
File: src/core/GridBasket.mqh
cpp//+------------------------------------------------------------------+
//| Activate quick exit mode                                          |
//+------------------------------------------------------------------+
void CGridBasket::ActivateQuickExitMode()
{
    if(m_quickExitMode)
    {
        Print("  ⚡ Quick exit already active");
        return;
    }
    
    Print("⚡ QUICK EXIT MODE ACTIVATED for ", EnumToString(m_direction));
    
    m_quickExitMode = true;
    m_quickExitStartTime = TimeCurrent();
    
    // Backup original target
    m_originalTarget = m_targetCycleUSD;
    
    // Calculate quick exit target
    m_quickExitTarget = CalculateQuickExitTarget();
    
    double currentPnL = GetFloatingPnL();
    
    Print("   Current PnL: $", currentPnL);
    Print("   Quick exit target: $", m_quickExitTarget);
    
    // Set new target (NEGATIVE!)
    m_targetCycleUSD = m_quickExitTarget;
    
    // Close far positions if enabled
    if(InpQuickExitCloseFar)
    {
        Print("   Closing far positions to accelerate exit...");
        CloseFarPositions();
        RecalculateBasketMetrics();
    }
    
    // Recalculate TP
    m_groupTPPrice = ComputeGroupTPPrice();
    
    double currentPrice = GetCurrentPrice();
    double distanceToTP = MathAbs(currentPrice - m_groupTPPrice) / _Point;
    
    Print("   New TP price: ", m_groupTPPrice);
    Print("   Distance to TP: ", distanceToTP, " pips");
    
    SetState(GRID_STATE_QUICK_EXIT);
    
    // Log event
    m_logger.Log("QUICK_EXIT_MODE_ON", m_direction);
}

//+------------------------------------------------------------------+
//| Calculate quick exit target based on mode                         |
//+------------------------------------------------------------------+
double CGridBasket::CalculateQuickExitTarget()
{
    double currentDD = GetFloatingPnL();
    double ddPercent = GetDDPercent();
    
    switch(InpQuickExitMode)
    {
        case QE_FIXED:
            return InpQuickExitLoss;  // -$10, -$20, etc.
            
        case QE_PERCENTAGE:
            // Accept X% of current DD
            return currentDD * InpQuickExitPercentage;  // e.g., 30% of -$200 = -$60
            
        case QE_DYNAMIC:
            // Dynamic based on DD severity
            if(ddPercent < -30.0)
                return -30.0;  // Heavy DD → larger acceptable loss
            else if(ddPercent < -20.0)
                return -20.0;  // Medium DD
            else
                return -10.0;  // Light DD
    }
    
    return InpQuickExitLoss;  // Default fallback
}

//+------------------------------------------------------------------+
//| Check if quick exit TP hit                                        |
//+------------------------------------------------------------------+
void CGridBasket::CheckQuickExitTP()
{
    if(!m_quickExitMode) return;
    
    double currentPnL = GetFloatingPnL();
    
    // Check if reached target
    if(currentPnL >= m_quickExitTarget)
    {
        Print("✅ QUICK EXIT TARGET REACHED!");
        Print("   Target: $", m_quickExitTarget);
        Print("   Actual: $", currentPnL);
        
        // Close all positions
        double realizedPnL = CloseAllPositions();
        
        Print("   🎯 Escaped trap with PnL: $", realizedPnL);
        
        // Deactivate mode
        DeactivateQuickExitMode();
        
        // Reseed if enabled
        if(InpQuickExitReseed)
        {
            Print("   🔄 Reseeding fresh basket...");
            ReseedBasket();
        }
        
        m_logger.Log("QUICK_EXIT_SUCCESS", m_direction);
        return;
    }
    
    // Check timeout
    int duration = (int)(TimeCurrent() - m_quickExitStartTime);
    if(duration > InpQuickExitTimeoutMinutes * 60)
    {
        Print("⏰ Quick exit timeout (", InpQuickExitTimeoutMinutes, " min) - Deactivate");
        DeactivateQuickExitMode();
    }
}

//+------------------------------------------------------------------+
//| Deactivate quick exit mode                                        |
//+------------------------------------------------------------------+
void CGridBasket::DeactivateQuickExitMode()
{
    if(!m_quickExitMode) return;
    
    Print("🔄 Quick exit mode deactivated for ", EnumToString(m_direction));
    
    m_quickExitMode = false;
    
    // Restore original target
    m_targetCycleUSD = m_originalTarget;
    
    // Recalculate TP
    m_groupTPPrice = ComputeGroupTPPrice();
    
    Print("   Restored target: $", m_targetCycleUSD);
    Print("   New TP: ", m_groupTPPrice);
    
    SetState(GRID_STATE_ACTIVE);
    
    m_logger.Log("QUICK_EXIT_MODE_OFF", m_direction);
}
Verification:
✅ Compiles
✅ Target calculated correctly (negative value)
✅ TP recalculated (closer to current price)
✅ Timeout works
✅ Reseed triggered after exit

☐ Task 3.4: Gap Management Implementation
File: src/core/GridBasket.mqhcpp//+------------------------------------------------------------------+
//| Calculate gap size between positions                              |
//+------------------------------------------------------------------+
double CGridBasket::CalculateGapSize()
{
    int posCount = GetPositionCount();
    if(posCount < 2) return 0;
    
    // Collect all position prices
    CArrayDouble prices;
    
    for(int i = 0; i < posCount; i++)
    {
        double price = GetPositionPrice(i);  // Your method to get position price
        prices.Add(price);
    }
    
    // Sort prices
    prices.Sort();
    
    // Find largest gap between consecutive positions
    double maxGap = 0;
    for(int i = 0; i < prices.Total() - 1; i++)
    {
        double gap = MathAbs(prices[i+1] - prices[i]) / _Point;
        if(gap > maxGap)
        {
            maxGap = gap;
        }
    }
    
    return maxGap;
}

//+------------------------------------------------------------------+
//| Fill bridge levels in gap                                         |
//+------------------------------------------------------------------+
void CGridBasket::FillBridgeLevels()
{
    if(!InpAutoFillBridge) return;
    
    int lastFilled = m_gridStateTracking.lastFilledLevel;
    if(lastFilled < 0) return;
    
    double lastPrice = m_gridStateTracking.lastFilledPrice;
    double currentPrice = GetCurrentPrice();
    double gapPips = MathAbs(currentPrice - lastPrice) / _Point;
    
    if(gapPips < 150)
    {
        // Small gap - normal fill
        PlaceNextPendingOrder();
        return;
    }
    
    Print("🌉 Large gap detected: ", gapPips, " pips - Creating bridge");
    
    double spacing = m_spacingEngine.ComputeSpacing();
    int bridgeLevels = (int)MathMin(gapPips / spacing, InpMaxBridgeLevels);
    
    if(bridgeLevels < 1)
    {
        Print("   Gap too small for bridge (spacing: ", spacing, " pips)");
        return;
    }
    
    Print("   Placing ", bridgeLevels, " bridge levels");
    
    // Place bridge levels
    int successCount = 0;
    for(int i = 1; i <= bridgeLevels; i++)
    {
        int newLevel = lastFilled + i;
        double newPrice;
        
        if(m_direction == DIR_SELL)
        {
            newPrice = lastPrice + (spacing * _Point * i);
        }
        else
        {
            newPrice = lastPrice - (spacing * _Point * i);
        }
        
        // Validate price
        if(!IsPriceReasonable(newPrice, currentPrice))
        {
            Print("   ├─ L", newLevel, " @ ", newPrice, " - Price unreasonable, skip");
            continue;
        }
        
        // Calculate lot size
        double lotSize = ComputeLotSize(newLevel);
        
        // Place pending order
        ulong ticket = m_executor.PlacePending(
            m_direction, 
            lotSize, 
            newPrice, 
            0, 
            0, 
            "Bridge-L" + IntegerToString(newLevel)
        );
        
        if(ticket > 0)
        {
            successCount++;
            Print("   ├─ Bridge L", newLevel, " @ ", newPrice, " ✅");
        }
        else
        {
            Print("   ├─ Bridge L", newLevel, " @ ", newPrice, " ❌ Failed");
        }
    }
    
    if(successCount > 0)
    {
        m_gridStateTracking.currentMaxLevel = lastFilled + successCount;
        Print("   └─ Bridge complete: ", successCount, " levels placed");
    }
    else
    {
        Print("   └─ Bridge failed: No levels placed");
    }
}

//+------------------------------------------------------------------+
//| Close positions that are too far from current price              |
//+------------------------------------------------------------------+
void CGridBasket::CloseFarPositions()
{
    double currentPrice = GetCurrentPrice();
    double threshold = InpMaxPositionDistance;
    
    // Collect far positions
    CArrayObj farPositions;
    int totalCount = GetPositionCount();
    
    for(int i = 0; i < totalCount; i++)
    {
        double posPrice = GetPositionPrice(i);
        double distance = MathAbs(currentPrice - posPrice) / _Point;
        
        if(distance > threshold)
        {
            farPositions.Add(GetPosition(i));  // Assuming you have GetPosition() method
        }
    }
    
    int farCount = farPositions.Total();
    if(farCount == 0)
    {
        Print("   No far positions to close (threshold: ", threshold, " pips)");
        return;
    }
    
    Print("✂️ Closing ", farCount, " far positions (>", threshold, " pips)");
    
    // Calculate total loss if closed
    double totalLoss = 0;
    for(int i = 0; i < farCount; i++)
    {
        CPosition* pos = (CPosition*)farPositions.At(i);
        totalLoss += pos.Profit();
    }
    
    Print("   Potential loss: $", totalLoss);
    
    // Check if loss acceptable
    if(totalLoss < InpMaxAcceptableLoss)
    {
        Print("   ⚠️ Loss exceeds acceptable limit ($", InpMaxAcceptableLoss, ")");
        Print("   Keep positions, set state to WAITING_REVERSAL");
        SetState(GRID_STATE_WAITING_REVERSAL);
        return;
    }
    
    Print("   Loss acceptable - Proceeding with closure");
    
    // Close far positions
    int closedCount = 0;
    double realizedLoss = 0;
    
    for(int i = 0; i < farCount; i++)
    {
        CPosition* pos = (CPosition*)farPositions.At(i);
        double profit = pos.Profit();
        ulong ticket = pos.Ticket();
        
        if(m_executor.ClosePosition(ticket))
        {
            closedCount++;
            realizedLoss += profit;
            Print("   ├─ Closed ticket #", ticket, " | Loss: $", profit);
        }
        else
        {
            Print("   ├─ Failed to close ticket #", ticket);
        }
    }
    
    Print("   └─ Closed ", closedCount, "/", farCount, " positions | Total loss: $", realizedLoss);
    
    // Recalculate basket metrics
    RecalculateBasketMetrics();
    
    int remaining = GetPositionCount();
    Print("✅ Remaining positions: ", remaining);
    Print("   New Average: ", m_averagePrice);
    Print("   New DD: $", GetFloatingPnL());
    
    // Check if need to reseed
    if(remaining < 2)
    {
        Print("🔄 Too few positions remaining - Triggering reseed");
        ReseedBasket();
    }
}

//+------------------------------------------------------------------+
//| Reseed basket from scratch                                        |
//+------------------------------------------------------------------+
void CGridBasket::ReseedBasket()
{
    Print("🔄 RESEEDING BASKET: ", EnumToString(m_direction));
    
    // Close any remaining positions
    int remaining = GetPositionCount();
    if(remaining > 0)
    {
        Print("   Closing ", remaining, " remaining positions...");
        CloseAllPositions();
    }
    
    // Reset all metrics
    m_averagePrice = 0;
    m_totalVolume = 0;
    m_gridStateTracking.Reset();
    m_quickExitMode = false;
    m_quickExitTarget = 0;
    
    // Cancel all pending orders
    CancelAllPendings();
    
    // Get current price for new seed
    double currentPrice = (m_direction == DIR_BUY) ? 
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
                         SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    m_seedPrice = currentPrice;
    
    Print("   New seed price: ", m_seedPrice);
    
    // Seed fresh grid
    SeedInitialGrid();
    
    Print("✅ Reseed complete - Fresh basket ready");
    
    m_logger.Log("RESEED", m_direction);
}

//+------------------------------------------------------------------+
//| Set basket state with logging                                     |
//+------------------------------------------------------------------+
void CGridBasket::SetState(ENUM_GRID_STATE newState)
{
    if(m_state == newState) return;
    
    ENUM_GRID_STATE oldState = m_state;
    m_state = newState;
    m_stateChangeTime = TimeCurrent();
    
    Print("🔄 State change: ", EnumToString(oldState), " → ", EnumToString(newState));
    
    // Log state change
    string details = StringFormat("State: %s -> %s", 
                                 EnumToString(oldState), 
                                 EnumToString(newState));
    m_logger.Log("STATE_CHANGE", m_direction, details);
}

//+------------------------------------------------------------------+
//| Get position open time (helper for trap detector)                |
//+------------------------------------------------------------------+
datetime CGridBasket::GetPositionOpenTime(int index)
{
    if(index < 0 || index >= m_positions.Total())
        return 0;
    
    CPosition* pos = (CPosition*)m_positions.At(index);
    return pos.OpenTime();
}☐ Task 3.5: Update GridBasket::Update() Method
File: src/core/GridBasket.mqhcpp//+------------------------------------------------------------------+
//| Main update function - ENHANCED VERSION                          |
//+------------------------------------------------------------------+
void CGridBasket::Update()
{
    // 1. Update basket metrics (existing)
    UpdateBasketMetrics();
    
    // 2. Detect level fills (NEW - lazy grid logic)
    CheckForLevelFills();
    
    // 3. State-based logic
    switch(m_state)
    {
        case GRID_STATE_ACTIVE:
            // Normal operations
            CheckForNextLevel();
            CheckForTPHit();
            break;
            
        case GRID_STATE_HALTED:
            // Check if can resume
            CheckResumeConditions();
            break;
            
        case GRID_STATE_QUICK_EXIT:
            // Monitor quick exit TP
            CheckQuickExitTP();
            break;
            
        case GRID_STATE_GRID_FULL:
            // Handle grid full
            HandleGridFull();
            break;
            
        case GRID_STATE_WAITING_REVERSAL:
            // Wait for trend reversal
            CheckForReversal();
            break;
            
        case GRID_STATE_WAITING_RESCUE:
            // Waiting for opposite basket TP
            // (Handled by LifecycleController)
            break;
    }
    
    // 4. Trap detection (always running, except in certain states)
    if(m_state == GRID_STATE_ACTIVE || 
       m_state == GRID_STATE_HALTED ||
       m_state == GRID_STATE_GRID_FULL)
    {
        if(m_trapDetector != NULL && m_trapDetector.DetectTrapConditions())
        {
            HandleTrapDetected();
        }
    }
    
    // 5. Gap management
    ManageGap();
    
    // 6. Basket-level stop loss check
    CheckBasketSL();
}

//+------------------------------------------------------------------+
//| Check for level fills (NEW)                                       |
//+------------------------------------------------------------------+
void CGridBasket::CheckForLevelFills()
{
    if(!InpLazyGridEnabled) return;
    
    // Track position count
    static int lastPositionCount = 0;
    int currentPositionCount = GetPositionCount();
    
    if(currentPositionCount > lastPositionCount)
    {
        // New position(s) opened
        int newFills = currentPositionCount - lastPositionCount;
        
        // Determine which level filled
        // (Simple approach: assume sequential filling)
        int newLevel = m_gridStateTracking.lastFilledLevel + newFills;
        
        OnLevelFilled(newLevel);
    }
    
    lastPositionCount = currentPositionCount;
}

//+------------------------------------------------------------------+
//| Check resume conditions when halted                               |
//+------------------------------------------------------------------+
void CGridBasket::CheckResumeConditions()
{
    // Check how long we've been halted
    int haltDuration = (int)(TimeCurrent() - m_haltTime);
    
    // Minimum halt time: 5 minutes
    if(haltDuration < 300) return;
    
    // Check if trend weakened
    bool trendOK = true;
    if(m_trendFilter != NULL && m_trendFilter.IsEnabled())
    {
        if(m_trendFilter.IsCounterTrend(m_direction))
        {
            trendOK = false;
        }
    }
    
    if(trendOK)
    {
        Print("🔄 Trend weakened - Resume grid expansion");
        SetState(GRID_STATE_ACTIVE);
        return;
    }
    
    // If trend still strong after 5 minutes → consider reducing
    if(haltDuration > 300)
    {
        Print("⚠️ Trend persists after 5 min - Checking for reduction");
        
        double gapSize = CalculateGapSize();
        if(gapSize > 300)
        {
            Print("   Large gap detected (", gapSize, " pips) - Reduce far positions");
            SetState(GRID_STATE_REDUCING);
            CloseFarPositions();
        }
    }
}

//+------------------------------------------------------------------+
//| Handle trap detection trigger                                     |
//+------------------------------------------------------------------+
void CGridBasket::HandleTrapDetected()
{
    if(m_quickExitMode)
    {
        Print("   ⚡ Quick exit already active");
        return;
    }
    
    Print("🚨 TRAP HANDLER triggered for ", EnumToString(m_direction));
    
    STrapState trapState = m_trapDetector.GetTrapState();
    
    Print("   Gap: ", trapState.gapSize, " pips");
    Print("   DD: ", trapState.ddAtDetection, "%");
    Print("   Conditions: ", trapState.conditionsMet, "/5");
    
    // Activate quick exit mode
    ActivateQuickExitMode();
}

//+------------------------------------------------------------------+
//| Manage gap - bridge or close far                                  |
//+------------------------------------------------------------------+
void CGridBasket::ManageGap()
{
    double gapSize = CalculateGapSize();
    
    if(gapSize < 150)
    {
        // No action needed
        return;
    }
    
    if(gapSize >= 150 && gapSize < 200)
    {
        // Monitor only
        static datetime lastLog = 0;
        if(TimeCurrent() - lastLog > 3600)  // Log hourly
        {
            Print("📊 Gap detected: ", gapSize, " pips (monitoring)");
            lastLog = TimeCurrent();
        }
        return;
    }
    
    if(gapSize >= 200 && gapSize < 400)
    {
        // Medium gap → Fill bridge
        static datetime lastBridge = 0;
        if(TimeCurrent() - lastBridge > 600)  // Max once per 10 min
        {
            Print("🌉 Medium gap: ", gapSize, " pips - Fill bridge");
            FillBridgeLevels();
            lastBridge = TimeCurrent();
        }
        return;
    }
    
    if(gapSize >= 400)
    {
        // Large gap → Close far positions
        Print("🚨 Large gap: ", gapSize, " pips - Close far positions");
        CloseFarPositions();
    }
}

//+------------------------------------------------------------------+
//| Handle grid full state                                            |
//+------------------------------------------------------------------+
void CGridBasket::HandleGridFull()
{
    Print("⚠️ Grid full handler");
    
    // Check if opposite basket is profitable
    // (This will be called from LifecycleController)
    // For now, just log
    
    static datetime lastLog = 0;
    if(TimeCurrent() - lastLog > 300)  // Log every 5 min
    {
        Print("   Grid full - DD: ", GetDDPercent(), "% | PnL: $", GetFloatingPnL());
        lastLog = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Check for trend reversal when waiting                             |
//+------------------------------------------------------------------+
void CGridBasket::CheckForReversal()
{
    // Check if trend reversed
    if(m_trendFilter != NULL && m_trendFilter.IsEnabled())
    {
        // Check if trend no longer counter to our direction
        if(!m_trendFilter.IsCounterTrend(m_direction))
        {
            Print("🔄 Trend reversal detected - Resume operations");
            SetState(GRID_STATE_ACTIVE);
            return;
        }
    }
    
    // Timeout check (30 minutes max waiting)
    int waitDuration = (int)(TimeCurrent() - m_stateChangeTime);
    if(waitDuration > 1800)
    {
        Print("⏰ Reversal wait timeout - Reseed basket");
        ReseedBasket();
    }
}

//+------------------------------------------------------------------+
//| Check basket-level stop loss                                      |
//+------------------------------------------------------------------+
void CGridBasket::CheckBasketSL()
{
    if(InpBasketSL_USD <= 0) return;  // Disabled
    
    double floatingPnL = GetFloatingPnL();
    
    if(floatingPnL < -InpBasketSL_USD)
    {
        Print("🚨 BASKET SL HIT for ", EnumToString(m_direction));
        Print("   Floating PnL: $", floatingPnL);
        Print("   Basket SL: $", -InpBasketSL_USD);
        Print("   Closing all positions...");
        
        CloseAllPositions();
        
        // Reseed or stop?
        if(InpAutoReseedAfterSL)
        {
            Print("   Auto-reseed enabled - Reseeding...");
            ReseedBasket();
        }
        else
        {
            Print("   Auto-reseed disabled - Basket stopped");
            SetState(GRID_STATE_EMERGENCY);
        }
        
        m_logger.Log("BASKET_SL_HIT", m_direction);
    }
}

//+------------------------------------------------------------------+
//| Modify ComputeGroupTPPrice for negative targets                   |
//+------------------------------------------------------------------+
double CGridBasket::ComputeGroupTPPrice()
{
    if(m_totalVolume <= 0) return 0;
    
    double avg = m_averagePrice;
    double target = m_targetCycleUSD;  // CAN BE NEGATIVE in quick exit!
    
    double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) 
                      / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    double fees = EstimateTotalFees();
    
    // Debug logging for quick exit
    if(m_quickExitMode)
    {
        Print("   [Quick Exit TP Calc]");
        Print("   Avg: ", avg, " | Target: $", target, " | Fees: $", fees);
        Print("   Volume: ", m_totalVolume, " | PointValue: ", pointValue);
    }
    
    if(m_direction == DIR_BUY)
    {
        // BUY: need Bid >= tp_price
        // Formula: (tp - avg) * pointValue * volume = target + fees
        double tp = avg + (target + fees) / (m_totalVolume * pointValue);
        
        if(m_quickExitMode)
        {
            double pipsFromAvg = (tp - avg) / _Point;
            Print("   [BUY TP] ", tp, " (", pipsFromAvg, " pips from avg)");
        }
        
        return NormalizeDouble(tp, _Digits);
    }
    else
    {
        // SELL: need Ask <= tp_price
        // Formula: (avg - tp) * pointValue * volume = target + fees
        double tp = avg - (target + fees) / (m_totalVolume * pointValue);
        
        if(m_quickExitMode)
        {
            double pipsFromAvg = (avg - tp) / _Point;
            Print("   [SELL TP] ", tp, " (", pipsFromAvg, " pips from avg)");
        }
        
        return NormalizeDouble(tp, _Digits);
    }
}Verification:
✅ Update() orchestrates all new logic
✅ State machine working
✅ Trap detection integrated
✅ Gap management integrated
✅ Basket SL enforced