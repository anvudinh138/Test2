3. SOLUTION ARCHITECTURE
3.1 Core Components
┌─────────────────────────────────────────────────────────────┐
│                  LIFECYCLE CONTROLLER                        │
│  (Orchestrates BUY + SELL baskets independently)            │
└─────────────────────────────────────────────────────────────┘
                    │                    │
        ┌───────────┴──────────┐  ┌─────┴──────────┐
        │   BUY BASKET         │  │  SELL BASKET    │
        │  (Lazy Grid Fill)    │  │ (Lazy Grid Fill)│
        └──────────────────────┘  └─────────────────┘
                    │                    │
        ┌───────────┴──────────────────┬─┴────────────────┐
        │                              │                  │
   ┌────┴─────┐              ┌────────┴───────┐  ┌──────┴─────┐
   │  TRAP    │              │  QUICK EXIT    │  │    GAP     │
   │ DETECTOR │              │     MODE       │  │  MANAGER   │
   └──────────┘              └────────────────┘  └────────────┘
        │                              │                  │
        └──────────────┬───────────────┴──────────────────┘
                       │
              ┌────────┴─────────┐
              │  TREND FILTER    │
              │  (EMA + ADX)     │
              └──────────────────┘
3.2 Module Interactions
mermaidsequenceDiagram
    participant T as OnTick()
    participant LC as LifecycleController
    participant B as GridBasket
    participant TD as TrapDetector
    participant QE as QuickExitMode
    participant GM as GapManager
    participant TF as TrendFilter

    T->>LC: Update()
    LC->>B: Update()
    
    B->>TD: DetectTrapConditions()
    TD->>TF: IsCounterTrend()
    TF-->>TD: Yes/No
    TD->>B: CalculateGapSize()
    TD->>B: GetDDPercent()
    TD-->>B: TrapDetected: true/false
    
    alt Trap Detected
        B->>QE: ActivateQuickExitMode()
        QE->>B: SetTarget(-$10)
        QE->>GM: CloseFarPositions()
        GM-->>QE: Positions closed
        QE->>B: RecalculateTP()
        B-->>LC: Quick exit active
    else No Trap
        B->>B: CheckForNewLevel()
        B->>TF: IsCounterTrend()
        alt Counter-trend
            TF-->>B: Yes - HALT expansion
        else Trend OK
            TF-->>B: No - Place next level
            B->>B: PlaceNextPendingOrder()
        end
    end
    
    B->>B: CheckTPHit()
    alt TP Hit
        B->>LC: BasketClosed(profit)
        LC->>B: ReduceOppositeTarget(profit)
        LC->>B: ReseedBasket()
    end

3.3 State Machine Diagram
mermaidstateDiagram-v2
    [*] --> ACTIVE: Initial Seed
    
    ACTIVE --> HALTED: Counter-trend detected
    ACTIVE --> QUICK_EXIT: Trap detected
    ACTIVE --> GRID_FULL: Max levels reached
    
    HALTED --> ACTIVE: Trend weakens
    HALTED --> REDUCING: Trend persists (5+ min)
    
    REDUCING --> ACTIVE: After reduce (pos >= 2)
    REDUCING --> RESEEDING: After reduce (pos < 2)
    
    QUICK_EXIT --> CLOSING: TP hit (small loss)
    QUICK_EXIT --> ACTIVE: Timeout / Trap resolved
    
    CLOSING --> RESEEDING: All positions closed
    
    GRID_FULL --> WAITING_RESCUE: Opposite basket in profit
    GRID_FULL --> EMERGENCY_REDUCE: Both baskets losing
    
    EMERGENCY_REDUCE --> RESEEDING: Reduced successfully
    
    WAITING_RESCUE --> ACTIVE: Opposite TP hit
    
    RESEEDING --> ACTIVE: Fresh basket seeded
    
    note right of QUICK_EXIT
        Target: -$10 to -$20
        TP closer than normal
        Close far positions
    end note
    
    note right of REDUCING
        Close positions > 250 pips
        Recalculate average
        Continue with remainder
    end note