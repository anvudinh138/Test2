7. PSEUDOCODE
7.1 Main Update Loop
FUNCTION OnTick():
    IF NewsFilter.IsTradingPaused():
        RETURN
    END IF
    
    LifecycleController.Update()
END FUNCTION

FUNCTION LifecycleController.Update():
    // Update both baskets independently
    BuyBasket.Update()
    SellBasket.Update()
    
    // Handle basket closures
    IF BuyBasket.IsTPHit():
        profit = BuyBasket.CloseAll()
        
        IF SellBasket.IsInQuickExitMode():
            SellBasket.ReduceTargetBy(profit * 2.0)  // Double help
        ELSE:
            SellBasket.ReduceTargetBy(profit)
        END IF
        
        BuyBasket.ReseedBasket()
    END IF
    
    IF SellBasket.IsTPHit():
        profit = SellBasket.CloseAll()
        
        IF BuyBasket.IsInQuickExitMode():
            BuyBasket.ReduceTargetBy(profit * 2.0)
        ELSE:
            BuyBasket.ReduceTargetBy(profit)
        END IF
        
        SellBasket.ReseedBasket()
    END IF
    
    // Monitor global risk
    CheckGlobalRisk()
END FUNCTION
7.2 Grid Basket Update
FUNCTION GridBasket.Update():
    // Update metrics
    UpdateBasketMetrics()
    
    // State-based logic
    SWITCH state:
        CASE GRID_STATE_ACTIVE:
            CheckForNewLevel()
            CheckForTPHit()
            
        CASE GRID_STATE_HALTED:
            CheckResumeConditions()
            
        CASE GRID_STATE_QUICK_EXIT:
            CheckQuickExitTP()
            
        CASE GRID_STATE_GRID_FULL:
            HandleGridFull()
    END SWITCH
    
    // Trap detection (always running)
    IF TrapDetector.DetectTrapConditions():
        HandleTrapDetected()
    END IF
    
    // Gap management
    gapSize = CalculateGapSize()
    IF gapSize > 200 AND gapSize < 400:
        FillBridgeLevels()
    ELSE IF gapSize >= 400:
        CloseFarPositions()
        IF positionCount < 2:
            ReseedBasket()
        END IF
    END IF
END FUNCTION
7.3 Trap Detection
FUNCTION TrapDetector.DetectTrapConditions():
    IF NOT InpTrapDetectionEnabled:
        RETURN FALSE
    END IF
    
    // Check all 5 conditions
    cond1 = CheckCondition_Gap()            // Gap > 200 pips
    cond2 = CheckCondition_CounterTrend()   // Strong counter-trend
    cond3 = CheckCondition_HeavyDD()        // DD < -20%
    cond4 = CheckCondition_MovingAway()     // Price moving away
    cond5 = CheckCondition_Stuck()          // Stuck > 30 min
    
    // Count met conditions
    conditionsMet = cond1 + cond2 + cond3 + cond4 + cond5
    
    isTrap = (conditionsMet >= InpTrapConditionsRequired)
    
    IF isTrap AND NOT trapState.detected:
        // Log trap detection
        Print("🚨 TRAP DETECTED")
        Print("  Conditions: ", conditionsMet, "/5")
        Print("  Gap: ", gapSize, " pips")
        Print("  DD: ", ddPercent, "%")
        
        trapState.detected = TRUE
        trapState.detectedTime = CurrentTime()
        trapState.conditionsMet = conditionsMet
    END IF
    
    RETURN isTrap
END FUNCTION

FUNCTION CheckCondition_Gap():
    gapSize = CalculateGapSize()
    RETURN (gapSize > InpTrapGapThreshold)
END FUNCTION

FUNCTION CheckCondition_CounterTrend():
    IF NOT TrendFilter.IsEnabled():
        RETURN FALSE
    END IF
    RETURN TrendFilter.IsCounterTrend(direction)
END FUNCTION

FUNCTION CheckCondition_HeavyDD():
    dd = GetDDPercent()
    RETURN (dd < InpTrapDDThreshold)
END FUNCTION

FUNCTION CheckCondition_MovingAway():
    currentPrice = GetCurrentPrice()
    avg = GetAveragePrice()
    
    IF TimeSinceLastCheck < 300 seconds:
        RETURN FALSE  // Need 5 min data
    END IF
    
    lastDistance = ABS(lastPrice - avg)
    currentDistance = ABS(currentPrice - avg)
    
    UpdateLastPrice(currentPrice)
    
    // Distance increased by >10%
    RETURN (currentDistance > lastDistance * 1.1)
END FUNCTION

FUNCTION CheckCondition_Stuck():
    IF positionCount == 0:
        RETURN FALSE
    END IF
    
    oldestTime = FindOldestPositionTime()
    stuckDuration = CurrentTime() - oldestTime
    
    // Stuck > 30 min AND still heavy DD
    RETURN (stuckDuration > 1800 AND GetDDPercent() < -15.0)
END FUNCTION
7.4 Quick Exit Mode
FUNCTION GridBasket.ActivateQuickExitMode():
    IF quickExitMode:
        RETURN  // Already active
    END IF
    
    Print("⚡ QUICK EXIT MODE ACTIVATED")
    
    quickExitMode = TRUE
    quickExitStartTime = CurrentTime()
    
    // Backup original target
    originalTarget = targetCycleUSD
    
    // Calculate quick exit target
    quickExitTarget = CalculateQuickExitTarget()
    
    Print("  Current PnL: $", GetFloatingPnL())
    Print("  Quick exit target: $", quickExitTarget)
    
    // Set new target (negative!)
    targetCycleUSD = quickExitTarget
    
    // Close far positions if enabled
    IF InpQuickExitCloseFar:
        CloseFarPositions()
        RecalculateBasketMetrics()
    END IF
    
    // Recalculate TP (will be much closer!)
    groupTPPrice = ComputeGroupTPPrice()
    
    Print("  New TP: ", groupTPPrice)
    Print("  Distance: ", ABS(currentPrice - groupTPPrice) / point, " pips")
    
    state = GRID_STATE_QUICK_EXIT
END FUNCTION

FUNCTION CalculateQuickExitTarget():
    SWITCH InpQuickExitMode:
        CASE QE_FIXED:
            RETURN InpQuickExitLoss  // -$10, -$20
            
        CASE QE_PERCENTAGE:
            currentDD = GetFloatingPnL()
            RETURN currentDD * InpQuickExitPercentage  // 30% of DD
            
        CASE QE_DYNAMIC:
            ddPercent = GetDDPercent()
            IF ddPercent < -30.0:
                RETURN -30.0
            ELSE IF ddPercent < -20.0:
                RETURN -20.0
            ELSE:
                RETURN -10.0
            END IF
    END SWITCH
END FUNCTION

FUNCTION GridBasket.CheckQuickExitTP():
    IF NOT quickExitMode:
        RETURN
    END IF
    
    currentPnL = GetFloatingPnL()
    
    // Check if reached target
    IF currentPnL >= quickExitTarget:
        Print("✅ QUICK EXIT TARGET REACHED!")
        Print("  Target: $", quickExitTarget)
        Print("  Actual: $", currentPnL)
        
        // Close all positions
        CloseAllPositions()
        
        // Deactivate mode
        DeactivateQuickExitMode()
        
        // Reseed if enabled
        IF InpQuickExitReseed:
            ReseedBasket()
        END IF
        
        RETURN
    END IF
    
    // Check timeout
    duration = CurrentTime() - quickExitStartTime
    IF duration > InpQuickExitTimeoutMinutes * 60:
        Print("⏰ Quick exit timeout")
        DeactivateQuickExitMode()
    END IF
END FUNCTION
7.5 Lazy Grid Fill
FUNCTION GridBasket.SeedInitialGrid():
    // Only seed 1-2 levels initially
    OpenMarketOrder()  // Level 0
    
    FOR i = 1 TO InpInitialWarmLevels:
        PlaceNextPendingOrder()
    END FOR
    
    currentMaxLevel = InpInitialWarmLevels
    lastFilledLevel = 0
    
    Print("✅ Initial grid seeded: ", InpInitialWarmLevels + 1, " levels")
END FUNCTION

FUNCTION GridBasket.OnLevelFilled(level):
    Print("📍 Level ", level, " filled @ ", price)
    
    // Update tracking
    lastFilledLevel = level
    lastFilledPrice = GetLevelPrice(level)
    lastFilledTime = CurrentTime()
    
    // Check if should expand
    IF NOT ShouldExpandGrid():
        RETURN
    END IF
    
    // Place next level
    PlaceNextPendingOrder()
END FUNCTION

FUNCTION GridBasket.ShouldExpandGrid():
    // Guard 1: Trend filter
    IF TrendFilter.IsCounterTrend(direction):
        Print("🛑 Counter-trend - HALT expansion")
        state = GRID_STATE_HALTED
        RETURN FALSE
    END IF
    
    // Guard 2: DD threshold
    IF GetDDPercent() < InpMaxDDForExpansion:
        Print("⚠️ DD threshold - HALT expansion")
        state = GRID_STATE_HALTED
        RETURN FALSE
    END IF
    
    // Guard 3: Max levels
    IF currentMaxLevel >= InpGridLevels:
        Print("✋ Max levels reached")
        state = GRID_STATE_GRID_FULL
        RETURN FALSE
    END IF
    
    // Guard 4: Distance check
    nextPrice = CalculateNextLevelPrice()
    distance = ABS(currentPrice - nextPrice) / point
    
    IF distance > InpMaxLevelDistance:
        Print("⚠️ Next level too far (", distance, " pips)")
        RETURN FALSE
    END IF
    
    RETURN TRUE
END FUNCTION

FUNCTION GridBasket.PlaceNextPendingOrder():
    nextLevel = currentMaxLevel + 1
    spacing = SpacingEngine.ComputeSpacing()
    
    IF direction == DIR_BUY:
        nextPrice = lastFilledPrice - spacing * point
    ELSE:
        nextPrice = lastFilledPrice + spacing * point
    END IF
    
    // Validate price is reasonable
    IF NOT IsPriceReasonable(nextPrice):
        Print("⚠️ Next price unreasonable: ", nextPrice)
        RETURN
    END IF
    
    // Place order
    ticket = OrderExecutor.PlacePending(nextLevel, nextPrice)
    
    IF ticket > 0:
        currentMaxLevel = nextLevel
        Print("✅ Placed L", nextLevel, " @ ", nextPrice)
    END IF
END FUNCTION
7.6 Gap Management
FUNCTION GridBasket.CalculateGapSize():
    IF positionCount < 2:
        RETURN 0
    END IF
    
    // Get all position prices
    prices = []
    FOR each position:
        prices.Add(position.OpenPrice())
    END FOR
    
    // Sort prices
    prices.Sort()
    
    // Find largest gap
    maxGap = 0
    FOR i = 0 TO prices.Count() - 2:
        gap = ABS(prices[i+1] - prices[i]) / point
        IF gap > maxGap:
            maxGap = gap
        END IF
    END FOR
    
    RETURN maxGap
END FUNCTION

FUNCTION GridBasket.FillBridgeLevels():
    IF NOT InpAutoFillBridge:
        RETURN
    END IF
    
    lastFilled = GetLastFilledLevel()
    lastPrice = GetLevelPrice(lastFilled)
    currentPrice = GetCurrentPrice()
    gapPips = ABS(currentPrice - lastPrice) / point
    
    IF gapPips < 150:
        // Small gap - normal fill
        PlaceNextLevel(lastFilled + 1)
        RETURN
    END IF
    
    Print("🌉 Large gap: ", gapPips, " pips - Creating bridge")
    
    spacing = SpacingEngine.ComputeSpacing()
    bridgeLevels = MIN(gapPips / spacing, InpMaxBridgeLevels)
    
    FOR i = 1 TO bridgeLevels:
        newLevel = lastFilled + i
        
        IF direction == DIR_SELL:
            newPrice = lastPrice + (spacing * point * i)
        ELSE:
            newPrice = lastPrice - (spacing * point * i)
        END IF
        
        IF IsPriceReasonable(newPrice, currentPrice):
            PlacePendingOrder(newLevel, newPrice)
            Print("  ├─ Bridge L", newLevel, " @ ", newPrice)
        END IF
    END FOR
    
    currentMaxLevel = lastFilled + bridgeLevels
END FUNCTION

FUNCTION GridBasket.CloseFarPositions():
    currentPrice = GetCurrentPrice()
    threshold = InpMaxPositionDistance
    
    farPositions = []
    
    // Find far positions
    FOR each position:
        distance = ABS(currentPrice - position.OpenPrice()) / point
        IF distance > threshold:
            farPositions.Add(position)
        END IF
    END FOR
    
    IF farPositions.Count() == 0:
        RETURN
    END IF
    
    Print("✂️ Closing ", farPositions.Count(), " far positions")
    
    totalLoss = 0
    FOR each farPosition:
        totalLoss += farPosition.Profit()
        Print("  ├─ Close L", farPosition.Level(), " | Loss: $", farPosition.Profit())
        OrderExecutor.ClosePosition(farPosition.Ticket())
    END FOR
    
    Print("  └─ Total loss: $", totalLoss)
    
    // Recalculate metrics
    RecalculateBasketMetrics()
    
    Print("✅ Remaining: ", positionCount)
    Print("   New Avg: ", averagePrice)
END FUNCTION