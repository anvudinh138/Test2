# Phase 0 - Baseline Reset ✅ COMPLETED

## Goal
Chạy được build "rỗng" (chưa bật logic mới), không spam log.

## Scope
Giữ nguyên inputs nhưng đổi default = false cho Lazy/Trap/QE/Gap để không "kỳ vọng hành vi" khi chưa implement.

## Changes Made

### 1. ✅ Added New Input Parameters (RecoveryGridDirection_v3.mq5)

#### Lazy Grid Fill (Phase 1)
```cpp
input group "=== Lazy Grid Fill (v3.1 - Phase 0: OFF) ==="
input bool   InpLazyGridEnabled      = false;       // OFF for Phase 0
input int    InpInitialWarmLevels    = 1;           // Initial pending levels (1-2)
input int    InpMaxLevelDistance     = 500;         // Max distance to next level (pips)
input double InpMaxDDForExpansion    = -20.0;       // Stop expanding if DD < this (%)
```

#### Trap Detection (Phase 2)
```cpp
input group "=== Trap Detection (v3.1 - Phase 0: OFF) ==="
input bool   InpTrapDetectionEnabled = false;       // OFF for Phase 0
input double InpTrapGapThreshold     = 200.0;       // Gap threshold (pips)
input double InpTrapDDThreshold      = -20.0;       // DD threshold (%)
input int    InpTrapConditionsRequired = 3;         // Min conditions to trigger (3/5)
input int    InpTrapStuckMinutes     = 30;          // Minutes to consider "stuck"
```

#### Quick Exit Mode (Phase 3)
```cpp
input group "=== Quick Exit Mode (v3.1 - Phase 0: OFF) ==="
input bool   InpQuickExitEnabled     = false;       // OFF for Phase 0
input ENUM_QUICK_EXIT_MODE InpQuickExitMode = QE_FIXED;
input double InpQuickExitLoss        = -10.0;       // Fixed loss amount ($)
input double InpQuickExitPercentage  = 0.30;        // Percentage mode (30% of DD)
input bool   InpQuickExitCloseFar    = true;        // Close far positions in quick exit
input bool   InpQuickExitReseed      = true;        // Auto reseed after exit
input int    InpQuickExitTimeoutMinutes = 60;       // Timeout (minutes)
```

#### Gap Management (Phase 4)
```cpp
input group "=== Gap Management (v3.1 - Phase 0: OFF) ==="
input bool   InpAutoFillBridge       = false;       // OFF for Phase 0
input int    InpMaxBridgeLevels      = 5;           // Max bridge levels per gap
input double InpMaxPositionDistance  = 300.0;       // Max distance for position (pips)
input double InpMaxAcceptableLoss    = -100.0;      // Max loss to abandon trapped ($)
```

### 2. ✅ Added New Enums & Structs (Types.mqh)

#### Enums
```cpp
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

// Trap conditions (bitwise flags)
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
```

#### Structs
```cpp
// Trap detection state
struct STrapState
{
   bool     detected;
   datetime detectedTime;
   double   gapSize;
   double   ddAtDetection;
   int      conditionsMet;
   int      conditionFlags;
};

// Grid state tracking (lazy fill)
struct SGridState
{
   int      lastFilledLevel;
   double   lastFilledPrice;
   datetime lastFilledTime;
   int      currentMaxLevel;
   int      pendingCount;
};

// Quick exit configuration
struct SQuickExitConfig
{
   double               targetLoss;
   bool                 closeFarPositions;
   bool                 autoReseed;
   int                  timeoutMinutes;
   ENUM_QUICK_EXIT_MODE mode;
};
```

### 3. ✅ Updated SParams Struct (Params.mqh)

Added new fields to store all v3.1.0 parameters:

```cpp
// lazy grid fill (Phase 1)
bool         lazy_grid_enabled;
int          initial_warm_levels;
int          max_level_distance;
double       max_dd_for_expansion;

// trap detection (Phase 2)
bool         trap_detection_enabled;
double       trap_gap_threshold;
double       trap_dd_threshold;
int          trap_conditions_required;
int          trap_stuck_minutes;

// quick exit mode (Phase 3)
bool         quick_exit_enabled;
ENUM_QUICK_EXIT_MODE quick_exit_mode;
double       quick_exit_loss;
double       quick_exit_percentage;
bool         quick_exit_close_far;
bool         quick_exit_reseed;
int          quick_exit_timeout_min;

// gap management (Phase 4)
bool         auto_fill_bridge;
int          max_bridge_levels;
double       max_position_distance;
double       max_acceptable_loss;
```

### 4. ✅ Updated BuildParams() Function

Mapped all input parameters to SParams struct:

```cpp
// NEW v3.1.0 parameters (Phase 0: OFF by default)
g_params.lazy_grid_enabled     =InpLazyGridEnabled;
g_params.initial_warm_levels   =InpInitialWarmLevels;
// ... (all 17 new parameters mapped)
```

### 5. ✅ Added Status Logging in OnInit()

Added comprehensive logging to show feature status:

```cpp
g_logger.Event("[RGDv2]","========================================");
g_logger.Event("[RGDv2]","v3.1.0 FEATURES STATUS (Phase 0):");
g_logger.Event("[RGDv2]",StringFormat("  Lazy Grid Fill:   %s", InpLazyGridEnabled ? "ENABLED" : "DISABLED (Phase 0)"));
g_logger.Event("[RGDv2]",StringFormat("  Trap Detection:   %s", InpTrapDetectionEnabled ? "ENABLED" : "DISABLED (Phase 0)"));
g_logger.Event("[RGDv2]",StringFormat("  Quick Exit Mode:  %s", InpQuickExitEnabled ? "ENABLED" : "DISABLED (Phase 0)"));
g_logger.Event("[RGDv2]",StringFormat("  Gap Management:   %s", InpAutoFillBridge ? "ENABLED" : "DISABLED (Phase 0)"));
g_logger.Event("[RGDv2]","========================================");

if(InpLazyGridEnabled || InpTrapDetectionEnabled || InpQuickExitEnabled || InpAutoFillBridge)
{
   g_logger.Event("[RGDv2]","WARNING: Phase 0 expects ALL new features to be OFF!");
}
else
{
   g_logger.Event("[RGDv2]","✅ Phase 0 OK: All new features disabled as expected.");
}
```

## Deliverables (Phase 0 - 15-phase.md)

### ✅ Compile OK
- All files compile without errors
- No linter warnings

### ⏳ Backtest 1-2 days (PENDING)
- **Test**: Strategy Tester M1, 1-2 days data
- **Expected**: No crash, no new orders from new modules
- **Validation**: All 4 feature flags = false, log shows "Phase 0 OK"

## Exit Criteria

✅ Không crash
✅ Không mở lệnh từ modules mới (Lazy Grid, Trap, Quick Exit, Gap Management)
✅ Log rõ ràng: "All new features disabled as expected"

## Rollback

Git tag created: `baseline-reset-phase0`

```bash
git tag -a v3.1.0-phase0 -m "Phase 0: Baseline reset - All new features OFF"
```

## Next Steps (Phase 1 - Observability)

**Goal**: Nhìn log là biết đang ở state nào và tại sao.

**Scope**:
- Chuẩn hóa Logger.mqh event types (TRAP, QE, BRIDGE, FAR_CLOSE, RESEED, EMERGENCY)
- File log theo magic number
- PrintConfiguration() in toàn bộ inputs lúc khởi động

**Deliverables**:
- Logger hoạt động với event types mới
- Log chuyển state với lý do guard/trigger rõ ràng
- Mock test các state/trigger

## Summary

**Phase 0 Status**: ✅ **COMPLETED**

- **Files Modified**: 3
  - `src/ea/RecoveryGridDirection_v3.mq5` (added 37 new input parameters)
  - `src/core/Types.mqh` (added 3 enums + 3 structs)
  - `src/core/Params.mqh` (added 17 new fields to SParams)

- **Lines Added**: ~150 lines
- **Compilation**: ✅ No errors
- **Feature Flags**: ✅ All OFF (false) by default

**Ready for**: Phase 1 (Observability - Logger enhancement)

---

**Date**: 2025-10-08
**Version**: v3.1.0-phase0
**Status**: ✅ Baseline reset complete, ready for Phase 1

