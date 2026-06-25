# State Machine Relationships — PlayerState / FlightInputState / InputMovingState
> File chính: `scripts/movement/ship_movement_integrate.gd` · Cập nhật: 2026-06-23

---

## 1. Tổng quan — 3 lớp state riêng biệt

Có **3 enum state** trong `ship_movement_integrate.gd`, mỗi enum phục vụ 1 layer khác nhau:

```text
┌─────────────────────────────────────────────────────┐
│                  LỚP 1: VẬT LÝ                       │
│              PlayerState {IDLE, MOVE}                 │
│  Điều khiển: _integrate_forces(), _physics_process()  │
│  Biến: current_state                                  │
├─────────────────────────────────────────────────────┤
│                  LỚP 2: INPUT                         │
│        FlightInputState {IDLE, SEQUENCE_MOVE,         │
│                          SHIFT_MOVE, ENERGY_TURN}     │
│  Điều khiển: _unhandled_input(), process_flight_input │
│  + inner state (SequenceMoveState / InputShiftState)  │
│  Biến: current_input_state                            │
├─────────────────────────────────────────────────────┤
│           LỚP 3: LEGACY (KHÔNG DÙNG)                  │
│   InputMovingState {IDLE, SEQUENCE_MOVE,              │
│                     SHIFT_DIRECTION, ENERGY_TURN}      │
│  Biến: current_moving_mode (tồn tại nhưng không        │
│         ảnh hưởng gì đến logic)                       │
└─────────────────────────────────────────────────────┘
```

---

## 2. PlayerState — Lớp vật lý

**Mục đích:** Xác định ship đang bay hay đứng im, ảnh hưởng đến `_integrate_forces`.

| Giá trị | Ý nghĩa | Xử lý trong `_integrate_forces` |
|---------|---------|-------------------------------|
| `IDLE` | Ship đứng im | `handle_state_idle` → phanh, damping, roll/pitch correction |
| `MOVE` | Ship đang bay tới waypoint | Gọi `compute_sequence_move_target_direction()` hoặc `compute_shift_move_target_direction()` |

**Chuyển đổi:**
```
IDLE ── move_to() → MOVE
MOVE ── hết waypoint → IDLE
```

**Code tham chiếu:** `change_state()`, `_integrate_forces()`, `handle_state_idle()`

---

## 3. FlightInputState — Lớp input state machine

**Mục đích:** Xác định **người chơi đang làm gì với chuột** — dispatch input event đến handler phù hợp.

| Giá trị | Kích hoạt | Inner State | Hành vi |
|---------|-----------|-------------|---------|
| `IDLE` | Mặc định | (không) | Click → move_to hoặc vào SEQUENCE_MOVE/SHIFT_MOVE/ENERGY_TURN |
| `SEQUENCE_MOVE` | Giữ `sequence_move` + click | `HOLD_MOUSE` → `CHANGE_DIRECTION` | Chờ click nhanh hoặc hold + drag để set arrival facing |
| `SHIFT_MOVE` | Nhấn `direction_shift_move` | `DRAG_MOUSE_AND_OFFSET` → `CHANGE_DIRECTION` | Drag chọn vị trí, click để set arrival facing |
| `ENERGY_TURN` | Nhấn `energy_turn` | `DRAG_MOUSE_AND_OFFSET` | Drag chọn hướng trên XZ → nhấn "move" để xoay 3x về hướng đó |

### Inner States

**SequenceMoveState** (dùng khi `FlightInputState.SEQUENCE_MOVE`):

| Giá trị | Ý nghĩa |
|---------|---------|
| `NONE` | Chưa vào sequence |
| `HOLD_MOUSE` | Đang giữ chuột, tích lũy `input_hold_timer`. Nếu release sớm → click nhanh. Nếu timer ≥ `input_hold_threshold` (0.2s) → chuyển `CHANGE_DIRECTION` |
| `CHANGE_DIRECTION` | Đã giữ đủ lâu, drag → update preview arrow. Release → confirm arrival_facing |

**InputShiftState** (dùng khi `FlightInputState.SHIFT_MOVE`):

| Giá trị | Ý nghĩa |
|---------|---------|
| `NONE` | Chưa vào shift |
| `DRAG_MOUSE_AND_OFFSET` | Đang di chuột, cập nhật `shift_target_position`, clamp bán kính. Press "move" → chuyển `CHANGE_DIRECTION` |
| `CHANGE_DIRECTION` | Drag → update preview arrow. Press "move" + `input_delay_timer > 0.1s` → confirm arrival_facing, về IDLE |

### Sơ đồ state machine

```text
                         ┌──────────┐
          ┌──────────────│   IDLE   │──────────────────────────┐
          │              └──────────┘                          │
          │ click + seq         │ press shift    press energy  │
          ▼                     │                  │           ▼
┌──────────────────┐            │                  │  ┌──────────────────────┐
│  SEQUENCE_MOVE   │◄───────────┘                  │  │     SHIFT_MOVE       │
│                  │                              │  │                      │
│ inner:           │                              │  │ inner:               │
│ HOLD_MOUSE       │                              │  │ DRAG_MOUSE_AND_      │
│   ├ release<0.2s│→ IDLE (waypoint mới)         │  │   OFFSET              │
│   └ timer≥0.2s  │→ CHANGE_DIRECTION            │  │   ├ press "move"     │→ CHANGE_DIR
│                  │                              │  │   └ press shift     │→ IDLE (cancel)
│ CHANGE_DIRECTION │                              │  │                      │
│   ├ drag        │→ preview vàng                │  │ CHANGE_DIRECTION     │
│   └ release     │→ confirm facing → IDLE       │  │   ├ drag            │→ preview vàng
│                  │                              │  │   └ press "move"    │→ confirm → IDLE
└──────────────────┘                              │  └──────────────────────┘
                                                  ▼
                              ┌──────────────────────────┐
                              │      ENERGY_TURN         │
                              │                          │
                              │ inner:                   │
                              │ DRAG_MOUSE_AND_OFFSET    │
                              │   ├ drag       │→ cập nhật target XZ
                              │   ├ press "move"│→ is_energy_turning=true
                              │   │             │→ IDLE → xoay 3x trong physics
                              │   └ press energy│→ IDLE (cancel)
                              └──────────────────────────┘
```

**Code tham chiếu:** `_unhandled_input()`, `_change_flight_state()`, `process_flight_input()`, `input_state_idle()`, `input_state_sequence_move()`, `input_state_shift_move()`

---

## 4. InputMovingState — LEGACY / DEAD CODE

### Kết luận: **KHÔNG DÙNG, HOÀN TOÀN THỪA**

| Evidence | Chi tiết |
|----------|---------|
| Chỉ gán 1 lần | `current_moving_mode = InputMovingState.IDLE` trong `_ready()` |
| Không ai gọi `change_moving_state()` | Không có lời gọi nào trong toàn project (file `ship_movement_integrate.gd`) |
| Không ai check `current_moving_mode` | Không có `if current_moving_mode == ...` trong bất kỳ logic nào |
| Chỉ hiển thị debug | `"\nMoving state : " + str(current_moving_mode)` — chỉ để đọc trên label |
| Nguồn gốc | Copy từ `docs/draff.gd` (file prototype cũ) — ở đó `current_moving_mode` được check ở vài chỗ |

**Nên xoá** hoặc comment rõ "LEGACY — sẽ xoá sau khi refactor".

---

## 5. Mối quan hệ giữa các state

### Luồng thực tế (không qua InputMovingState):

```
Input Event
  │
  ▼
FlightInputState (current_input_state)
  │── IDLE           → PlayerState  không bị ảnh hưởng trực tiếp
  │── SEQUENCE_MOVE  → PlayerState  không bị ảnh hưởng trực tiếp
  └── SHIFT_MOVE     → PlayerState  không bị ảnh hưởng trực tiếp
         │
         │ (khi click xác nhận hoặc click di chuyển)
         ▼
PlayerState (current_state)
  │── IDLE → ship đứng im
  └── MOVE → ship bay tới waypoint
```

> `FlightInputState` quyết định **người chơi đang thao tác gì**.
> `PlayerState` quyết định **ship đang làm gì về mặt vật lý**.
> Chúng độc lập và **không khóa chặt nhau**.

### Ví dụ:
- `FlightInputState.IDLE` + `PlayerState.MOVE`: người chơi không làm gì, nhưng ship đang bay
- `FlightInputState.SHIFT_MOVE` + `PlayerState.MOVE`: người chơi đang drag shift waypoint trong khi ship vẫn bay tới target cũ
- `FlightInputState.SEQUENCE_MOVE` + `PlayerState.IDLE`: người chơi đang giữ chuột để chọn hướng, ship chưa di chuyển

---

## 6. Cách thêm 1 move mới (ví dụ: ENERGY_TURN)

Giả sử bạn muốn thêm move `ENERGY_TURN` — ship xoay tại chỗ về hướng chỉ định.

### Bước 1: Thêm vào `FlightInputState` (nếu cần input state mới)

```gdscript
enum FlightInputState { IDLE, SEQUENCE_MOVE, SHIFT_MOVE, ENERGY_TURN }
```

### Bước 2: Tạo inner state enum (nếu cần inner state)

```gdscript
enum EnergyTurnState {NONE, SELECTING_DIRECTION, CONFIRMING}
```

### Bước 3: Thêm routing trong `_unhandled_input()`

```gdscript
FlightInputState.ENERGY_TURN: input_state_energy_turn(event, mouse_hover_position, camera_basis)
```

### Bước 4: Tạo handler function

```gdscript
func input_state_energy_turn(event: InputEvent, mouse_hover_position: Variant, camera_basis: Basis) -> void:
    # Xử lý input cho energy turn
    pass
```

### Bước 5: Thêm trigger trong `input_state_idle()`

```gdscript
# Nhấn nút energy turn
if event.is_action_pressed("energy_turn") and mouse_hover_position != null:
    _change_flight_state(FlightInputState.ENERGY_TURN)
```

### Bước 6: Thêm cleanup trong `_change_flight_state()`

```gdscript
# Trong phần cleanup cho state cũ (khi rời ENERGY_TURN)
FlightInputState.ENERGY_TURN:
    # clean up energy turn state
    pass

# Trong phần init cho state mới (khi vào ENERGY_TURN)
FlightInputState.ENERGY_TURN:
    current_input_inner_state = EnergyTurnState.SELECTING_DIRECTION
    # init...
```

### Bước 7: (Nếu move có hành vi vật lý mới) — Thêm waypoint type hoặc xử lý trong PlayerState.MOVE

Nếu `ENERGY_TURN` là waypoint đặc biệt (giống "shift"), thêm type:

```gdscript
# Trong create_energy_turn_waypoint():
Movement_Waypoint.new(pos, prev_pos, "energy_turn")

# Trong _integrate_forces → PlayerState.MOVE:
"energy_turn":
    compute_energy_turn_target_direction(...)
```

### Bước 8: Đồng bộ lên Global_Input (nếu cần)

```gdscript
# Trong _change_flight_state():
FlightInputState.ENERGY_TURN:
    Global_Input.change_input_state(Global_Input.InputState.ENERGY_TURN)  # cần thêm enum
```

### Checklist tóm tắt:

| Bước | File | Thay đổi |
|------|------|----------|
| 1 | `ship_movement_integrate.gd` | Thêm vào `FlightInputState` enum |
| 2 | `ship_movement_integrate.gd` | (Nếu cần) Thêm inner state enum |
| 3 | `ship_movement_integrate.gd` | Thêm `match` case trong `_unhandled_input()` |
| 4 | `ship_movement_integrate.gd` | Viết `input_state_energy_turn()` |
| 5 | `ship_movement_integrate.gd` | Thêm trigger trong `input_state_idle()` |
| 6 | `ship_movement_integrate.gd` | Update `_change_flight_state()` (cleanup + init) |
| 7 | `ship_movement_integrate.gd` | (Nếu có physics) Thêm xử lý trong `_integrate_forces` |
| 8 | (Nếu cần) | Thêm `Global_Input.InputState` enum |
| — | `docs/ship_input_system.md` | Cập nhật mode table + flow diagram |
| — | `docs/state_relationships.md` | Cập nhật state machine diagram |

---

## 7. Memo cho dev — Các cạm bẫy thường gặp

| # | Vấn đề | Giải thích |
|---|--------|-----------|
| 1 | Quên cleanup inner state | Khi rời `FlightInputState`, `_change_flight_state()` tự động reset `current_input_inner_state`. Nếu thêm state mới, phải thêm cleanup + init tương ứng. |
| 2 | `change_moving_state()` là legacy | Đừng gọi hàm này. Nó không ảnh hưởng gì. |
| 3 | Không đồng bộ lên `Global_Input` | Camera có thể ăn mất input nếu không set `Global_Input.InputState`. |
| 4 | `_unhandled_input` vs `_input` | `_unhandled_input` chạy sau `_input`, nên Global_Input và Camera xử lý trước. Nếu Global_Input gọi `set_input_as_handled()`, ship sẽ không nhận event. |
| 5 | Mouse mode guard | Đầu `_unhandled_input` có `if event is InputEventMouseButton and Input.mouse_mode != MOUSE_MODE_VISIBLE: return`. Nếu thêm move dùng chuột, phải set `MOUSE_MODE_VISIBLE`. |
