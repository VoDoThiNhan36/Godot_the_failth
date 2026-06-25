# Tài liệu: Luồng Kinematic Override — ship_movement_integrate.gd
> RigidBody3D · Godot 4 · Cập nhật: 2026-06-23
> Áp dụng cho file `scripts/movement/ship_movement_integrate.gd` (thay thế `ship_movement.gd` cũ)

---

## 1. TỔNG QUAN KIẾN TRÚC

```
_integrate_forces(state)
│
├── [Tính toán chung]
│   ├── distance_to_target, direction_to_target, ship_heading
│   ├── danger_throttle_factor = 1.0
│   └── distance_traveled += ...
│
├── [PlayerState Machine]
│   ├── IDLE → handle_state_idle + damping linear/angular/lateral velocity
│   │           + apply_roll_correction + apply_pitch_correction
│   │
│   └── MOVE → match current_waypoint.type
│       ├── "sequence" → compute_sequence_move_target_direction()
│       │                 compute_sequence_move_lateral_damping()
│       └── "shift"    → compute_shift_move_target_direction()
│
├── [STEERING]
│   ├── Xa (distance > ship_length × 3) → Fajen (gán angular_velocity)
│   └── Gần (distance ≤ ship_length × 3) → update_rotation (quaternion lerp)
│
├── apply_roll_clamp(state)
├── apply_pitch_clamp(state)
└── [debug labels]
```

> **Nguyên tắc Kinematic Override:**
> - KHÔNG dùng `apply_central_force` / `apply_torque` (force-based) cho main movement
> - THAY VÀO ĐÓ: gán trực tiếp `state.linear_velocity` (qua lateral damping) + `state.angular_velocity`
> - Chỉ `handle_state_idle` và `compute_*_thrust_control` dùng `apply_central_force` (lực đẩy/phang)
> - Steering dùng **velocity gán**, không dùng torque
> - `_integrate_forces(state)` chạy mỗi physics frame, can thiệp sau khi engine tích lũy forces

---

## 2. STATE IDLE

```
PlayerState.IDLE trong _integrate_forces:
├── handle_state_idle(delta)
│   └── apply_central_force(-linear_velocity * max_thrust_force * ratio * 0.5)
│       → Phanh bằng lực ngược chiều
│
├── apply_roll_correction(state, delta)   ← Lerp angular velocity để roll về 0
├── apply_pitch_correction(state, delta)  ← Lerp angular velocity để pitch cân bằng
│
└── Khi current_waypoint == null và linear_velocity != Vector3.ZERO:
    ├── state.linear_velocity.move_toward(ZERO, linear_damp_value * ratio * delta)
    ├── state.angular_velocity.lerp(ZERO, angular_damp_value * rot_ratio * delta)
    ├── lateral_velocity.lerp(ZERO, lateral_damp_value * ratio * delta)
    └── forward_velocity.lerp(ZERO, lateral_damp_value * ratio * delta)
```

**Điều kiện chuyển vào IDLE:**
- Khởi đầu mặc định
- Khi `move_to()` gọi `change_state(MOVE)`
- Về IDLE khi hết waypoint (trong compute_*_target_direction)

---

## 3. STATE MOVE

### 3.1 Sequence Move — `compute_sequence_move_target_direction()`

```
1. DIRECTION BLENDING:
   distance > blend_arrival_distance (3.0m):
     → current_target_direction = direction_to_target

   blend_arrival_distance ≥ distance > arrival_radius (1.0m) và hết waypoint:
     → blend_weight = clamp((dist - blend) / blend, 0.2, 1.0)
     → slerp(direction_to_target, current_waypoint.direction, blend_weight)
     → Ý nghĩa: gần đích thì blend về hướng click chuột ban đầu

   distance ≤ arrival_radius:
     → is_at_current_waypoint_threshold = true
     → Nếu còn waypoint: load_next_waypoint()
     → Nếu hết: về IDLE, gán arrival_facing

2. rotation_desired_direction = current_target_direction  ← cho steering

3. THRUST CONTROL — compute_sequence_move_thrust_control():
   braking_dist = v² / (2 * max_thrust_force / mass)

   alignment ≥ 0.85:
     auto_throttle = alignment³
     distance > braking_dist → tăng ga
       current_thrust_force → max_thrust
       apply_central_force(heading * thrust * throttle)
     distance ≤ braking_dist → giảm ga (braking blend)
       target_force = max_thrust * (dist / braking_dist) * ratio
       steering_force = (target_force - current) * heading
       apply_central_force(steering_force.limit_length(max_thrust))

   alignment < 0.85 → phanh
     auto_throttle → 0
     apply_central_force(-linear_velocity * max_thrust * ratio)

4. LATERAL DAMPING — compute_sequence_move_lateral_damping():
   → forward_velocity = heading * dot(linear_velocity, heading)
   → lateral_velocity = linear_velocity - forward_velocity
   → lateral_velocity.lerp(ZERO, lateral_damp_value * ratio * delta)
   → state.linear_velocity = forward_velocity + lateral_velocity
```

### 3.2 Shift Move — `compute_shift_move_target_direction()`

```
1. DIRECTION + ARRIVAL FACING BLEND:
   distance > arrival_radius và chưa threshold:
     → current_target_direction = direction_to_target
     → Chuẩn hóa arrival_facing xuống mặt phẳng XZ
     → angle = ship_heading.angle_to(arrival_facing)
     → desired_turn_speed = max_angular_speed * (rcs_torque / mass)
     → time_to_rotate = angle / max(desired_turn_speed, 0.0001)
     → rotate_start_dist = linear_speed * time_to_rotate * 1.5
     → Nếu distance ≤ rotate_start_dist:
         blend_t = clamp(1 - dist / rotate_start_dist, 0, 1)
         rotation_desired_direction = slerp(heading, arrival_facing, ease(blend_t, 2))

   distance ≤ arrival_radius:
     → load_next_waypoint() hoặc về IDLE

2. THRUST CONTROL — compute_shift_move_thrust_control():
   → Giống sequence nhưng alignment threshold thấp hơn (0.5)
   → Không có braking blend phức tạp

3. LATERAL: giữ nguyên lateral velocity (không triệt tiêu)
```

---

## 4. STEERING

### 4.1 Fajen Warren (xa — distance > ship_length × 3)

```
Điều kiện: distance_to_target > ship_length * 3.0

current_steering_mode = FAJEN_WARREN
max_engine_accel = rotation_power_to_mass_ratio  (= (torque + rcs) / mass)

1. fajen_steering.compute_fajen_angular_acceleration(
     ship, heading, direction_to_target, target_pos, delta, max_engine_accel)
   → Steering tự:
     • Tính raw accel từ công thức Fajen (goal + obstacle + damping)
     • Clamp theo max_engine_accel
     • Tích lũy nội bộ: fajen_angular_velocity += accel * delta
     • Damping: lerp(ZERO, angular_damping * delta)
     • Clamp max speed

2. fajen_vel = fajen_steering.get_fajen_angular_velocity()

3. state.angular_velocity = yaw_axis * fajen_vel.y + pitch_axis * fajen_vel.x
   → GÁN TRỰC TIẾP angular velocity, không qua torque

4. Danger throttle:
   total_repulsion > 5.0
     → auto_throttle *= clamp(1 - repulsion / 50, 0.1, 1.0)
```

### 4.2 Manual Rotation (gần — distance ≤ ship_length × 3)

```
Điều kiện: distance_to_target ≤ ship_length * 3.0

current_steering_mode = NONE
fajen_steering.set_fajen_angular_velocity(Vector2.ZERO)  // reset momentum

update_rotation(state, rotation_desired_direction, delta):
  a. Xây dựng target_basis từ desired_dir:
     z_axis = -desired_dir.normalized()   // Z = sau lưng
     x_axis = up_ref.cross(z_axis).normalized()
     y_axis = z_axis.cross(x_axis).normalized()

  b. diff_quat = target_quat * current_quat.inverse()
     axis = diff_quat.get_axis()
     angle = diff_quat.get_angle()  → chuẩn hóa [-PI, PI]

  c. Rotation delay: nếu angle tăng đột ngột > delay_threshold (60°)
     → delay_timer = rotation_start_delay (0.1s)
     → angle_change_factor → 0 (tạm dừng xoay)

  d. Fine zone: nếu angle < fine_rad (1°)
     → angle_fine_factor = max(0.7, angle / fine_rad)

  e. turn_speed = angle * rotation_p * fine_factor * change_factor
     → Clamp: max_angular_speed * rotation_power_to_mass_ratio

  f. target_angular_velocity = axis * turn_speed
  g. state.angular_velocity.lerp(target, rotation_power_to_mass * rotation_d * delta)
```

---

## 5. ALWAYS-ON CORRECTIONS

### 5.1 Roll Correction — `apply_roll_correction(state, delta)`

```
1. roll_angle = ship_up.signed_angle_to(Vector3.UP, roll_axis)
2. target_roll_velocity = roll_axis * roll_angle * (rotation_p * 0.5) * stable_ratio
3. Tách current_roll_velocity = angular_velocity.project(roll_axis)
4. rest = angular_velocity - current_roll_velocity
5. new_roll = current_roll_velocity.lerp(target, rot_power * (rot_d*0.5) * damp_roll * stable * delta)
6. state.angular_velocity = rest + new_roll
```

### 5.2 Pitch Correction — `apply_pitch_correction(state, delta)`

```
→ Giống roll correction nhưng trên pitch_axis (basis.x)
```

### 5.3 Roll Clamp — `apply_roll_clamp(state)`

```
1. roll_rad = asin(clamp(-basis.z.y, -1, 1))
2. Nếu |roll_rad| > max_roll_rad (6°):
   → Nếu đang quay ra ngoài → current_roll_vel = ZERO
```

### 5.4 Pitch Clamp — `apply_pitch_clamp(state)`

```
→ Giống roll clamp nhưng check pitch angle > max_pitch_angle (10°)
```

---

## 6. LUỒNG THỰC THI TRONG 1 PHYSICS FRAME

```
Physics Frame Start
│
├── _integrate_forces(state)
│   │
│   ├── distance_to_target, direction_to_target, ship_heading
│   │
│   ├── [PLAYERSTATE.IDLE]
│   │   ├── handle_state_idle() → apply_central_force(phang)
│   │   ├── apply_roll_correction(state, delta)
│   │   ├── apply_pitch_correction(state, delta)
│   │   └── damping: move_toward / lerp linear, angular, lateral velocity
│   │
│   ├── [PLAYERSTATE.MOVE]
│   │   ├── compute_sequence_move_target_direction(state, distance, direction, heading, delta)
│   │   │   ├── direction blending → rotation_desired_direction
│   │   │   ├── compute_sequence_move_thrust_control() → apply_central_force()
│   │   │   └── compute_sequence_move_lateral_damping() → state.linear_velocity
│   │   │
│   │   └──— hoặc ——
│   │   ├── compute_shift_move_target_direction(state, distance, direction, heading, delta)
│   │   │   ├── arrival facing blend → rotation_desired_direction
│   │   │   └── compute_shift_move_thrust_control() → apply_central_force()
│   │   │   (giữ nguyên lateral velocity)
│   │
│   ├── [STEERING]
│   │   ├── distance > ship_length * 3
│   │   │   → Fajen → state.angular_velocity = yaw*fajen.y + pitch*fajen.x
│   │   └── distance ≤ ship_length * 3
│   │       → update_rotation → state.angular_velocity.lerp(target, strength*delta)
│   │
│   ├── apply_roll_clamp(state)
│   └── apply_pitch_clamp(state)
│
└── [Engine: tích hợp velocity vào transform]
    ├── position += linear_velocity * delta
    ├── rotation = angular_velocity → quaternion
    └── (không có force/torque accumulation — đã gán velocity trực tiếp)
```

---

## 7. BẢNG BIẾN SỐ QUAN TRỌNG

| Biến | Kiểu | Ý nghĩa | Nguồn |
|------|------|---------|-------|
| `linear_velocity` | Vector3 | Vận tốc tịnh tiến (m/s) | RigidBody3D built-in |
| `angular_velocity` | Vector3 | Vận tốc góc (rad/s) | RigidBody3D built-in |
| `mass` | float | Khối lượng (kg) | RigidBody3D built-in |
| `linear_power_to_mass_ratio` | float | `max_thrust_force / mass` — tỉ lệ lực/kg | `ship_movement_integrate` |
| `rotation_power_to_mass_ratio` | float | `(torque + rcs) / mass` — tỉ lệ xoay/kg | `ship_movement_integrate` |
| `current_thrust_force` | float | Lực đẩy hiện tại (nội suy tăng/giảm) | `ship_movement_integrate` |
| `auto_throttle` | float | Hệ số ga [0, 1] = `alignment³ × danger_factor` | `ship_movement_integrate` |
| `rotation_desired_direction` | Vector3 | Hướng muốn xoay về (cho manual rotation) | `ship_movement_integrate` |
| `current_target_direction` | Vector3 | Hướng blend hiện tại tới target | `ship_movement_integrate` |
| `rotation_p` | float | Proportional gain cho PD rotation | `ship_movement_integrate` |
| `rotation_d` | float | Damping gain cho PD rotation | `ship_movement_integrate` |
| `fajen_angular_velocity` | Vector2 | Momentum nội bộ Fajen (x=pitch, y=yaw) | `steering_fajen_warrent` |
| `fajen_kg` | float | Goal attraction strength (20) | `steering_fajen_warrent` |
| `fajen_ko` | float | Obstacle repulsion strength (180) | `steering_fajen_warrent` |
| `fajen_b` | float | Angular damping trong công thức Fajen (2.2) | `steering_fajen_warrent` |
| `fajen_c3` | float | Obstacle angular sensitivity (6.0) | `steering_fajen_warrent` |
| `fajen_c4` | float | Obstacle distance decay (0.2) | `steering_fajen_warrent` |
| `lateral_velocity` | Vector3 | Vận tốc ngang (tách từ linear) | `ship_movement_integrate` |
| `forward_velocity` | Vector3 | Vận tốc dọc theo heading | `ship_movement_integrate` |
| `braking_dist` | float | `v² / (2 * max_thrust / mass)` — cục bộ | local variable |
| `blend_arrival_distance` | float | 3.0m — bắt đầu blend direction | export |
| `arrival_radius` | float | 1.0m — ngưỡng đến đích | export |
| `ship_length` | float | Độ dài AABB của ship | tính từ mesh |

---

## 8. ĐIỂM DỄ BUG — CHECKLIST DEBUG

| # | Triệu chứng | Nguyên nhân thường gặp | Biến cần check |
|---|-------------|----------------------|----------------|
| 1 | Ship quay ngược khi đến đích | `rotation_desired_direction` = Vector3.ZERO | `desired_dir.length_squared()` trong `update_rotation` |
| 2 | Pitch không về 0 sau khi dừng | `apply_pitch_correction` không chạy (IDLE state) | `angular_velocity`, `pitch_angle` |
| 3 | Ship dao động ở đích | Fajen momentum không reset khi vào gần | `fajen_steering.fajen_angular_velocity` |
| 4 | Click chuột không nhận | Sai `FlightInputState` hoặc `Input.mouse_mode != VISIBLE` | `current_input_state`, `mouse_mode` |
| 5 | Waypoint spam khi drag | Thiếu guard `event.is_action_released()` | `input_state_sequence_move()` |
| 6 | Ship bay vòng tròn | `lateral_damp_value` quá nhỏ → lateral velocity không tắt | `lateral_velocity.length()`, `lateral_damp_value` |
| 7 | Ship lắc lư roll liên tục | `angular_stable_power_ratio` quá thấp | `apply_roll_correction`, `roll_angle` |
| 8 | Fajen không tránh obstacle | `nearby_obstacles` rỗng, sai `collision_mask` | `obstacle_count`, `fajen_area_collision_mask` |
| 9 | Shift move không blend hướng | `arrival_facing` chưa được set (vẫn là direction mặc định) | `current_waypoint.arrival_facing` |
| 10 | Rotation delay không hoạt động | `rotation_delay_threshold` (60°) quá lớn | `rotation_delay_timer`, `angle_abs` |
| 11 | Dùng nhầm torque với velocity | Code cũ dùng `apply_torque`, mới dùng gán `angular_velocity` | Phân biệt `_integrate_forces` vs `_physics_process` |
