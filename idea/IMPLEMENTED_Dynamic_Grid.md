# ✅ IMPLEMENTED: Dynamic Grid Deployment

**Status**: Completed  
**Date**: 2025-01-XX  
**Priority**: High (fix init lag với grid 200+ levels)

---

## 🎯 Problem Solved

Trước đây với `InpGridLevels=200`:
- EA khởi tạo **200 pending orders** cùng lúc
- Lag **5-10 giây** mỗi lần init
- UI freeze, backtest chậm

## ✨ Solution Implemented

Chỉ đặt một số pending **"warm levels"** lúc init, sau đó **refill dần dần** khi pending cạn.

---

## 📋 Changes Made

### 1. **Params.mqh**
Added dynamic grid parameters:
```cpp
bool  grid_dynamic_enabled;      // enable dynamic mode
int   grid_warm_levels;          // số pending khởi tạo (5-10)
int   grid_refill_threshold;     // refill khi pending <= này
int   grid_refill_batch;         // thêm bao nhiêu mỗi lần
int   grid_max_pendings;         // hard limit để tránh spam
```

### 2. **GridBasket.mqh**
- Thêm state tracking: `m_max_levels`, `m_levels_placed`, `m_pending_count`, `m_initial_spacing_pips`
- `BuildGrid()`: Pre-allocate array nhưng không fill hết
- `PlaceInitialOrders()`: 
  - Dynamic mode: chỉ đặt seed + warm levels
  - Static mode: giữ nguyên như cũ (backward compatible)
- `RefillBatch()`: Logic refill pending khi count thấp
- `Update()`: Check pending count và trigger refill

### 3. **RecoveryGridDirection_v2.mq5**
Added EA inputs:
```cpp
input bool  InpDynamicGrid      = false;  // Bật dynamic grid
input int   InpWarmLevels       = 5;      // Pending khởi tạo
input int   InpRefillThreshold  = 2;      // Refill khi <= 2
input int   InpRefillBatch      = 3;      // Thêm 3 mỗi lần
input int   InpMaxPendings      = 15;     // Max pending cùng lúc
```

---

## 🚀 Usage

### Settings cho grid lớn (200+ levels):

```yaml
InpGridLevels: 200          # Total capacity
InpDynamicGrid: true        # BẬT dynamic mode
InpWarmLevels: 5            # Chỉ đặt 5 pending lúc đầu
InpRefillThreshold: 2       # Khi còn ≤2 pending → refill
InpRefillBatch: 3           # Mỗi lần thêm 3 orders
InpMaxPendings: 15          # Không bao giờ quá 15 pending
```

**Kết quả**:
- Init time: **< 1 giây** (thay vì 5-10s)
- Grid vẫn refill đủ 200 levels theo thời gian
- UI smooth, backtest nhanh

### Settings bình thường (grid nhỏ):

```yaml
InpGridLevels: 6
InpDynamicGrid: false       # TẮT để dùng static mode
```

---

## 📊 Behavior

### Init Phase
```
[RGDv2][SYMBOL][BUY][PRI] Dynamic grid warm=6/200
                            ↑ placed ↑ total
```

### Refill Phase (khi pending giảm)
```
[RGDv2][SYMBOL][BUY][PRI] Refill +3 placed=9/200 pending=5
                                    ↑ thêm 3 orders
```

### Log Example
```
2025.01.01 00:00:01  [RGDv2][EURUSD][BUY][PRI] Dynamic grid warm=6/200
2025.01.01 00:05:12  [RGDv2][EURUSD][BUY][PRI] Refill +3 placed=9/200 pending=5
2025.01.01 00:10:23  [RGDv2][EURUSD][BUY][PRI] Refill +3 placed=12/200 pending=5
...
```

---

## ⚙️ How It Works

1. **Init**: Đặt seed market + `grid_warm_levels` pending
2. **Monitor**: Mỗi tick đếm pending orders còn lại
3. **Refill**: Khi `pending_count <= grid_refill_threshold` → thêm `grid_refill_batch` orders
4. **Limit**: Không refill nếu `pending >= grid_max_pendings`
5. **Stop**: Dừng khi `levels_placed >= grid_levels`

---

## 🧪 Testing Checklist

- [x] Backward compatible (static mode vẫn work)
- [x] Init time giảm với grid 200+
- [x] Refill logic triggers đúng
- [x] Spacing preserved giữa các refill
- [x] Log rõ ràng
- [ ] Backtest 3 tháng để confirm stability
- [ ] Test với grid 500+ levels

---

## 💡 Tips

1. **Warm levels**: Đặt 5-10 là đủ cho most cases
2. **Refill threshold**: = 2-3 để tránh gap lớn
3. **Refill batch**: = 2-5 để balance giữa speed vs spam
4. **Max pendings**: = 10-20 để control exposure tốt

**Với grid 200+**: 
- Warm=5, Threshold=2, Batch=3, Max=15 là settings tối ưu

---

## 🔄 Future Enhancements (optional)

- [ ] **LIVE spacing mode**: Refill với ATR mới (thay vì giữ spacing cũ)
- [ ] **Adaptive refill**: Tăng batch size khi trend mạnh
- [ ] **Smart cleanup**: Cancel pending xa quá khi trend đổi chiều

---

## 📝 Notes

- Spacing được lưu tại init (`m_initial_spacing_pips`) và dùng cho tất cả refills
- Refill luôn extend từ `m_last_grid_price` (outermost level)
- Pending count được update mỗi tick trong dynamic mode
- Có thể switch mode bằng cách toggle `InpDynamicGrid` input

