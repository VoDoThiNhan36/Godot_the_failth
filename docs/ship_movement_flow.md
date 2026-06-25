# Ship Movement Flow (IDLE → MOVE → IDLE)
> File: `scripts/movement/ship_movement_integrate.gd` · Kinematic Override via `_integrate_forces()`

## 1. IDLE State
- **Condition:** `current_waypoint == null`
- **Behavior trong `_integrate_forces` → `PlayerState.IDLE`:**
  - `handle_state_idle()`: `apply_central_force(-linear_velocity * max_thrust_force * ratio * 0.5)` — phanh
  - `apply_roll_correction(state, delta)` + `apply_pitch_correction(state, delta)` — auto-stabilize
  - Nếu `current_waypoint == null` và `linear_velocity != Vector3.ZERO`:
    - `state.linear_velocity.move_toward(ZERO, linear_damp_value * ratio * delta)`
    - `state.angular_velocity.lerp(ZERO, angular_damp_value * rot_ratio * delta)`
    - `lateral_velocity.lerp(ZERO, lateral_damp_value * ratio * delta)`
    - `forward_velocity.lerp(ZERO, lateral_damp_value * ratio * delta)`

## 2. Adding a Waypoint (`move_to`)
- **Trigger:** Player clicks → `_unhandled_input` → `input_state_idle()` hoặc `input_state_sequence_move()`
- **Behavior:**
  - Nếu không phải sequence, `clear_all_waypoints()` — xóa queue cũ
  - Cộng `current_target_height_offset` vào Y
  - Lấy `previous_position` (từ waypoint cuối hoặc `global_position`)
  - Tạo `Movement_Waypoint.new(pos, prev_pos, "sequence")`
  - `add_child(point_marker)` — hiển thị marker
  - Nếu chưa moving → `load_next_waypoint()` + `change_state(MOVE)`

## 3. MOVE State (Following Waypoints)
- **Condition:** `current_waypoint != null`
- **Behavior trong `_integrate_forces`:**
  - Tính `distance_to_target`, `direction_to_target`, `ship_heading`
  - Match `current_waypoint.type`:

### 3A. Sequence Move — `compute_sequence_move_target_direction()`

```text
distance > blend_arrival_distance (mặc định 3.0m)
  → current_target_direction = direction_to_target (hướng thẳng tới target)

blend_arrival_distance ≥ distance > arrival_radius (và hết waypoint)
  → blend_weight = clamp((distance - blend) / blend, 0.2, 1.0)
  → slerp(direction_to_target, current_waypoint.direction, blend_weight)
  → Ý nghĩa: gần đích thì blend về hướng click chuột ban đầu

distance ≤ arrival_radius (mặc định 1.0m)
  → is_at_current_waypoint_threshold = true
  → Nếu còn waypoint → load_next_waypoint()
  → Nếu hết → về IDLE + set arrival_facing
```

### 3B. Shift Move — `compute_shift_move_target_direction()`

```text
distance > arrival_radius (và chưa threshold)
  → current_target_direction = direction_to_target
  → Tính angle giữa ship_heading và arrival_facing (đã chuẩn hóa XZ)
  → desired_turn_speed = max_angular_speed * (max_turn_torque_rcs / mass)
  → time_to_rotate = angle / max(desired_turn_speed, 0.0001)
  → rotate_start_dist = linear_speed * time_to_rotate * 1.5
  → Nếu distance ≤ rotate_start_dist:
      blend_t = clamp(1 - distance / rotate_start_dist, 0, 1)
      rotation_desired_direction = slerp(ship_heading, arrival_facing, ease(blend_t, 2))

distance ≤ arrival_radius
  → load_next_waypoint() hoặc về IDLE + set arrival_facing
```

### 3C. Steering (Rotation)

**Xa** (distance > ship_length × 3.0): **Fajen Warren** — gán trực tiếp angular_velocity
```text
→ current_steering_mode = FAJEN_WARREN
→ max_engine_accel = rotation_power_to_mass_ratio  (= (torque + rcs) / mass)
→ fajen_steering.compute_fajen_angular_acceleration(...)
    → Steering tự tích lũy momentum nội bộ (fajen_angular_velocity Vector2)
    → Clamp max, damping mọi frame
→ fajen_vel = fajen_steering.get_fajen_angular_velocity()
→ state.angular_velocity = yaw_axis * fajen_vel.y + pitch_axis * fajen_vel.x
→ Nếu total_repulsion > 5.0: auto_throttle *= clamp(1 - repulsion/50, 0.1, 1.0)
```

**Gần** (distance ≤ ship_length × 3.0): **Manual Rotation** (Quaternion-based PD controller)
```text
→ current_steering_mode = NONE
→ fajen_steering.set_fajen_angular_velocity(Vector2.ZERO)  // reset Fajen momentum
→ update_rotation(state, rotation_desired_direction, delta)
    → Xây dựng target_basis từ desired_dir + Vector3.UP
    → diff_quat = target_quat * current_quat.inverse()
    → axis, angle = diff_quat.get_axis(), diff_quat.get_angle()
    → Rotation delay detection: nếu angle tăng đột ngột > delay_threshold
      → delay_timer, angle_change_factor → 0
    → Fine zone: nếu angle < fine_rad → angle_fine_factor giảm dần
    → turn_speed = angle * rotation_p * fine_factor * change_factor
    → target_angular_velocity = axis * turn_speed
    → state.angular_velocity.lerp(target, rotation_power_to_mass * rotation_d * delta)
```

### 3D. Thrust Control — `compute_sequence_move_thrust_control()`

```text
braking_dist = v² / (2 * max_thrust_force / mass)

alignment ≥ 0.85:
  auto_throttle = alignment³
  distance > braking_dist:  → tăng ga (còn xa)
    current_thrust_force → max_thrust_force
    apply_central_force(heading * thrust * throttle)
  distance ≤ braking_dist:  → giảm ga (vùng phanh)
    target_force = max_thrust * (dist / braking_dist) * ratio
    steering_force = (target_force - current) * heading
    apply_central_force(steering_force.limit_length(max_thrust))

alignment < 0.85:
  → Phanh: auto_throttle → 0
  → apply_central_force(-linear_velocity * max_thrust * ratio)
```

### 3E. Shift Thrust Control — `compute_shift_move_thrust_control()`

```text
Giống sequence nhưng:
- alignment threshold thấp hơn (0.5 thay vì 0.85)
- Không có braking blend — chỉ phanh khi distance ≤ braking_dist
```

### 3F. Lateral Damping

```text
→ forward_speed = linear_velocity.dot(heading)
→ forward_velocity = heading * forward_speed
→ lateral_velocity = linear_velocity - forward_velocity
→ lateral_velocity.lerp(ZERO, lateral_damp_value * ratio * delta)
→ state.linear_velocity = forward_velocity + lateral_velocity
```

## 4. Always-on Corrections (chạy sau steering mỗi frame)

| Function | Effect |
|---|---|
| `apply_roll_correction(state, delta)` | Lerp angular velocity để đưa roll về 0 |
| `apply_pitch_correction(state, delta)` | Lerp angular velocity để giữ pitch cân bằng |
| `apply_roll_clamp(state)` | Chặn roll vượt `max_roll_angle` (6°) |
| `apply_pitch_clamp(state)` | Chặn pitch vượt `max_pitch_angle` (10°) |

## 5. Returning to IDLE
- **Condition:** Hết waypoint + vừa đến đích (`distance ≤ arrival_radius`)
- **Behavior:**
  - `current_waypoint = null`
  - `change_state(PlayerState.IDLE)`
  - `rotation_desired_direction` = arrival_facing (chuẩn hóa XZ)
  - Ship tự phanh + damping về 0 ở IDLE state

---

## Key Functions (trong `ship_movement_integrate.gd`)

| Function | Purpose |
|---|---|
| `handle_state_idle(delta)` | Braking force (`apply_central_force`) + reset throttle |
| `change_state(new_state)` | Switch PlayerState (IDLE ↔ MOVE) |
| `move_to(pos, is_sequence)` | Add waypoint, init movement |
| `clear_all_waypoints()` | Clear queue + remove markers |
| `load_next_waypoint()` | Pop next waypoint, set as current |
| `_integrate_forces(state)` | Main physics loop — kinematic override |
| `compute_sequence_move_target_direction(...)` | Direction blending + thrust control for sequence |
| `compute_shift_move_target_direction(...)` | Arrival-facing blend for shift waypoints |
| `compute_sequence_move_thrust_control(...)` | Thrust calc for sequence (alignment + braking) |
| `compute_shift_move_thrust_control(...)` | Thrust calc for shift (simpler braking) |
| `compute_sequence_move_lateral_damping(...)` | Kill lateral velocity (sequence) |
| `update_rotation(state, desired_dir, delta)` | Manual steering via quaternion PD controller |
| `apply_roll_correction(...)` / `apply_pitch_correction(...)` | Auto-stabilize roll/pitch |
| `apply_roll_clamp(...)` / `apply_pitch_clamp(...)` | Hard limit max roll/pitch angles |
| `create_shift_waypoint(pos)` | Create a shift-type waypoint |
