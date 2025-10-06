//+------------------------------------------------------------------+
//| PresetManager.mqh - Symbol-specific preset configurations       |
//+------------------------------------------------------------------+
#ifndef __RGD_V2_PRESET_MANAGER_MQH__
#define __RGD_V2_PRESET_MANAGER_MQH__

#include "Params.mqh"

//+------------------------------------------------------------------+
//| Preset types                                                      |
//+------------------------------------------------------------------+
enum ENUM_SYMBOL_PRESET
  {
   PRESET_AUTO = 0,      // Auto-detect from chart symbol
   PRESET_EURUSD = 1,    // EURUSD conservative
   PRESET_XAUUSD = 2,    // XAUUSD wide spacing (tested +472%)
   PRESET_GBPUSD = 3,    // GBPUSD medium volatility
   PRESET_USDJPY = 4,    // USDJPY medium volatility
   PRESET_CUSTOM = 99    // Manual override (no preset)
  };

//+------------------------------------------------------------------+
//| Preset Manager - Apply optimal settings per symbol               |
//+------------------------------------------------------------------+
class CPresetManager
  {
public:
   //+------------------------------------------------------------------+
   //| Apply preset to params struct                                    |
   //+------------------------------------------------------------------+
   static void ApplyPreset(SParams &params, ENUM_SYMBOL_PRESET preset, const string symbol)
     {
      // Auto-detect preset from symbol
      if(preset == PRESET_AUTO)
        {
         preset = DetectPresetFromSymbol(symbol);
        }

      // Apply preset-specific settings
      switch(preset)
        {
         case PRESET_EURUSD:
            ApplyEURUSD(params);
            break;

         case PRESET_XAUUSD:
            ApplyXAUUSD(params);
            break;

         case PRESET_GBPUSD:
            ApplyGBPUSD(params);
            break;

         case PRESET_USDJPY:
            ApplyUSDJPY(params);
            break;

         case PRESET_CUSTOM:
            // No changes - user controls all parameters
            break;

         default:
            // Fallback to EURUSD
            ApplyEURUSD(params);
            break;
        }
     }

   //+------------------------------------------------------------------+
   //| Get preset name for logging                                      |
   //+------------------------------------------------------------------+
   static string GetPresetName(ENUM_SYMBOL_PRESET preset)
     {
      switch(preset)
        {
         case PRESET_AUTO:    return "AUTO";
         case PRESET_EURUSD:  return "EURUSD";
         case PRESET_XAUUSD:  return "XAUUSD";
         case PRESET_GBPUSD:  return "GBPUSD";
         case PRESET_USDJPY:  return "USDJPY";
         case PRESET_CUSTOM:  return "CUSTOM";
         default:             return "UNKNOWN";
        }
     }

private:
   //+------------------------------------------------------------------+
   //| Auto-detect preset from symbol name                              |
   //+------------------------------------------------------------------+
   static ENUM_SYMBOL_PRESET DetectPresetFromSymbol(const string symbol)
     {
      string upper = symbol;
      StringToUpper(upper);

      if(StringFind(upper, "XAU") >= 0 || StringFind(upper, "GOLD") >= 0)
         return PRESET_XAUUSD;

      if(StringFind(upper, "GBP") >= 0 && StringFind(upper, "USD") >= 0)
         return PRESET_GBPUSD;

      if(StringFind(upper, "USD") >= 0 && StringFind(upper, "JPY") >= 0)
         return PRESET_USDJPY;

      if(StringFind(upper, "EUR") >= 0 && StringFind(upper, "USD") >= 0)
         return PRESET_EURUSD;

      // Default fallback
      return PRESET_EURUSD;
     }

   //+------------------------------------------------------------------+
   //| EURUSD Preset (Default Conservative)                             |
   //+------------------------------------------------------------------+
   static void ApplyEURUSD(SParams &params)
     {
      // Spacing (conservative for low volatility)
      params.spacing_pips = 25.0;
      params.spacing_atr_mult = 0.6;
      params.min_spacing_pips = 12.0;
      params.atr_timeframe = PERIOD_M15;

      // Dynamic Grid
      params.grid_warm_levels = 5;
      params.grid_refill_threshold = 2;
      params.grid_refill_batch = 3;
      params.grid_max_pendings = 15;

      // Profit Target
      params.target_cycle_usd = 6.0;

      // Grid Protection
      params.grid_cooldown_minutes = 30;

      // Execution
      // slippage_pips: Use input value (0 for EURUSD)
     }

   //+------------------------------------------------------------------+
   //| XAUUSD Preset (Wide Spacing - Tested +472%)                      |
   //+------------------------------------------------------------------+
   static void ApplyXAUUSD(SParams &params)
     {
      // Spacing (wide for high volatility)
      params.spacing_pips = 150.0;        // 6x wider than EURUSD
      params.spacing_atr_mult = 1.0;      // Full ATR responsiveness
      params.min_spacing_pips = 80.0;     // Higher safety floor
      params.atr_timeframe = PERIOD_H1;   // Capture longer trends

      // Dynamic Grid (conservative)
      params.grid_warm_levels = 3;        // Fewer pending orders
      params.grid_refill_threshold = 1;   // Refill earlier
      params.grid_refill_batch = 2;       // Smaller batches
      params.grid_max_pendings = 10;      // Limit exposure

      // Profit Target
      params.target_cycle_usd = 10.0;     // Higher spread

      // Grid Protection
      params.grid_cooldown_minutes = 60;  // XAU trends last longer

      // Execution
      // slippage_pips: Use input value (20 for XAUUSD)
     }

   //+------------------------------------------------------------------+
   //| GBPUSD Preset (Medium Volatility)                                |
   //+------------------------------------------------------------------+
   static void ApplyGBPUSD(SParams &params)
     {
      // Spacing (medium - between EUR and XAU)
      params.spacing_pips = 50.0;         // 2x EURUSD
      params.spacing_atr_mult = 0.8;
      params.min_spacing_pips = 25.0;
      params.atr_timeframe = PERIOD_M30;

      // Dynamic Grid
      params.grid_warm_levels = 4;
      params.grid_refill_threshold = 2;
      params.grid_refill_batch = 2;
      params.grid_max_pendings = 12;

      // Profit Target
      params.target_cycle_usd = 8.0;      // GBP spread higher than EUR

      // Grid Protection
      params.grid_cooldown_minutes = 45;

      // Execution
      // slippage_pips: Use input value (10 recommended)
     }

   //+------------------------------------------------------------------+
   //| USDJPY Preset (Medium Volatility)                                |
   //+------------------------------------------------------------------+
   static void ApplyUSDJPY(SParams &params)
     {
      // Spacing (medium)
      params.spacing_pips = 40.0;
      params.spacing_atr_mult = 0.7;
      params.min_spacing_pips = 20.0;
      params.atr_timeframe = PERIOD_M30;

      // Dynamic Grid
      params.grid_warm_levels = 4;
      params.grid_refill_threshold = 2;
      params.grid_refill_batch = 3;
      params.grid_max_pendings = 12;

      // Profit Target
      params.target_cycle_usd = 7.0;

      // Grid Protection
      params.grid_cooldown_minutes = 40;

      // Execution
      // slippage_pips: Use input value (5 recommended)
     }
  };

#endif // __RGD_V2_PRESET_MANAGER_MQH__
