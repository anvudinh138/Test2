8. FLOWCHARTS
8.1 Main Update Flow
mermaidflowchart TD
    Start([OnTick]) --> NewsCheck{News Filter<br/>Paused?}
    NewsCheck -->|Yes| End([Return])
    NewsCheck -->|No| UpdateLC[Update LifecycleController]
    
    UpdateLC --> UpdateBuy[Update BUY Basket]
    UpdateLC --> UpdateSell[Update SELL Basket]
    
    UpdateBuy --> CheckBuyTP{BUY TP Hit?}
    CheckBuyTP -->|Yes| CloseBuy[Close BUY Basket]
    CloseBuy --> CheckSellQE{SELL in<br/>Quick Exit?}
    CheckSellQE -->|Yes| HelpSellx2[Reduce SELL target x2]
    CheckSellQE -->|No| HelpSell[Reduce SELL target]
    HelpSellx2 --> ReseedBuy[Reseed BUY]
    HelpSell --> ReseedBuy
    
    CheckBuyTP -->|No| CheckSellTP
    ReseedBuy --> CheckSellTP
    
    UpdateSell --> CheckSellTP{SELL TP Hit?}
    CheckSellTP -->|Yes| CloseSell[Close SELL Basket]
    CloseSell --> CheckBuyQE{BUY in<br/>Quick Exit?}
    CheckBuyQE -->|Yes| HelpBuyx2[Reduce BUY target x2]
    CheckBuyQE -->|No| HelpBuy[Reduce BUY target]
    HelpBuyx2 --> ReseedSell[Reseed SELL]
    HelpBuy --> ReseedSell
    
    CheckSellTP -->|No| GlobalRisk
    ReseedSell --> GlobalRisk
    
    GlobalRisk[Check Global Risk] --> End
8.2 Grid Basket Update Flow
mermaidflowchart TD
    Start([Basket Update]) --> UpdateMetrics[Update Basket Metrics]
    UpdateMetrics --> StateSwitch{Current State?}
    
    StateSwitch -->|ACTIVE| CheckNewLevel[Check for New Level]
    StateSwitch -->|HALTED| CheckResume[Check Resume Conditions]
    StateSwitch -->|QUICK_EXIT| CheckQETP[Check Quick Exit TP]
    StateSwitch -->|GRID_FULL| HandleFull[Handle Grid Full]
    
    CheckNewLevel --> TrapDetect[Run Trap Detection]
    CheckResume --> TrapDetect
    CheckQETP --> TrapDetect
    HandleFull --> TrapDetect
    
    TrapDetect --> IsTrap{Trap<br/>Detected?}
    IsTrap -->|Yes| ActivateQE[Activate Quick Exit Mode]
    IsTrap -->|No| GapCheck
    
    ActivateQE --> GapCheck[Check Gap Size]
    
    GapCheck --> GapSize{Gap Size?}
    GapSize -->|"< 200 pips"| NormalOps[Continue Normal]
    GapSize -->|"200-400 pips"| BridgeFill[Fill Bridge Levels]
    GapSize -->|"> 400 pips"| CloseFar[Close Far Positions]
    
    CloseFar --> CheckRemaining{Remaining<br/>Positions?}
    CheckRemaining -->|"< 2"| Reseed[Reseed Basket]
    CheckRemaining -->|">= 2"| NormalOps
    
    BridgeFill --> NormalOps
    Reseed --> End([Return])
    NormalOps --> End
8.3 Trap Detection Logic
flowchart TD
    Start([Detect Trap]) --> Enabled{Trap Detection<br/>Enabled?}
    Enabled -->|No| ReturnFalse([Return FALSE])
    Enabled -->|Yes| CheckCond1
    
    CheckCond1[Check: Gap > 200 pips] --> Cond1{Met?}
    Cond1 -->|Yes| Count1[Count = 1]
    Cond1 -->|No| Count0[Count = 0]
    
    Count1 --> CheckCond2
    Count0 --> CheckCond2
    
    CheckCond2[Check: Counter-Trend] --> Cond2{Met?}
    Cond2 -->|Yes| Inc2[Count +1]
    Cond2 -->|No| Skip2[ ]
    
    Inc2 --> CheckCond3
    Skip2 --> CheckCond3
    
    CheckCond3[Check: DD < -20%] --> Cond3{Met?}
    Cond3 -->|Yes| Inc3[Count +1]
    Cond3 -->|No| Skip3[ ]
    
    Inc3 --> CheckCond4
    Skip3 --> CheckCond4
    
    CheckCond4[Check: Moving Away] --> Cond4{Met?}
    Cond4 -->|Yes| Inc4[Count +1]
    Cond4 -->|No| Skip4[ ]
    
    Inc4 --> CheckCond5
    Skip4 --> CheckCond5
    
    CheckCond5[Check: Stuck > 30min] --> Cond5{Met?}
    Cond5 -->|Yes| Inc5[Count +1]
    Cond5 -->|No| Skip5[ ]
    
    Inc5 --> EvalCount
    Skip5 --> EvalCount
    
    EvalCount{Count >=<br/>Required?} -->|Yes| LogTrap[Log Trap Detection]
    EvalCount -->|No| ReturnFalse
    
    LogTrap --> SetState[Set trapState.detected = TRUE]
    SetState --> ReturnTrue([Return TRUE])
8.4 Quick Exit Mode Flow
mermaidflowchart TD
    Start([Quick Exit<br/>Activated]) --> BackupTarget[Backup Original Target]
    BackupTarget --> CalcTarget[Calculate Quick Exit Target]
    
    CalcTarget --> ModeCheck{Exit Mode?}
    ModeCheck -->|FIXED| UseFixed["Target = -$10"]
    ModeCheck -->|PERCENTAGE| UsePercent["Target = DD * 30%"]
    ModeCheck -->|DYNAMIC| UseDynamic["Target = Dynamic<br/>based on DD"]
    
    UseFixed --> SetTarget
    UsePercent --> SetTarget
    UseDynamic --> SetTarget
    
    SetTarget[Set targetCycleUSD] --> CloseFarCheck{Close Far<br/>Enabled?}
    CloseFarCheck -->|Yes| CloseFar[Close Far Positions]
    CloseFarCheck -->|No| RecalcTP
    
    CloseFar --> RecalcMetrics[Recalculate Metrics]
    RecalcMetrics --> RecalcTP[Recalculate TP Price]
    
    RecalcTP --> PrintInfo["Print: New TP closer!"]
    PrintInfo --> SetState[State = QUICK_EXIT]
    
    SetState --> Monitor[Monitor Loop]
    Monitor --> CheckTP{Current PnL >=<br/>Target?}
    
    CheckTP -->|Yes| Success[✅ Target Reached!]
    CheckTP -->|No| CheckTimeout{Timeout?}
    
    Success --> CloseAll[Close All Positions]
    CloseAll --> Deactivate[Deactivate Quick Exit]
    Deactivate --> ReseedCheck{Auto<br/>Reseed?}
    
    ReseedCheck -->|Yes| Reseed[Reseed Basket]
    ReseedCheck -->|No| End([Return])
    
    Reseed --> End
    
    CheckTimeout -->|Yes| TimeoutDeactivate[Timeout - Deactivate]
    CheckTimeout -->|No| Monitor
    
    TimeoutDeactivate --> RestoreTarget[Restore Original Target]
    RestoreTarget --> End
8.5 Lazy Grid Fill Flow
mermaidflowchart TD
    Start([Level Filled]) --> UpdateTrack[Update Last Filled Level]
    UpdateTrack --> ShouldExpand{Should<br/>Expand?}
    
    ShouldExpand --> Guard1{Trend<br/>OK?}
    Guard1 -->|Counter-trend| Halt1[HALT - Counter-trend]
    Guard1 -->|OK| Guard2
    
    Guard2{DD<br/>OK?}
    Guard2 -->|Too deep| Halt2[HALT - DD threshold]
    Guard2 -->|OK| Guard3
    
    Guard3{Max levels<br/>reached?}
    Guard3 -->|Yes| GridFull[State = GRID_FULL]
    Guard3 -->|No| Guard4
    
    Guard4{Distance<br/>reasonable?}
    Guard4 -->|Too far| Skip[Skip - Too far]
    Guard4 -->|OK| CalcNext
    
    CalcNext[Calculate Next Level Price] --> CalcSpacing[Get Spacing from Engine]
    CalcSpacing --> ValidatePrice{Price<br/>Reasonable?}
    
    ValidatePrice -->|No| Skip
    ValidatePrice -->|Yes| PlaceOrder[Place Pending Order]
    
    PlaceOrder --> Success{Order<br/>Placed?}
    Success -->|Yes| UpdateMax[Update currentMaxLevel]
    Success -->|No| Error[Log Error]
    
    UpdateMax --> End([Return])
    Error --> End
    Halt1 --> End
    Halt2 --> End
    GridFull --> End
    Skip --> End
8.6 Gap Management Decision Tree
mermaidflowchart TD
    Start([Gap Detected]) --> CalcGap[Calculate Gap Size]
    CalcGap --> GapSize{Gap Size?}
    
    GapSize -->|"< 150 pips"| Normal[Normal Operation]
    GapSize -->|"150-200 pips"| Watch[Monitor - No action yet]
    GapSize -->|"200-400 pips"| Medium[Medium Gap]
    GapSize -->|"> 400 pips"| Large[Large Gap]
    
    Medium --> BridgeCheck{Auto Fill<br/>Bridge?}
    BridgeCheck -->|Yes| CalcBridge[Calculate Bridge Levels]
    BridgeCheck -->|No| Normal
    
    CalcBridge --> BridgeLimit{Levels<br/><= Max?}
    BridgeLimit -->|Yes| PlaceBridge[Place Bridge Levels]
    BridgeLimit -->|No| LimitBridge[Place Max Bridge Levels]
    
    PlaceBridge --> Normal
    LimitBridge --> Normal
    
    Large --> IdentifyFar[Identify Far Positions]
    IdentifyFar --> CheckLoss{Loss<br/>Acceptable?}
    
    CheckLoss -->|Yes| CloseFar[Close Far Positions]
    CheckLoss -->|No| KeepWait[Keep - Wait for reversal]
    
    CloseFar --> RecalcMetrics[Recalculate Metrics]
    RecalcMetrics --> CheckRemaining{Positions<br/>Remaining?}
    
    CheckRemaining -->|"< 2"| Reseed[Reseed Basket]
    CheckRemaining -->|">= 2"| ContinueReduced[Continue with Reduced]
    
    Reseed --> End([Return])
    ContinueReduced --> End
    KeepWait --> SetWaiting[State = WAITING_REVERSAL]
    SetWaiting --> End
    Normal --> End
    Watch --> End
8.7 Complete State Transition Diagram
mermaidstateDiagram-v2
    [*] --> ACTIVE: Initial Seed
    
    ACTIVE --> HALTED: Counter-trend detected
    ACTIVE --> QUICK_EXIT: Trap detected (3/5 conditions)
    ACTIVE --> GRID_FULL: Max levels reached
    ACTIVE --> ACTIVE: Level filled, expand OK
    
    HALTED --> ACTIVE: Trend weakens
    HALTED --> REDUCING: Trend persists > 5 min
    HALTED --> QUICK_EXIT: Trap conditions met
    
    REDUCING --> ACTIVE: Positions >= 2 after reduce
    REDUCING --> RESEEDING: Positions < 2 after reduce
    
    QUICK_EXIT --> RESEEDING: Quick exit TP hit
    QUICK_EXIT --> ACTIVE: Timeout / conditions resolved
    QUICK_EXIT --> QUICK_EXIT: Monitoring TP
    
    GRID_FULL --> WAITING_RESCUE: Opposite basket profitable
    GRID_FULL --> EMERGENCY: Both baskets losing
    GRID_FULL --> HALTED: Trend detected
    
    WAITING_RESCUE --> ACTIVE: Opposite TP hit, target reduced
    WAITING_RESCUE --> EMERGENCY: Wait timeout
    
    EMERGENCY --> REDUCING: Emergency protocol
    
    RESEEDING --> ACTIVE: Fresh basket seeded
    
    ACTIVE --> [*]: Basket TP hit (normal close)
    QUICK_EXIT --> [*]: Quick exit successful
    
    note right of QUICK_EXIT
        Target: -$10 to -$20
        TP much closer
        Close far positions
        Timeout: 60 min
    end note
    
    note right of REDUCING
        Close positions > 250 pips
        Recalculate average
        If < 2 positions → Reseed
    end note
    
    note right of GRID_FULL
        No more levels to place
        Wait for TP or rescue
        Emergency if both baskets full
    end note
