import re

with open('src/core/PresetManager.mqh', 'r') as f:
    lines = f.readlines()

cleaned = []
skip_next = False
for line in lines:
    # Skip lines with removed parameters
    if any(x in line for x in ['grid_dynamic_enabled', 'grid_warm_levels', 'grid_refill_threshold', 
                                'grid_refill_batch', 'grid_max_pendings', 'grid_protection_enabled', 
                                'grid_cooldown_minutes', 'trend_filter_enabled', 'trend_action', 
                                'trend_ema_timeframe', 'trend_ema_period', 'trend_adx_period', 
                                'trend_adx_threshold', 'trend_buffer_pips']):
        continue
    # Skip comment lines about removed features
    if any(x in line for x in ['Grid Protection', 'Trend Filter', 'Dynamic Grid']):
        continue
    cleaned.append(line)

with open('src/core/PresetManager.mqh', 'w') as f:
    f.writelines(cleaned)

print("Cleaned PresetManager.mqh")
