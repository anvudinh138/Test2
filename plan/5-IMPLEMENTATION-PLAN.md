5.1 Phase 1: Core Lazy Grid Fill (Week 1)
Task 1.1: Modify GridBasket for Lazy Fill
File: src/core/GridBasket.mqh
Changes:

Add lazy grid tracking members
Implement SeedInitialGrid() - only 1-2 levels
Implement OnLevelFilled() - expand on demand
Implement CheckForNextLevel() - with trend guard

New Functions:
cppclass CGridBasket
{
private:
    // Lazy grid tracking
    SGridState m_gridState;
    
    // New methods
    void SeedInitialGrid();
    void OnLevelFilled(int level);
    bool CheckForNextLevel();
    int GetLastFilledLevel();
    double GetLevelPrice(int level);
    bool IsPriceReasonable(double pendingPrice);
};
Task 1.2: Integrate with Trend Filter
File: src/core/GridBasket.mqh
Changes:

Check trend BEFORE placing each level
Halt expansion if counter-trend detected
Resume expansion when trend weakens

Logic:
cppvoid CGridBasket::OnLevelFilled(int level)
{
    // 1. Check trend FIRST
    if(m_trendFilter.IsCounterTrend(m_direction)) {
        Print("🛑 Counter-trend - HALT expansion");
        m_state = GRID_STATE_HALTED;
        return;
    }
    
    // 2. Check DD threshold
    if(GetDDPercent() < InpMaxDDForExpansion) {
        Print("⚠️ DD threshold - HALT expansion");
        m_state = GRID_STATE_HALTED;
        return;
    }
    
    // 3. OK → Place next level
    PlaceNextPendingOrder();
}
Task 1.3: Testing

Test lazy fill in range market (should expand normally)
Test lazy fill in strong trend (should halt expansion)
Test resume after trend weakens


5.2 Phase 2: Trap Detection System (Week 1-2)
Task 2.1: Create TrapDetector Module
New File: src/core/TrapDetector.mqh
cppclass CTrapDetector
{
private:
    CGridBasket* m_basket;          // Reference to basket
    CTrendFilter* m_trendFilter;    // Reference to trend filter
    STrapState m_trapState;         // Current trap state
    
    // Price tracking for movement detection
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
    
    STrapState GetTrapState() const { return m_trapState; }
    void Reset();
};
Implementation:
cppbool CTrapDetector::DetectTrapConditions()
{
    if(!InpTrapDetectionEnabled) return false;
    
    // Check all 5 conditions
    bool cond1 = CheckCondition_Gap();
    bool cond2 = CheckCondition_CounterTrend();
    bool cond3 = CheckCondition_HeavyDD();
    bool cond4 = CheckCondition_MovingAway();
    bool cond5 = CheckCondition_Stuck();
    
    // Count conditions met
    int count = 0;
    if(cond1) count++;
    if(cond2) count++;
    if(cond3) count++;
    if(cond4) count++;
    if(cond5) count++;
    
    bool isTrap = (count >= InpTrapConditionsRequired);
    
    if(isTrap && !m_trapState.detected) {
        // New trap detected
        m_trapState.detected = true;
        m_trapState.detectedTime = TimeCurrent();
        m_trapState.conditionsMet = count;
        m_trapState.gapSize = m_basket.CalculateGapSize();
        m_trapState.ddAtDetection = m_basket.GetDDPercent();
        
        LogTrapDetection(cond1, cond2, cond3, cond4, cond5);
    }
    
    return isTrap;
}

bool CTrapDetector::CheckCondition_Gap()
{
    double gapSize = m_basket.CalculateGapSize();
    return (gapSize > InpTrapGapThreshold);
}

bool CTrapDetector::CheckCondition_CounterTrend()
{
    if(!m_trendFilter.IsEnabled()) return false;
    return m_trendFilter.IsCounterTrend(m_basket.GetDirection());
}

bool CTrapDetector::CheckCondition_HeavyDD()
{
    double dd = m_basket.GetDDPercent();
    return (dd < InpTrapDDThreshold);
}

bool CTrapDetector::CheckCondition_MovingAway()
{
    double currentPrice = m_basket.GetCurrentPrice();
    double avg = m_basket.GetAveragePrice();
    
    if(TimeCurrent() - m_lastPriceTime < 300) {
        return false;  // Need 5 min data
    }
    
    double lastDistance = MathAbs(m_lastPrice - avg);
    double currentDistance = MathAbs(currentPrice - avg);
    
    m_lastPrice = currentPrice;
    m_lastPriceTime = TimeCurrent();
    
    // Moving away if distance increased by >10%
    return (currentDistance > lastDistance * 1.1);
}

bool CTrapDetector::CheckCondition_Stuck()
{
    if(m_basket.GetPositionCount() == 0) return false;
    
    // Find oldest position
    datetime oldestTime = TimeCurrent();
    for(int i = 0; i < m_basket.GetPositionCount(); i++) {
        CPosition* pos = m_basket.GetPosition(i);
        if(pos.OpenTime() < oldestTime) {
            oldestTime = pos.OpenTime();
        }
    }
    
    int stuckDuration = (int)(TimeCurrent() - oldestTime);
    
    // Stuck > threshold AND still heavy DD
    return (stuckDuration > InpTrapStuckMinutes * 60 && 
            m_basket.GetDDPercent() < -15.0);
}
Task 2.2: Integrate TrapDetector with GridBasket
File: src/core/GridBasket.mqh
Changes:
cppclass CGridBasket
{
private:
    CTrapDetector* m_trapDetector;
    
public:
    void Update()
    {
        // Existing updates...
        UpdateMetrics();
        CheckForTP();
        
        // NEW: Check for trap
        if(m_trapDetector.DetectTrapConditions()) {
            HandleTrapDetected();
        }
    }
    
    void HandleTrapDetected()
    {
        Print("🚨 TRAP DETECTED for ", EnumToString(m_direction));
        STrapState trap = m_trapDetector.GetTrapState();
        Print("   Conditions met: ", trap.conditionsMet, "/5");
        Print("   Gap: ", trap.gapSize, " pips");
        Print("   DD: ", trap.ddAtDetection, "%");
        
        // Activate quick exit mode
        ActivateQuickExitMode();
    }
};
Task 2.3: Testing

Test trap detection with simulated gap scenario
Test false positives (normal DD should NOT trigger)
Test all 5 conditions individually


5.3 Phase 3: Quick Exit Mode (Week 2)
Task 3.1: Implement Quick Exit Logic
File: src/core/GridBasket.mqh
New Members:
cppclass CGridBasket
{
private:
    bool m_quickExitMode;
    double m_quickExitTarget;
    double m_originalTarget;
    datetime m_quickExitStartTime;
    
public:
    void ActivateQuickExitMode();
    void DeactivateQuickExitMode();
    void CheckQuickExitTP();
    double CalculateQuickExitTarget();
};
Implementation:
cppvoid CGridBasket::ActivateQuickExitMode()
{
    if(m_quickExitMode) return;  // Already active
    
    Print("⚡ QUICK EXIT MODE ACTIVATED for ", EnumToString(m_direction));
    
    m_quickExitMode = true;
    m_quickExitStartTime = TimeCurrent();
    
    // Backup original target
    m_originalTarget = m_targetCycleUSD;
    
    // Calculate quick exit target
    m_quickExitTarget = CalculateQuickExitTarget();
    
    Print("   Current PnL: $", GetFloatingPnL());
    Print("   Quick exit target: $", m_quickExitTarget);
    
    // Set new target
    m_targetCycleUSD = m_quickExitTarget;
    
    // Close far positions if enabled
    if(InpQuickExitCloseFar) {
        Print("   Closing far positions to accelerate exit...");
        CloseFarPositions();
        RecalculateBasketMetrics();
    }
    
    // Recalculate TP
    m_groupTPPrice = ComputeGroupTPPrice();
    
    Print("   New TP price: ", m_groupTPPrice);
    Print("   Distance to TP: ", 
          MathAbs(GetCurrentPrice() - m_groupTPPrice) / _Point, " pips");
    
    m_state = GRID_STATE_QUICK_EXIT;
    m_logger.Log("QUICK_EXIT_MODE_ON", m_direction);
}

double CGridBasket::CalculateQuickExitTarget()
{
    switch(InpQuickExitMode)
    {
        case QE_FIXED:
            return InpQuickExitLoss;  // -$10, -$20
            
        case QE_PERCENTAGE:
        {
            double currentDD = GetFloatingPnL();
            return currentDD * InpQuickExitPercentage;  // e.g., 30% of -$200 = -$60
        }
        
        case QE_DYNAMIC:
        {
            double ddPercent = GetDDPercent();
            if(ddPercent < -30.0) return -30.0;
            else if(ddPercent < -20.0) return -20.0;
            else return -10.0;
        }
    }
    
    return InpQuickExitLoss;
}

void CGridBasket::CheckQuickExitTP()
{
    if(!m_quickExitMode) return;
    
    double currentPnL = GetFloatingPnL();
    
    // Check if reached target
    if(currentPnL >= m_quickExitTarget) {
        Print("✅ QUICK EXIT TARGET REACHED!");
        Print("   Target: $", m_quickExitTarget);
        Print("   Actual: $", currentPnL);
        
        // Close all positions
        CloseAllPositions();
        
        Print("   🎯 Escaped trap with loss: $", currentPnL);
        
        // Deactivate mode
        DeactivateQuickExitMode();
        
        // Reseed if enabled
        if(InpQuickExitReseed) {
            Print("   🔄 Reseeding fresh basket...");
            ReseedBasket();
        }
        
        m_logger.Log("QUICK_EXIT_SUCCESS", m_direction);
        return;
    }
    
    // Check timeout
    int duration = (int)(TimeCurrent() - m_quickExitStartTime);
    if(duration > InpQuickExitTimeoutMinutes * 60) {
        Print("⏰ Quick exit timeout - Deactivate");
        DeactivateQuickExitMode();
    }
}

void CGridBasket::DeactivateQuickExitMode()
{
    if(!m_quickExitMode) return;
    
    Print("🔄 Quick exit mode deactivated for ", EnumToString(m_direction));
    
    m_quickExitMode = false;
    m_targetCycleUSD = m_originalTarget;
    m_state = GRID_STATE_ACTIVE;
    
    // Recalculate TP
    m_groupTPPrice = ComputeGroupTPPrice();
    
    m_logger.Log("QUICK_EXIT_MODE_OFF", m_direction);
}
Task 3.2: Update TP Calculation for Negative Targets
File: src/core/GridBasket.mqh
Modify: ComputeGroupTPPrice()
cppdouble CGridBasket::ComputeGroupTPPrice()
{
    if(m_totalVolume <= 0) return 0;
    
    double avg = m_averagePrice;
    double target = m_targetCycleUSD;  // CAN BE NEGATIVE!
    
    double pointValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE) 
                      / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    double fees = EstimateTotalFees();
    
    // Debug logging
    if(m_quickExitMode) {
        Print("   [Quick Exit TP Calc]");
        Print("   Avg: ", avg, " | Target: $", target, " | Fees: $", fees);
    }
    
    if(m_direction == DIR_BUY) {
        // BUY: (tp - avg) * pointValue * volume = target + fees
        double tp = avg + (target + fees) / (m_totalVolume * pointValue);
        
        if(m_quickExitMode) {
            Print("   [BUY TP] ", tp, " (", (tp - avg)/_Point, " pips from avg)");
        }
        
        return NormalizeDouble(tp, _Digits);
    }
    else {
        // SELL: (avg - tp) * pointValue * volume = target + fees
        double tp = avg - (target + fees) / (m_totalVolume * pointValue);
        
        if(m_quickExitMode) {
            Print("   [SELL TP] ", tp, " (", (avg - tp)/_Point, " pips from avg)");
        }
        
        return NormalizeDouble(tp, _Digits);
    }
}
Task 3.3: Testing

Test quick exit activation on trap detection
Test TP hit with negative target (-$10)
Test timeout deactivation
Test reseed after quick exit


5.4 Phase 4: Gap Management (Week 2-3)
Task 4.1: Implement Gap Calculator
File: src/core/GridBasket.mqh
New Functions:
cppclass CGridBasket
{
public:
    double CalculateGapSize();
    void FillBridgeLevels();
    void CloseFarPositions();
    bool IsPriceReasonable(double pendingPrice, double currentPrice);
};
Implementation:
cppdouble CGridBasket::CalculateGapSize()
{
    if(m_positions.Total() < 2) return 0;
    
    // Sort positions by price
    CArrayDouble prices;
    for(int i = 0; i < m_positions.Total(); i++) {
        CPosition* pos = m_positions.At(i);
        prices.Add(pos.OpenPrice());
    }
    prices.Sort();
    
    // Find largest gap between consecutive positions
    double maxGap = 0;
    for(int i = 0; i < prices.Total() - 1; i++) {
        double gap = MathAbs(prices[i+1] - prices[i]) / _Point;
        if(gap > maxGap) {
            maxGap = gap;
        }
    }
    
    return maxGap;
}

void CGridBasket::FillBridgeLevels()
{
    if(!InpAutoFillBridge) return;
    
    int lastFilled = GetLastFilledLevel();
    if(lastFilled < 0) return;
    
    double lastFilledPrice = GetLevelPrice(lastFilled);
    double currentPrice = GetCurrentPrice();
    double gapPips = MathAbs(currentPrice - lastFilledPrice) / _Point;
    
    if(gapPips < 150) {
        // Small gap, normal fill
        PlaceNextLevel(lastFilled + 1);
        return;
    }
    
    Print("🌉 Large gap detected: ", gapPips, " pips - Creating bridge");
    
    double spacing = m_spacingEngine.ComputeSpacing();
    int bridgeLevels = (int)MathMin(gapPips / spacing, InpMaxBridgeLevels);
    
    for(int i = 1; i <= bridgeLevels; i++) {
        int newLevel = lastFilled + i;
        double newPrice;
        
        if(m_direction == DIR_SELL) {
            newPrice = lastFilledPrice + (spacing * _Point * i);
        }
        else {
            newPrice = lastFilledPrice - (spacing * _Point * i);
        }
        
        if(IsPriceReasonable(newPrice, currentPrice)) {
            PlacePendingOrder(newLevel, newPrice);
            Print("  ├─ Bridge L", newLevel, " @ ", newPrice);
        }
    }
    
    m_currentMaxLevel = lastFilled + bridgeLevels;
}

void CGridBasket::CloseFarPositions()
{
    double currentPrice = GetCurrentPrice();
    double threshold = InpMaxPositionDistance;
    
    CArrayObj farPositions;
    
    // Find far positions
    for(int i = 0; i < m_positions.Total(); i++) {
        CPosition* pos = m_positions.At(i);
        double distance = MathAbs(currentPrice - pos.OpenPrice()) / _Point;
        
        if(distance > threshold) {
            farPositions.Add(pos);
        }
    }
    
    if(farPositions.Total() == 0) return;
    
    Print("✂️ Closing ", farPositions.Total(), " far positions (>", threshold, " pips)");
    
    double totalLoss = 0;
    for(int i = 0; i < farPositions.Total(); i++) {
        CPosition* pos = farPositions.At(i);
        totalLoss += pos.Profit();
        
        Print("  ├─ Close L", pos.Level(), " @ ", pos.OpenPrice(), 
              " | Loss: $", pos.Profit());
        
        m_executor.ClosePosition(pos.Ticket());
    }
    
    Print("  └─ Total loss: $", totalLoss);
    
    // Recalculate basket metrics
    RecalculateBasketMetrics();
    
    Print("✅ Remaining positions: ", m_positions.Total());
    Print("   New Average: ", m_averagePrice);
    Print("   New DD: $", GetFloatingPnL());
}

bool CGridBasket::IsPriceReasonable(double pendingPrice, double currentPrice)
{
    double distance = MathAbs(currentPrice - pendingPrice) / _Point;
    
    if(m_direction == DIR_SELL) {
        // SELL pending must be ABOVE current price
        return (pendingPrice > currentPrice) && (distance < InpMaxLevelDistance);
    }
    else {
        // BUY pending must be BELOW current price
        return (pendingPrice < currentPrice) && (distance < InpMaxLevelDistance);
    }
}
Task 4.2: Integrate Gap Management with States
File: src/core/GridBasket.mqh
Add to Update():
cppvoid CGridBasket::Update()
{
    // Existing updates...
    
    // Check gap and manage
    if(m_state == GRID_STATE_ACTIVE || m_state == GRID_STATE_HALTED) {
        double gapSize = CalculateGapSize();
        
        if(gapSize > 200 && gapSize < 400) {
            // Medium gap → Fill bridge
            FillBridgeLevels();
        }
        else if(gapSize >= 400) {
            // Large gap → Close far positions
            Print("🚨 Large gap (", gapSize, " pips) - Closing far positions");
            CloseFarPositions();
            
            if(m_positions.Total() < 2) {
                // Too few positions after closing → Reseed
                Print("🔄 Too few positions - Reseed basket");
                ReseedBasket();
            }
        }
    }
}
Task 4.3: Testing

Test bridge fill with medium gap (200-400 pips)
Test close far positions with large gap (>400 pips)
Test reseed after closing far positions


5.5 Phase 5: Integration & Polish (Week 3)
Task 5.1: Update LifecycleController
File: src/core/LifecycleController.mqh
Changes:

Ensure both baskets update independently
Handle basket closure with profit redistribution
Monitor for global issues (both baskets trapped)

Enhanced Logic:
cppvoid CLifecycleController::Update()
{
    // Update both baskets
    m_buyBasket.Update();
    m_sellBasket.Update();
    
    // Check for basket closures
    if(m_buyBasket.IsTPHit()) {
        double profit = m_buyBasket.CloseAll();
        
        Print("💰 BUY basket closed with profit: $", profit);
        
        // Reduce SELL target
        if(m_sellBasket.IsInQuickExitMode()) {
            // Double the help if SELL in quick exit
            m_sellBasket.ReduceTargetBy(profit * 2.0);
            Print("   ✅ SELL quick exit helped (x2 multiplier)");
        }
        else {
            m_sellBasket.ReduceTargetBy(profit);
            Print("   ✅ SELL target reduced");
        }
        
        // Reseed BUY
        m_buyBasket.ReseedBasket();
    }
    
    if(m_sellBasket.IsTPHit()) {
        double profit = m_sellBasket.CloseAll();
        
        Print("💰 SELL basket closed with profit: $", profit);
        
        if(m_buyBasket.IsInQuickExitMode()) {
            m_buyBasket.ReduceTargetBy(profit * 2.0);
            Print("   ✅ BUY quick exit helped (x2 multiplier)");
        }
        else {
            m_buyBasket.ReduceTargetBy(profit);
            Print("   ✅ BUY target reduced");
        }
        
        m_sellBasket.ReseedBasket();
    }
    
    // Check for global issues
    CheckGlobalRisk();
}

void CLifecycleController::CheckGlobalRisk()
{
    bool buyTrapped = m_buyBasket.IsInQuickExitMode() || 
                     m_buyBasket.GetState() == GRID_STATE_HALTED;
    bool sellTrapped = m_sellBasket.IsInQuickExitMode() || 
                      m_sellBasket.GetState() == GRID_STATE_HALTED;
    
    if(buyTrapped && sellTrapped) {
        Print("🚨 BOTH BASKETS IN TROUBLE");
        
        double totalDD = m_buyBasket.GetFloatingPnL() + 
                        m_sellBasket.GetFloatingPnL();
        
        Print("   Total floating: $", totalDD);
        
        // Emergency protocol if both deep in DD
        if(totalDD < -InpSessionSL_USD * 0.5) {  // 50% of session SL
            Print("   ⚠️ Emergency: Close worst basket");
            
            // Close the basket with worse DD
            if(m_buyBasket.GetDDPercent() < m_sellBasket.GetDDPercent()) {
                Print("   Closing BUY basket (worse DD)");
                m_buyBasket.CloseAll();
                m_buyBasket.ReseedBasket();
            }
            else {
                Print("   Closing SELL basket (worse DD)");
                m_sellBasket.CloseAll();
                m_sellBasket.ReseedBasket();
            }
        }
    }
}
Task 5.2: Add Comprehensive Logging
File: src/core/Logger.mqh
New Events:
cppenum ENUM_LOG_EVENT
{
    // Existing...
    LOG_TRAP_DETECTED,
    LOG_QUICK_EXIT_ON,
    LOG_QUICK_EXIT_OFF,
    LOG_QUICK_EXIT_SUCCESS,
    LOG_BRIDGE_FILL,
    LOG_FAR_POSITIONS_CLOSED,
    LOG_RESEED,
    LOG_EMERGENCY_CLOSE
};

void CLogger::Log(ENUM_LOG_EVENT event, ENUM_BASKET_DIRECTION direction, string details = "")
{
    string timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
    string dirStr = EnumToString(direction);
    string eventStr = EnumToString(event);
    
    string message = StringFormat("[%s] %s | %s | %s", 
                                 timestamp, dirStr, eventStr, details);
    
    // Write to file
    int handle = FileOpen("EA_Log_" + IntegerToString(InpMagic) + ".txt", 
                         FILE_WRITE | FILE_READ | FILE_TXT);
    if(handle != INVALID_HANDLE) {
        FileSeek(handle, 0, SEEK_END);
        FileWriteString(handle, message + "\n");
        FileClose(handle);
    }
    
    // Print to terminal
    Print(message);
}
Task 5.3: Update Main EA File
File: src/ea/RecoveryGridDirection_v3.mq5
Add to OnTick():
cppvoid OnTick()
{
    // News filter check
    if(g_newsFilter != NULL && g_newsFilter.IsTradingPaused()) {
        return;
    }
    
    // Update lifecycle
    if(g_lifecycle != NULL) {
        g_lifecycle.Update();
    }
    
    // Performance monitoring
    static datetime lastLog = 0;
    if(TimeCurrent() - lastLog > 3600) {  // Log every hour
        LogPerformanceMetrics();
        lastLog = TimeCurrent();
    }
}

void LogPerformanceMetrics()
{
    double buyPnL = g_lifecycle.GetBuyBasket().GetFloatingPnL();
    double sellPnL = g_lifecycle.GetSellBasket().GetFloatingPnL();
    double totalPnL = buyPnL + sellPnL;
    
    Print("===== PERFORMANCE METRICS =====");
    Print("BUY Basket:");
    Print("  Positions: ", g_lifecycle.GetBuyBasket().GetPositionCount());
    Print("  Floating: $", buyPnL);
    Print("  State: ", EnumToString(g_lifecycle.GetBuyBasket().GetState()));
    
    Print("SELL Basket:");
    Print("  Positions: ", g_lifecycle.GetSellBasket().GetPositionCount());
    Print("  Floating: $", sellPnL);
    Print("  State: ", EnumToString(g_lifecycle.GetSellBasket().GetState()));
    
    Print("Total Floating: $", totalPnL);
    Print("==============================");
}