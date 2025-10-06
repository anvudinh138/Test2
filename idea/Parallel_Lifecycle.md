# Parallel Lifecycle / Reset Controller Specification

## Goals
- Khi một lifecycle chính (BUY/SELL pair) bị "gồng" quá lâu, cho phép khởi tạo lifecycle mới song song để tận dụng biến động mới mà không phá cấu trúc hiện có.
- Cho phép phân tách drawdown của basket cũ khỏi logic mở grid mới (giữ magic khác).
- Cung cấp cơ chế giám sát và thu hồi lifecycle cũ khi rủi ro đạt ngưỡng (hoặc khi giá hồi đủ).
- Bảo toàn an toàn vốn: giới hạn tổng exposure across lifecycles, đồng bộ risk cap.

## Concept Overview
- **Lifecycle Manager**: tầng mới ở EA (`CStrategySupervisor`) quản lý danh sách `CLifecycleController` (mỗi controller tương ứng một magic code).
- **Primary Lifecycle**: lifecycle đầu tiên gắn với magic mặc định (ví dụ `InpMagic`).
- **Legacy Lifecycle(s)**: khi primary báo "quá tải" (đạt trigger), supervisor spawn lifecycle mới với magic +1 (hoặc offset) để chạy grid mới.
- **Handover**: khi legacy đóng rổ thua/hòa vốn, nó dừng và supervisor xóa khỏi danh sách.

## Trigger Conditions to Spawn New Lifecycle
1. `primary` trong trạng thái thua kéo dài: `time_in_dd >= lc_spawn_min_bars` và `drawdown >= lc_spawn_dd_usd`.
2. Trend filter cho thấy thị trường vẫn có thể khai thác (slope/ATR cao) nhưng primary bị block (lockdown hoặc exposure cap).
3. `PortfolioLedger.TotalExposureLots()` + projected lot cho lifecycle mới ≤ `lc_max_total_lots`.
4. Cooldown: lần spawn trước cách hiện tại ≥ `lc_spawn_cooldown_bars`.

## Behaviour Once Spawned
- Supervisor tạo `CLifecycleController` mới với `magic = base_magic + index`.
- Lifecycle mới seeded với grid chuẩn (spacing/lots default) nhưng có flag `is_secondary`.
- Hedge/rescue logic chạy độc lập; ledger theo dõi exposure theo magic (cần mở rộng `CPortfolioLedger` để hỗ trợ nhiều magic).
- `primary` vẫn chạy nhưng có thể bị lockdown → không mở thêm order; chờ rescue/partial close/hand-off.

## Synchronization & Risk Control
- Supervisor loop (OnTick) sẽ:
  1. Gọi `Update()` tất cả lifecycle active.
  2. Tổng hợp exposure, realized profit, lock status.
  3. Nếu tổng exposure > cap hoặc equity dd vượt `session_sl_usd`, ra lệnh `FlattenAll()` cho mọi lifecycle.
- Legacy lifecycle có timeout `lc_legacy_max_bars`. Nếu vượt mà chưa hòa vốn → buộc đóng (fail-safe).

## Termination Conditions for Legacy Lifecycle
- Basket loser đã đóng hòa vốn (PnL ≥ 0) → log and delete.
- Drawdown vượt `lc_legacy_force_close_dd` → flatten and delete.
- Equity trailing stop hit (qua ledger) → flatten and delete.

## Parameters
| Input | Default | Meaning |
| --- | --- | --- |
| `InpLcEnableParallel` | false | Bật chế độ nhiều lifecycle. |
| `InpLcMaxActive` | 2 | Số lifecycle đồng thời (1 primary + n-1 legacy). |
| `InpLcSpawnMinBars` | 60 | Basket thua của primary phải tồn tại ≥ n bar. |
| `InpLcSpawnDD_USD` | 25.0 | Drawdown USD tối thiểu để spawn lifecycle mới. |
| `InpLcSpawnCooldownBars` | 120 | Cooldown giữa các lần spawn. |
| `InpLcLegacyMaxBars` | 200 | Legacy phải hoàn tất trong X bar. |
| `InpLcLegacyForceCloseDD` | 15.0 | Nếu legacy lỗ vượt USD này → đóng cưỡng bức. |
| `InpLcMaxTotalLots` | 3.0 | Tổng exposure allowed across lifecycles. |
| `InpLcMagicOffset` | 10 | Mỗi lifecycle mới dùng magic `base + offset * index`. |

Mapping vào `SParams` hoặc struct riêng `SLifecycleConfig` nếu muốn tách biệt.

## Architecture Changes
1. **New Supervisor class**
```cpp
class CStrategySupervisor
{
private:
    struct ControllerSlot
    {
        CLifecycleController *controller;
        long magic;
        bool primary;
        datetime spawn_time;
    };

    CArrayObj m_controllers; // active controllers
    long      m_base_magic;
    SParams   m_params;
    CSpacingEngine *m_spacing;
    COrderValidator *m_validator;
    CLogger *m_log;
    // ... references to ledger/executor/rescue factories

public:
    bool InitPrimary();
    void UpdateAll();
    void Shutdown();

private:
    bool ShouldSpawnLegacy();
    bool SpawnLegacy();
    void ReapFinished();
};
```

2. **EA Entry (OnInit)**
- Thay vì tạo single `CLifecycleController`, tạo `CStrategySupervisor`, pass dependencies.
- Supervisor tạo primary controller.

3. **Ledger**
- Update `CPortfolioLedger::TotalExposureLots` để tính theo tất cả magic trong danh sách.
- Có thể dùng `SetOfMagics` hoặc `std::map<long,double>`.

4. **OrderExecutor / RescueEngine**
- Mỗi controller cần executor riêng hoặc share executor nhưng set magic trước khi dùng.
- RescueEngine nhận params chung; optionally use `magic` to tag logs.

## Flowchart Supervisor
```mermaid
flowchart TD
    A[OnTick] --> B[Supervisor.UpdateAll]
    B --> C[Loop controllers]
    C -->|for each| D{Controller active?}
    D -- Yes --> E[controller->Update()]
    E --> F[Collect stats (DD, exposure)]
    F --> G{ShouldSpawnLegacy?}
    G -- Yes --> H[SpawnLegacy()]
    G -- No --> I[Check legacy termination]
    H --> I
    I --> J[FlattenAll if risk breached]
    J --> K[Reap finished controllers]
```

## Pseudo-code Highlights
```pseudo
bool CStrategySupervisor::ShouldSpawnLegacy()
{
    if(!params.lc_enable_parallel) return false;
    if(ActiveControllers() >= params.lc_max_active) return false;
    if(TimeSince(m_last_spawn) < params.lc_spawn_cooldown_bars) return false;

    CLifecycleController *primary = PrimaryController();
    if(primary == NULL) return false;

    if(primary->CurrentDrawdownUsd() < params.lc_spawn_dd_usd) return false;
    if(primary->TimeInDrawdownBars() < params.lc_spawn_min_bars) return false;
    if(!primary->Locked()) return false; // optionally require it to be locked/blocked

    double projected_lot = params.lot_base;
    if(ledger.TotalExposureLots(AllMagics()) + projected_lot > params.lc_max_total_lots)
        return false;

    return true;
}
```

```pseudo
bool CStrategySupervisor::SpawnLegacy()
{
    long magic = m_base_magic + params.lc_magic_offset * ActiveControllers();
    CLifecycleController *legacy = new CLifecycleController(..., magic);
    if(!legacy.Init()) { delete legacy; return false; }

    ControllerSlot slot;
    slot.controller = legacy;
    slot.magic = magic;
    slot.primary = false;
    slot.spawn_time = TimeCurrent();
    m_controllers.Add(slot);
    if(m_log) m_log.Event("[Supervisor]", StringFormat("Spawn legacy magic=%ld", magic));
    m_last_spawn = CurrentBarIndex();
    return true;
}
```

```pseudo
void CStrategySupervisor::ReapFinished()
{
    for each slot in m_controllers:
        if(slot.controller->IsFinished() || slot.primary==false && slot.controller->LegacyTimeout())
        {
            slot.controller->Shutdown();
            delete slot.controller;
            remove slot;
            if(m_log) m_log.Event("[Supervisor]", StringFormat("Legacy magic=%ld removed", slot.magic));
        }
}
```

```pseudo
bool CLifecycleController::IsFinished()
{
    return (!m_buy.IsActive() && !m_sell.IsActive());
}

bool CLifecycleController::LegacyTimeout()
{
    if(m_primary) return false;
    if(BarsSince(m_spawn_time) >= params.lc_legacy_max_bars)
        return true;
    if(CurrentDrawdownUsd() >= params.lc_legacy_force_close_dd)
        return true;
    return false;
}
```

## Testing Checklist
1. **Trend kéo dài**: primary vào lockdown → supervisor spawn legacy; legacy hoạt động độc lập (log magic khác). Quan sát exposure tổng ≤ `lc_max_total_lots`.
2. **Reset**: khi legacy đóng rổ (profit hoặc BE), supervisor xóa; primary tiếp tục, spawn cooldown áp dụng.
3. **Stress**: cố tình đặt `lc_max_active = 3` và trend dài để xem log spawn/kill chính xác.
4. **Risk breach**: nếu equity drawdown vượt `session_sl_usd`, supervisor buộc tất cả lifecycles flatten.
5. **Resource**: đảm bảo OnDeinit gọi `Supervisor.Shutdown()` đóng gọn mọi controller, không rò rỉ.
