# Ship Movement Flow (IDLE → MOVE → IDLE)
> File: `scripts/movement/ship_movement_integrate.gd` · Kinematic Override via `_integrate_forces()`
> Cập nhật: 2026-06-26 · Bổ sung 3-tier Priority Pipeline + `recalculate_power_ratios`

---

## 1. Kiến trúc `_integrate_forces` — 3 Tầng Priority Pipeline

```
_integrate_forces(state)
│
├── [TẦNG 1: THRUST + DIRECTION]
│   └── PlayerState dispatch:
│       ├── IDLE → phanh, damping, roll/pitch correction
│       └── MOVE → match current_waypoint.type
│           ├── "sequence" → direction blending + lateral damping + thrust
│           └── "shift"    → arrival-facing blend + thrust (ko lateral damping)
│
├── [TẦNG 2: STEERING]
│   ├── Energy turn → update_rotation() (ratio đã được boost bởi recalculate_power_ratios)
│   ├── Xa (distance > ship_length × 5) → Fajen Warren
│   └── Gần (distance ≤ ship_length × 5) → Manual rotation
│
├── [TẦNG 3: STABILIZE] — luôn chạy
│   ├── apply_roll_clamp(state)
│   └── apply_pitch_clamp(state)
```

> **Nguyên tắc Kinematic Override:**
> - Gán trực tiếp `state.linear_velocity` (qua lateral damping) + `state.angular_velocity`
> - Chỉ `handle_state_idle` và `compute_*_thrust_control` dùng `apply_central_force`
> - Steering dùng **velocity gán**, không dùng torque

---

## 2. IDLE State
- **Condition:** `current_waypoint == null` (và `PlayerState.IDLE`)
- **Behavior trong `_integrate_forces` → `PlayerState.IDLE`:**
  - `handle_state_idle()`: `apply_central_force(-linear_velocity * max_thrust_force * linear_power_to_mass_ratio * 0.5)` — phanh
  - `apply_roll_correction(state, delta)` + `apply_pitch_correction(state, delta)` — auto-stabilize
  - Nếu `current_waypoint == null` và `linear_velocity != Vector3.ZERO`:
    - `state.linear_velocity.move_toward(ZERO, linear_damp_value * linear_power_to_mass_ratio * delta)`
    - `state.angular_velocity.lerp(ZERO, angular_damp_value * rotation_power_to_mass_ratio * delta)`
    - `lateral_velocity.move_toward(ZERO, lateral_damp_value * linear_power_to_mass_ratio * delta)`
    - `forward_velocity.move_toward(ZERO, lateral_damp_value * linear_power_to_mass_ratio * delta)`

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

## 5. TẦNG 2: STEERING

### 5A. Energy Turn (ưu tiên cao nhất)

- **Condition:** `is_energy_turning == true` (set bởi `input_state_energy_turn`)
- **Behavior:**
  - Reset `rotation_delay_timer`, `angle_change_factor`, `angle_fine_factor`
  - `lateral_velocity = lerp(ZERO, 0.5 * delta)` — triệt tiêu trượt ngang nhẹ
  - Gọi `update_rotation(state, energy_turn_desired_dir, delta)`
  - `rotation_power_to_mass_ratio` đã được boost 3x bởi `recalculate_power_ratios()`
  - Thoát khi `ship_heading.angle_to(energy_turn_desired_dir) < 1°`
  - Thoát → gọi `recalculate_power_ratios()` để trả ratio về bình thường

### 5B. Fajen Warren (xa — distance > ship_length × 5.0)

```text
current_steering_mode = FAJEN_WARREN
max_engine_accel = rotation_power_to_mass_ratio

1. fajen_steering.compute_fajen_angular_acceleration(...)
   → Steering tự tích lũy momentum nội bộ
2. state.angular_velocity = yaw * fajen_vel.y + pitch * fajen_vel.x
3. Danger throttle: total_repulsion > 5.0
   → auto_throttle *= clamp(1 - repulsion/50, 0.1, 1.0)
```

### 5C. Manual Rotation (gần — distance ≤ ship_length × 5.0)

```text
current_steering_mode = NONE
fajen_steering.set_fajen_angular_velocity(Vector2.ZERO)  // reset Fajen

update_rotation(state, rotation_desired_direction, delta):
  a. Xây dựng target_basis từ desired_dir + Vector3.UP
  b. diff_quat = target_quat * current_quat.inverse()
  c. Rotation delay detection
  d. Fine zone scaling
  e. turn_speed = angle * rotation_p * fine_factor * change_factor
     → Clamp: max_angular_speed * rotation_power_to_mass_ratio
  f. state.angular_velocity.lerp(target, rotation_power_to_mass * rotation_d * delta)
```

---

## 6. TẦNG 3: STABILIZE (luôn chạy)

| Function | Effect |
|---|---|
| `apply_roll_correction(state, delta)` | Lerp angular velocity để đưa roll về 0 |
| `apply_pitch_correction(state, delta)` | Lerp angular velocity để giữ pitch cân bằng |
| `apply_roll_clamp(state)` | Chặn roll vượt `max_roll_angle` (6°) |
| `apply_pitch_clamp(state)` | Chặn pitch vượt `max_pitch_angle` (10°) |

---

## 7. Engine Parameters — `recalculate_power_ratios()`

Hàm tập trung tính `linear_power_to_mass_ratio` và `rotation_power_to_mass_ratio`
dựa trên các flag đang active:

```gdscript
func recalculate_power_ratios():
    var combusion_boost = combusion_boost_multiplier if is_combusion_boost_active else 1.0   # 2.0 | 1.0
    var rotation_boost  = combusion_rotation_multiplier if is_combusion_boost_active else 0.0 # 0.25 | 0.0
    var turn_boost      = energy_turn_multiplier if is_energy_turning else 1.0                # 3.0  | 1.0

    linear_power_to_mass_ratio   = (max_thrust_force * combusion_boost) / mass
    rotation_power_to_mass_ratio = ((max_turn_torque + max_turn_torque_rcs) * (combusion_boost + (combusion_boost * rotation_boost)) * turn_boost) / mass
```

**Công thức rotation chi tiết:**
```
rotation_power_to_mass_ratio = (torque + rcs_torque) × (boost + boost × rotation_boost) × turn_boost / mass
```

Trong đó:
- `boost` = `combusion_boost_multiplier` (2.0) nếu `is_combusion_boost_active`, else 1.0
- `rotation_boost` = `combusion_rotation_multiplier` (0.25) nếu boost active, else 0.0
- → Khi boost: `(2.0 + 2.0 × 0.25) = 2.5×` rotation power
- `turn_boost` = `energy_turn_multiplier` (3.0) nếu energy turn, else 1.0
- → Khi cả boost + energy turn: `2.5 × 3.0 = 7.5×` rotation power

---

## 8. Returning to IDLE

- **Condition:** Hết waypoint (`distance ≤ arrival_radius`)
- **Behavior:**
  - `current_waypoint = null`
  - `change_state(PlayerState.IDLE)`
  - `rotation_desired_direction` = arrival_facing (chuẩn hóa XZ)
  - Ship tự phanh + damping về 0 ở IDLE state

---

## Key Functions

| Function | Purpose |
|---|---|
| `handle_state_idle(delta)` | Braking force + reset throttle |
| `change_state(new_state)` | Switch PlayerState (IDLE ↔ MOVE) |
| `move_to(pos, is_sequence)` | Add waypoint, init movement |
| `clear_all_waypoints()` | Clear queue + remove markers |
| `load_next_waypoint()` | Pop next waypoint, set as current |
| `_integrate_forces(state)` | Main physics — 3-tier pipeline |
| `recalculate_power_ratios()` | Recalculate engine ratios from flags |
| `update_rotation(state, dir, delta)` | Manual steering via quaternion PD |
| `compute_sequence_move_target_direction(...)` | Direction blending + thrust control |
| `compute_shift_move_target_direction(...)` | Arrival-facing blend + thrust control |
| `compute_sequence_move_thrust_control(...)` | Thrust calc with braking blend |
| `compute_shift_move_thrust_control(...)` | Thrust calc (simpler brake) |
| `compute_sequence_move_lateral_damping(...)` | Kill lateral velocity (sequence) |
| `apply_roll_correction/pitch_correction(...)` | Auto-stabilize |
| `apply_roll_clamp/pitch_clamp(...)` | Hard limit max angles |


| `handle_state_idle(delta)` | Braking force + reset throttle |
| `change_state(new_state)` | Switch PlayerState (IDLE ↔ MOVE) |
| `move_to(pos, is_sequence)` | Add waypoint, init movement |
| `clear_all_waypoints()` | Clear queue + remove markers |
| `load_next_waypoint()` | Pop next waypoint, set as current |
| `_integrate_forces(state)` | Main physics — 3-tier pipeline |
| `recalculate_power_ratios()` | Recalculate engine ratios from flags |
| `update_rotation(state, dir, delta)` | Manual steering via quaternion PD |
| `compute_sequence_move_target_direction(...)` | Direction blending + thrust control |
| `compute_shift_move_target_direction(...)` | Arrival-facing blend + thrust control |
| `compute_sequence_move_thrust_control(...)` | Thrust calc with braking blend |
| `compute_shift_move_thrust_control(...)` | Thrust calc (simpler brake) |
| `compute_sequence_move_lateral_damping(...)` | Kill lateral velocity (sequence) |
| `apply_roll_correction/pitch_correction(...)` | Auto-stabilize |
| `apply_roll_clamp/pitch_clamp(...)` | Hard limit max angles |
