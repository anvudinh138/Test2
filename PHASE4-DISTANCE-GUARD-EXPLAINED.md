# 📏 Distance Guard - Giải Thích Chi Tiết

## ❓ Câu Hỏi: "Distance Guard Hoạt Động Như Thế Nào?"

> **User**: "Distance: Stops if next level > InpMaxLevelDistance (500 pips): usecase này là sao bạn nhỉ, là giá tăng mạnh trong vài giây và lố 500 pip thì ko refill đúng ko"

---

## ✅ Trả Lời: ĐÚNG, nhưng có 1 chút khác biệt!

### 🎯 Distance Guard Là Gì?

**Guard này đo khoảng cách từ LEVEL SEED (level 0) đến LEVEL TIẾP THEO sẽ place.**

---

## 📐 Cách Hoạt Động

### Example: BUY Basket

**Seed**:
- Level 0 (market): `2030.00` ← Market order được fill ngay
- Level 1 (pending): `2029.75` (25 pips below) ← Pending limit

**Expansion**:
```
Spacing = 25 pips
Anchor = 2030.00 (level 0 seed price)

Level 1: 2030.00 - (25 * 1) = 2029.75  → Distance = 25 pips  ✓
Level 2: 2030.00 - (25 * 2) = 2029.50  → Distance = 50 pips  ✓
Level 3: 2030.00 - (25 * 3) = 2029.25  → Distance = 75 pips  ✓
Level 4: 2030.00 - (25 * 4) = 2029.00  → Distance = 100 pips ✓
```

**Nếu `InpMaxLevelDistance = 80` pips**:
```
Level 1: Distance = 25 pips   → ✓ OK (< 80)
Level 2: Distance = 50 pips   → ✓ OK (< 80)
Level 3: Distance = 75 pips   → ✓ OK (< 80)
Level 4: Distance = 100 pips  → ❌ BLOCKED! (> 80)

Log: "Expansion blocked: Distance 100.0 pips > 80.0 max"
```

Grid **dừng ở level 3**, không mở level 4!

---

## 🚨 Use Case: Khi Nào Guard Này Kích Hoạt?

### Scenario 1: Spacing Lớn
```
InpSpacingStepPips = 100 pips
InpMaxLevelDistance = 300 pips
InpGridLevels = 5

Level 0: 2030.00
Level 1: 2029.00  → Distance = 100  ✓
Level 2: 2028.00  → Distance = 200  ✓
Level 3: 2027.00  → Distance = 300  ✓
Level 4: 2026.00  → Distance = 400  ❌ BLOCKED!
```

**Lý do**: Spacing quá lớn → level xa quá → rủi ro cao!

### Scenario 2: Dynamic ATR Spacing (Volatility Cao)
```
ATR = 80 pips → Spacing = 80 * 0.6 = 48 pips
InpMaxLevelDistance = 150 pips

Level 0: 2030.00
Level 1: 2029.52  → Distance = 48   ✓
Level 2: 2029.04  → Distance = 96   ✓
Level 3: 2028.56  → Distance = 144  ✓
Level 4: 2028.08  → Distance = 192  ❌ BLOCKED!
```

**Lý do**: Volatility cao → ATR tăng → spacing lớn → nhanh chóng vượt limit!

### Scenario 3: Giá KHÔNG ẢNH HƯỞNG Trực Tiếp! ⚠️

**QUAN TRỌNG**: Distance guard **KHÔNG PHẢI** về giá tăng/giảm nhanh!

```
Giá hiện tại: 2025.00 (giảm 5$ từ seed!)
Seed anchor: 2030.00

Level tiếp theo: 2029.00
Distance = |2029.00 - 2030.00| = 100 pips

→ Guard chỉ care LEVEL TIẾP THEO cách SEED bao xa!
→ Không care giá thị trường hiện tại đang ở đâu!
```

---

## 🤔 Vậy Nếu Giá Tăng/Giảm Nhanh Thì Sao?

### Example: Giá Giảm Nhanh (BUY basket có lợi)

```
Seed: 2030.00
Current price: 2020.00 (giá giảm 10$ = 1000 pips!)

Level 4 sẽ place tại: 2029.00
Distance from seed: 100 pips

→ ✓ Guard PASS (< 500 pips)
→ Pending sẽ được place tại 2029.00
→ Nhưng IsPriceReasonable() check: 2029.00 < 2020.00? NO!
→ ❌ BLOCKED by Guard 4: "Price on wrong side of market"
```

**Kết luận**: Có guard khác (`IsPriceReasonable`) để handle case này!

### Example: Giá Tăng Nhanh (BUY basket bị trap)

```
Seed: 2030.00
Current price: 2035.00 (giá tăng 5$ = 500 pips!)

Level 4 sẽ place tại: 2029.00
Distance from seed: 100 pips

→ ✓ Distance guard PASS
→ ✓ IsPriceReasonable() PASS (2029.00 < 2035.00 = BUY below ✓)
→ ✓ Pending placed thành công!

Nhưng basket đang floating loss -500 pips!
→ DD guard có thể kick in nếu DD < -20%
```

**Kết luận**: DD guard sẽ protect trong case này!

---

## 🎯 Guard Priority (Order of Checks)

```cpp
bool ShouldExpandGrid()
{
   // 1. Max Levels (hard limit)
   if(currentMaxLevel >= max_levels - 1)
      return false;  // Can't expand beyond grid size
   
   // 2. DD Threshold (risk management)
   if(dd_pct < max_dd_expansion)
      return false;  // Losing too much, stop!
   
   // 3. Distance (structural limit)
   if(distance_pips > max_distance)
      return false;  // Next level too far from seed
   
   // 4. Price Direction (safety check)
   if(!IsPriceReasonable(next_price))
      return false;  // Pending on wrong side of market
   
   return true;  // All clear!
}
```

---

## 📊 Recommended Settings

### Conservative (Tight Control):
```
InpMaxLevelDistance = 100-150 pips
InpSpacingStepPips = 25 pips
InpGridLevels = 5

→ Max 4 levels (0-3), distance = 75 pips
```

### Moderate (Default):
```
InpMaxLevelDistance = 300-500 pips
InpSpacingStepPips = 25 pips
InpGridLevels = 5

→ Max 5 levels (0-4), distance = 100 pips
```

### Aggressive (Wide Grid):
```
InpMaxLevelDistance = 1000 pips
InpSpacingStepPips = 50-100 pips
InpGridLevels = 10

→ Max 10 levels, distance = 500-900 pips
```

---

## 🔒 Safety Net

**Distance guard** là safety net để:
1. ✅ Prevent over-extension (grid quá xa)
2. ✅ Limit max exposure (không place quá nhiều level xa seed)
3. ✅ Work with dynamic spacing (ATR thay đổi)
4. ✅ Protect against misconfiguration (spacing quá lớn)

**Kết hợp với**:
- **DD guard**: Stop if losing too much
- **Price guard**: Stop if price on wrong side
- **Max levels**: Hard limit grid size

---

## 💡 Summary

| Guard | Purpose | Checks |
|-------|---------|--------|
| **Max Levels** | Hard limit | `currentLevel >= max - 1` |
| **DD Threshold** | Risk management | `DD% < -20%` |
| **Distance** | Structural limit | `nextLevel distance > 500 pips from seed` |
| **Price Direction** | Safety | `BUY below / SELL above market` |

**Distance guard = "Đừng place pending quá xa so với điểm seed ban đầu"**  
**Không phải = "Giá thị trường di chuyển nhanh"** (đó là job của DD guard và Price guard!)

---

**Bạn muốn adjust settings này không?** Hay keep default 500 pips? 🎯

