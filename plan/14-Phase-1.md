14. STEP-BY-STEP IMPLEMENTATION CHECKLIST
Phase 1: Foundation Setup (Day 1-2)
☐ Task 1.1: Update Types.mqh
File: src/core/Types.mqh
cpp//+------------------------------------------------------------------+
//| NEW ENUMERATIONS                                                  |
//+------------------------------------------------------------------+

// Grid basket states
enum ENUM_GRID_STATE
{
    GRID_STATE_ACTIVE,          // Normal operation
    GRID_STATE_HALTED,          // Halted due to trend
    GRID_STATE_QUICK_EXIT,      // Quick exit mode active
    GRID_STATE_REDUCING,        // Reducing far positions
    GRID_STATE_GRID_FULL,       // Grid full, no more levels
    GRID_STATE_WAITING_RESCUE,  // Waiting opposite basket TP
    GRID_STATE_WAITING_REVERSAL,// Waiting for trend reversal
    GRID_STATE_EMERGENCY,       // Emergency mode
    GRID_STATE_RESEEDING        // Reseeding basket
};

// Trap conditions (for flagging)
enum ENUM_TRAP_CONDITION
{
    TRAP_COND_NONE = 0,         // No condition
    TRAP_COND_GAP = 1,          // Large gap exists
    TRAP_COND_COUNTER_TREND = 2,// Strong counter-trend
    TRAP_COND_HEAVY_DD = 4,     // Heavy drawdown
    TRAP_COND_MOVING_AWAY = 8,  // Price moving away from avg
    TRAP_COND_STUCK = 16        // Stuck too long without recovery
};

// Quick exit mode
enum ENUM_QUICK_EXIT_MODE
{
    QE_FIXED,                   // Fixed loss amount
    QE_PERCENTAGE,              // % of current DD
    QE_DYNAMIC                  // Dynamic based on DD severity
};

//+------------------------------------------------------------------+
//| NEW STRUCTURES                                                    |
//+------------------------------------------------------------------+

// Trap detection state
struct STrapState
{
    bool detected;              // Trap active?
    datetime detectedTime;      // When detected
    double gapSize;             // Gap in pips
    double ddAtDetection;       // DD when trap detected
    int conditionsMet;          // How many conditions (0-5)
    int conditionFlags;         // Bitwise flags of conditions
    
    // Constructor
    STrapState() : detected(false), detectedTime(0), gapSize(0), 
                   ddAtDetection(0), conditionsMet(0), conditionFlags(0) {}
    
    // Reset
    void Reset()
    {
        detected = false;
        detectedTime = 0;
        gapSize = 0;
        ddAtDetection = 0;
        conditionsMet = 0;
        conditionFlags = 0;
    }
};

// Grid state tracking
struct SGridState
{
    int lastFilledLevel;        // Last level that was filled
    double lastFilledPrice;     // Price of last filled level
    datetime lastFilledTime;    // When last level filled
    int currentMaxLevel;        // Current max level placed
    int pendingCount;           // Active pending orders
    
    // Constructor
    SGridState() : lastFilledLevel(-1), lastFilledPrice(0), lastFilledTime(0),
                   currentMaxLevel(0), pendingCount(0) {}
    
    // Reset
    void Reset()
    {
        lastFilledLevel = -1;
        lastFilledPrice = 0;
        lastFilledTime = 0;
        currentMaxLevel = 0;
        pendingCount = 0;
    }
};

// Quick exit configuration
struct SQuickExitConfig
{
    double targetLoss;          // Target loss (-$10, -$20)
    bool closeFarPositions;     // Close far positions?
    bool autoReseed;            // Reseed after exit?
    int timeoutMinutes;         // Timeout for mode
    ENUM_QUICK_EXIT_MODE mode;  // Exit mode
    
    // Constructor
    SQuickExitConfig() : targetLoss(-10.0), closeFarPositions(true),
                        autoReseed(true), timeoutMinutes(60), mode(QE_FIXED) {}
};
Verification:
✅ Compile Types.mqh without errors
✅ All enums accessible
✅ All structs have proper constructors

☐ Task 1.2: Update Params.mqh
File: src/core/Params.mqh
cpp//+------------------------------------------------------------------+
//| INPUT PARAMETERS - LAZY GRID FILL                                |
//+------------------------------------------------------------------+
input group "=== Lazy Grid Fill ==="
input bool   InpLazyGridEnabled = true;           // Enable lazy grid fill
input int    InpInitialWarmLevels = 1;            // Initial pending levels (1-3)
input int    InpMaxLevelDistance = 500;           // Max distance to next level (pips)
input double InpMaxDDForExpansion = -20.0;        // Stop expanding if DD < this (%)

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - TRAP DETECTION                                |
//+------------------------------------------------------------------+
input group "=== Trap Detection ==="
input bool   InpTrapDetectionEnabled = true;      // Enable trap detection
input double InpTrapGapThreshold = 200.0;         // Gap threshold (pips)
input double InpTrapDDThreshold = -20.0;          // DD threshold (%)
input int    InpTrapConditionsRequired = 3;       // Min conditions to trigger (3/5)
input int    InpTrapStuckMinutes = 30;            // Minutes to consider "stuck"

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - QUICK EXIT MODE                               |
//+------------------------------------------------------------------+
input group "=== Quick Exit Mode ==="
input bool   InpQuickExitEnabled = true;          // Enable quick exit
input ENUM_QUICK_EXIT_MODE InpQuickExitMode = QE_FIXED;  // Exit mode
input double InpQuickExitLoss = -10.0;            // Fixed loss amount ($)
input double InpQuickExitPercentage = 0.30;       // Percentage mode (30% of DD)
input bool   InpQuickExitCloseFar = true;         // Close far positions in quick exit
input bool   InpQuickExitReseed = true;           // Auto reseed after exit
input int    InpQuickExitTimeoutMinutes = 60;     // Timeout (minutes)

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - GAP MANAGEMENT                                |
//+------------------------------------------------------------------+
input group "=== Gap Management ==="
input bool   InpAutoFillBridge = true;            // Auto fill bridge levels
input int    InpMaxBridgeLevels = 5;              // Max bridge levels per gap
input double InpMaxPositionDistance = 300.0;      // Max distance for position (pips)
input double InpMaxAcceptableLoss = -100.0;       // Max loss to abandon trapped ($)

//+------------------------------------------------------------------+
//| INPUT PARAMETERS - BASKET MANAGEMENT                             |
//+------------------------------------------------------------------+
input group "=== Basket SL/TP ==="
input double InpBasketSL_USD = 100.0;             // Basket stop loss ($, 0=disabled)
input bool   InpAutoReseedAfterSL = true;         // Auto reseed after SL hit
Verification:
✅ All inputs compile
✅ Grouped logically
✅ Sensible default values
✅ Comments clear

