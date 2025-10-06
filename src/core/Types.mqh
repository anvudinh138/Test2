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

enum EJobStatus
  {
   JOB_ACTIVE    = 0,  // Trading normally
   JOB_FULL      = 1,  // Grid full, waiting for price return or spawn new
   JOB_STOPPED   = 2,  // SL hit or user stop
   JOB_ABANDONED = 3   // DD too high, other jobs can't save this
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

// Forward declaration for SJob (avoid circular dependency)
class CLifecycleController;

struct SJob
  {
   int                   job_id;              // Unique job identifier
   long                  magic;               // Magic number for this job
   datetime              created_at;          // Job spawn time

   // Lifecycle (existing structure)
   CLifecycleController *controller;          // BUY + SELL baskets

   // Job-specific risk
   double                job_sl_usd;          // Max loss for this job (e.g., -$50)
   double                job_dd_threshold;    // Drawdown % to abandon job (e.g., 30%)

   // Status
   EJobStatus            status;              // ACTIVE, FULL, STOPPED, ABANDONED
   bool                  is_full;             // Grid full (all levels filled)
   bool                  is_tsl_active;       // Trailing stop active

   // Stats
   double                realized_pnl;        // Total realized P&L
   double                unrealized_pnl;      // Current floating P&L
   double                peak_equity;         // Peak equity for this job
  };

#endif // __RGD_V2_TYPES_MQH__
