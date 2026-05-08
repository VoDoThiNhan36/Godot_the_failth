# Tài liệu: Kiến trúc Centralized Input + Camera Mode + Gameplay Mode
> Godot 4 · Project `3d_modular` · Cập nhật: 2026-05-06

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

### 3.3. Sơ đồ tổng quát

```text
Input Event
   │
   ▼
ship_moving_scene.gd
  _input(event)
   ├── _input_global(event)            # luôn active
   ├── _input_active_camera(event)     # zoom/orbit/look
   └── route theo current_gameplay_mode
     └── _input_flight(event)

   (gọi API xuống node gameplay)
        ├── ship_player.move_to(...)
        ├── ship_player.adjust_target_height(...)
        └── ship_player.clear_all_waypoints()

   (gọi API xuống camera rig active)
     └── current_rig.handle_scene_input(event) -> bool
```

---

## 4. Phân vai trách nhiệm theo file

### `scenes/ship_moving_scene.gd`

- Chứa `enum GameplayInputMode` và `current_gameplay_mode`.
- Chứa input router `_input(event)`.
- Chứa `_input_global(event)` cho input luôn bật:
  - `ui_cancel`
  - đổi camera
- Chứa `_input_active_camera(event)` để chuyển event cho camera rig đang active.
- Chứa `_input_flight(event)` cho logic điều khiển tàu:
  - click move
  - scroll đổi cao độ
  - clear waypoint theo modifier
- Chứa `_switch_gameplay_mode(new_mode)` cho các gameplay mode tương lai.

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

- Không xử lý input trực tiếp (`_input`, `_unhandled_input`).
- Chỉ chứa API gameplay:
  - `move_to(new_position, is_sequence)`
  - `adjust_target_height(offset)`
  - `clear_all_waypoints()`
- Chịu trách nhiệm tính toán vật lý/động học.

---

## 5. Luồng xử lý input hiện tại

### 5.1. Thứ tự ưu tiên tổng quát

```text
_input(event)
  ├── 1. _input_global(event)
  ├── 2. _input_active_camera(event)
  └── 3. _input_<gameplay_mode>(event)
```

Ý nghĩa:
- input global luôn ưu tiên cao nhất
- camera chỉ ăn input camera thật sự
- gameplay nhận phần event còn lại

### 5.2. Click để di chuyển

```text
_input_flight(event)
  └── nếu event là MouseButton + pressed + action "move"
      └── raycast lấy click_pos
          └── ship_player.move_to(click_pos, is_sequence)
              └── set_input_as_handled()
```

### 5.3. Scroll để chỉnh cao độ / zoom camera

#### Free camera + scroll thường

```text
_input_active_camera(event)
  └── camera_free.handle_scene_input(event)
      └── zoom spring arm
          └── return true
```

#### Free camera + gameplay modifier

```text
_input_flight(event)
  └── nếu event là WHEEL_UP/WHEEL_DOWN
      ├── nếu giữ "direction_shift_move"
      │   └── ship_player.clear_all_waypoints()
      └── nếu giữ "sequence_move"
          └── ship_player.adjust_target_height(offset)

      └── set_input_as_handled()
```

Lý do hoạt động được:
- `camera_free_node.gd` sẽ **không consume scroll** nếu đang giữ:
  - `sequence_move`
  - `direction_shift_move`

=> Event được nhường cho gameplay logic phía sau.

### 5.4. Đổi camera

```text
_input_global(event)
  └── change_camera_bw_free_n_character
  ├── sang camera free    -> switch_to(camera_3d_free)
  └── về camera character -> switch_to(camera_3d_character_far)
```

Lưu ý:
- Không đổi `current_gameplay_mode`
- Vì vậy free camera vẫn tạo waypoint được

---

## 6. Quản lý input cho "node bên trong"

### Nguyên tắc

- Node con **không đọc input trực tiếp** nếu input đó là gameplay chung.
- Node con chỉ nhận lệnh qua hàm public.
- Camera là trường hợp đặc biệt: được phép có input riêng, nhưng phải đi qua API chung.

Ví dụ tốt:
- `scene controller` đọc scroll rồi gọi `ship_player.adjust_target_height(offset)`.
- `scene controller` gọi `Global_Camera.current_rig.handle_scene_input(event)` rồi nhận `true/false`.

Ví dụ không nên (trừ trường hợp đặc biệt):
- `ship_player` tự bắt `InputEventMouseButton` trong `_unhandled_input`.
- scene tự viết toàn bộ chi tiết zoom/orbit của từng loại camera.

### Trường hợp ngoại lệ

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

- Tên hàm input theo pattern:
  - `_input_global(event)`
  - `_input_active_camera(event)`
  - `_input_<gameplay_mode>(event)`
- Tên API gameplay dùng động từ rõ nghĩa:
  - `move_to`, `clear_all_waypoints`, `adjust_target_height`
- Tên API camera:
  - `handle_scene_input(event) -> bool`
- Không gọi `Input.is_action_pressed()` trực tiếp trong script vật lý (trừ prototype ngắn hạn).
- Camera consume event bằng `return true`, không tự quyết định routing gameplay phía sau.

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
