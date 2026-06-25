# Tài liệu: Kiến trúc Centralized Input + Camera Mode + Gameplay Mode
> Godot 4 · Project `3d_modular` · Cập nhật: 2026-06-23

> ⚠️ **Ghi chú kiến trúc thực tế:** Từ bản refactor gần đây, `ship_movement_integrate.gd` (RigidBody3D) tự xử lý input flight qua `_unhandled_input()` thay vì scene controller. Scene controller (`ship_moving_scene.gd`) chỉ còn là shell gọi `Global_Input`. Xem các section 4, 5 để biết chi tiết.

---

## 1. Mục tiêu tài liệu

Tài liệu này mô tả cách quản lý input khi game bắt đầu phức tạp:
- Tránh input chồng chéo giữa nhiều node.
- Tách rõ **đọc input** và **thực thi gameplay**.
- Tách rõ **camera mode** và **gameplay mode**.
- Dễ mở rộng mode mới (`FACING_SET`, `BUILDER`, ...).
- Dễ debug vì mọi quyết định input nằm tại 1 nơi.

---

## 2. Vấn đề thường gặp (trước khi refactor)

Khi nhiều node cùng xử lý `_input()` hoặc `_unhandled_input()`:
- Khó biết event được ăn ở node nào.
- Dễ conflict (ví dụ vừa scroll đổi cao độ, vừa trigger hành vi node khác).
- Đổi phím / remap Input Map sẽ phải sửa nhiều script.
- Tăng độ phức tạp khi có nhiều state gameplay.

---

## 3. Kiến trúc khuyến nghị

### 3.1. Quy tắc chính

1. **Scene Controller** là nơi duy nhất đọc input thô.
2. Node gameplay (ship, module...) không tự đọc input, chỉ expose API.
3. Camera rig có thể xử lý input riêng, nhưng phải đi qua API chung do scene gọi xuống.
4. **Camera mode** và **gameplay mode** là 2 lớp trạng thái khác nhau, không gộp chung.
5. Khi đã xử lý event, gọi `get_viewport().set_input_as_handled()` để chặn lan truyền.

### 3.2. Tách 2 lớp trạng thái

#### Camera mode

Quyết định **camera nào đang active**:
- free camera
- character camera far
- character camera close

Camera mode hiện tại được quản lý bởi:
- `Global_Camera.current_rig`
- `Global_Camera.switch_to(...)`

#### Gameplay mode

Quyết định **người chơi đang làm gì với world**:
- `FLIGHT`
- `FACING_SET` (tương lai)
- `BUILDER` (tương lai)

Điểm quan trọng:

> Đổi camera **không đồng nghĩa** với đổi gameplay mode.

Ví dụ:
- đang ở `FLIGHT`
- người chơi chuyển sang free camera
- gameplay vẫn là `FLIGHT`
- nghĩa là vẫn có thể click tạo waypoint bình thường

### 3.3. Sơ đồ tổng quát (thực tế hiện tại)

```text
Input Event
   │
   ├── [1] Global_Input._input(event)          # menu, toggle mouse
   │     └── Global_Camera.handle_input(event)  # switch cam, zoom, orbit
   │           (bỏ qua nếu đang giữ sequence_move / direction_shift_move)
   │
   ├── [2] ship_moving_scene._input(event)     # shell — chỉ pass qua Global_Input
   │
   └── [3] ship_movement_integrate._unhandled_input(event)  ← MAIN!
         └── FlightInputState Machine
               ├── IDLE          → click → move_to / create_shift_waypoint
               ├── SEQUENCE_MOVE → hold timer → click nhanh hoặc drag để set facing
               └── SHIFT_MOVE    → drag để chỉnh vị trí → click để set facing

   (Gọi API nội bộ trong ship — không qua scene controller)
        ├── move_to() / create_shift_waypoint()
        ├── adjust_waypoint_target_height() / adjust_shift_target_height()
        ├── set_arrival_facing_preview() / confirm_last_waypoint_arrival_facing()
        └── clear_all_waypoints()
```

### 3.4. Lớp đồng bộ — Global_Input

```
Global_Input.InputState { NONE, SEQUENCE_MOVE, SHIFT_MOVE }
  ↑ ship đồng bộ mỗi khi đổi FlightInputState
  ↓
Global_Camera.handle_input() check state để quyết định có ăn scroll/click không
```

- Khi ship vào `FlightInputState.SEQUENCE_MOVE` → set `Global_Input.InputState.SEQUENCE_MOVE`
- Khi ship vào `FlightInputState.SHIFT_MOVE` → set `Global_Input.InputState.SHIFT_MOVE`
- Về IDLE → set `Global_Input.InputState.NONE`
- Camera dùng `camera_exclude_input_list` + `camera_exclude_state_list` để skip input nếu cần

---

## 4. Phân vai trách nhiệm theo file (thực tế hiện tại)

### `scenes/ship_moving_scene.gd`

- Chứa `enum GameplayInputMode` và `current_gameplay_mode` (hiện chỉ có `FLIGHT`).
- `_input(event)` — chỉ gọi `Global_Input._input(event)` rồi pass.
- **Không còn xử lý input flight** — toàn bộ đã chuyển xuống ship.
- Có `_switch_gameplay_mode(new_mode)` cho tương lai.

### `camera/scripts/camera_base.gd`

- Chứa API input chung cho camera:
  - `handle_scene_input(event) -> bool`
- Mặc định trả `false` nếu camera không xử lý event.

### `camera/scripts/camera_free_node.gd`

- Tự xử lý input camera riêng qua `handle_scene_input(event)`:
  - mouse look
  - scroll zoom
- Nếu đang giữ modifier gameplay như `sequence_move` hoặc `direction_shift_move` thì trả `false` để nhường input xuống ship logic.

### `camera/scripts/camera_character_node.gd`

- Tự xử lý input orbit / zoom qua `handle_scene_input(event)`.
- Có thể giữ chuột để orbit quanh tàu mà không cần scene biết chi tiết implementation.

### `scripts/movement/ship_movement_integrate.gd`

- **Tự xử lý input flight** qua `_unhandled_input(event)` — đây là nơi duy nhất xử lý gameplay input.
- Chứa toàn bộ `FlightInputState` machine:
  - `IDLE` → nhận click để move / shift / clear
  - `SEQUENCE_MOVE` → click nhanh (waypoint) hoặc hold (drag để set arrival facing)
  - `SHIFT_MOVE` → drag để chọn vị trí, click để set facing
- Chứa API gameplay (gọi nội bộ):
  - `move_to(pos, is_sequence)`
  - `adjust_waypoint_target_height(offset)` / `adjust_shift_target_height(offset)`
  - `set_arrival_facing_preview(dir, active)` / `confirm_last_waypoint_arrival_facing()`
  - `clear_all_waypoints()`
- Chịu trách nhiệm tính toán vật lý/động học qua `_integrate_forces(state)`.

### `scripts/global/global_input.gd`

- Xử lý global input: menu, toggle mouse, đổi camera.
- Nhận diện `InputState` để camera biết khi nào không nên ăn input.
- Chứa `camera_exclude_input_list` và `camera_exclude_state_list` để camera skip input khi đang ở gameplay mode.

### `scripts/global/global_camera.gd`

- Quản lý camera rig active + switch camera.
- `handle_input(event)` — xử lý switch camera, mouse look, zoom.
- Check `Global_Input.camera_exclude_input_list` và `camera_exclude_state_list` để không consume input khi đang ở gameplay mode.

---

## 5. Luồng xử lý input thực tế

### 5.1. Thứ tự ưu tiên tổng quát

```text
Input Event
  │
  ├── [1] Global_Input._input(event)
  │     ├── Menu / ESC / Toggle mouse
  │     └── Global_Camera.handle_input(event)
  │           ├── Switch camera (FREE ↔ SHIP_FAR ↔ SHIP_CLOSE)
  │           ├── Mouse look (xoay camera)
  │           └── Zoom (scroll → spring arm length)
  │           (bỏ qua nếu đang giữ "sequence_move" hoặc "direction_shift_move")
  │
  └── [2] ship_movement_integrate._unhandled_input(event)  ← Main flight input
        └── FlightInputState Machine
              └── dispatch theo state hiện tại
```

> Scene controller (`ship_moving_scene.gd`) không còn tham gia xử lý input flight.

### 5.2. Click để di chuyển

```text
_unhandled_input(event)
  └── nếu FlightInputState.IDLE + action "move" + mouse_mode == VISIBLE
      └── raycast lấy click_pos
          ├── Nếu giữ "sequence_move" → buffer pos → vào SEQUENCE_MOVE
          └── Nếu không → move_to(click_pos, is_sequence=false) ngay
```

### 5.3. Sequence Move — Click vs Hold

```text
IDLE + click "move" + giữ "sequence_move"
  └── buffer sequence_target_position → vào SEQUENCE_MOVE
      └── HOLD_MOUSE (inner state)
            ├── release < 0.2s → move_to(pos, true) + về IDLE
            └── hold ≥ 0.2s → CHANGE_DIRECTION (inner state)
                  └── drag chuột → preview arrow vàng
                  └── release → confirm arrival_facing + về IDLE
```

### 5.4. Shift Move — Drag to set position + facing

```text
IDLE + action "direction_shift_move"
  └── create_shift_waypoint(raycast_pos) → vào SHIFT_MOVE
      └── DRAG_MOUSE_AND_OFFSET (inner state)
            └── mouse hover → cập nhật waypoint pos (clamp radius)
            └── press "move" → CHANGE_DIRECTION (inner state)
                  └── drag → preview arrow vàng
                  └── press "move" + delay > 0.1s → confirm facing + về IDLE
            └── press "direction_shift_move" lần nữa → cancel, về IDLE
```

### 5.5. Scroll — Chỉnh độ cao

```text
[Trong input_state_idle / input_state_sequence_move]
  └── Giữ "sequence_move" + scroll → adjust_waypoint_target_height(±1)

[Trong input_state_shift_move]
  └── Scroll (không cần modifier) → adjust_shift_target_height(±1)
```

Camera **không** nhận scroll khi đang giữ `sequence_move` hoặc `direction_shift_move` nhờ guard trong `Global_Camera.handle_input()`.

### 5.6. Đổi camera

```text
Global_Input._input(event)
  └── Global_Camera.handle_input(event)
      ├── "change_to_free_camera"      → switch_to(camera_3d_free)
      ├── "change_to_character_camera" → switch_to(camera_3d_character_far/close)
      ├── MouseMotion (nếu CAPTURED)   → xoay camera (orbit/look)
      └── "camera_zoom_in/out"         → zoom spring arm
```

Lưu ý: Đổi camera không đổi `current_gameplay_mode`.

---

## 6. Quản lý input cho "node bên trong"

### Nguyên tắc (khuyến nghị)

- Node con **không đọc input trực tiếp** nếu input đó là gameplay chung.
- Node con chỉ nhận lệnh qua hàm public.
- Camera là trường hợp đặc biệt: được phép có input riêng, nhưng phải đi qua API chung.

### Thực tế hiện tại (2026-06)

Hiện tại, `ship_movement_integrate.gd` (RigidBody3D — node con của scene) tự xử lý input flight qua `_unhandled_input()`. Đây là một **lệch khỏi kiến trúc khuyến nghị** vì:
- Gộp input state machine + physics + waypoint management vào 1 file (~900 dòng).
- Scene controller (`ship_moving_scene.gd`) bị rỗng, không còn vai trò routing.
- Khó mở rộng gameplay mode mới vì input logic nằm trong node vật lý.

Nếu có thời gian refactor, nên đưa `FlightInputState` machine về scene controller hoặc một node riêng.

### Trường hợp ngoại lệ (vẫn áp dụng)

Node con có thể tự xử lý input khi:
- Input đó chỉ phục vụ node đó, độc lập gameplay tổng (ví dụ camera orbit riêng).
- Hoặc là tool/editor mode tách biệt hoàn toàn.

Khi đó vẫn nên:
- có 1 hàm API chuẩn chung,
- được scene gọi theo thứ tự ưu tiên,
- và trả `bool` để báo đã consume event hay chưa.

---

## 7. Mẫu mở rộng gameplay mode mới (FACING_SET)

Khi cần mode giữ phím để đặt hướng đến waypoint:

1. Thêm gameplay mode:
```gdscript
enum GameplayInputMode { FLIGHT, FACING_SET }
```

2. Thêm route trong `_input(event)`:
```gdscript
match current_gameplay_mode:
  GameplayInputMode.FLIGHT: _input_flight(event)
  GameplayInputMode.FACING_SET: _input_facing_set(event)
```

3. Tạo hàm xử lý riêng:
```gdscript
func _input_facing_set(event: InputEvent) -> void:
  if event.is_action_released("set_facing"):
    # confirm facing ...
    _switch_gameplay_mode(GameplayInputMode.FLIGHT)
    get_viewport().set_input_as_handled()
```

Kết quả:
- Khi ở `FACING_SET`, input của `FLIGHT` tự động không chạy.
- Nhưng camera active vẫn có thể là free hoặc character tùy nhu cầu.

---

## 8. Checklist khi thêm input mới

- [ ] Input mới thuộc camera mode hay gameplay mode?
- [ ] Đã đặt code ở `scene controller` chưa?
- [ ] Nếu là camera input: đã nằm trong `handle_scene_input()` chưa?
- [ ] Nếu là gameplay input: node gameplay đã có hàm API public chưa?
- [ ] Đã gọi `set_input_as_handled()` sau khi xử lý chưa?
- [ ] Có cần nhường input theo modifier không?
- [ ] Có log debug khi switch gameplay mode không?

---

## 9. Quick conventions cho team

- Tên hàm input theo pattern (khuyến nghị):
  - `_input_global(event)`
  - `_input_active_camera(event)`
  - `_input_<gameplay_mode>(event)`
- Tên API gameplay dùng động từ rõ nghĩa:
  - `move_to`, `clear_all_waypoints`, `adjust_waypoint_target_height`
- Tên API camera:
  - `handle_scene_input(event) -> bool`
- Tránh gọi `Input.is_action_pressed()` trực tiếp trong script vật lý (hiện tại ship vẫn gọi trong `_unhandled_input` — cần refactor sau).
- Camera consume event bằng `return true`, không tự quyết định routing gameplay phía sau.
- Flight input state machine nên nằm ở scene controller, không phải trong RigidBody3D.
- Khi thêm state mới, đồng bộ lên `Global_Input.InputState` để camera biết.

---

## 10. Kết luận

Với project hiện tại, combo **Centralized Input + Camera Mode + Gameplay Mode** là điểm cân bằng tốt nhất:
- Đủ đơn giản để maintain nhanh.
- Đủ rõ ràng để mở rộng feature mới.
- Giảm mạnh lỗi input chồng chéo giữa nhiều node.
- Cho phép free camera vẫn điều khiển world nếu muốn.

Nếu sau này số mode tăng mạnh, có thể nâng cấp tiếp sang:
- `InputHandlerStack` (push/pop layer), hoặc
- state object class riêng cho mỗi gameplay mode.
