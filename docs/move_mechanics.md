# Move Mechanics — Các Move & Ảnh Hưởng Đến Engine Parameters
> File chính: `scripts/movement/ship_movement_integrate.gd` · Cập nhật: 2026-06-26

---

## 1. Tổng Quan — Engine Parameters

Ship có **2 tham số engine** được tính tập trung qua `recalculate_power_ratios()`:

| Parameter | Công thức | Ảnh hưởng |
|---|---|---|
| `linear_power_to_mass_ratio` | `(max_thrust_force × boost) / mass` | Lực đẩy (thrust) |
| `rotation_power_to_mass_ratio` | `((torque + rcs) × (boost + boost × rot_boost) × turn_boost) / mass` | Tốc độ xoay (rotation) |

Các **flag** ảnh hưởng đến các multiplier trong công thức:

| Flag | Multiplier | Mặc định | Kích hoạt | Tỉ lệ lên Ratio |
|---|---|---|---|---|
| `is_combusion_boost_active` | `combusion_boost` | 1.0 | 2.0 | Linear: ×2, Rotation: ×(2+2×0.25) = ×2.5 |
| `is_energy_turning` | `turn_boost` | 1.0 | 3.0 | Rotation: ×3 |

---

## 2. Các Move Hiện Tại

### 2A. Sequence Move (di chuyển thường + queue waypoint)

| Thuộc tính | Giá trị |
|---|---|
| **Input trigger** | Click trái (`move`) — không giữ `sequence_move` |
| **FlightInputState** | `IDLE` (tạo waypoint ngay) hoặc `SEQUENCE_MOVE` (click nhanh sau hold) |
| **PlayerState** | `MOVE` |
| **Waypoint type** | `"sequence"` |
| **Engine ảnh hưởng** | Không — dùng ratio mặc định |

**Luồng:**
```
click → move_to(pos, false) → clear queue → tạo waypoint → load → MOVE
  └── _integrate_forces: match "sequence"
       ├── compute_sequence_move_target_direction()  ← direction blending
       ├── compute_sequence_move_thrust_control()    ← thrust + braking
       └── compute_sequence_move_lateral_damping()   ← triệt tiêu lateral
```

**Đặc điểm:**
- Xóa queue cũ, bay thẳng đến điểm mới
- Gần đích: blend hướng về `arrival_facing`
- Có `braking_dist` — giảm ga dần khi gần đích
- Lateral velocity bị triệt tiêu (chống trượt)

---

### 2B. Sequence + Hold (click + giữ để chỉnh arrival facing)

| Thuộc tính | Giá trị |
|---|---|
| **Input trigger** | Giữ `sequence_move` + click trái + giữ chuột > 0.2s |
| **FlightInputState** | `SEQUENCE_MOVE` → inner: `HOLD_MOUSE` → `CHANGE_DIRECTION` |
| **PlayerState** | `IDLE` (chưa tạo waypoint) hoặc `MOVE` (nếu đang bay) |
| **Waypoint type** | `"sequence"` (với `arrival_facing` được set) |
| **Engine ảnh hưởng** | Không |

**Luồng:**
```
giữ sequence_move + click → buffer pos → vào SEQUENCE_MOVE
  └── input_hold_timer += delta
      ├── release < 0.2s → click nhanh → move_to() → MOVE (giống 2A)
      └── ≥ 0.2s → inner = CHANGE_DIRECTION
          └── drag → preview vàng
          └── release → confirm arrival_facing → về IDLE
```

---

### 2C. Shift Move (chọn vị trí + hướng arrival)

| Thuộc tính | Giá trị |
|---|---|
| **Input trigger** | Nhấn `direction_shift_move` |
| **FlightInputState** | `SHIFT_MOVE` → inner: `DRAG_MOUSE_AND_OFFSET` → `CHANGE_DIRECTION` |
| **PlayerState** | `MOVE` (sau khi confirm) |
| **Waypoint type** | `"shift"` |
| **Engine ảnh hưởng** | Không — dùng ratio mặc định |

**Luồng:**
```
nhấn shift_move → create_shift_waypoint() → vào SHIFT_MOVE
  └── DRAG_MOUSE_AND_OFFSET:
      ├── di chuột → cập nhật shift_target_position + marker
      ├── scroll → adjust_shift_target_height()
      └── press "move" → inner = CHANGE_DIRECTION
  └── CHANGE_DIRECTION:
      ├── drag → preview vàng (arrival_facing)
      └── press "move" + delay > 0.1s → confirm facing → về IDLE + MOVE
```

**Đặc điểm (khác sequence):**
- Waypoint có `type = "shift"` và `arrival_facing` được set manual
- Ship blend hướng từ `direction_to_target` → `arrival_facing` dần khi gần đích
- **Không** triệt tiêu lateral velocity
- Alignment threshold thấp hơn (0.5 thay vì 0.85)
- Braking đơn giản — không có braking blend

---

### 2D. Energy Turn (xoay tại chỗ — không waypoint)

| Thuộc tính | Giá trị |
|---|---|
| **Input trigger** | Nhấn `energy_turn` → chọn hướng → nhấn `move` |
| **FlightInputState** | `ENERGY_TURN` → inner: `DRAG_MOUSE_AND_OFFSET` |
| **PlayerState** | `IDLE` (không tạo waypoint) |
| **Waypoint type** | Không có waypoint |
| **Engine ảnh hưởng** | `rotation_power_to_mass_ratio ×= 3.0` |

**Luồng:**
```
nhấn energy_turn → vào ENERGY_TURN
  └── DRAG_MOUSE_AND_OFFSET:
      ├── di chuột → cập nhật target trên XZ (clamp radius)
      └── press "move" → energy_turn_desired_dir set → is_energy_turning = true
                            → recalculate_power_ratios()  ← rotation boost ×3
                            → về IDLE
  └── cancel: press "energy_turn" lại hoặc left-click

_trong _integrate_forces:
  TẦNG 2: if is_energy_turning → update_rotation() với ratio đã ×3
  → tự thoát khi angle < 1° → recalculate_power_ratios() → trả ratio về gốc
```

**Đặc điểm:**
- **Không tạo waypoint** — ship xoay tại chỗ
- `rotation_power_to_mass_ratio` được ×3 (qua `recalculate_power_ratios`)
- Rotation dùng `update_rotation()` — đã được PD controller xử lý
- Lateral velocity bị lerp về 0 (0.5 × delta)
- Có auto-thoát khi gần đúng hướng (< 1°)
- Không thể bật `combusion_boost` khi đang energy turn

---

### 2E. Combustion Boost (toggle — tăng engine power)

| Thuộc tính | Giá trị |
|---|---|
| **Input trigger** | Nhấn `combusion_boost` (toggle) |
| **FlightInputState** | Bất kỳ (trừ ENERGY_TURN) |
| **PlayerState** | Bất kỳ |
| **Waypoint type** | Bất kỳ |
| **Engine ảnh hưởng** | `linear ×= 2.0`, `rotation ×= 2.5` |

**Công thức:**
```gdscript
# Khi is_combusion_boost_active = true:
combusion_boost = 2.0
rotation_boost  = 0.25  # chỉ nhân thêm vào rotation

linear_power_to_mass_ratio   = (max_thrust_force × 2.0) / mass           # ×2
rotation_power_to_mass_ratio = ((torque + rcs) × (2.0 + 2.0 × 0.25)) / mass  # ×2.5
```

**Đặc điểm:**
- Toggle: bấm lần 1 bật, lần 2 tắt
- Không thể bật khi đang energy turn (`and not is_energy_turning`)
- Gọi `recalculate_power_ratios()` để cập nhật
- Ảnh hưởng lên **cả thrust và rotation** nhưng rotation mạnh hơn (×2.5)

---

## 3. Tổng Hợp — Flag Combinations

| `is_energy_turning` | `is_combusion_boost_active` | `linear_power_to_mass_ratio` | `rotation_power_to_mass_ratio` |
|---|---|---|---|
| false | false | `thrust / mass` | `(torque + rcs) / mass` |
| false | true | `thrust × 2 / mass` | `(torque + rcs) × 2.5 / mass` |
| true | false | `thrust / mass` | `(torque + rcs) × 3 / mass` |
| true | true | `thrust × 2 / mass` | `(torque + rcs) × 7.5 / mass` |

---

## 4. State Machine Layers (Tóm tắt)

```
Layer 1: FlightInputState (input handling)
├── IDLE           — chờ click, shift, energy, scroll
├── SEQUENCE_MOVE  — phân biệt click nhanh vs hold để set facing
├── SHIFT_MOVE     — drag chọn vị trí → set facing
└── ENERGY_TURN    — drag chọn hướng → confirm xoay

Layer 2: PlayerState (physics)
├── IDLE  — phanh + damping
└── MOVE  — bay tới waypoint

Layer 3: Engine Flags (multipliers)
├── is_combusion_boost_active → boost ×2 (linear) / ×2.5 (rotation)
└── is_energy_turning         → rotation ×3 (chỉ khi đang xoay)
```

**Nguyên tắc:** `FlightInputState` và `PlayerState` **độc lập** — không khóa chặt nhau.
Ví dụ: có thể `FlightInputState.SHIFT_MOVE` + `PlayerState.MOVE` (đang bay + đang kéo shift).

---

## 5. Thêm Move Mới

Để thêm 1 move mới, cần:

1. **Nếu move có waypoint:** Thêm 1 case trong `match current_waypoint.type` (TẦNG 1)
2. **Nếu move không waypoint:** Thêm 1 `elif` flag check trong TẦNG 2 (steering) hoặc trong TẦNG 1 (thrust)
3. **Nếu move ảnh hưởng engine:** Thêm multiplier vào `recalculate_power_ratios()`
4. **Nếu move cần input riêng:** Thêm `FlightInputState` enum + handler function
