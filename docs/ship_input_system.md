# Ship Input System — Tài liệu kỹ thuật
> Cập nhật: 2026-06-23 · File chính: `scripts/movement/ship_movement_integrate.gd`

## Tổng quan kiến trúc

```
Input Event → Global_Input._input() → Global_Camera.handle_input()
                                           │
                                           └── (nếu không bị exclude)
                                                  ↓ (event còn lại)
ship_movement_integrate._unhandled_input(event)
  └── FlightInputState Machine
        ├── IDLE          → click → move / shift
        ├── SEQUENCE_MOVE → click nhanh hoặc hold + drag
        └── SHIFT_MOVE    → drag chọn vị trí → set facing
```

Ship **tự đọc input** qua `_unhandled_input()`. Scene controller (`ship_moving_scene.gd`) chỉ còn là shell gọi `Global_Input`. Flight input state machine nằm hoàn toàn trong `ship_movement_integrate.gd`.

---

## Các mode di chuyển

### PlayerState (vật lý)
| State | Ý nghĩa |
|---|---|
| `IDLE` | Ship đứng im / đang phanh |
| `MOVE` | Ship đang bay tới waypoint |

### FlightInputState (input state machine)
| State | Kích hoạt | Hành vi |
|---|---|---|
| `IDLE` | Mặc định | Chờ click / shift / scroll |
| `SEQUENCE_MOVE` | Giữ `sequence_move` + click | Buffer pos → chờ click nhanh hoặc hold để chỉnh hướng |
| `SHIFT_MOVE` | Nhấn `direction_shift_move` | Drag chọn vị trí trong bán kính → chọn hướng arrival |
| `ENERGY_TURN` | Nhấn `energy_turn` | Drag chọn hướng trên XZ → nhấn "move" để xoay 3x về hướng đó |

### Inner State
| Outer State | Inner State | Ý nghĩa |
|---|---|---|
| `SEQUENCE_MOVE` | `HOLD_MOUSE` | Đang đếm timer, chờ phân biệt click vs hold |
| `SEQUENCE_MOVE` | `CHANGE_DIRECTION` | Đã vào hold mode, đang drag để set arrival facing |
| `SHIFT_MOVE` | `DRAG_MOUSE_AND_OFFSET` | Đang di chuột để chọn vị trí waypoint |
| `SHIFT_MOVE` | `CHANGE_DIRECTION` | Đã chọn vị trí, đang drag để set arrival facing |
| `ENERGY_TURN` | `NONE` | Chưa vào energy turn |
| `ENERGY_TURN` | `DRAG_MOUSE_AND_OFFSET` | Đang di chuột để chọn hướng. Press "move" → set `is_energy_turning=true` + về IDLE |
---

## Input Controls

### Click to move

```
[MOUSE_MODE_VISIBLE] + click trái (move action)
  → shoot_ray_3d() lấy điểm trên mặt phẳng world
  → Vào input_state_idle():
       ├── Nếu giữ "sequence_move" → buffer pos vào SEQUENCE_MOVE
       └── Nếu không → move_to(click_pos, is_sequence=false) ngay
```

- Không giữ sequence: clear queue, di chuyển thẳng đến điểm mới
- Giữ sequence: buffer pos → vào SEQUENCE_MOVE (chờ click nhanh hoặc hold)

---

### Sequence + Click vs Hold (phân biệt bằng timer)

```
[Trong input_state_idle]
Click "move" + giữ "sequence_move"
  → Raycast → sequence_target_position = click_pos
  → _change_flight_state(SEQUENCE_MOVE)
  → inner = HOLD_MOUSE, input_hold_timer = 0.0

[Trong process_flight_input] (mỗi frame)
  → input_hold_timer += delta

[Trong input_state_sequence_move]
  │
  ├── Thả chuột < 0.2s  →  CLICK NHANH
  │       move_to(sequence_target_position, true)
  │       → Tạo waypoint MỚI trong queue
  │       → về IDLE
  │
  └── input_hold_timer ≥ 0.2s → HOLD MODE
          inner = CHANGE_DIRECTION
          → KHÔNG tạo waypoint mới
          → Chờ drag để set arrival_facing waypoint cuối
          → Thả chuột → confirm facing → về IDLE
```

**Cơ chế:** timer (`input_hold_timer`) được tích lũy trong `process_flight_input()` mỗi frame. Khi release, nếu timer < `input_hold_threshold` (0.2s) → click nhanh. Nếu timer ≥ threshold → hold mode.

**Tại sao ray cast ngay khi nhấn?** Để vị trí world được tính tại đúng thời điểm click, không bị lệch nếu camera/tàu di chuyển trong lúc chờ timer.

> Lưu ý: Không còn biến `_is_press_pending`, `_pending_click_pos`, `_is_holding_sequence_mouse`. Thay thế bằng state machine: `current_input_inner_state`, `sequence_target_position`, `input_hold_timer`.

---

### Drag để set Arrival Facing

Khi đã vào HOLD MODE (`current_input_inner_state == CHANGE_DIRECTION`):

```
Di chuyển chuột (InputEventMouseMotion)
│
├─ mouse_direction_accumulated += event.relative   # Vector2 tích lũy hướng
│
└─ Nếu mouse_direction_accumulated.length_squared() ≥ 1.0:
        preview_dir = calculate_translate_direction_from_mouse_motion(
                          mouse_direction_accumulated, camera_basis)
        set_arrival_facing_preview(preview_dir, true)
        → Hiện mũi tên VÀNG tại waypoint cuối

Thả chuột sau drag:
        confirm_last_waypoint_arrival_facing()
        → Ghi preview_dir vào waypoint.arrival_facing
        → Tắt mũi tên vàng
        → về IDLE
```

> **Khác biệt so với doc cũ:** Chỉ dùng **1 biến** `mouse_direction_accumulated` (Vector2) cho cả phát hiện threshold và tính hướng. Không có scalar riêng. Threshold dùng `length_squared() < 1.0` (≈ 1 pixel).

---

### Project 2D mouse → World XZ direction

```gdscript
func calculate_translate_direction_from_mouse_motion(accum: Vector2, camera_basis: Basis) -> Vector3:
```

> Gồm 2 tham số: `accum` (Vector2 tích lũy) và `camera_basis` (basis của camera hiện tại). Không còn dùng global camera basis vì ship tự gọi.

Chuyển đổi vector 2D màn hình → hướng world XZ dựa theo góc nhìn camera:

```
accum.x (+) = kéo phải  → hướng camera-right  (basis.x)
accum.y (+) = kéo xuống → hướng camera-forward (basis.z, flatten Y=0)
```

**Ví dụ — Camera nhìn về phía Bắc (−Z):**
```
cam_right        = (1, 0, 0)   # Đông
cam_forward_flat = (0, 0, 1)   # Nam

accum = (30, 8)  → kéo phải nhiều, xuống ít
world_dir = (1,0,0)*30 + (0,0,1)*8 = (30,0,8).normalized()
          ≈ Đông-Nam nhẹ
```

**Ví dụ — Camera xoay 90° nhìn về phía Đông (+X):**
```
cam_right        = (0, 0, 1)   # Nam
cam_forward_flat = (1, 0, 0)   # Đông

accum = (30, 8)  → cùng cử chỉ chuột
world_dir = (0,0,1)*30 + (1,0,0)*8 = (8,0,30).normalized()
          ≈ Nam-Đông nhẹ  ← tự thích nghi theo camera!
```

---

### ENERGY_TURN — Chọn hướng và xoay (3x power)

```
[MOUSE_MODE_VISIBLE] + nhấn "energy_turn"
  → vào ENERGY_TURN (inner = DRAG_MOUSE_AND_OFFSET)
  → di chuột → cập nhật target trên mặt phẳng XZ (clamp radius)
  → DebugDraw3D: vòng tròn cam + mũi tên từ ship đến target
  → nhấn "move" để xác nhận:
      • is_energy_turning = true
      • về IDLE
      • _integrate_forces: update_rotation với 3x rotation_power_to_mass_ratio
      • tự thoát khi angle < 1°
  → nhấn "energy_turn" lần nữa hoặc left-click → cancel, về IDLE
```

**Giới hạn:**
- Target luôn nằm trên mặt phẳng XZ (cùng Y với ship)
- Clamp trong `energy_turn_radius` (mặc định 10m)
- Scroll không có tác dụng — ENERGY_TURN không tạo waypoint

### Scroll — Chỉnh độ cao

```
[Trong input_state_idle hoặc input_state_sequence_move]
Giữ "sequence_move" + scroll  →  adjust_waypoint_target_height(±1)
                                  chỉnh Y của waypoint cuối trong queue
                                  (có giới hạn theo góc pitch tối đa)

[Trong input_state_shift_move — không cần modifier]
Scroll                        →  adjust_shift_target_height(±1)
                                  cộng dồn offset, clamp [-30, 30]
```

Camera **không** nhận scroll khi đang giữ `sequence_move`, `direction_shift_move` hoặc `energy_turn` nhờ guard trong `Global_Camera.handle_input()`. Energy turn cũng không dùng scroll.

---

## Ship APIs (gọi nội bộ trong ship_movement_integrate.gd)

| Hàm | Mô tả |
|---|---|
| `move_to(pos, is_sequence)` | Tạo waypoint, thêm queue hoặc clear+set mới |
| `adjust_waypoint_target_height(offset)` | Chỉnh Y waypoint cuối trong queue (có pitch limit) |
| `adjust_shift_target_height(offset)` | Chỉnh offset Y cho shift, clamp [-30, 30] |
| `set_arrival_facing_preview(dir, active)` | Bật/tắt mũi tên vàng preview |
| `confirm_last_waypoint_arrival_facing()` | Ghi hướng drag vào waypoint.arrival_facing |
| `clear_all_waypoints()` | Xóa toàn bộ waypoint queue + marker |
| `create_shift_waypoint(pos)` | Tạo waypoint kiểu "shift" |
| `load_next_waypoint()` | Pop waypoint đầu queue |
| `_draw_energy_turn_debug(ship_pos, target_pos)` | Vẽ debug circle + arrow cho ENERGY_TURN |

> (Legacy) `change_moving_state(mode)` — tồn tại nhưng không còn được gọi, `current_moving_mode` không ảnh hưởng logic.

---

## FlightInputState Machine (trong ship_movement_integrate.gd)

| Biến | Kiểu | Ý nghĩa |
|---|---|---|
| `current_input_state` | `FlightInputState` | State hiện tại: IDLE / SEQUENCE_MOVE / SHIFT_MOVE / ENERGY_TURN |
| `current_input_inner_state` | `Variant` (enum) | Inner state: `SequenceMoveState`, `InputShiftState`, hoặc `InputEnergyTurnState` |
| `input_hold_timer` | `float` | Đếm thời gian giữ chuột (s) |
| `input_hold_threshold` | `float` | Ngưỡng 0.2s để phân biệt click vs hold |
| `input_delay_timer` | `float` | Delay chống chuyển state quá nhanh giữa DRAG → CHANGE |
| `sequence_target_position` | `Vector3` | Vị trí click được buffer khi vào SEQUENCE_MOVE |
| `mouse_direction_accumulated` | `Vector2` | Vector tích lũy hướng chuột khi drag |
| `shift_target_position` | `Vector3` | Vị trí waypoint shift hiện tại |
| `shift_target_distance` | `float` | Khoảng cách từ ship đến shift target |
| `energy_turn_target_position` | `Vector3` | Vị trí target trên XZ cho ENERGY_TURN |
| `is_energy_turning` | `bool` | Flag xoay 3x trong `_integrate_forces` |
| `energy_turn_desired_dir` | `Vector3` | Hướng normalized để xoay về |

### SequenceMoveState (inner state cho SEQUENCE_MOVE)
| Giá trị | Ý nghĩa |
|---|---|
| `NONE` | Chưa vào sequence |
| `HOLD_MOUSE` | Đang giữ chuột, chờ timer để phân biệt click vs hold |
| `CHANGE_DIRECTION` | Đã hold đủ lâu, đang drag để set arrival facing |

### InputShiftState (inner state cho SHIFT_MOVE)
| Giá trị | Ý nghĩa |
|---|---|
| `NONE` | Chưa vào shift |
| `DRAG_MOUSE_AND_OFFSET` | Đang di chuột để chọn vị trí waypoint (clamp radius) |
| `CHANGE_DIRECTION` | Đã chọn vị trí xong, đang drag để set arrival facing |

---

## Luồng tổng hợp

```text
[MOUSE_MODE_VISIBLE]

[IDLE]
├── Click "move" (không sequence) → move_to() ngay, về MOVE
├── Click "move" + giữ "sequence_move"
│     ↓ buffer sequence_target_position
│     ↓ vào SEQUENCE_MOVE (inner=HOLD_MOUSE)
│     ↓
│     ├── Release < 0.2s (click nhanh)
│     │     → move_to(pos, true) → waypoint mới → về IDLE
│     │
│     └── Hold ≥ 0.2s
│           → inner = CHANGE_DIRECTION
│           → drag → preview arrow vàng
│           → release → confirm facing → về IDLE
│
├── Press "direction_shift_move"
│     ↓ create_shift_waypoint()
│     ↓ vào SHIFT_MOVE (inner=DRAG_MOUSE_AND_OFFSET)
│     ↓
│     ├── Drag chuột → cập nhật waypoint pos (clamp radius)
│     ├── Press "move" → inner = CHANGE_DIRECTION
│     │     → drag → preview arrow vàng
│     │     → press "move" + delay > 0.1s → confirm facing → về IDLE
│     └── Press "direction_shift_move" lần nữa → cancel → về IDLE
│
├── Press "energy_turn"
│     ↓ set energy_turn_target_position từ raycast
│     ↓ vào ENERGY_TURN (inner=DRAG_MOUSE_AND_OFFSET)
│     ↓
│     ├── Drag chuột → cập nhật target trên XZ (clamp radius)
│     │     → DebugDraw3D: circle + arrow
│     ├── Press "move" (chuột trái) → confirm:
│     │     → energy_turn_desired_dir = direction
│     │     → is_energy_turning = true
│     │     → về IDLE
│     │     → _integrate_forces: reset rotation delay + xoay 3x đến khi angle < 1°
│     └── Press "energy_turn" lần nữa → cancel → về IDLE
│
├── Scroll + "sequence_move" → adjust_waypoint_target_height()
└── Press "clear_waypoints" → clear all → về IDLE
```
