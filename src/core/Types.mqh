//+------------------------------------------------------------------+
//| Project: Recovery Grid Direction v2                              |
//| Purpose: Shared enums and POD structures                         |
//+------------------------------------------------------------------+
#ifndef __RGD_V2_TYPES_MQH__
#define __RGD_V2_TYPES_MQH__

enum EDirection
  {
   DIR_BUY  = 0,
   DIR_SELL = 1
  };

enum ESpacingMode
  {
   SPACING_PIPS   = 0,
   SPACING_ATR    = 1,
   SPACING_HYBRID = 2
  };

enum EBasketKind
  {
   BASKET_PRIMARY = 0,
   BASKET_HEDGE   = 1
  };

enum ETrendAction
  {
   TREND_ACTION_NONE      = 0,  // Block new seeds only (default)
   TREND_ACTION_CLOSE_ALL = 1,  // Close counter-trend basket immediately
   TREND_ACTION_NO_REFILL = 2   // Block refills, allow existing positions
  };

// Phase 13: Market state classification
enum EMarketState
  {
   MARKET_RANGE         = 0,  // ADX < 25, sideways
   MARKET_WEAK_TREND    = 1,  // ADX 25-35, mild trend
   MARKET_STRONG_TREND  = 2,  // ADX 35-45, strong trend
   MARKET_EXTREME_TREND = 3   // ADX > 45, extreme trend (danger!)
  };


struct SGridLevel
  {
   double price;   // entry price for pending level
   double lot;     // lot size for this level
   ulong  ticket;  // ticket once placed
   bool   filled;  // level already converted to position
  };

struct SBasketSummary
  {
   EDirection direction;
   EBasketKind kind;
   double total_lot;
   double avg_price;
   double pnl_usd;
   double tp_price;
   double last_grid_price;
   bool   trailing_active;
  };


//+------------------------------------------------------------------+
//| NEW ENUMERATIONS FOR v3.1.0 (Phase 0: Defined but unused)       |
//+------------------------------------------------------------------+

// Grid basket states (for future state machine)
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

// Trap conditions (bitwise flags for multi-condition detection)
enum ENUM_TRAP_CONDITION
  {
   TRAP_COND_NONE = 0,         // No condition
   TRAP_COND_GAP = 1,          // Large gap exists (bit 0)
   TRAP_COND_COUNTER_TREND = 2,// Strong counter-trend (bit 1)
   TRAP_COND_HEAVY_DD = 4,     // Heavy drawdown (bit 2)
   TRAP_COND_MOVING_AWAY = 8,  // Price moving away from avg (bit 3)
   TRAP_COND_STUCK = 16        // Stuck too long without recovery (bit 4)
  };

// Quick exit mode
enum ENUM_QUICK_EXIT_MODE
  {
   QE_FIXED,                   // Fixed loss amount (-$10)
   QE_PERCENTAGE,              // % of current DD (30%)
   QE_DYNAMIC                  // Dynamic based on DD severity
  };

//+------------------------------------------------------------------+
//| NEW STRUCTURES FOR v3.1.0 (Phase 0: Defined but unused)         |
//+------------------------------------------------------------------+

// Trap detection state
struct STrapState
  {
   bool     detected;          // Trap active?
   datetime detectedTime;      // When detected
   double   gapSize;           // Gap in pips
   double   ddAtDetection;     // DD when trap detected
   int      conditionsMet;     // How many conditions (0-5)
   int      conditionFlags;    // Bitwise flags of conditions
   
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

// Grid state tracking (lazy fill)
struct SGridState
  {
   int      lastFilledLevel;   // Last level that was filled
   double   lastFilledPrice;   // Price of last filled level
   datetime lastFilledTime;    // When last level filled
   int      currentMaxLevel;   // Current max level placed
   int      pendingCount;      // Active pending orders
   
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
   double               targetLoss;        // Target loss (-$10, -$20)
   bool                 closeFarPositions; // Close far positions?
   bool                 autoReseed;        // Reseed after exit?
   int                  timeoutMinutes;    // Timeout for mode
   ENUM_QUICK_EXIT_MODE mode;              // Exit mode
   
   // Constructor
   SQuickExitConfig() : targetLoss(-10.0), closeFarPositions(true),
                       autoReseed(true), timeoutMinutes(60), mode(QE_FIXED) {}
  };

#endif // __RGD_V2_TYPES_MQH__
