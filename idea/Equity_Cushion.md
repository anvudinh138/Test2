# Equity Cushion / Insurance Basket Specification

## Goals
- Khi lifecycle chính chịu trend mạnh, tạo "insurance basket" đi cùng xu hướng để tích luỹ lợi nhuận bù drawdown.
- Insurance basket độc lập với hedge thông thường để tránh phá cấu trúc hedge/loser.
- Tự động đóng khi đạt mục tiêu hoặc khi thị trường đảo chiều, nhằm không tạo rủi ro mới.
- Giúp chiến lược có thêm nguồn lợi nhuận khi trend tiếp diễn lâu.

## Concept
- **Insurance Basket**: rổ lệnh nhỏ, theo cùng chiều với trend hiện tại (ngược lại với loser).
- **Activation**: chỉ bật khi trend rất mạnh và loser không thể về TP trong thời gian dài.
- **Auto-Trail**: dùng TSL chặt để khoá lợi nhuận nhanh, optional trailing equity.
- **Profit Allocation**: lợi nhuận từ insurance dùng để giảm target của basket loser hoặc để tăng equity buffer.

## Activation Criteria
1. Life-cycle đang lockdown hoặc `TrendBlocksRescue()` true liên tục ≥ `ins_cooldown_bars`.
2. Drawdown của loser ≥ `ins_dd_trigger_usd`.
3. Trend slope cao (`TrendSlopeValue()` ≥ `ins_slope_threshold`) và giá vượt `ins_price_breakout_mult` × ATR so với avg loser.
4. Tổng exposure + insurance lot ≤ `ins_max_total_lots` để tránh quá tải.
5. Insurance chưa active (chỉ một rổ insurance tại một thời điểm).

## Behaviour
- Khi kích hoạt, mở một market order direction = trend (ví dụ trend lên → BUY), lot = `ins_lot`.
- Đặt TSL ngay (start = `ins_tsl_start`, step = `ins_tsl_step`).
- Đặt TP theo `ins_target_usd` (hoặc trailing). Mục tiêu: chốt nhanh, không giữ lâu.
- Nếu partial closes hoặc adaptive spacing giảm drawdown loser xuống dưới `ins_dd_exit_usd` → đóng insurance để tránh drawdown song song.
- Nếu trend đảo (`TrendSlopeValue()` < `ins_slope_exit`) hoặc giá quay về avg loser, đóng insurance.
- Khi insurance đóng với profit > 0 → gọi `loser.ReduceTargetBy(profit * ins_target_apply_pct)`.

## Parameters
| Input | Default | Notes |
| --- | --- | --- |
| `InpInsEnable` | false | Bật/tắt insurance basket. |
| `InpInsLot` | 0.05 | Lot size insurance. |
| `InpInsDDTriggerUSD` | 15.0 | DD loser cần đạt để kích hoạt. |
| `InpInsDDExitUSD` | 8.0 | Nếu DD giảm dưới mức này → đóng insurance. |
| `InpInsSlopeThreshold` | 0.0010 | EMA slope yêu cầu để bật. |
| `InpInsSlopeExit` | 0.0004 | Slope giảm dưới → đóng. |
| `InpInsPriceBreakoutMult` | 1.5 | Giá vượt X ATR so với avg loser. |
| `InpInsTSLStart` | 200 | Điểm để bật trailing. |
| `InpInsTSLStep` | 100 | Bước trail. |
| `InpInsTargetUSD` | 8.0 | Lợi nhuận mục tiêu/TP (optional). |
| `InpInsTargetApplyPct` | 0.8 | Phần trăm profit dùng để giảm TP loser. |
| `InpInsMaxTotalLots` | 1.0 | Exposure limit riêng cho insurance. |
| `InpInsCooldownBars` | 30 | Thời gian phải chờ trước khi tạo insurance mới. |

Mapping sang `SParams`: `ins_enable`, `ins_lot`, `ins_dd_trigger_usd`, `ins_dd_exit_usd`, `ins_slope_threshold`, `ins_slope_exit`, `ins_price_breakout_mult`, `ins_tsl_start`, `ins_tsl_step`, `ins_target_usd`, `ins_target_apply_pct`, `ins_max_total_lots`, `ins_cooldown_bars`.

## Flowchart
```mermaid
flowchart TD
    A[OnTick] --> B{Insurance active?}
    B -- No --> C{Eligible to activate?}
    C -- Yes --> D[Open insurance basket]
    D --> E[Set TSL/TP]
    C -- No --> G[No action]

    B -- Yes --> F[Manage insurance (TSL, TP)]
    F --> H{Exit conditions hit?}
    H -- Yes --> I[Close insurance; apply profit]
    H -- No --> G
```

## Pseudo-code
```pseudo
struct SInsuranceState
{
    bool   active;
    long   ticket;
    datetime activated_at;
    double entry_price;
};

class CLifecycleController
{
    SInsuranceState m_ins;
    datetime m_last_ins_close;

    void UpdateInsurance(CGridBasket *loser,
                         double price,
                         double atr_points,
                         double slope)
    {
        if(!m_params.ins_enable)
            return;

        if(!m_ins.active)
        {
            if(CanActivateInsurance(loser, price, atr_points, slope))
                ActivateInsurance(price);
        }
        else
        {
            ManageInsurance(loser, price, slope);
        }
    }
}
```

```pseudo
bool CLifecycleController::CanActivateInsurance(CGridBasket *loser,
                                                double price,
                                                double atr_points,
                                                double slope)
{
    if(loser == NULL) return false;
    if(atr_points <= 0) return false;
    if(TimeSince(m_last_ins_close) < params.ins_cooldown_bars) return false;
    if(loser.BasketPnL() >= -params.ins_dd_trigger_usd) return false;
    if(slope < params.ins_slope_threshold) return false;

    double breakout = fabs(price - loser.AveragePrice());
    if(breakout < params.ins_price_breakout_mult * atr_points)
        return false;

    double insurance_volume = NormalizeLot(params.ins_lot);
    if(!ledger.ExposureAllowed(insurance_volume + loser.TotalLot(), AllMagics()))
        return false;

    return true;
}
```

```pseudo
void CLifecycleController::ActivateInsurance(double price)
{
    double lot = NormalizeLot(params.ins_lot);
    if(lot <= 0) return;

    EDirection dir = (TrendSlopeValue() > 0 ? DIR_BUY : DIR_SELL);
    ulong ticket = m_executor.Market(dir, lot, "Insurance");
    if(ticket > 0)
    {
        m_ins.active = true;
        m_ins.ticket = ticket;
        m_ins.activated_at = TimeCurrent();
        m_ins.entry_price = price;
        SetupInsuranceStops(ticket, dir);
        m_log.Event(Tag(), "[Insurance] activated");
    }
}
```

```pseudo
void CLifecycleController::ManageInsurance(CGridBasket *loser,
                                           double price,
                                           double slope)
{
    if(!PositionSelectByTicket(m_ins.ticket))
    {
        m_ins.active = false;
        m_last_ins_close = TimeCurrent();
        return;
    }

    double pnl = PositionGetDouble(POSITION_PROFIT);

    bool exit = false;
    if(loser == NULL || loser.BasketPnL() >= -params.ins_dd_exit_usd)
        exit = true;
    if(slope < params.ins_slope_exit)
        exit = true;
    if(price near loser.AveragePrice())
        exit = true;
    if(pnl >= params.ins_target_usd)
        exit = true;

    if(exit)
    {
        double realized = ClosePosition(m_ins.ticket, "Insurance exit");
        if(realized > 0 && loser != NULL)
            loser.ReduceTargetBy(realized * params.ins_target_apply_pct);
        m_ins.active = false;
        m_last_ins_close = TimeCurrent();
    }
}
```

```pseudo
void CLifecycleController::SetupInsuranceStops(ulong ticket, EDirection dir)
{
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double start = params.ins_tsl_start * point;
    double step = params.ins_tsl_step * point;
    // set initial SL = entry ± start, then ManageInsurance trailing updates.
}
```

## Testing Checklist
1. **Trend mạnh liên tục**: insurance bật, thu profit sớm; log `[Insurance]` và profit được áp dụng vào loser target.
2. **Đảo chiều nhanh**: insurance TSL/exit đóng kịp, không bị giữ lỗ lớn.
3. **Sideway**: các điều kiện activate không đạt → insurance không bật.
4. **Equity impact**: theo dõi equity curve khi insurance hoạt động để đảm bảo không vượt exposure cap.
5. **Multiple activations**: sau khi đóng, cooldown hoạt động (không spam insurance). Test interplay với partial close và adaptive spacing.
