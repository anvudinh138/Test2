# Dynamic Grid Deployment Specification

## Problem
Với `InpGridLevels` lớn (100–1000), hệ thống hiện tại tạo toàn bộ limit orders ngay tại OnInit (`BuildGrid`), dẫn tới:
- Lag UI/backtest do hàng trăm pending.
- Spacing cố định tại thời điểm bootstrap, không thích ứng khi ATR/spacing thay đổi.
- Khó điều chỉnh grid khi vừa mở đã chạy trend khác.

## Goals
- Chỉ duy trì một số lượng nhỏ pending "đệm" quanh giá – nạp thêm khi gần cạn.
- Cho phép spacing/lot của các level mới được tính lại theo ATR/hybrid tại thời điểm refill.
- Giữ nguyên hành vi logic basket: market seed + pending queue, TP gộp, rescue…
- Giảm load cho terminal khi người dùng muốn dùng `grid_levels` rất lớn.

## Terminology
- **Max levels**: tổng level user khai báo (`InpGridLevels`).
- **Warm levels**: số pending được bật ngay khi seed basket.
- **Buffer threshold**: số pending tối thiểu; khi pending ≤ threshold thì refill.
- **Batch size**: số level mới được thêm mỗi lần refill.

## Parameters (đề xuất)
| Input | Default | Ý nghĩa |
| --- | --- | --- |
| `InpGridWarmLevels` | 4 | Số pending khởi tạo mỗi hướng (không tính market seed). |
| `InpGridRefillThreshold` | 2 | Khi pending chưa khớp ≤ ngưỡng này → nạp thêm. |
| `InpGridRefillBatch` | 2 | Số level thêm mỗi lần refill. |
| `InpGridRefillSpacingMode` | `LIVE` | Cách tính spacing khi refill: `LIVE` (ATR hiện tại) hoặc `STATIC` (spacing ban đầu). |
| `InpGridMaxPendings` | 12 | Giới hạn cứng pending đồng thời (safety). |

Mapping vào `SParams`: `grid_warm_levels`, `grid_refill_threshold`, `grid_refill_batch`, `grid_refill_mode`, `grid_max_pendings`.

## State Additions (CGridBasket)
- `int m_max_levels;` tổng capacity (bao gồm seed).
- `int m_levels_placed;` số level đã create.
- `int m_pending_count;` pending còn lại.
- `double m_last_anchor_price;` giá tham chiếu khi đặt level cuối.
- Queue/array `m_levels` vẫn giữ full metadata; các level chưa tạo `ticket=0`.

## Flow
```mermaid
flowchart TD
    A[Init Basket] --> B[Place market seed]
    B --> C[Place warm pending (grid_warm_levels)]
    C --> D[Set m_levels_placed]
    D --> E[Update loop]
    E --> F[RefreshState]
    F --> G{Pending <= threshold?}
    G -- Yes --> H[RefillBatch()]
    H --> I[Place new limits, update counters]
    G -- No --> I
    I --> J{levels_placed >= max_levels?}
    J -- Yes --> K[Stop refilling]
    J -- No --> E
```

## Refill Logic
```pseudo
void CGridBasket::RefillBatch(double current_price)
{
    if(m_levels_placed >= m_max_levels) return;
    int available = m_max_levels - m_levels_placed;
    int to_add = MathMin(params.grid_refill_batch, available);

    for(int i=0; i<to_add; ++i)
    {
        double spacing_pips = ComputeSpacingPips();
        double spacing_px = m_spacing->ToPrice(spacing_pips);
        double price = NextLevelPrice(current_price, spacing_px);
        double lot = LevelLot(m_levels_placed); // scale per tier

        // validate broker distance via validator
        if(m_executor.CanPlace(price))
        {
            ulong ticket = m_executor.Limit(dir, price, lot, "RGDv2_GridDyn");
            if(ticket>0)
            {
                m_levels[m_levels_placed].price = price;
                m_levels[m_levels_placed].lot = lot;
                m_levels[m_levels_placed].ticket = ticket;
                m_levels[m_levels_placed].filled = false;
                m_levels_placed++;
                m_pending_count++;
                m_last_anchor_price = price;
            }
        }
    }
}
```

### ComputeSpacingPips()
- Nếu `grid_refill_mode == STATIC`: dùng spacing đã lưu khi init (m_initial_spacing_pips).
- Nếu `LIVE`: gọi `m_spacing->SpacingPips()` mỗi lần refill → spacing phản ánh ATR mới.
- Bảo đảm spacing ≥ `min_spacing_pips` (đã trong `SpacingEngine`).

### NextLevelPrice()
- Với BUY: `price = min(last_anchor_price, current_price) - spacing_px`.
- Với SELL: `price = max(last_anchor_price, current_price) + spacing_px`.
- Cập nhật `m_last_anchor_price` cho lần sau.

### Pending Count Tracking
- `RefreshState()`/`Update()` cần kiểm tra pending open orders để đếm lại (sử dụng `OrdersTotal()` loop). Hoặc duy trì counter khi order filled/cancelled: khi pending khớp thành position (detect via `OrderSelect` + `OrderType`), set `m_levels[i].filled=true; m_pending_count--`.
- Nếu pending bị canceled/errored, remove/attempt to re-place.

## Integration Points
1. **Init** (`Init(anchor_price)`)
   - Set `m_max_levels = params.grid_levels`.
   - `PlaceInitialOrders` chỉ seed market + `grid_warm_levels` pending.
   - `m_levels_placed = 1 + grid_warm_levels` (counting market seed level index 0).

2. **Update()**
   - Sau `RefreshState()` và `ManageTrailing()` thêm `MaintainDynamicGrid()`:
```cpp
void CGridBasket::MaintainDynamicGrid()
{
    if(m_levels_placed >= m_max_levels)
        return;
    if(m_pending_count <= m_params.grid_refill_threshold)
    {
        double price = (m_direction==DIR_BUY)?SymbolInfoDouble(m_symbol,SYMBOL_BID)
                                             :SymbolInfoDouble(m_symbol,SYMBOL_ASK);
        RefillBatch(price);
    }
}
```

3. **Filled Detection**
   - Kết hợp `PositionsHistory` hoặc so sánh ticket: khi `OrderSelect(ticket)` fails, assume filled/canceled → adjust `m_pending_count` và `m_levels[i].filled`.
   - Hoặc đọc `HistoryDealGetTicket` – but for spec, note that implementation needs to watch for status change.

4. **Logging**
- `m_log.Event(Tag(), "[GridRefill] added=2 placed=8 pending=5 spacing=..." )` giúp debug.

## Edge Cases / Considerations
- **Broker Limits**: Validate `StopsLevel` khi đặt price mới. Nếu spacing dynamic gần giá, applique `OrderValidator`.
- **Spread spikes**: khi ATR giảm, `LIVE` spacing có thể nhỏ → consider min spacing multiplier.
- **Backfill after flat**: Khi basket đóng/halt → reset counters; next `Init` seed normal.
- **Reseed (TryReseedBasket)**: Ensure warm levels apply cho seed mới.
- **Max pending guard**: nếu pending count đã ≥ `grid_refill_max_pending`, skip refill (prevents runaway if orders not filling).

## Testing Checklist
1. **High grid level (e.g., 200)**: On init, verify only warm levels placed; log count.
2. **Trend fill**: khi giá vào sâu, pending count giảm → RefillBatch log triggered, spacing recalculated (check ATR change).
3. **Sideway**: ensure refill không spam (pending không xuống dưới threshold liên tục) – tune batch and threshold.
4. **Ensure cap**: khi `grid_levels` exhausted, no further refill; total orders ≤ max.
5. **Performance**: run with 1000 levels – compare chart lag vs. old behavior.
6. **Error handling**: simulate reject (e.g., price violation) → system reattempt later without breaking state.

## Potential Drawbacks
- Logic refill phức tạp hơn; cần robust tracking trạng thái pending và khớp lệnh.
- Nếu spacing recalculated liên tục trong LIVE mode, có thể tạo pattern spacing không đồng đều → cần logging theo dõi.
- Trong điều kiện fill chậm/choppy, có thể refill liên tục -> consider additional debounce (e.g., min seconds between refills).

