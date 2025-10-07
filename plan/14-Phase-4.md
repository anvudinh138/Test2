14. STEP-BY-STEP IMPLEMENTATION CHECKLIST
Phase 4: LifecycleController Integration (Day 8-9)
☐ Task 4.1: Update LifecycleController::Update()
File: src/core/LifecycleController.mqh
cpp//+------------------------------------------------------------------+
//| Main update - ENHANCED VERSION                                    |
//+------------------------------------------------------------------+
void CLifecycleController::Update()
{
    // Update both baskets independently
    m_buyBasket.Update();
    m_sellBasket.Update();
    
    // Handle basket closures
    HandleBasketClosures();
    
    // Check for global risk
    CheckGlobalRisk();
    
    // Performance tracking
    UpdatePerformanceMetrics();
}

//+------------------------------------------------------------------+
//| Handle basket closures with profit redistribution                |
//+------------------------------------------------------------------+
void CLifecycleController::HandleBasketClosures()
{
    // Check BUY basket TP
    if(m_buyBasket.IsTPHit())
    {
        double profit = m_buyBasket.CloseAll();
        
        Print("💰 BUY BASKET CLOSED");
        Print("   Realized profit: $", profit);
        
        // Check if SELL basket in quick exit mode
        if(m_sellBasket.IsInQuickExitMode())
        {
            // Apply x2 multiplier to help SELL escape faster
            double helpAmount = profit * 2.0;
            m_sellBasket.ReduceTargetBy(helpAmount);
            
            Print("   ✅ SELL in quick exit - Applied x2 help: $", helpAmount);
        }
        else
        {
            // Normal profit reduction
            m_sellBasket.ReduceTargetBy(profit);
            Print("   ✅ SELL target reduced by: $", profit);
        }
        
        // Reseed BUY basket
        m_buyBasket.ReseedBasket();
        
        Print("   🔄 BUY basket reseeded");
        
        // Log cycle
        m_cycleCount++;
        m_sessionProfit += profit;
        m_logger.Log("BASKET_CLOSED_TP", DIR_BUY, StringFormat("Profit: $%.2f", profit));
    }
    
    // Check SELL basket TP (same logic)
    if(m_sellBasket.IsTPHit())
    {
        double profit = m_sellBasket.CloseAll();
        
        Print("💰 SELL BASKET CLOSED");
        Print("   Realized profit: $", profit);
        
        if(m_buyBasket.IsInQuickExitMode())
        {
            double helpAmount = profit * 2.0;
            m_buyBasket.ReduceTargetBy(helpAmount);
            Print("   ✅ BUY in quick exit - Applied x2 help: $", helpAmount);
        }
        else
        {
            m_buyBasket.ReduceTargetBy(profit);
            Print("   ✅ BUY target reduced by: $", profit);
        }
        
        m_sellBasket.ReseedBasket();
        Print("   🔄 SELL basket reseeded");
        
        m_cycleCount++;
        m_sessionProfit += profit;
        m_logger.Log("BASKET_CLOSED_TP", DIR_SELL, StringFormat("Profit: $%.2f", profit));
    }
}

//+------------------------------------------------------------------+
//| Check for global risk situations                                  |
//+------------------------------------------------------------------+
void CLifecycleController::CheckGlobalRisk()
{
    // Check if both baskets in trouble
    bool buyInTrouble = (m_buyBasket.GetState() == GRID_STATE_QUICK_EXIT ||
                        m_buyBasket.GetState() == GRID_STATE_HALTED ||
                        m_buyBasket.GetState() == GRID_STATE_GRID_FULL);
    
    bool sellInTrouble = (m_sellBasket.GetState() == GRID_STATE_QUICK_EXIT ||
                         m_sellBasket.GetState() == GRID_STATE_HALTED ||
                         m_sellBasket.GetState() == GRID_STATE_GRID_FULL);
    
    if(buyInTrouble && sellInTrouble)
    {
        // Both baskets struggling
        double buyPnL = m_buyBasket.GetFloatingPnL();
        double sellPnL = m_sellBasket.GetFloatingPnL();
        double totalPnL = buyPnL + sellPnL;
        
        static datetime lastGlobalRiskLog = 0;
        if(TimeCurrent() - lastGlobalRiskLog > 300)  // Log every 5 min
        {
            Print("🚨 GLOBAL RISK WARNING");
            Print("   Both baskets in trouble");
            Print("   BUY state: ", EnumToString(m_buyBasket.GetState()), " | PnL: $", buyPnL);
            Print("   SELL state: ", EnumToString(m_sellBasket.GetState()), " | PnL: $", sellPnL);
            Print("   Total floating: $", totalPnL);
            
            lastGlobalRiskLog = TimeCurrent();
        }
        
        // Emergency protocol if total DD exceeds threshold
        if(totalPnL < -InpSessionSL_USD * 0.5)  // 50% of session SL
        {
            Print("🚨🚨 EMERGENCY PROTOCOL TRIGGERED");
            Print("   Total PnL: $", totalPnL, " (threshold: $", -InpSessionSL_USD * 0.5, ")");
            
            HandleEmergency(buyPnL, sellPnL);
        }
    }
    
    // Check session-level SL
    CheckSessionSL();
}

//+------------------------------------------------------------------+
//| Handle emergency situation                                        |
//+------------------------------------------------------------------+
void CLifecycleController::HandleEmergency(double buyPnL, double sellPnL)
{
    Print("   Emergency decision: Close worst basket");
    
    // Close the basket with worse DD
    if(buyPnL < sellPnL)
    {
        Print("   🗑️ Closing BUY basket (worse DD: $", buyPnL, ")");
        
        double realizedLoss = m_buyBasket.CloseAll();
        Print("   Realized loss: $", realizedLoss);
        
        // Reseed BUY
        m_buyBasket.ReseedBasket();
        
        m_logger.Log("EMERGENCY_CLOSE", DIR_BUY, StringFormat("Loss: $%.2f", realizedLoss));
    }
    else
    {
        Print("   🗑️ Closing SELL basket (worse DD: $", sellPnL, ")");
        
        double realizedLoss = m_sellBasket.CloseAll();
        Print("   Realized loss: $", realizedLoss);
        
        // Reseed SELL
        m_sellBasket.ReseedBasket();
        
        m_logger.Log("EMERGENCY_CLOSE", DIR_SELL, StringFormat("Loss: $%.2f", realizedLoss));
    }
    
    Print("   ✅ Emergency handled - Continue with remaining basket");
}

//+------------------------------------------------------------------+
//| Check session-level stop loss (backup safety)                     |
//+------------------------------------------------------------------+
void CLifecycleController::CheckSessionSL()
{
    if(InpSessionSL_USD <= 0) return;  // Disabled
    
    double totalPnL = m_buyBasket.GetFloatingPnL() + m_sellBasket.GetFloatingPnL();
    
    if(totalPnL < -InpSessionSL_USD)
    {
        Print("🚨🚨 SESSION SL HIT");
        Print("   Total PnL: $", totalPnL);
        Print("   Session SL: $", -InpSessionSL_USD);
        Print("   STOPPING ALL TRADING");
        
        // Close both baskets
        m_buyBasket.CloseAll();
        m_sellBasket.CloseAll();
        
        // Set emergency state
        m_buyBasket.SetState(GRID_STATE_EMERGENCY);
        m_sellBasket.SetState(GRID_STATE_EMERGENCY);
        
        m_sessionState = SESSION_STOPPED;
        
        m_logger.Log("SESSION_SL_HIT", DIR_BUY, StringFormat("Total PnL: $%.2f", totalPnL));
        
        // Alert user
        Alert("SESSION SL HIT! Total PnL: $", totalPnL, " - Trading stopped");
    }
}

//+------------------------------------------------------------------+
//| Update performance metrics                                        |
//+------------------------------------------------------------------+
void CLifecycleController::UpdatePerformanceMetrics()
{
    static datetime lastUpdate = 0;
    
    if(TimeCurrent() - lastUpdate < 3600) return;  // Update hourly
    
    double buyPnL = m_buyBasket.GetFloatingPnL();
    double sellPnL = m_sellBasket.GetFloatingPnL();
    double totalPnL = buyPnL + sellPnL;
    
    Print("===== PERFORMANCE METRICS =====");
    Print("Session profit: $", m_sessionProfit);
    Print("Cycles completed: ", m_cycleCount);
    
    Print("BUY Basket:");
    Print("  State: ", EnumToString(m_buyBasket.GetState()));
    Print("  Positions: ", m_buyBasket.GetPositionCount());
    Print("  Floating: $", buyPnL);
    Print("  DD%: ", m_buyBasket.GetDDPercent(), "%");
    Print("  Gap: ", m_buyBasket.CalculateGapSize(), " pips");
    
    Print("SELL Basket:");
    Print("  State: ", EnumToString(m_sellBasket.GetState()));
    Print("  Positions: ", m_sellBasket.GetPositionCount());
    Print("  Floating: $", sellPnL);
    Print("  DD%: ", m_sellBasket.GetDDPercent(), "%");
    Print("  Gap: ", m_sellBasket.CalculateGapSize(), " pips");
    
    Print("Total Floating: $", totalPnL);
    Print("==============================");
    
    lastUpdate = TimeCurrent();
}
Verification:
✅ Both baskets update independently
✅ Profit redistribution working
✅ x2 multiplier for quick exit help
✅ Global risk monitoring active
✅ Emergency protocol defined