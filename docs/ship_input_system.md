# Ship Input System — Tài liệu kỹ thuật

## Tổng quan kiến trúc

```
_input(event)
  ├── _input_global()         → luôn active (ESC, đổi camera)
  ├── _input_active_camera()  → camera xử lý zoom/orbit trước
  └── _input_flight()         → gameplay: move, facing, scroll
```

Ship **không tự đọc input**. Scene controller (`ship_moving_scene.gd`) đọc input rồi gọi API của ship. Lợi ích: dễ remap, dễ test, không conflict.

---

## Các mode di chuyển

| Mode | Kích hoạt | Hành vi |
|---|---|---|
| `SEQUENCE` | Giữ `sequence_move` + click | Thêm waypoint vào hàng đợi |
| `SHIFT_DIRECTION` | Giữ `direction_shift_move` + scroll | Chỉnh độ cao target hiện tại |

---

## Input Controls

### Click to move

```
[MOUSE_MODE_VISIBLE] + click trái (move action)
  → shoot_ray_3d() lấy điểm trên mặt phẳng world
  → ship_player.move_to(click_pos, is_sequence)
```

- Không giữ sequence: clear queue, di chuyển thẳng đến điểm mới
- Giữ sequence: thêm vào hàng đợi waypoint

---

### Sequence + Click vs Hold (phân biệt bằng timer)

```
Nhấn xuống (sequence đang giữ)
│
├─ Ray cast ngay → lưu vào _pending_click_pos
├─ _is_press_pending = true
└─ _hold_timer = 0.0
        │
        [_process] _hold_timer += delta mỗi frame
        │
        ├── Thả chuột < 0.2s  →  CLICK
        │       ship_player.move_to(_pending_click_pos, true)
        │       → Tạo waypoint MỚI trong queue
        │
        └── Giữ >= 0.2s  →  HOLD MODE
                _is_holding_sequence_mouse = true
                → KHÔNG tạo waypoint mới
                → Chờ drag để set arrival_facing waypoint cuối
```

**Tại sao ray cast ngay khi nhấn?** Để vị trí world được tính tại đúng thời điểm click, không bị lệch nếu camera/tàu di chuyển trong lúc chờ timer.

---

### Drag để set Arrival Facing

Khi đã vào HOLD MODE (`_is_holding_sequence_mouse = true`):

```
Di chuyển chuột
│
├─ _facing_drag_accumulated += event.relative.length()   # tổng pixel (scalar)
├─ _facing_dir_accum += event.relative                   # tổng vector 2D
│
└─ Nếu accumulated > 12px (threshold):
        _is_in_facing_drag_mode = true
        preview_dir = _get_facing_dir_from_accum(_facing_dir_accum)
        ship_player.set_arrival_facing_preview(preview_dir, true)
        → Hiện mũi tên VÀNG tại waypoint cuối

Thả chuột sau drag:
        ship_player.confirm_last_waypoint_arrival_facing()
        → Ghi preview_dir vào waypoint.arrival_facing
        → Tắt mũi tên vàng
```

**Tại sao dùng 2 biến riêng?**

| Biến | Kiểu | Dùng để |
|---|---|---|
| `_facing_drag_accumulated` | `float` (scalar) | Đo **khoảng cách** pixel để kích hoạt drag mode |
| `_facing_dir_accum` | `Vector2` (vector) | Đo **hướng** tổng thể để tính world direction |

Ví dụ kéo zigzag `→ → ↓ ← →`:
- `accumulated = 5+5+3+2+5 = 20` → đủ để kích hoạt
- `dir_accum = (5+5-2+5, 3) = (13, 3)` → hướng chủ đạo là sang phải

---

### Project 2D mouse → World XZ direction

```gdscript
func _get_facing_dir_from_accum(accum: Vector2) -> Vector3:
```

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

### Scroll — Chỉnh độ cao

```
direction_shift_move + scroll  →  adjust_shift_target_height(±1)
                                   cộng dồn offset, clamp [-30, 30]

sequence_move + scroll         →  adjust_waypoint_target_height(±1)
                                   chỉnh Y của waypoint cuối trong queue
                                   (có giới hạn theo góc pitch tối đa)
```

Camera **không** nhận scroll khi đang giữ một trong hai modifier trên (guard trong `camera_character_node.gd`).

---

## Ship APIs (gọi từ scene controller)

| Hàm | Mô tả |
|---|---|
| `move_to(pos, is_sequence)` | Tạo waypoint, thêm queue hoặc clear+set mới |
| `change_moving_state(mode)` | Đổi giữa SEQUENCE / SHIFT_DIRECTION |
| `adjust_waypoint_target_height(offset)` | Chỉnh Y waypoint cuối trong queue |
| `adjust_shift_target_height(offset)` | Chỉnh offset Y dùng cho SHIFT_DIRECTION |
| `set_arrival_facing_preview(dir, active)` | Bật/tắt mũi tên vàng preview |
| `confirm_last_waypoint_arrival_facing()` | Ghi hướng drag vào waypoint.arrival_facing |

---

## Biến trạng thái quan trọng (ship_moving_scene.gd)

| Biến | Ý nghĩa |
|---|---|
| `_is_press_pending` | Đang chờ phân biệt click vs hold |
| `_hold_timer` | Đếm thời gian giữ chuột |
| `_hold_threshold` | Ngưỡng giây để kích hoạt hold mode (mặc định 0.2s) |
| `_pending_click_pos` | Vị trí world lưu lại từ lúc nhấn |
| `_is_holding_sequence_mouse` | Đã vào hold mode, đang chờ drag |
| `_is_in_facing_drag_mode` | Đã kéo đủ pixel, đang update preview |
| `_facing_drag_threshold` | Pixel tối thiểu để kích hoạt drag (mặc định 12px) |
| `_facing_drag_accumulated` | Tổng pixel đã kéo (scalar) |
| `_facing_dir_accum` | Tổng vector 2D chuột để tính hướng world |

---

## Luồng tổng hợp

```
[MOUSE_MODE_VISIBLE]

Nhấn chuột trái
├── Không sequence → move_to() ngay, xong
└── Có sequence:
        ↓ buffer click_pos, bắt đầu timer
        ↓
        Thả < 0.2s              Giữ >= 0.2s
            ↓                       ↓
        move_to()            hold mode active
        waypoint mới              ↓
                             Di chuyển chuột
                                  ↓
                             > 12px drag
                                  ↓
                             preview arrow (vàng)
                                  ↓
                             Thả chuột
                                  ↓
                             confirm arrival_facing
                             (waypoint cuối, không tạo mới)
```
