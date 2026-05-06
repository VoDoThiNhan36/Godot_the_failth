# Tài liệu: Luồng Apply Force Movement — ship_movement.gd
> RigidBody3D · Godot 4 · Cập nhật: 2026-04-16

---

## 1. TỔNG QUAN KIẾN TRÚC

```
_physics_process(delta)
│
├── [State Machine]
│   ├── IDLE  → handle_state_idle(delta)
│   └── MOVE  → handle_state_move(delta)
│
├── apply_roll_correction()     ← chạy MỌI FRAME, mọi state
├── apply_pitch_clamp()         ← chạy MỌI FRAME, mọi state
└── [debug / UI]
```

> **Nguyên tắc RigidBody3D:**
> - `apply_central_force(F)` → tích lũy trong frame, được engine apply ở **cuối** physics step
> - `apply_torque(T)` → tương tự, tích lũy rồi apply cuối step
> - **KHÔNG** mix `apply_*force` với set trực tiếp `linear_velocity` trong cùng 1 frame → conflict

---

## 2. STATE IDLE — `handle_state_idle(delta)`

```
handle_state_idle(delta)
│
├── 1. PHANH TỊNH TIẾN
│   ├── Điều kiện  : linear_velocity.length() > 0.01
│   ├── Công thức  : F_brake = -normalize(v) × max_brake_force × mass
│   ├── API        : apply_central_force(F_brake)
│   └── Đơn vị     : Newton (N)
│
└── 2. CÂN BẰNG TƯ THẾ
    └── auto_stable_ship_indie_state(delta)
        ├── PITCH (ngóc/cúi đầu)
        │   ├── pitch_error = asin(clamp(forward.y, -1, 1))      ← radian, >0 ngóc lên
        │   ├── pitch_axis  = -basis.x                            ← trục X local âm
        │   ├── P_term      = pitch_error × angular_acceleration × stabilization_speed
        │   ├── D_term      = angular_velocity.dot(pitch_axis) × angular_damp_value × 5.0
        │   ├── torque      = (P_term - D_term) × mass
        │   ├── Nếu |pitch_error| > 0.005 hoặc |pitch_vel| > 0.01
        │   │   └── apply_torque(pitch_axis × torque)
        │   └── Ngược lại (đã phẳng)
        │       └── angular_velocity -= project(angular_velocity, pitch_axis)   ← dập micro-oscillation
        │
        └── YAW DAMPING (hãm xoay ngang khi đứng im)
            ├── yaw_axis    = Vector3.UP
            ├── current_yaw_vel = angular_velocity.dot(Vector3.UP)
            ├── Nếu |yaw_vel| > 0.01
            │   └── apply_torque(-UP × yaw_vel × angular_damp_value × mass × 5.0)
            └── Ngược lại
                └── angular_velocity -= project(angular_velocity, UP)
```

**Điều kiện chuyển vào IDLE:**
- `move_to()` chưa được gọi → state khởi đầu mặc định
- `distance < waypoint_switch_distance` và `ship_movement_waypoints.is_empty()` và `linear_velocity.length() < 0.05` → `change_state(IDLE)` từ trong MOVE

---

## 3. STATE MOVE — `handle_state_move(delta)`

### 3.1 Sơ đồ tổng thể

```
handle_state_move(delta)
│
├── A. TÍNH TOÁN HƯỚNG (Direction Blending)
│
├── B. STEERING TORQUE
│   ├── Xa (distance > ship_length × 5)  → Fajen apply_torque()
│   └── Gần                              → PID apply_torque()
│
├── C. WAYPOINT SWITCHING
│   ├── Còn waypoint → load_next_waypoint()
│   └── Đích cuối   → PHANH CUỐI → change_state(IDLE)
│
├── D. THUẬT TOÁN ARRIVE (Thrust Force)
│   ├── distance > min_stopping_distance → apply_central_force(thrust)
│   └── distance ≤ min_stopping_distance → apply_central_force(brake)
│
└── E. LATERAL DAMPENING
    └── apply_central_force(-lateral_velocity × friction × mass)
```

---

### 3.2 A — Tính toán hướng (Direction Blending)

```
rotation_blend_distance = distance_threshold × 2.0

distance > rotation_blend_distance
    → is_at_current_waypoint_threshold = false
    → raw_direction = direction_to_target           ← hướng thẳng tới target

distance ∈ (distance_threshold, rotation_blend_distance]
    → [chỉ tính khi NOT is_at_current_waypoint_threshold]
    → blend_weight = clamp((distance - threshold) / blend_distance, 0.8, 1.0)
    → raw_direction = slerp(current_target_direction, direction_to_target, blend_weight)
    → Ý nghĩa: gần đích thì xoay mũi về hướng click chuột ban đầu cho mượt

distance ≤ distance_threshold
    → is_at_current_waypoint_threshold = true
    → raw_direction = current_target_direction      ← giữ hướng click ban đầu

[KHỞI TẠO MẶC ĐỊNH]
    raw_direction = current_target_direction        ← fallback nếu không nhánh nào gán
    (Quan trọng: tránh Vector3(0,0,0) khi is_at_threshold = true và distance ở vùng elif)
```

---

### 3.3 B — Steering Torque

#### Fajen (xa: `distance > ship_length × 5.0`)

```
1. Lấy vận tốc góc THỰC từ RigidBody3D:
   real_angular_vel.x = angular_velocity.dot(basis.x)    ← pitch
   real_angular_vel.y = angular_velocity.dot(Vector3.UP) ← yaw

2. compute_fajen_angular_acceleration(heading, raw_direction, real_angular_vel)
   └── Trả về: { angular_accel: Vector2(pitch, yaw), repulsion_force: float }

3. Clamp gia tốc theo sức động cơ:
   applied_accel_pitch = clamp(accel.x, -angular_acceleration, angular_acceleration)
   applied_accel_yaw   = clamp(accel.y, -angular_acceleration, angular_acceleration)

4. Đổi gia tốc → Torque (N·m):
   pitch_torque = basis.x × applied_accel_pitch × mass
   yaw_torque   = Vector3.UP × applied_accel_yaw × mass

5. apply_torque(yaw_torque + pitch_torque)

6. Danger throttle (nếu repulsion > 5.0):
   danger_throttle_factor = clamp(1.0 - repulsion / 50.0, 0.1, 1.0)
```

#### Fajen nội bộ — `compute_fajen_angular_acceleration()`

```
Công thức Fajen-Warren:
  phi_ddot = -b·phi_dot - kg·(phi - psi_g)·(exp(-0.4·dg) + 0.4)
             + Σ ko·(phi - psi_o)·exp(-6|phi - psi_o|)·exp(-c4·do)

Với:
  phi       = góc hiện tại của tàu (yaw hoặc pitch)
  psi_g     = góc mục tiêu
  psi_o     = góc obstacle
  dg        = distance đến goal
  do        = distance đến obstacle (từ raycast hit)
  b         = fajen_b = 4.2      (damping)
  kg        = fajen_kg = 12.0    (lực hút goal)
  ko        = fajen_ko × (1 + √obs_radius)  (lực đẩy obstacle, scale theo kích thước)
  c4        = fajen_c4 = 0.2     (suy giảm theo khoảng cách obstacle)

Bước tính:
  1. Tính phi_yaw, phi_pitch của ship và target (atan2)
  2. Tính goal_error = fposmod(phi - psi_g + PI, TAU) - PI  ← chuẩn hóa [-PI, PI]
  3. phi_ddot += -b·phi_dot - kg·error·(exp(-0.4·dg) + 0.4)
  4. Với mỗi obstacle (≤ fajen_max_obstacles):
     - Raycast để lấy hit_position và ước tính obs_radius
     - Bỏ qua obstacle phía sau: dot(heading, dir_to_obs) < -0.25
     - obs_error = fposmod(phi - psi_o + PI, TAU) - PI
     - phi_ddot += dynamic_ko × obs_error × exp(-6|obs_error|) × exp(-c4·do)
  5. Anti-deadlock noise nếu angular_vel ≈ 0 và phi_ddot ≈ 0
```

#### PID Controller (gần: `distance ≤ ship_length × 5.0`)

```
update_character_rotation(delta, heading, desired_direction, distance, min_stopping_dist)

1. cross = heading.cross(desired_direction)
   ├── |cross|² < 0.001 và dot < -0.9  → rotation_axis = Vector3.UP (tránh 180° deadlock)
   ├── |cross|² < 0.001 và dot ≥ -0.9  → đã thẳng hàng, return
   └── Bình thường                      → rotation_axis = cross.normalized()

2. angle_error = heading.angle_to(desired_direction)   ← radian

3. PID:
   P = pid_rot_p × angle_error
   I = pid_rot_i × (rot_error_integral += angle_error × delta)
   D = pid_rot_d × angular_velocity.dot(rotation_axis)
   pid_accel = clamp(P + I - D, -angular_acceleration, angular_acceleration)

4. pid_torque = pid_accel × mass
   ├── |pid_torque| > 0.05 → apply_torque(rotation_axis × pid_torque)
   └── Ngược lại           → angular_velocity = lerp(angular_velocity, ZERO, 10·delta)

5. Level-out khi gần đích cuối:
   ├── Điều kiện: waypoints.is_empty() AND distance ≤ min_stopping_distance
   ├── flat_desired = desired_direction với y = 0
   ├── blend = clamp(1 - distance / max_linear_speed, 0, 1)
   └── apply_torque(level_cross.normalized() × blend × angular_acceleration × mass × 0.5)
```

---

### 3.4 C — Waypoint Switching

```
waypoint_switch_distance:
    ├── Không còn waypoint: distance_threshold / 2.0
    └── Còn waypoint      : max_linear_speed × 0.5   ← cắt góc sớm khi đang chạy nhanh

distance < waypoint_switch_distance:
    ├── Còn waypoint → load_next_waypoint()
    │   ├── queue_free() marker cũ
    │   ├── pop_front() → current_waypoint, current_target_position, current_target_direction
    │   └── fajen_angular_velocity × 0.5   ← bẻ cua nhanh
    │
    └── Đích cuối:
        ├── linear_velocity = move_toward(ZERO, max_brake_force × delta)
        │   (KHÔNG dùng apply_central_force ở đây — tránh conflict với force tích lũy)
        │
        └── linear_velocity.length() < 0.05:
            ├── linear_velocity = Vector3.ZERO   ← ép về 0 tuyệt đối
            ├── auto_throttle   = 0.0
            ├── change_state(IDLE)               ← kích hoạt pitch/yaw stabilization
            └── return                           ← thoát sớm, không tính ARRIVE
```

---

### 3.5 D — Arrive Behavior (Thrust Force)

```
min_stopping_distance = v² / (2 × max_brake_force / mass)
min_stopping_distance = clamp(min_stopping_dist, distance_threshold, ∞)

─────────────────────────────────────────────────────────
Trường hợp: distance > min_stopping_distance (chưa cần phanh gấp)
─────────────────────────────────────────────────────────

1. Tính target_speed:
   ├── Waypoint giữa : min(distance / (braking_factor × 0.5), max_linear_speed)  ← giữ max speed
   └── Đích cuối     : clamp(distance / braking_factor, 0.05, max_linear_speed)   ← giảm dần

2. Tính auto_throttle:
   auto_throttle = clamp(heading_alignment, 0, 1)  ← alignment = dot(heading, desired_dir)
   auto_throttle = auto_throttle³                  ← lũy thừa 3: nhạy hơn khi lệch
   auto_throttle × danger_throttle_factor          ← giảm khi obstacle nguy hiểm

3. Nếu heading_alignment > 0 (mũi tàu hướng về phía target):
   desired_velocity = ship_heading × (target_speed × auto_throttle)
   steering_force   = desired_velocity - linear_velocity          ← delta velocity
   steering_force   = clamp_length(steering_force, max_thrust_force)
   apply_central_force(steering_force × mass)                     ← Newton

4. Nếu heading_alignment ≤ 0 (mũi tàu quay ngược):
   apply_central_force(-normalize(linear_velocity) × deceleration)

─────────────────────────────────────────────────────────
Trường hợp: distance ≤ min_stopping_distance (vùng phanh gấp)
─────────────────────────────────────────────────────────

Nếu linear_velocity.length() > 0.1:
    ├── Đích cuối      : apply_central_force(-normalize(v) × deceleration × mass)
    └── Waypoint giữa  : apply_central_force(-normalize(v) × deceleration × 0.5 × mass)

Nếu linear_velocity.length() ≤ 0.1:
    linear_velocity = Vector3.ZERO   ← ép về 0, tránh micro-drift
```

---

### 3.6 E — Lateral Dampening (chống bay vòng tròn)

```
Mục đích: triệt tiêu vận tốc ngang (không theo hướng mũi tàu)

1. Tách linear_velocity thành 2 thành phần:
   forward_speed    = linear_velocity.dot(ship_heading_vector)         ← scalar
   forward_velocity = ship_heading_vector × forward_speed              ← vector
   lateral_velocity = linear_velocity - forward_velocity               ← phần ngang

2. effective_friction:
   ├── Mặc định: lateral_friction
   └── distance < distance_threshold / 2: lateral_friction × 2.0     ← tăng khi sát đích

3. Nếu lateral_velocity.length() > 0.1 (deadzone):
   apply_central_force(-lateral_velocity × effective_friction × mass)
   (Đơn vị: N — triệt tiêu vận tốc ngang)

4. Clamp tốc độ tối đa (RigidBody3D không tự clamp):
   Nếu linear_velocity.length() > max_linear_speed:
       linear_velocity = normalize(linear_velocity) × max_linear_speed
```

---

## 4. ALWAYS-ON CORRECTIONS (chạy mọi frame sau state machine)

### 4.1 `apply_roll_correction()`

```
Mục đích: giữ tàu không bị lật ngang (roll = 0)

1. ship_up   = basis.y                                  ← trục Y local (lên)
2. roll_error = ship_up.cross(Vector3.UP)               ← vector lệch roll
3. roll_axis  = basis.z                                 ← trục Z forward = trục roll
4. apply_torque(roll_axis × roll_error.dot(roll_axis) × roll_correction_torque)
5. apply_torque(-project(angular_velocity, basis.z) × angular_damp_value)   ← damping roll
```

### 4.2 `apply_pitch_clamp()`

```
Mục đích: giới hạn góc pitch tối đa (max_pitch_angle = 45°)

1. pitch = asin(clamp(-basis.z.y, -1, 1))             ← pitch hiện tại (radian)
2. max_pitch_rad = deg_to_rad(max_pitch_angle)
3. Nếu |pitch| > max_pitch_rad:
   pitch_error = pitch - sign(pitch) × max_pitch_rad   ← độ lệch so với giới hạn
   apply_torque(-basis.x × pitch_error × angular_acceleration)
```

---

## 5. LUỒNG FORCE THEO TRÌNH TỰ THỰC THI TRONG 1 PHYSICS FRAME

```
Physics Frame Start
│
├── [Engine: đọc linear_velocity, angular_velocity từ frame trước]
│
├── _physics_process(delta)
│   │
│   ├── handle_state_MOVE / IDLE
│   │   ├── apply_central_force(thrust/brake)    ─┐
│   │   ├── apply_torque(fajen/PID)               ├─ tích lũy vào force buffer
│   │   └── apply_central_force(lateral_brake)   ─┘
│   │
│   ├── apply_roll_correction()
│   │   └── apply_torque(roll)                   ─┐
│   │                                              ├─ tiếp tục tích lũy
│   └── apply_pitch_clamp()                        │
│       └── apply_torque(pitch_limit)             ─┘
│
└── [Engine: tích hợp tất cả force/torque accumulated]
    ├── linear_velocity  += (Σ F / mass) × delta
    ├── angular_velocity += (Σ T / inertia) × delta
    ├── Áp dụng linear_damp, angular_damp
    └── Cập nhật global_transform (position, rotation)

Physics Frame End
```

---

## 6. BẢNG BIẾN SỐ QUAN TRỌNG

| Biến | Kiểu | Ý nghĩa | Ghi chú |
|------|------|---------|---------|
| `linear_velocity` | Vector3 | Vận tốc tịnh tiến (m/s) | Built-in RigidBody3D |
| `angular_velocity` | Vector3 | Vận tốc góc (rad/s) | Built-in RigidBody3D |
| `mass` | float | Khối lượng (kg) | Built-in RigidBody3D |
| `fajen_angular_velocity` | Vector2 | Momentum Fajen: x=pitch, y=yaw | Riêng biệt, dùng trong draff |
| `current_target_direction` | Vector3 | Hướng lúc click chuột (normalize) | Giữ nguyên đến khi đến đích |
| `raw_direction` | Vector3 | Hướng sau blend, trước Fajen | Khởi tạo = current_target_direction |
| `desired_direction` | Vector3 | Hướng cuối cùng (sau Fajen/PID) | Dùng để tính heading_alignment |
| `heading_alignment` | float | dot(heading, desired): [-1, 1] | 1.0 = thẳng hướng, -1.0 = ngược |
| `auto_throttle` | float | Hệ số ga: [0, 1] | alignment³ × danger_factor |
| `min_stopping_distance` | float | v² / (2·a) | Quãng đường phanh tối thiểu |
| `is_at_current_waypoint_threshold` | bool | Đã vào vùng đích chưa | Ngăn direction flip |

---

## 7. ĐIỂM DỄ BUG — CHECKLIST DEBUG

| # | Triệu chứng | Nguyên nhân thường gặp | Biến cần check |
|---|-------------|----------------------|----------------|
| 1 | Tàu quay ngược khi đến đích | `raw_direction` không được gán (Vector3.ZERO) | `raw_direction`, `is_at_current_waypoint_threshold` |
| 2 | Pitch không về 0 sau khi dừng | `change_state(IDLE)` không trigger | `linear_velocity.length()`, `current_state` |
| 3 | Tàu dao động ở đích, không dừng | Mix `apply_central_force` + set `linear_velocity` cùng frame | Logic waypoint cuối |
| 4 | Click chuột không nhận | `_input` bị thay bằng `_unhandled_input` hoặc thiếu guard `is InputEventMouseButton` | `ship_moving_scene.gd` |
| 5 | Waypoint spam khi drag | Thiếu guard `event is InputEventMouseButton` | `ship_moving_scene.gd` |
| 6 | Tàu bay vòng tròn | `lateral_dampening` yếu hoặc `lateral_friction` quá nhỏ | `lateral_velocity`, `effective_friction` |
| 7 | Tàu lắc lư roll liên tục | `roll_correction_torque` quá nhỏ hoặc `angular_damp` quá thấp | `apply_roll_correction`, `angular_damp_value` |
| 8 | Fajen không tránh obstacle | `collision_mask` sai layer hoặc obstacle không có CollisionShape | `setup_fajen_area()`, collision layers |
| 9 | Tàu không bẻ cua qua waypoint | `fajen_angular_velocity` không reset, đà quán tính quá lớn | `load_next_waypoint()`, `fajen_angular_velocity` |
| 10 | PID rung lắc gần đích | `pid_rot_d` quá nhỏ (D-term không đủ phanh) hoặc `pid_rot_p` quá lớn | `pid_rot_p`, `pid_rot_d` |
