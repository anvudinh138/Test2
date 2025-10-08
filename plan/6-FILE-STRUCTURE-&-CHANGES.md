6. FILE STRUCTURE & CHANGES
6.1 New Files
src/core/TrapDetector.mqh          // NEW - Trap detection logic
6.2 Modified Files
src/core/GridBasket.mqh            // MAJOR - Lazy fill, quick exit, gap management
src/core/LifecycleController.mqh   // MODERATE - Global risk monitoring
src/core/Types.mqh                 // MINOR - New enums and structs
src/core/Params.mqh                // MODERATE - New input parameters
src/core/Logger.mqh                // MINOR - New log events
src/ea/RecoveryGridDirection_v3.mq5 // MINOR - Performance logging
6.3 Unchanged Files (Reference Only)
src/core/SpacingEngine.mqh         // NO CHANGE
src/core/OrderExecutor.mqh         // NO CHANGE
src/core/OrderValidator.mqh        // NO CHANGE
src/core/NewsFilter.mqh            // NO CHANGE
src/core/TrendFilter.mqh           // NO CHANGE (used by trap detector)
src/core/PresetManager.mqh         // NO CHANGE
src/core/MathHelpers.mqh           // NO CHANGE