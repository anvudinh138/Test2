# Adaptive Spacing / Time-In-Trade De-rate Specification

## Goals
- Giảm tốc độ DCA khi basket thua mở quá lâu hoặc drawdown tăng, để tránh run-away exposure trong trend kéo dài.
- Tự động nới spacing (hoặc giảm lot) dựa trên thời gian ở trạng thái thua và biến động hiện tại.
- Giữ hành vi bình thường khi thị trường sideway hoặc basket mới mở (không ảnh hưởng lợi nhuận thường nhật).
- Cho phép kết hợp với Trend Lockdown và Partial Close (ưu tiên kiểm tra flag trước khi can thiệp).

## Key Concepts
1. **Time-In-Trade (TiT)**: số bar kể từ khi basket chuyển âm lần đầu hoặc từ lần khớp lệnh mới nhất. Lưu trong `CGridBasket`: `m_time_in_drawdown_bars`.
2. **Exposure Tier**: bậc giới hạn khi TiT và drawdown vượt mốc. Mỗi bậc nới spacing và giảm lot scale.
3. **Volatility Adaption**: dùng ATR để đảm bảo spacing không quá rộng khi volatility nhỏ.
4. **Reset Conditions**: khi basket đóng ở TP hoặc về hòa vốn, reset cấu hình để không ảnh hưởng lifecycle mới.

## Parameters
| Input | Default | Ý nghĩa |
| --- | --- | --- |
| `InpAdaptEnable` | true | Bật/tắt cơ chế adaptive spacing. |
| `InpAdaptTierBars` | `20,40,80` | Ngưỡng bar cho các tier. |
| `InpAdaptTierDDPct` | `3,5,8` | Ngưỡng drawdown (% balance hoặc USD) tương ứng tier. |
| `InpAdaptSpacingMult` | `1.2,1.5,2.0` | Hệ số spacing nhân với spacing cơ bản cho mỗi tier. |
| `InpAdaptLotScaleMult` | `0.8,0.6,0.4` | Nhân hệ số `lot_scale` khi deploy level mới trong tier. |
| `InpAdaptATRFloor` | 0.5 | Nếu ATR giảm, spacing không nhỏ hơn `min_spacing_pips * InpAdaptATRFloor`. |
| `InpAdaptRearmBars` | 10 | Số bar cần giá hồi gần avg để reset xuống tier thấp hơn. |

Mapping sang `SParams`: `adapt_enabled`, `adapt_tier_bars[]`, `adapt_tier_dd_pct[]`, `adapt_spacing_mult[]`, `adapt_lot_scale_mult[]`, `adapt_atr_floor`, `adapt_rearm_bars`.

## Flow
```mermaid
flowchart TD
    A[OnTick] --> B[Update baskets]
    B --> C{Basket loser active?}
    C -- No --> N[Normal flow]
    C -- Yes --> D[Compute TiT, drawdown, ATR]
    D --> E[Determine tier via TiT/DD]
    E --> F{Tier > 0?}
    F -- No --> N
    F -- Yes --> G[Apply tier overrides]
    G --> H[SpacingEngine AdaptiveSpacing()]
    H --> I[Grid maintenance uses adaptive spacing/lot]
    I --> J{Reset conditions met?}
    J -- Yes --> K[Reset tier]
    J -- No --> N
```

## Behaviour
1. **Tracking Time-In-Trade**
   - Trong `CGridBasket::Update()`, nếu `BasketPnL() < 0`, tăng `m_time_in_dd_bars`. Nếu ≥ 0, reset = 0.
   - Lưu `m_max_drawdown_usd` cho basket.

2. **Tier Selection**
   - Trong `LifecycleController.Update()` hoặc `GridBasket.Update()`, gọi `DetermineAdaptTier(dd_usd, time_in_dd)` trả về tier index.
   - `dd_usd` có thể chuyển sang % balance (lấy `AccountInfoDouble(ACCOUNT_BALANCE)`), hoặc giữ USD nếu balance không có.

3. **Applying Overrides**
   - Khi tier ≥ 0:
     - Spacing multiplier = `params-spacing * adapt_spacing_mult[tier]`.
     - Lot scale multiplier = `params.lot_scale * adapt_lot_scale_mult[tier]`.
   - Implement trong `CGridBasket::MaintainGrid()` khi đặt limit mới: dùng `EffectiveSpacing()` thay cho spacing gốc, `EffectiveLotScale(idx)`.
   - `SpacingEngine` giữ spacing chuẩn; basket quyết định spacing override.

4. **ATR Floor**
   - Khi nới spacing, kiểm tra ATR (via `m_spacing.AtrPips()`). Spacing cuối cùng = `max(base_spacing * multiplier, params.min_spacing_pips * adapt_atr_floor)`.

5. **Reset Conditions**
   - Nếu basket PnL ≥ 0 → tier = -1, reset multipliers.
   - Nếu giá quay lại gần avg trong `adapt_rearm_bars` (distance < 0.5 × spacing): giảm tier một cấp.
   - Khi Basket closes (GroupTP/TSL) → reset counters.

6. **Integration with Trend Lockdown & Partial Close**
   - Nếu lockdown active, adaptive spacing vẫn giữ tier nhưng rescue bị block. Cần log tier tại thời điểm lockdown.
   - Partial close có thể giảm lot, khi lot < `pc_min_lots_remain` → tier có thể giảm; guard logic không bị ảnh hưởng.

## Pseudo-code
```pseudo
int CGridBasket::DetermineAdaptTier(double dd_usd, int time_in_dd)
{
    if(!m_params.adapt_enabled)
        return -1;

    int tier_by_time = -1;
    for(int i=ArraySize(m_params.adapt_tier_bars)-1; i>=0; --i)
        if(time_in_dd >= m_params.adapt_tier_bars[i])
            { tier_by_time = i; break; }

    int tier_by_dd = -1;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double dd_pct = (balance>0 ? 100.0*dd_usd/balance : dd_usd);
    for(int i=ArraySize(m_params.adapt_tier_dd_pct)-1; i>=0; --i)
        if(dd_pct >= m_params.adapt_tier_dd_pct[i])
            { tier_by_dd = i; break; }

    return MathMax(tier_by_time, tier_by_dd);
}
```

```pseudo
void CGridBasket::UpdateAdaptiveState(double atr_pips)
{
    if(!m_params.adapt_enabled)
    {
        m_adapt_tier = -1;
        return;
    }

    if(m_pnl_usd >= 0)
    {
        m_adapt_tier = -1;
        m_time_in_dd_bars = 0;
        m_max_drawdown_usd = 0;
        return;
    }

    m_time_in_dd_bars++;
    m_max_drawdown_usd = MathMax(m_max_drawdown_usd, -m_pnl_usd);

    int tier = DetermineAdaptTier(m_max_drawdown_usd, m_time_in_dd_bars);
    if(tier >= 0)
    {
        m_adapt_tier = tier;
        double base_spacing = m_spacing->SpacingPips();
        double mult = m_params.adapt_spacing_mult[tier];
        m_effective_spacing_pips = base_spacing * mult;
        double atr_floor = m_params.min_spacing_pips * m_params.adapt_atr_floor;
        double atr_based = (atr_pips>0 ? MathMax(base_spacing, atr_pips) : base_spacing);
        m_effective_spacing_pips = MathMax(m_effective_spacing_pips, atr_floor);
    }
    else
    {
        m_adapt_tier = -1;
        m_effective_spacing_pips = m_spacing->SpacingPips();
    }
}
```

```pseudo
double CGridBasket::EffectiveSpacingPips()
{
    if(!m_params.adapt_enabled || m_adapt_tier < 0)
        return m_spacing->SpacingPips();
    return m_effective_spacing_pips;
}

double CGridBasket::EffectiveLotScale(int level_index)
{
    double scale = MathPow(m_params.lot_scale, level_index);
    if(m_params.adapt_enabled && m_adapt_tier >= 0)
        scale *= m_params.adapt_lot_scale_mult[m_adapt_tier];
    return NormalizeVolumeValue(scale*m_params.lot_base);
}
```

```pseudo
void CGridBasket::MaintainGrid()
{
    double spacing_px = m_spacing->ToPrice(EffectiveSpacingPips());
    // when replacing/cascading pending orders, use spacing_px instead of base.
    // For each new level beyond current filled count, apply EffectiveLotScale.
}
```

```pseudo
void CGridBasket::MaybeDowngradeTier(double price)
{
    if(m_adapt_tier <= 0) return;
    double distance = fabs(price - m_avg_price);
    double spacing_px = m_spacing->ToPrice(EffectiveSpacingPips());
    if(distance < spacing_px*0.5)
    {
        m_tier_downgrade_counter++;
        if(m_tier_downgrade_counter >= m_params.adapt_rearm_bars)
        {
            m_adapt_tier--;
            m_tier_downgrade_counter=0;
        }
    }
    else
    {
        m_tier_downgrade_counter=0;
    }
}
```

## Logging & Monitoring
- Khi tier thay đổi: `m_log.Event(Tag(), "[AdaptTier] tier=%d spacing=%.1f lot_scale=%.2f")`.
- Lưu vào journal: `time_in_dd`, `max_dd`, `effective_spacing` để kiểm chứng.

## Testing Checklist
1. **Trend kéo dài**: xác nhận tier tăng dần, spacing/lot giảm, DCA chậm lại. Khi giá đảo chiều và basket đóng → tier reset.
2. **Sideway**: TiT nhỏ, tier không kích hoạt, spacing vẫn như cũ.
3. **Retest sâu nhưng nhanh**: đảm bảo tier không nhảy quá cao nếu thời gian ngắn (cooldown). Khi Partial Close diễn ra, tier có giảm/giữ hợp lý.
4. **Lockdown kết hợp**: khi lockdown bật trong tier cao, log hiển thị tier để bạn đánh giá.
5. **Stress**: backtest 3 tháng tick-by-tick, export log spacing & lot để so sánh baseline vs adapt.
